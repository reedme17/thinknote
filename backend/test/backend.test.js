import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, readFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { Readable } from "node:stream";
import { createThinknoteServer } from "../src/app.js";

test("creating a note auto-enqueues and completes enrichment", async () => {
    const app = await createApp({ autoEnrichOnCreate: true, autoEnrichDelayHours: 0 });
    try {
        const createResponse = await request(app, "/api/notes", {
            method: "POST",
            body: {
                title: "Idea garden",
                text: "Thinknote should help unfinished thoughts mature quietly in the background."
            }
        });

        assert.equal(createResponse.status, 201);
        assert.equal(createResponse.json.note.status, "queued");
        assert.ok(createResponse.json.job.id);
        assert.equal(createResponse.json.job.priority, "background");

        await app.services.jobs.runDueJobs(new Date());
        const noteResponse = await request(app, `/api/notes/${createResponse.json.note.id}`);
        assert.equal(noteResponse.status, 200);
        assert.equal(noteResponse.json.note.status, "enriched");
        assert.equal(noteResponse.json.note.rawText, "Thinknote should help unfinished thoughts mature quietly in the background.");
        assert.ok(noteResponse.json.note.enrichments.length > 0);
        assert.ok(noteResponse.json.note.enrichments[0].headline.length > 0);
        assert.ok(noteResponse.json.note.enrichments[0].growthParagraphs.length > 0);
        assert.ok(noteResponse.json.note.sources.length > 0);
        assert.ok(noteResponse.json.note.revisions.length >= 2);
    } finally {
        await app.close();
    }
});

test("manual enrichment can be scheduled for later without mutating raw text", async () => {
    const app = await createApp();
    try {
        const createResponse = await request(app, "/api/notes", {
            method: "POST",
            body: {
                text: "A note should stay raw while background growth appends a better headline later."
            }
        });

        const noteId = createResponse.json.note.id;
        const future = new Date(Date.now() + 60 * 60 * 1000).toISOString();
        const enqueueResponse = await request(app, `/api/notes/${noteId}/enrich`, {
            method: "POST",
            body: {
                wait: false,
                earliestRunAt: future,
                priority: "background"
            }
        });

        assert.equal(enqueueResponse.status, 202);
        assert.equal(enqueueResponse.json.job.earliestRunAt, future);
        assert.equal(enqueueResponse.json.job.priority, "background");

        await app.services.jobs.runDueJobs(new Date());
        let noteResponse = await request(app, `/api/notes/${noteId}`);
        assert.equal(noteResponse.json.note.status, "queued");
        assert.equal(noteResponse.json.note.rawText, "A note should stay raw while background growth appends a better headline later.");

        await app.services.jobs.runDueJobs(new Date(Date.now() + 2 * 60 * 60 * 1000));
        noteResponse = await request(app, `/api/notes/${noteId}`);
        assert.equal(noteResponse.json.note.status, "enriched");
        assert.equal(noteResponse.json.note.rawText, "A note should stay raw while background growth appends a better headline later.");
        assert.ok(noteResponse.json.note.title.length > 0);
        assert.ok(noteResponse.json.note.enrichments[0].growthParagraphs.length > 0);
    } finally {
        await app.close();
    }
});

test("patching a note creates a user revision", async () => {
    const app = await createApp();
    try {
        const createResponse = await request(app, "/api/notes", {
            method: "POST",
            body: {
                text: "A note about semantic links between ideas."
            }
        });

        const noteId = createResponse.json.note.id;
        const updateResponse = await request(app, `/api/notes/${noteId}`, {
            method: "PATCH",
            body: {
                title: "Updated title",
                text: "A better note about semantic links between notes and related themes."
            }
        });

        assert.equal(updateResponse.status, 200);
        assert.equal(updateResponse.json.note.title, "Updated title");
        assert.equal(updateResponse.json.note.revisions[0].type, "user_edit");
    } finally {
        await app.close();
    }
});

test("posting a note with the same client id upserts remote state", async () => {
    const app = await createApp();
    try {
        const first = await request(app, "/api/notes", {
            method: "POST",
            body: {
                id: "client-note-1",
                title: "Original title",
                text: "original text"
            }
        });

        const second = await request(app, "/api/notes", {
            method: "POST",
            body: {
                id: "client-note-1",
                title: "Updated title",
                text: "updated text"
            }
        });

        assert.equal(first.status, 201);
        assert.equal(second.status, 200);
        assert.equal(second.json.note.id, "client-note-1");
        assert.equal(second.json.note.title, "Updated title");
        assert.equal(second.json.note.rawText, "updated text");
    } finally {
        await app.close();
    }
});

test("chat endpoint persists multi-turn thread messages", async () => {
    const app = await createApp();
    try {
        const createResponse = await request(app, "/api/notes", {
            method: "POST",
            body: {
                text: "Users should move smoothly from canvas to conversation to saved note."
            }
        });

        const noteId = createResponse.json.note.id;
        const chatResponse = await request(app, "/api/chat", {
            method: "POST",
            body: {
                noteId,
                message: "Help sharpen this into a product thesis."
            }
        });

        assert.equal(chatResponse.status, 201);
        assert.equal(chatResponse.json.messages.length, 2);
        assert.equal(chatResponse.json.note.id, noteId);

        const threadsResponse = await request(app, `/api/notes/${noteId}/threads`);
        assert.equal(threadsResponse.status, 200);
        assert.equal(threadsResponse.json.threads.length, 1);
        assert.equal(threadsResponse.json.threads[0].messages.length, 2);
    } finally {
        await app.close();
    }
});

test("related note endpoint returns semantic neighbors after enrichment", async () => {
    const app = await createApp({ autoEnrichOnCreate: true, autoEnrichDelayHours: 0 });
    try {
        const first = await request(app, "/api/notes", {
            method: "POST",
            body: {
                text: "A note about unfinished ideas becoming a connected knowledge garden."
            }
        });
        const second = await request(app, "/api/notes", {
            method: "POST",
            body: {
                text: "A note about connecting related thoughts into a personal knowledge garden."
            }
        });

        await app.services.jobs.runDueJobs(new Date());
        await app.services.jobs.runDueJobs(new Date());

        const relatedResponse = await request(app, `/api/notes/${second.json.note.id}/related`);
        assert.equal(relatedResponse.status, 200);
        assert.ok(relatedResponse.json.related.length >= 1);
        assert.equal(relatedResponse.json.related[0].note.id, first.json.note.id);
    } finally {
        await app.close();
    }
});

test("store persistence includes richer schema", async () => {
    const app = await createApp({ autoEnrichOnCreate: true, autoEnrichDelayHours: 0 });
    try {
        await request(app, "/api/notes", {
            method: "POST",
            body: {
                text: "Observe how richer schema persists revisions, jobs, and threads."
            }
        });

        await app.services.jobs.runDueJobs(new Date());
        const raw = await readFile(app.config.storePath, "utf8");
        const parsed = JSON.parse(raw);
        assert.equal(parsed.version, 3);
        assert.ok(Array.isArray(parsed.notes));
        assert.ok(Array.isArray(parsed.jobs));
        assert.ok(Array.isArray(parsed.threads));
        assert.ok(Array.isArray(parsed.messages));
        assert.equal(parsed.jobs[0].priority, "background");
        assert.ok(typeof parsed.jobs[0].earliestRunAt === "string");
        assert.ok(Array.isArray(parsed.notes[0].enrichments[0].growthParagraphs));
    } finally {
        await app.close();
    }
});

test("health reports openai provider when configured", async () => {
    const app = await createApp({
        env: {
            AI_PROVIDER: "openai",
            OPENAI_API_KEY: "test-openai-key"
        }
    });
    try {
        const healthResponse = await request(app, "/health");
        assert.equal(healthResponse.status, 200);
        assert.equal(healthResponse.json.provider, "openai");
    } finally {
        await app.close();
    }
});

test("health reports cerebras provider when configured", async () => {
    const app = await createApp({
        env: {
            AI_PROVIDER: "cerebras",
            CEREBRAS_API_KEY: "test-cerebras-key"
        }
    });
    try {
        const healthResponse = await request(app, "/health");
        assert.equal(healthResponse.status, 200);
        assert.equal(healthResponse.json.provider, "cerebras");
    } finally {
        await app.close();
    }
});

test("openai provider uses responses API for enrichment", async () => {
    const requestedUrls = [];
    const app = await createApp(
        {
            env: {
                AI_PROVIDER: "openai",
                OPENAI_API_KEY: "test-openai-key",
                OPENAI_BASE_URL: "https://api.openai.test/v1"
            }
        },
        async (url) => {
            requestedUrls.push(String(url));
            return {
                ok: true,
                status: 200,
                async json() {
                    return {
                        output_text: JSON.stringify({
                            headline: "A quieter background growth loop.",
                            growthParagraphs: ["This is one appended paragraph."],
                            timelineSummary: "Growth added",
                            relatedIdeas: [],
                            prompts: [],
                            sources: []
                        })
                    };
                }
            };
        }
    );

    try {
        const result = await app.services.ai.generateEnrichment({
            note: { id: "n1", title: "Original", rawText: "Original raw text", text: "Original raw text" },
            focus: "",
            relatedNotes: []
        });

        assert.equal(result.provider, "openai");
        assert.equal(requestedUrls[0], "https://api.openai.test/v1/responses");
    } finally {
        await app.close();
    }
});

test("cerebras provider uses chat completions API for enrichment", async () => {
    const requestedUrls = [];
    const app = await createApp(
        {
            env: {
                AI_PROVIDER: "cerebras",
                CEREBRAS_API_KEY: "test-cerebras-key",
                CEREBRAS_BASE_URL: "https://api.cerebras.test/v1"
            }
        },
        async (url) => {
            requestedUrls.push(String(url));
            return {
                ok: true,
                status: 200,
                async json() {
                    return {
                        choices: [
                            {
                                message: {
                                    content: JSON.stringify({
                                        headline: "A quieter background growth loop.",
                                        growthParagraphs: ["This is one appended paragraph."],
                                        timelineSummary: "Growth added",
                                        relatedIdeas: [],
                                        prompts: [],
                                        sources: []
                                    })
                                }
                            }
                        ]
                    };
                }
            };
        }
    );

    try {
        const result = await app.services.ai.generateEnrichment({
            note: { id: "n1", title: "Original", rawText: "Original raw text", text: "Original raw text" },
            focus: "",
            relatedNotes: []
        });

        assert.equal(result.provider, "cerebras");
        assert.equal(requestedUrls[0], "https://api.cerebras.test/v1/chat/completions");
    } finally {
        await app.close();
    }
});

test("unconfigured provider surfaces an error instead of returning mock enrichment", async () => {
    const app = await createApp({ env: { AI_PROVIDER: "auto" } });
    try {
        await assert.rejects(
            () =>
                app.services.ai.generateEnrichment({
                    note: { id: "n1", title: "Original", rawText: "Original raw text", text: "Original raw text" },
                    focus: "",
                    relatedNotes: []
                }),
            /No AI provider is configured/
        );
    } finally {
        await app.close();
    }
});

test("waited enrichment returns an error when the AI provider fails", async () => {
    const app = await createApp(
        {
            env: {
                AI_PROVIDER: "openai",
                OPENAI_API_KEY: "test-openai-key",
                SEARCH_PROVIDER: "none"
            },
            jobMaxRetries: 0
        },
        async () => ({
            ok: false,
            status: 503,
            async text() {
                return "provider unavailable";
            }
        })
    );

    try {
        const createResponse = await request(app, "/api/notes", {
            method: "POST",
            body: {
                text: "A note that should fail honestly."
            }
        });

        const enrichResponse = await request(app, `/api/notes/${createResponse.json.note.id}/enrich`, {
            method: "POST",
            body: { wait: true }
        });

        assert.equal(enrichResponse.status, 502);
        assert.match(enrichResponse.json.error, /AI response unavailable/i);
    } finally {
        await app.close();
    }
});

async function createApp(overrides = {}, fetchImpl = mockFetch) {
    const dataDir = await mkdtemp(path.join(os.tmpdir(), "thinknote-backend-test-"));
    const overrideEnv = overrides.env || {};
    const { env: _, ...restOverrides } = overrides;
    const config = {
        backendRoot: dataDir,
        dataDir,
        storePath: path.join(dataDir, "store.json"),
        port: 0,
        env: {
            AI_PROVIDER: "mock",
            SEARCH_PROVIDER: "embedded",
            ...overrideEnv
        },
        aiProvider: String(overrideEnv.AI_PROVIDER || "mock").trim().toLowerCase(),
        searchProvider: String(overrideEnv.SEARCH_PROVIDER || "embedded").trim().toLowerCase(),
        jobPollIntervalMs: 1000000,
        jobMaxRetries: 2,
        autoEnrichOnCreate: false,
        autoEnrichDelayHours: 24,
        seedDefaultNotes: false,
        ...restOverrides
    };

    const app = await createThinknoteServer({ config, fetchImpl });
    app.config = config;
    return app;
}

async function request(app, pathName, { method = "GET", body } = {}) {
    const payload = body ? JSON.stringify(body) : "";
    const req = Readable.from(payload ? [Buffer.from(payload)] : []);
    req.method = method;
    req.url = pathName;
    req.headers = {
        host: "localhost",
        "content-type": "application/json"
    };

    const chunks = [];
    let resolveEnd;
    const ended = new Promise((resolve) => {
        resolveEnd = resolve;
    });

    const res = {
        statusCode: 200,
        headers: {},
        setHeader(name, value) {
            this.headers[name] = value;
        },
        writeHead(statusCode, headers = {}) {
            this.statusCode = statusCode;
            Object.assign(this.headers, headers);
        },
        end(value) {
            if (value) {
                chunks.push(Buffer.isBuffer(value) ? value : Buffer.from(String(value)));
            }
            resolveEnd();
        }
    };

    await app.handleRequest(req, res);
    await ended;
    const text = Buffer.concat(chunks).toString("utf8");
    return {
        status: res.statusCode,
        json: text ? JSON.parse(text) : null
    };
}

async function mockFetch() {
    return {
        ok: false,
        status: 500,
        async json() {
            return {};
        }
    };
}
