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
                void processor.runDueJobs();
            }, config.jobPollIntervalMs);
        },
        stop() {
            if (timer) {
                clearInterval(timer);
                timer = null;
            }
        },
        async enqueueEnrichment(noteId, payload = {}, triggerSource = "manual") {
            const job = {
                id: randomUUID(),
                noteId,
                type: "enrich_note",
                status: "queued",
                triggerSource,
                payload,
                retryCount: 0,
                maxRetries: config.jobMaxRetries,
                lastError: null,
                output: null,
                createdAt: new Date().toISOString(),
                updatedAt: new Date().toISOString(),
                startedAt: null,
                completedAt: null,
                nextRunAt: new Date().toISOString()
            };

            await store.transaction((state) => {
                state.jobs.unshift(job);
                const note = state.notes.find((entry) => entry.id === noteId);
                if (note) {
                    note.status = "queued";
                    note.updatedAt = new Date().toISOString();
                    store.createTimelineEvent(note, "job_queued", `Enrichment queued from ${triggerSource}`);
                }
            });

            logger.info("job_enqueued", { jobId: job.id, noteId, triggerSource });
            return job;
        },
        async runDueJobs() {
            if (running) {
                return;
            }

            const nextJob = store
                .getState()
                .jobs.find((job) => ["queued", "retrying"].includes(job.status) && new Date(job.nextRunAt).getTime() <= Date.now());

            if (!nextJob) {
                return;
            }

            running = true;
            try {
                await runJob(nextJob);
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

    async function runJob(job) {
        const startedAt = new Date().toISOString();

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

                if (currentJob.retryCount <= currentJob.maxRetries) {
                    currentJob.status = "retrying";
                    currentJob.nextRunAt = new Date(Date.now() + currentJob.retryCount * 1500).toISOString();
                } else {
                    currentJob.status = "failed";
                    currentJob.completedAt = new Date().toISOString();
                }

                if (note) {
                    note.status = currentJob.status === "failed" ? "failed" : "queued";
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
            relatedNotes
        });

        const completedAt = new Date().toISOString();
        const revision = {
            id: randomUUID(),
            createdAt: completedAt,
            type: "ai_enrichment",
            summary: `Enrichment from ${enrichment.provider}`,
            text: enrichment.expansion,
            sourceJobId: job.id
        };

        const completedJob = await store.transaction((state) => {
            const currentJob = state.jobs.find((entry) => entry.id === job.id);
            const currentNote = state.notes.find((entry) => entry.id === job.noteId);
            if (!currentJob || !currentNote) {
                return null;
            }

            currentNote.status = "enriched";
            currentNote.updatedAt = completedAt;
            currentNote.lastEnrichedAt = completedAt;
            currentNote.prompts = enrichment.prompts;
            currentNote.sources = enrichment.sources;
            currentNote.links = relatedLinks;
            currentNote.relatedNoteIds = relatedLinks.map((link) => link.noteId);
            currentNote.enrichments.unshift({
                id: randomUUID(),
                createdAt: completedAt,
                provider: enrichment.provider,
                expansion: enrichment.expansion,
                relatedIdeas: enrichment.relatedIdeas,
                prompts: enrichment.prompts,
                links: relatedLinks,
                sources: enrichment.sources
            });
            currentNote.revisions.unshift(revision);
            store.createTimelineEvent(currentNote, "note_enriched", `Note enriched by ${enrichment.provider}`);
            if (relatedLinks.length > 0) {
                store.createTimelineEvent(currentNote, "related_notes_updated", `${relatedLinks.length} related notes refreshed`);
            }

            currentJob.status = "completed";
            currentJob.completedAt = completedAt;
            currentJob.updatedAt = completedAt;
            currentJob.output = {
                enrichmentId: currentNote.enrichments[0].id,
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

    return processor;
}
