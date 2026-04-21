import { randomUUID } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";

export async function createStore({ config, logger }) {
    await mkdir(config.dataDir, { recursive: true });

    let state = await loadState(config.storePath, logger);
    let persistChain = Promise.resolve();

    const store = {
        getState() {
            return state;
        },
        async save() {
            persistChain = persistChain.then(() => writeFile(config.storePath, JSON.stringify(state, null, 2)));
            await persistChain;
        },
        async transaction(mutator) {
            const result = mutator(state);
            await store.save();
            return result;
        },
        getNote(noteId) {
            return state.notes.find((note) => note.id === noteId) || null;
        },
        getJob(jobId) {
            return state.jobs.find((job) => job.id === jobId) || null;
        },
        getThread(threadId) {
            return state.threads.find((thread) => thread.id === threadId) || null;
        },
        listThreadMessages(threadId) {
            return state.messages
                .filter((message) => message.threadId === threadId)
                .sort((left, right) => left.createdAt.localeCompare(right.createdAt));
        },
        createTimelineEvent(note, type, summary, extra = {}) {
            note.timeline.unshift({
                id: randomUUID(),
                type,
                createdAt: new Date().toISOString(),
                summary,
                ...extra
            });
        },
        touchAnalytics(name) {
            state.analytics[name] = (state.analytics[name] || 0) + 1;
        }
    };

    return store;
}

async function loadState(storePath, logger) {
    try {
        const raw = await readFile(storePath, "utf8");
        return migrate(JSON.parse(raw), logger);
    } catch {
        const initial = migrate({}, logger);
        await writeFile(storePath, JSON.stringify(initial, null, 2));
        return initial;
    }
}

function migrate(input, logger) {
    const source = input && typeof input === "object" ? input : {};
    const state = {
        version: 2,
        notes: Array.isArray(source.notes) ? source.notes.map(migrateNote) : [],
        jobs: Array.isArray(source.jobs) ? source.jobs.map(migrateJob) : [],
        threads: Array.isArray(source.threads) ? source.threads.map(migrateThread) : [],
        messages: Array.isArray(source.messages) ? source.messages.map(migrateMessage) : [],
        analytics: source.analytics && typeof source.analytics === "object" ? source.analytics : {}
    };

    if (Array.isArray(source.chats) && source.chats.length > 0) {
        for (const chat of source.chats) {
            const threadId = randomUUID();
            state.threads.push({
                id: threadId,
                noteId: typeof chat.noteId === "string" ? chat.noteId : null,
                relatedNoteIds: typeof chat.noteId === "string" ? [chat.noteId] : [],
                title: "Migrated conversation",
                createdAt: chat.createdAt || new Date().toISOString(),
                updatedAt: chat.createdAt || new Date().toISOString()
            });
            state.messages.push(
                {
                    id: randomUUID(),
                    threadId,
                    role: "user",
                    text: chat.message || "",
                    provider: "user",
                    sources: [],
                    createdAt: chat.createdAt || new Date().toISOString()
                },
                {
                    id: randomUUID(),
                    threadId,
                    role: "assistant",
                    text: chat.reply || "",
                    provider: chat.provider || "mock",
                    sources: [],
                    createdAt: chat.createdAt || new Date().toISOString()
                }
            );
        }
        logger.info("store_migrated_chats", { count: source.chats.length });
    }

    return state;
}

function migrateNote(note) {
    const createdAt = note.createdAt || new Date().toISOString();
    const updatedAt = note.updatedAt || createdAt;
    const rawText = typeof note.rawText === "string" ? note.rawText : note.text || "";

    return {
        id: note.id || randomUUID(),
        title: typeof note.title === "string" && note.title.trim() ? note.title.trim() : deriveTitle(rawText),
        text: rawText,
        rawText,
        status: note.status || "captured",
        createdAt,
        updatedAt,
        lastEnrichedAt: note.lastEnrichedAt || null,
        latestChatReply: typeof note.latestChatReply === "string" ? note.latestChatReply : null,
        enrichments: Array.isArray(note.enrichments) ? note.enrichments : [],
        prompts: Array.isArray(note.prompts) ? note.prompts : [],
        sources: Array.isArray(note.sources) ? note.sources.map(migrateSource) : [],
        links: Array.isArray(note.links) ? note.links.map(migrateLink) : [],
        relatedNoteIds: Array.isArray(note.relatedNoteIds) ? note.relatedNoteIds : [],
        timeline: Array.isArray(note.timeline) ? note.timeline : [],
        revisions: Array.isArray(note.revisions)
            ? note.revisions
            : [
                  {
                      id: randomUUID(),
                      createdAt,
                      type: "user_capture",
                      summary: "Initial note capture",
                      text: rawText
                  }
              ]
    };
}

function migrateJob(job) {
    const createdAt = job.createdAt || new Date().toISOString();
    return {
        id: job.id || randomUUID(),
        noteId: job.noteId || null,
        type: job.type || "enrich_note",
        status: job.status || "queued",
        triggerSource: job.triggerSource || "unknown",
        payload: job.payload && typeof job.payload === "object" ? job.payload : {},
        retryCount: Number(job.retryCount || 0),
        maxRetries: Number(job.maxRetries || 3),
        lastError: typeof job.lastError === "string" ? job.lastError : null,
        output: job.output && typeof job.output === "object" ? job.output : null,
        createdAt,
        updatedAt: job.updatedAt || createdAt,
        startedAt: job.startedAt || null,
        completedAt: job.completedAt || null,
        nextRunAt: job.nextRunAt || createdAt
    };
}

function migrateThread(thread) {
    const createdAt = thread.createdAt || new Date().toISOString();
    return {
        id: thread.id || randomUUID(),
        noteId: typeof thread.noteId === "string" ? thread.noteId : null,
        relatedNoteIds: Array.isArray(thread.relatedNoteIds) ? thread.relatedNoteIds : thread.noteId ? [thread.noteId] : [],
        title: typeof thread.title === "string" ? thread.title : "Conversation",
        createdAt,
        updatedAt: thread.updatedAt || createdAt
    };
}

function migrateMessage(message) {
    return {
        id: message.id || randomUUID(),
        threadId: message.threadId,
        role: message.role || "assistant",
        text: typeof message.text === "string" ? message.text : "",
        provider: typeof message.provider === "string" ? message.provider : "mock",
        sources: Array.isArray(message.sources) ? message.sources.map(migrateSource) : [],
        createdAt: message.createdAt || new Date().toISOString()
    };
}

function migrateSource(source) {
    return {
        id: source.id || randomUUID(),
        title: typeof source.title === "string" ? source.title : "Untitled source",
        url: typeof source.url === "string" ? source.url : "",
        snippet: typeof source.snippet === "string" ? source.snippet : "",
        publisher: typeof source.publisher === "string" ? source.publisher : "",
        query: typeof source.query === "string" ? source.query : "",
        score: Number(source.score || 0),
        retrievedAt: source.retrievedAt || new Date().toISOString()
    };
}

function migrateLink(link) {
    return {
        id: link.id || randomUUID(),
        noteId: typeof link.noteId === "string" ? link.noteId : null,
        title: typeof link.title === "string" ? link.title : "Related note",
        relationship: typeof link.relationship === "string" ? link.relationship : "related",
        confidence: Number(link.confidence || 0),
        summary: typeof link.summary === "string" ? link.summary : ""
    };
}

function deriveTitle(text) {
    return String(text || "")
        .split(/\s+/)
        .slice(0, 6)
        .join(" ")
        .trim() || "Untitled";
}
