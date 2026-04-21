import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, readFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { Readable } from "node:stream";
import { createThinknoteServer } from "../src/app.js";

test("creating a note auto-enqueues and completes enrichment", async () => {
    const app = await createApp();
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

        await app.services.jobs.runDueJobs();
        const noteResponse = await request(app, `/api/notes/${createResponse.json.note.id}`);
        assert.equal(noteResponse.status, 200);
        assert.equal(noteResponse.json.note.status, "enriched");
        assert.ok(noteResponse.json.note.enrichments.length > 0);
        assert.ok(noteResponse.json.note.sources.length > 0);
        assert.ok(noteResponse.json.note.revisions.length >= 2);
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

        const threadsResponse = await request(app, `/api/notes/${noteId}/threads`);
        assert.equal(threadsResponse.status, 200);
        assert.equal(threadsResponse.json.threads.length, 1);
        assert.equal(threadsResponse.json.threads[0].messages.length, 2);
    } finally {
        await app.close();
    }
});

test("related note endpoint returns semantic neighbors after enrichment", async () => {
    const app = await createApp();
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

        await app.services.jobs.runDueJobs();
        await app.services.jobs.runDueJobs();

        const relatedResponse = await request(app, `/api/notes/${second.json.note.id}/related`);
        assert.equal(relatedResponse.status, 200);
        assert.ok(relatedResponse.json.related.length >= 1);
        assert.equal(relatedResponse.json.related[0].note.id, first.json.note.id);
    } finally {
        await app.close();
    }
});

test("store persistence includes richer schema", async () => {
    const app = await createApp();
    try {
        await request(app, "/api/notes", {
            method: "POST",
            body: {
                text: "Observe how richer schema persists revisions, jobs, and threads."
            }
        });

        await app.services.jobs.runDueJobs();
        const raw = await readFile(app.config.storePath, "utf8");
        const parsed = JSON.parse(raw);
        assert.equal(parsed.version, 2);
        assert.ok(Array.isArray(parsed.notes));
        assert.ok(Array.isArray(parsed.jobs));
        assert.ok(Array.isArray(parsed.threads));
        assert.ok(Array.isArray(parsed.messages));
    } finally {
        await app.close();
    }
});

async function createApp() {
    const dataDir = await mkdtemp(path.join(os.tmpdir(), "thinknote-backend-test-"));
    const config = {
        backendRoot: dataDir,
        dataDir,
        storePath: path.join(dataDir, "store.json"),
        port: 0,
        env: {},
        jobPollIntervalMs: 1000000,
        jobMaxRetries: 2,
        autoEnrichOnCreate: true
    };

    const app = await createThinknoteServer({ config, fetchImpl: mockFetch });
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
