import { randomUUID } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";

export async function createStore({ config, logger }) {
    await mkdir(config.dataDir, { recursive: true });

    let state = await loadState(config.storePath, config, logger);
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

async function loadState(storePath, config, logger) {
    try {
        const raw = await readFile(storePath, "utf8");
        const parsed = JSON.parse(raw);
        const migrated = migrate(parsed, config, logger);
        if (JSON.stringify(parsed) !== JSON.stringify(migrated)) {
            await writeFile(storePath, JSON.stringify(migrated, null, 2));
        }
        return migrated;
    } catch {
        const initial = migrate({}, config, logger);
        await writeFile(storePath, JSON.stringify(initial, null, 2));
        return initial;
    }
}

function migrate(input, config, logger) {
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

    if (state.notes.length === 0 && config.seedDefaultNotes !== false) {
        state.notes = buildDefaultNotes();
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

function buildDefaultNotes() {
    return [
        buildDefaultNote({
            id: "seed-reading-compression",
            title: "Reading is compression. Writing is decompression. The ratio between them tells you how clearly you actually understand something.",
            text: "reading is compression, writing is decompression",
            status: "enriched",
            updatedAt: seedTimestamp(14, 32),
            grownCount: 3,
            growthParagraphs: [
                "When you read, you're absorbing many people's thinking, condensed. When you write, you're forced to unpack a single thread and make it survive daylight. The act of writing reveals where the compression was doing the thinking for you.",
                "A useful test: if you can't decompress an idea into your own words without the scaffolding falling apart, you probably imported the conclusion but not the path.",
                "That makes writing a diagnostic, not just an output format. It exposes whether the idea has actually become yours."
            ],
            prompts: [
                "Is the inverse true — does decompression (writing) actually compress future reading?",
                "What's the equivalent for listening and conversation?",
                "Could this reframe how we evaluate AI-generated summaries?"
            ],
            sources: [
                {
                    title: "Writing and Speaking",
                    url: "https://paulgraham.com/writing44.html",
                    snippet: "Having good ideas is most of writing well. If you know what you're talking about, you can say it in the plainest words.",
                    publisher: "paulgraham.com"
                },
                {
                    title: "The Noncentral Fallacy",
                    url: "https://www.lesswrong.com/posts/2J6iHq8x7P8N6L9XK/the-noncentral-fallacy-the-worst-argument-in-the-world",
                    snippet: "Compression loses information; the question is which information you can afford to lose.",
                    publisher: "lesswrong.com"
                }
            ]
        }),
        buildDefaultNote({
            id: "seed-tool-worldview",
            title: "Every tool quietly teaches you its worldview. Figma teaches layers. Excel teaches tables. What does a feed teach?",
            text: "every tool teaches you a worldview",
            status: "queued",
            updatedAt: seedTimestamp(13, 18),
            grownCount: 2,
            growthParagraphs: [
                "The UI of a tool is its epistemology: the categories it makes easy become the categories you think in.",
                "A feed, for example, may teach recency and reaction before reflection. Over time the interface becomes a quiet tutor for attention itself."
            ]
        }),
        buildDefaultNote({
            id: "seed-taste-pattern-recognition",
            title: "Taste is just pattern recognition across a huge dataset of things you paid full attention to.",
            text: "taste = pattern recognition at scale",
            status: "enriched",
            updatedAt: seedTimestamp(11, 47),
            grownCount: 1,
            growthParagraphs: [
                "Taste compounds when attention gets specific enough to remember structure, not just preference. What feels intuitive later is often the residue of many slow comparisons you once made on purpose."
            ]
        }),
        buildDefaultNote({
            id: "seed-productivity-anxiety",
            title: "Most \"productivity\" advice is actually about managing anxiety, not output.",
            text: "productivity is anxiety management in disguise",
            status: "enriched",
            updatedAt: seedTimestamp(10, 3),
            grownCount: 2,
            growthParagraphs: [
                "A lot of systems promise clarity, but what they really deliver is temporary emotional relief. The ritual matters because it reduces uncertainty, even when it does little to increase the amount of meaningful work that gets finished.",
                "That is why productivity theater can feel effective even when nothing meaningful moved: the system successfully soothed the operator."
            ]
        })
    ];
}

function buildDefaultNote({ id, title, text, status, updatedAt, grownCount, growthParagraphs, prompts = [], sources = [] }) {
    const createdAt = new Date(new Date(updatedAt).getTime() - 15 * 60 * 1000).toISOString();
    const timelineSummary = `Growth ${grownCount}x`;

    return {
        id,
        title,
        text,
        rawText: text,
        status,
        createdAt,
        updatedAt,
        lastEnrichedAt: status === "queued" ? null : updatedAt,
        latestChatReply: null,
        enrichments: growthParagraphs.length
            ? [
                  {
                      id: `${id}-enrichment`,
                      createdAt: updatedAt,
                      provider: "prototype",
                      expansion: growthParagraphs.join("\n\n"),
                      relatedIdeas: [],
                      prompts,
                      links: [],
                      sources: sources.map((source) => ({
                          id: randomUUID(),
                          title: source.title,
                          url: source.url,
                          snippet: source.snippet,
                          publisher: source.publisher || "",
                          query: "",
                          score: 0,
                          retrievedAt: updatedAt
                      }))
                  }
              ]
            : [],
        prompts,
        sources: sources.map((source) => ({
            id: randomUUID(),
            title: source.title,
            url: source.url,
            snippet: source.snippet,
            publisher: source.publisher || "",
            query: "",
            score: 0,
            retrievedAt: updatedAt
        })),
        links: [],
        relatedNoteIds: [],
        timeline: [
            {
                id: `${id}-timeline`,
                type: status === "queued" ? "note_growing" : "note_enriched",
                createdAt: updatedAt,
                summary: timelineSummary
            }
        ],
        revisions: [
            {
                id: `${id}-revision`,
                createdAt,
                type: "user_capture",
                summary: "Initial note capture",
                text
            }
        ]
    };
}

function seedTimestamp(hour, minute) {
    const now = new Date();
    now.setHours(hour, minute, 0, 0);
    return now.toISOString();
}
