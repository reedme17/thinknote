import { randomUUID } from "node:crypto";
import { buildRelatedLinks } from "./links.js";

export function createJobProcessor({ config, store, logger, ai }) {
    let timer = null;
    let running = false;
    const waiters = new Map();

    const processor = {
        start() {
            if (timer) {
                return;
            }

            timer = setInterval(() => {
                void processor.runDueJobs(new Date());
            }, config.jobPollIntervalMs);
        },
        stop() {
            if (timer) {
                clearInterval(timer);
                timer = null;
            }
        },
        async enqueueEnrichment(noteId, payload = {}, triggerSource = "manual", options = {}) {
            const createdAt = new Date().toISOString();
            const earliestRunAt = normalizeIsoDate(options.earliestRunAt || payload.earliestRunAt, createdAt);
            const priority = normalizePriority(options.priority || payload.priority, triggerSource);
            const maxRuns = normalizePositiveInteger(options.maxRuns ?? payload.maxRuns, 1);
            const job = {
                id: randomUUID(),
                noteId,
                type: "enrich_note",
                status: "queued",
                triggerSource,
                payload,
                priority,
                earliestRunAt,
                retryCount: 0,
                maxRetries: config.jobMaxRetries,
                runCount: 0,
                maxRuns,
                lastError: null,
                output: null,
                createdAt,
                updatedAt: createdAt,
                startedAt: null,
                completedAt: null,
                nextRunAt: earliestRunAt
            };

            await store.transaction((state) => {
                state.jobs.unshift(job);
                const note = state.notes.find((entry) => entry.id === noteId);
                if (note) {
                    note.status = "queued";
                    note.updatedAt = new Date().toISOString();
                    const scheduleSummary =
                        new Date(earliestRunAt).getTime() > Date.now()
                            ? `Growth scheduled from ${triggerSource}`
                            : `Enrichment queued from ${triggerSource}`;
                    store.createTimelineEvent(note, "job_queued", scheduleSummary, {
                        priority,
                        earliestRunAt
                    });
                }
            });

            logger.info("job_enqueued", { jobId: job.id, noteId, triggerSource, priority, earliestRunAt });
            return job;
        },
        async runDueJobs(now = new Date()) {
            if (running) {
                return;
            }

            const nextJob = store
                .getState()
                .jobs.find(
                    (job) =>
                        ["queued", "retrying"].includes(job.status) &&
                        job.runCount < job.maxRuns &&
                        new Date(job.nextRunAt).getTime() <= now.getTime()
                );

            if (!nextJob) {
                return;
            }

            running = true;
            try {
                await runJob(nextJob, now);
            } finally {
                running = false;
            }
        },
        waitForJob(jobId, timeoutMs = 15000) {
            const existing = store.getJob(jobId);
            if (existing && ["completed", "failed"].includes(existing.status)) {
                return Promise.resolve(existing);
            }

            return new Promise((resolve) => {
                const timeout = setTimeout(() => {
                    waiters.delete(jobId);
                    resolve(store.getJob(jobId));
                }, timeoutMs);

                waiters.set(jobId, (job) => {
                    clearTimeout(timeout);
                    waiters.delete(jobId);
                    resolve(job);
                });
            });
        }
    };

    async function runJob(job, now = new Date()) {
        const startedAt = now.toISOString();

        await store.transaction((state) => {
            const currentJob = state.jobs.find((entry) => entry.id === job.id);
            const note = state.notes.find((entry) => entry.id === job.noteId);
            if (!currentJob) {
                return;
            }

            currentJob.status = "running";
            currentJob.startedAt = startedAt;
            currentJob.updatedAt = startedAt;

            if (note) {
                note.status = "processing";
                note.updatedAt = startedAt;
                store.createTimelineEvent(note, "job_started", "Background enrichment started");
            }
        });

        logger.info("job_started", { jobId: job.id, noteId: job.noteId });

        try {
            if (job.type !== "enrich_note") {
                throw new Error(`Unsupported job type: ${job.type}`);
            }

            const completed = await processEnrichmentJob(job);
            resolveWaiter(completed);
        } catch (error) {
            const message = error instanceof Error ? error.message : String(error);
            const failedJob = await store.transaction((state) => {
                const currentJob = state.jobs.find((entry) => entry.id === job.id);
                const note = state.notes.find((entry) => entry.id === job.noteId);
                if (!currentJob) {
                    return null;
                }

                currentJob.retryCount += 1;
                currentJob.lastError = message;
                currentJob.updatedAt = new Date().toISOString();

                if (shouldRetryJob(currentJob)) {
                    currentJob.status = "retrying";
                    currentJob.nextRunAt = new Date(Date.now() + retryDelayMs(currentJob.retryCount)).toISOString();
                } else {
                    currentJob.status = "failed";
                    currentJob.completedAt = new Date().toISOString();
                }

                if (note) {
                    note.status = currentJob.status === "failed" ? "failed" : currentJob.status;
                    note.updatedAt = new Date().toISOString();
                    store.createTimelineEvent(
                        note,
                        currentJob.status === "failed" ? "job_failed" : "job_retrying",
                        currentJob.status === "failed"
                            ? `Enrichment failed: ${message}`
                            : `Enrichment retry scheduled after error: ${message}`
                    );
                }

                return currentJob;
            });

            logger.error("job_failed", {
                jobId: job.id,
                noteId: job.noteId,
                detail: message,
                retryCount: failedJob?.retryCount || 0,
                status: failedJob?.status || "missing"
            });

            if (failedJob && failedJob.status === "failed") {
                resolveWaiter(failedJob);
            }
        }
    }

    async function processEnrichmentJob(job) {
        const note = store.getNote(job.noteId);
        if (!note) {
            throw new Error("Note not found for job");
        }

        const relatedLinks = buildRelatedLinks(note, store.getState().notes);
        const relatedNotes = relatedLinks
            .map((link) => store.getNote(link.noteId))
            .filter(Boolean);
        const enrichment = await ai.generateEnrichment({
            note,
            focus: typeof job.payload.focus === "string" ? job.payload.focus : "",
            includeWeb: job.payload.includeWeb !== false,
            followUpGuidance: typeof job.payload.followUpGuidance === "string" ? job.payload.followUpGuidance : "",
            relatedNotes
        });
        const growthParagraphs = normalizeGrowthParagraphs(enrichment.growthParagraphs);
        const expansion = growthParagraphs.join("\n\n");
        const headline = normalizeHeadline(enrichment.headline, note);
        const timelineSummary = normalizeTimelineSummary(enrichment.timelineSummary);

        const completedAt = new Date().toISOString();
        const revision = {
            id: randomUUID(),
            createdAt: completedAt,
            type: "ai_enrichment",
            summary: `Enrichment from ${enrichment.provider}`,
            text: expansion,
            sourceJobId: job.id
        };

        const completedJob = await store.transaction((state) => {
            const currentJob = state.jobs.find((entry) => entry.id === job.id);
            const currentNote = state.notes.find((entry) => entry.id === job.noteId);
            if (!currentJob || !currentNote) {
                return null;
            }

            currentNote.status = "enriched";
            currentNote.title = headline;
            currentNote.updatedAt = completedAt;
            currentNote.lastEnrichedAt = completedAt;
            currentNote.latestChatReply = enrichment.followUpContext ? null : currentNote.latestChatReply;
            currentNote.prompts = enrichment.prompts;
            currentNote.sources = enrichment.sources;
            currentNote.links = relatedLinks;
            currentNote.relatedNoteIds = relatedLinks.map((link) => link.noteId);
            currentNote.enrichments.unshift({
                id: randomUUID(),
                createdAt: completedAt,
                provider: enrichment.provider,
                headline,
                growthParagraphs,
                timelineSummary,
                expansion,
                relatedIdeas: enrichment.relatedIdeas,
                prompts: enrichment.prompts,
                links: relatedLinks,
                sources: enrichment.sources,
                followUpContext: enrichment.followUpContext || null
            });
            currentNote.revisions.unshift(revision);
            store.createTimelineEvent(currentNote, "note_enriched", timelineSummary, {
                provider: enrichment.provider
            });
            if (relatedLinks.length > 0) {
                store.createTimelineEvent(currentNote, "related_notes_updated", `${relatedLinks.length} related notes refreshed`);
            }

            currentJob.status = "completed";
            currentJob.runCount += 1;
            currentJob.completedAt = completedAt;
            currentJob.updatedAt = completedAt;
            currentJob.output = {
                enrichmentId: currentNote.enrichments[0].id,
                headline: currentNote.title,
                paragraphCount: growthParagraphs.length,
                sourceCount: enrichment.sources.length,
                relatedCount: relatedLinks.length
            };

            return currentJob;
        });

        logger.info("job_completed", {
            jobId: job.id,
            noteId: job.noteId,
            sourceCount: enrichment.sources.length,
            relatedCount: relatedLinks.length
        });

        return completedJob;
    }

    function resolveWaiter(job) {
        const waiter = waiters.get(job?.id);
        if (waiter) {
            waiter(job);
        }
    }

    function shouldRetryJob(job) {
        return job.maxRetries < 0 || job.retryCount <= job.maxRetries;
    }

    function retryDelayMs(retryCount) {
        const baseMs = normalizePositiveInteger(config.jobRetryBaseMs, 1500);
        const maxDelayMs = normalizePositiveInteger(config.jobRetryMaxDelayMs, 300000);
        const exponential = baseMs * 2 ** Math.min(Math.max(retryCount - 1, 0), 8);
        const jitter = Math.floor(Math.random() * baseMs);
        return Math.min(exponential + jitter, maxDelayMs);
    }

    return processor;
}

function normalizeIsoDate(value, fallback) {
    if (typeof value !== "string") {
        return fallback;
    }

    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? fallback : parsed.toISOString();
}

function normalizePriority(value, triggerSource) {
    if (typeof value === "string" && value.trim()) {
        return value.trim();
    }

    return triggerSource === "manual" ? "user_initiated" : "background";
}

function normalizePositiveInteger(value, fallback) {
    const parsed = Number(value);
    if (!Number.isFinite(parsed) || parsed < 1) {
        return fallback;
    }

    return Math.floor(parsed);
}

function normalizeGrowthParagraphs(value) {
    if (!Array.isArray(value)) {
        return ["A new growth pass completed, but no structured paragraphs were returned."];
    }

    const paragraphs = value
        .filter((item) => typeof item === "string")
        .map((item) => item.trim())
        .filter(Boolean);

    return paragraphs.length > 0 ? paragraphs.slice(0, 3) : ["A new growth pass completed, but no structured paragraphs were returned."];
}

function normalizeHeadline(value, note) {
    const fallback = String(note.title || note.rawText || note.text || "").trim();
    const raw = typeof value === "string" && value.trim() ? value.trim() : fallback;
    const compact = raw.replace(/\s+/g, " ").replace(/\.{3,}/g, "").trim();
    if (compact.length <= 90) {
        return compact;
    }

    const sliced = compact.slice(0, 90);
    const boundary = sliced.lastIndexOf(" ");
    return (boundary > 50 ? sliced.slice(0, boundary) : sliced).trim();
}

function normalizeTimelineSummary(value) {
    if (typeof value !== "string" || !value.trim()) {
        return "New growth added";
    }

    return value.trim().replace(/\s+/g, " ").slice(0, 80);
}
