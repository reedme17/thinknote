import { createServer } from "node:http";
import { randomUUID } from "node:crypto";
import { createAIOrchestrator } from "./ai.js";
import { createJobProcessor } from "./jobs.js";
import { createLogger } from "./logger.js";
import { createRetrievalClient } from "./retrieval.js";
import { createStore } from "./store.js";

export async function createThinknoteServer({ config, fetchImpl = fetch }) {
    const logger = createLogger();
    const store = await createStore({ config, logger });
    const retrieval = createRetrievalClient({ config, logger, fetchImpl });
    const ai = createAIOrchestrator({ config, logger, retrieval, fetchImpl });
    const jobs = createJobProcessor({ config, store, logger, ai });
    const services = { store, retrieval, ai, jobs, logger };

    jobs.start();

    const handleRequest = async (req, res) => {
        const startedAt = Date.now();
        try {
            setCorsHeaders(res);

            if (req.method === "OPTIONS") {
                res.writeHead(204);
                res.end();
                return;
            }

            const url = new URL(req.url || "/", `http://${req.headers.host || "localhost"}`);
            const route = matchRoute(req.method || "GET", url.pathname);
            if (!route) {
                sendJson(res, 404, { error: "Not found" });
                return;
            }

            const body = await readJsonBody(req);
            await route.handler({ req, res, url, params: route.params, body, services, config });

            logger.info("request_completed", {
                method: req.method,
                path: url.pathname,
                latencyMs: Date.now() - startedAt
            });
        } catch (error) {
            logger.error("request_failed", {
                method: req.method,
                detail: error instanceof Error ? error.message : String(error),
                latencyMs: Date.now() - startedAt
            });
            sendJson(res, error?.statusCode || 500, {
                error: error?.statusCode ? "Bad request" : "Internal server error",
                detail: error instanceof Error ? error.message : String(error)
            });
        }
    };

    const server = createServer(handleRequest);

    return {
        server,
        handleRequest,
        services,
        logger,
        async close() {
            jobs.stop();
            if (!server.listening) {
                return;
            }
            await new Promise((resolve, reject) => {
                server.close((error) => {
                    if (error) {
                        reject(error);
                        return;
                    }
                    resolve();
                });
            });
        }
    };
}

function matchRoute(method, pathname) {
    const routes = [
        ["GET", /^\/health$/, handleHealth],
        ["GET", /^\/api\/notes$/, handleListNotes],
        ["POST", /^\/api\/notes$/, handleCreateNote],
        ["GET", /^\/api\/notes\/(?<noteId>[^/]+)$/, handleGetNote],
        ["PATCH", /^\/api\/notes\/(?<noteId>[^/]+)$/, handleUpdateNote],
        ["GET", /^\/api\/notes\/(?<noteId>[^/]+)\/related$/, handleGetRelatedNotes],
        ["GET", /^\/api\/notes\/(?<noteId>[^/]+)\/threads$/, handleListThreadsForNote],
        ["POST", /^\/api\/notes\/(?<noteId>[^/]+)\/enrich$/, handleEnrichNote],
        ["GET", /^\/api\/jobs$/, handleListJobs],
        ["GET", /^\/api\/jobs\/(?<jobId>[^/]+)$/, handleGetJob],
        ["GET", /^\/api\/threads$/, handleListThreads],
        ["POST", /^\/api\/threads$/, handleCreateThread],
        ["GET", /^\/api\/threads\/(?<threadId>[^/]+)$/, handleGetThread],
        ["POST", /^\/api\/threads\/(?<threadId>[^/]+)\/messages$/, handleCreateThreadMessage],
        ["POST", /^\/api\/chat$/, handleChat]
    ];

    for (const [routeMethod, pattern, handler] of routes) {
        if (method !== routeMethod) {
            continue;
        }

        const match = pathname.match(pattern);
        if (!match) {
            continue;
        }

        return { handler, params: match.groups || {} };
    }

    return null;
}

async function handleHealth({ res, services }) {
    const state = services.store.getState();
    sendJson(res, 200, {
        ok: true,
        provider: services.ai.providerName,
        retrievalProvider: services.retrieval.providerName,
        noteCount: state.notes.length,
        queuedJobs: state.jobs.filter((job) => ["queued", "retrying", "running"].includes(job.status)).length
    });
}

async function handleListNotes({ res, services, url }) {
    const notes = [...services.store.getState().notes]
        .sort((left, right) => new Date(right.updatedAt).getTime() - new Date(left.updatedAt).getTime())
        .map((note) => decorateNote(note, services.store, url.searchParams.get("includeThreads") === "true"));
    sendJson(res, 200, { notes });
}

async function handleCreateNote({ res, body, services, config }) {
    const text = typeof body?.text === "string" ? body.text.trim() : "";
    const title = typeof body?.title === "string" ? body.title.trim() : deriveTitle(text);
    const requestedId = typeof body?.id === "string" && body.id.trim() ? body.id.trim() : null;

    if (!text) {
        sendJson(res, 400, { error: "Field `text` is required." });
        return;
    }

    if (requestedId) {
        const existing = services.store.getNote(requestedId);
        if (existing) {
            await services.store.transaction((state) => {
                const current = state.notes.find((entry) => entry.id === requestedId);
                current.rawText = text;
                current.text = text;
                current.title = title || deriveTitle(text);
                current.updatedAt = new Date().toISOString();
            });

            sendJson(res, 200, {
                note: decorateNote(services.store.getNote(requestedId), services.store, false),
                job: null
            });
            return;
        }
    }

    const now = new Date().toISOString();
    const note = {
        id: requestedId || randomUUID(),
        title: title || deriveTitle(text),
        text,
        rawText: text,
        createdAt: now,
        updatedAt: now,
        status: "captured",
        lastEnrichedAt: null,
        latestChatReply: null,
        enrichments: [],
        links: [],
        sources: [],
        prompts: [],
        relatedNoteIds: [],
        timeline: [
            {
                id: randomUUID(),
                type: "note_created",
                createdAt: now,
                summary: "Note created"
            }
        ],
        revisions: [
            {
                id: randomUUID(),
                createdAt: now,
                type: "user_capture",
                summary: "Initial note capture",
                text
            }
        ]
    };

    await services.store.transaction((state) => {
        state.notes.unshift(note);
        services.store.touchAnalytics("captureCount");
    });

    const shouldScheduleGrowth = body?.scheduleGrowth === true || config.autoEnrichOnCreate;
    let queuedJob = null;
    if (shouldScheduleGrowth) {
        const earliestRunAt =
            typeof body?.earliestRunAt === "string"
                ? body.earliestRunAt
                : new Date(Date.now() + config.autoEnrichDelayHours * 60 * 60 * 1000).toISOString();
        queuedJob = await services.jobs.enqueueEnrichment(
            note.id,
            {
                focus: typeof body?.focus === "string" ? body.focus.trim() : "",
                includeWeb: body?.includeWeb !== false
            },
            "auto_capture",
            {
                earliestRunAt,
                priority: "background",
                maxRuns: 1
            }
        );
    }

    sendJson(res, 201, {
        note: decorateNote(services.store.getNote(note.id), services.store, false),
        job: queuedJob
    });
}

async function handleGetNote({ res, params, services }) {
    const note = services.store.getNote(params.noteId);
    if (!note) {
        sendJson(res, 404, { error: "Note not found." });
        return;
    }

    sendJson(res, 200, { note: decorateNote(note, services.store, true) });
}

async function handleUpdateNote({ res, params, body, services }) {
    const note = services.store.getNote(params.noteId);
    if (!note) {
        sendJson(res, 404, { error: "Note not found." });
        return;
    }

    const nextText = typeof body?.text === "string" ? body.text.trim() : note.rawText;
    const nextTitle = typeof body?.title === "string" ? body.title.trim() : note.title;

    if (!nextText) {
        sendJson(res, 400, { error: "Field `text` cannot be empty." });
        return;
    }

    await services.store.transaction((state) => {
        const current = state.notes.find((entry) => entry.id === note.id);
        current.rawText = nextText;
        current.text = nextText;
        current.title = nextTitle || deriveTitle(nextText);
        current.updatedAt = new Date().toISOString();
        current.status = "edited";
        current.revisions.unshift({
            id: randomUUID(),
            createdAt: current.updatedAt,
            type: "user_edit",
            summary: "User edited note",
            text: nextText
        });
        services.store.createTimelineEvent(current, "note_edited", "Note updated by user");
    });

    sendJson(res, 200, { note: decorateNote(services.store.getNote(note.id), services.store, true) });
}

async function handleGetRelatedNotes({ res, params, services }) {
    const note = services.store.getNote(params.noteId);
    if (!note) {
        sendJson(res, 404, { error: "Note not found." });
        return;
    }

    const related = note.links.map((link) => ({
        ...link,
        note: decorateNote(services.store.getNote(link.noteId), services.store, false)
    }));

    sendJson(res, 200, { related });
}

async function handleListThreadsForNote({ res, params, services }) {
    const threads = services.store
        .getState()
        .threads.filter((thread) => thread.noteId === params.noteId || thread.relatedNoteIds.includes(params.noteId))
        .map((thread) => decorateThread(thread, services.store));

    sendJson(res, 200, { threads });
}

async function handleEnrichNote({ res, params, body, services, url }) {
    const note = services.store.getNote(params.noteId);
    if (!note) {
        sendJson(res, 404, { error: "Note not found." });
        return;
    }

    const wait = body?.wait !== false && url.searchParams.get("wait") !== "false";
    const now = new Date();
    const job = await services.jobs.enqueueEnrichment(
        note.id,
        {
            focus: typeof body?.focus === "string" ? body.focus.trim() : "",
            includeWeb: body?.includeWeb !== false
        },
        typeof body?.triggerSource === "string" && body.triggerSource.trim() ? body.triggerSource.trim() : "manual",
        {
            earliestRunAt: wait ? now.toISOString() : body?.earliestRunAt,
            priority:
                typeof body?.priority === "string" && body.priority.trim()
                    ? body.priority.trim()
                    : wait
                      ? "user_initiated"
                      : "background",
            maxRuns: body?.maxRuns
        }
    );

    if (wait) {
        await services.jobs.runDueJobs(now);
        const completedJob = await services.jobs.waitForJob(job.id);
        const refreshed = services.store.getNote(note.id);
        sendJson(res, 200, {
            note: decorateNote(refreshed, services.store, true),
            job: completedJob
        });
        return;
    }

    sendJson(res, 202, { job });
}

async function handleListJobs({ res, services }) {
    sendJson(res, 200, { jobs: services.store.getState().jobs });
}

async function handleGetJob({ res, params, services }) {
    const job = services.store.getJob(params.jobId);
    if (!job) {
        sendJson(res, 404, { error: "Job not found." });
        return;
    }

    sendJson(res, 200, { job });
}

async function handleListThreads({ res, services }) {
    const threads = services.store.getState().threads.map((thread) => decorateThread(thread, services.store));
    sendJson(res, 200, { threads });
}

async function handleCreateThread({ res, body, services }) {
    const noteId = typeof body?.noteId === "string" ? body.noteId : null;
    const relatedNoteIds = Array.isArray(body?.relatedNoteIds)
        ? body.relatedNoteIds.filter((item) => typeof item === "string")
        : noteId
          ? [noteId]
          : [];

    if (noteId && !services.store.getNote(noteId)) {
        sendJson(res, 404, { error: "Note not found." });
        return;
    }

    const now = new Date().toISOString();
    const thread = {
        id: randomUUID(),
        noteId,
        relatedNoteIds,
        title: typeof body?.title === "string" && body.title.trim() ? body.title.trim() : "Conversation",
        createdAt: now,
        updatedAt: now
    };

    await services.store.transaction((state) => {
        state.threads.unshift(thread);
    });

    sendJson(res, 201, { thread: decorateThread(thread, services.store) });
}

async function handleGetThread({ res, params, services }) {
    const thread = services.store.getThread(params.threadId);
    if (!thread) {
        sendJson(res, 404, { error: "Thread not found." });
        return;
    }

    sendJson(res, 200, { thread: decorateThread(thread, services.store) });
}

async function handleCreateThreadMessage({ res, params, body, services }) {
    const thread = services.store.getThread(params.threadId);
    if (!thread) {
        sendJson(res, 404, { error: "Thread not found." });
        return;
    }

    const message = typeof body?.message === "string" ? body.message.trim() : "";
    if (!message) {
        sendJson(res, 400, { error: "Field `message` is required." });
        return;
    }

    const note = thread.noteId ? services.store.getNote(thread.noteId) : null;
    const relatedNotes = thread.relatedNoteIds.map((noteId) => services.store.getNote(noteId)).filter(Boolean);
    const existingMessages = services.store.listThreadMessages(thread.id);
    const reply = await services.ai.generateChatReply({
        note,
        message,
        threadMessages: existingMessages,
        relatedNotes
    });

    const createdAt = new Date().toISOString();
    const userMessage = {
        id: randomUUID(),
        threadId: thread.id,
        role: "user",
        text: message,
        provider: "user",
        sources: [],
        createdAt
    };
    const assistantMessage = {
        id: randomUUID(),
        threadId: thread.id,
        role: "assistant",
        text: reply.text,
        provider: reply.provider,
        sources: reply.sources || [],
        createdAt: new Date().toISOString()
    };

    await services.store.transaction((state) => {
        state.messages.push(userMessage, assistantMessage);
        const currentThread = state.threads.find((entry) => entry.id === thread.id);
        currentThread.updatedAt = assistantMessage.createdAt;
        services.store.touchAnalytics("chatCount");
        if (note) {
            const currentNote = state.notes.find((entry) => entry.id === note.id);
            currentNote.latestChatReply = reply.text;
            currentNote.updatedAt = assistantMessage.createdAt;
            services.store.createTimelineEvent(currentNote, "chat_updated", "AI conversation advanced");
        }
    });

    sendJson(res, 201, {
        chat: buildLegacyChat({ thread, noteId: note?.id || null, message, reply }),
        note: note ? decorateNote(services.store.getNote(note.id), services.store, true) : null,
        thread: decorateThread(services.store.getThread(thread.id), services.store),
        messages: [userMessage, assistantMessage]
    });
}

async function handleChat({ res, body, services }) {
    const noteId = typeof body?.noteId === "string" ? body.noteId : null;
    const note = noteId ? services.store.getNote(noteId) : null;
    if (noteId && !note) {
        sendJson(res, 404, { error: "Note not found." });
        return;
    }

    let thread = services.store
        .getState()
        .threads.find((entry) => entry.noteId === noteId && entry.title === "Default note chat");

    if (!thread) {
        const now = new Date().toISOString();
        thread = {
            id: randomUUID(),
            noteId,
            relatedNoteIds: noteId ? [noteId] : [],
            title: "Default note chat",
            createdAt: now,
            updatedAt: now
        };

        await services.store.transaction((state) => {
            state.threads.unshift(thread);
        });
    }

    await handleCreateThreadMessage({
        res,
        params: { threadId: thread.id },
        body,
        services
    });
}

function setCorsHeaders(res) {
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");
    res.setHeader("Access-Control-Allow-Methods", "GET, POST, PATCH, OPTIONS");
}

function sendJson(res, statusCode, data) {
    res.writeHead(statusCode, { "Content-Type": "application/json; charset=utf-8" });
    res.end(JSON.stringify(data, null, 2));
}

async function readJsonBody(req) {
    const chunks = [];
    for await (const chunk of req) {
        chunks.push(chunk);
    }

    if (chunks.length === 0) {
        return null;
    }

    const raw = Buffer.concat(chunks).toString("utf8").trim();
    if (!raw) {
        return null;
    }

    try {
        return JSON.parse(raw);
    } catch {
        const error = new Error("Request body must be valid JSON.");
        error.statusCode = 400;
        throw error;
    }
}

function decorateNote(note, store, includeThreads) {
    if (!note) {
        return null;
    }

    const decorated = {
        ...note,
        relatedNotes: note.links
            .map((link) => ({
                ...link,
                note: store.getNote(link.noteId)
                    ? {
                          id: store.getNote(link.noteId).id,
                          title: store.getNote(link.noteId).title,
                          status: store.getNote(link.noteId).status,
                          updatedAt: store.getNote(link.noteId).updatedAt
                      }
                    : null
            }))
            .filter((link) => link.note)
    };

    if (includeThreads) {
        decorated.threads = store
            .getState()
            .threads.filter((thread) => thread.noteId === note.id || thread.relatedNoteIds.includes(note.id))
            .map((thread) => decorateThread(thread, store));
    }

    return decorated;
}

function decorateThread(thread, store) {
    if (!thread) {
        return null;
    }

    return {
        ...thread,
        messages: store.listThreadMessages(thread.id),
        notes: thread.relatedNoteIds.map((noteId) => {
            const note = store.getNote(noteId);
            return note
                ? {
                      id: note.id,
                      title: note.title,
                      status: note.status
                  }
                : null;
        }).filter(Boolean)
    };
}

function deriveTitle(text) {
    return String(text || "")
        .split(/\s+/)
        .slice(0, 6)
        .join(" ")
        .trim() || "Untitled";
}

function buildLegacyChat({ thread, noteId, message, reply }) {
    return {
        id: thread.id,
        noteId,
        message,
        reply: reply.text,
        provider: reply.provider,
        createdAt: new Date().toISOString()
    };
}
