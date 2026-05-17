import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const backendRoot = path.resolve(__dirname, "..");

export function loadConfig() {
    const env = loadEnv(path.join(backendRoot, ".env"));
    const dataDir = path.join(backendRoot, "data");

    return {
        backendRoot,
        dataDir,
        storePath: path.join(dataDir, "store.json"),
        port: Number(env.PORT || 8787),
        env,
        jobPollIntervalMs: Number(env.JOB_POLL_INTERVAL_MS || 500),
        jobMaxRetries: Number(env.JOB_MAX_RETRIES || 3),
        autoEnrichOnCreate: env.AUTO_ENRICH_ON_CREATE === "true",
        autoEnrichDelayHours: Number(env.AUTO_ENRICH_DELAY_HOURS || 24),
        seedDefaultNotes: env.SEED_DEFAULT_NOTES !== "false",
        aiProvider: normalizeAIProvider(env.AI_PROVIDER),
        searchProvider: normalizeSearchProvider(env.SEARCH_PROVIDER)
    };
}

function normalizeAIProvider(value) {
    const normalized = String(value || "auto").trim().toLowerCase();
    if (["auto", "openai", "cerebras", "mock"].includes(normalized)) {
        return normalized;
    }
    return "auto";
}

function normalizeSearchProvider(value) {
    const normalized = String(value || "none").trim().toLowerCase();
    if (["none", "embedded", "remote"].includes(normalized)) {
        return normalized;
    }
    return "none";
}

function loadEnv(filePath) {
    const values = { ...process.env };

    try {
        const content = readFileSync(filePath, "utf8");
        for (const line of content.split("\n")) {
            const trimmed = line.trim();
            if (!trimmed || trimmed.startsWith("#")) {
                continue;
            }

            const separator = trimmed.indexOf("=");
            if (separator <= 0) {
                continue;
            }

            const key = trimmed.slice(0, separator).trim();
            const value = trimmed.slice(separator + 1).trim();
            values[key] = value;
        }
    } catch {
        // .env is optional.
    }

    return values;
}
