import { randomUUID } from "node:crypto";

export function createAIOrchestrator({ config, logger, retrieval, fetchImpl = fetch }) {
    const llmConfig = resolveLLMConfig(config);
    const providerName = llmConfig.provider;

    return {
        providerName,
        async generateEnrichment({ note, focus = "", includeWeb = true, relatedNotes = [] }) {
            const retrievalBundle = includeWeb ? await retrieval.retrieve({ note, focus, limit: 3 }) : { query: "", results: [] };

            if (llmConfig.provider === "mock") {
                return generateMockEnrichment({ note, focus, relatedNotes, retrievalBundle });
            }

            if (llmConfig.provider === "unconfigured") {
                throw new Error(llmConfig.detail);
            }

            return generateEnrichmentWithLLM({
                note,
                focus,
                relatedNotes,
                retrievalBundle,
                llmConfig,
                fetchImpl
            });
        },
        async generateChatReply({ note, message, threadMessages = [], relatedNotes = [] }) {
            if (llmConfig.provider === "mock") {
                return {
                    provider: "mock",
                    text: buildMockChatReply({ note, message, threadMessages, relatedNotes }),
                    sources: []
                };
            }

            if (llmConfig.provider === "unconfigured") {
                throw new Error(llmConfig.detail);
            }

            return generateChatReplyWithLLM({
                note,
                message,
                threadMessages,
                relatedNotes,
                llmConfig,
                fetchImpl
            });
        }
    };
}

async function generateEnrichmentWithLLM({ note, focus, relatedNotes, retrievalBundle, llmConfig, fetchImpl }) {
    const prompt = buildEnrichmentPrompt({ note, focus, relatedNotes, retrievalBundle });
    const json = llmConfig.provider === "cerebras"
        ? await callCerebrasForJSON({ llmConfig, fetchImpl, prompt })
        : await callOpenAIResponses({ llmConfig, fetchImpl, input: prompt });
    const parsed = JSON.parse(json);

    return {
        provider: llmConfig.provider,
        headline: normalizeHeadline(parsed.headline, note),
        growthParagraphs: normalizeGrowthParagraphs(parsed.growthParagraphs),
        timelineSummary: normalizeTimelineSummary(parsed.timelineSummary),
        relatedIdeas: toStringArray(parsed.relatedIdeas),
        prompts: toStringArray(parsed.prompts),
        sources: normalizeSources(parsed.sources, retrievalBundle.results)
    };
}

async function generateChatReplyWithLLM({ note, message, threadMessages, relatedNotes, llmConfig, fetchImpl }) {
    const prompt = buildChatPrompt({ note, message, threadMessages, relatedNotes });
    const text = llmConfig.provider === "cerebras"
        ? await callCerebrasForText({ llmConfig, fetchImpl, prompt })
        : await callOpenAIResponses({ llmConfig, fetchImpl, input: prompt });

    return {
        provider: llmConfig.provider,
        text,
        sources: []
    };
}

async function callOpenAIResponses({ llmConfig, fetchImpl, input }) {
    const response = await fetchImpl(`${llmConfig.baseURL}/responses`, {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${llmConfig.apiKey}`
        },
        body: JSON.stringify({
            model: llmConfig.model,
            input,
            text: {
                format: {
                    type: "text"
                }
            }
        })
    });

    if (!response.ok) {
        const detail = await safeReadText(response);
        throw new Error(`OpenAI request failed with status ${response.status}${detail ? `: ${detail}` : ""}`);
    }

    const payload = await response.json();
    const text = extractOpenAIText(payload);

    if (typeof text !== "string" || !text.trim()) {
        throw new Error(`${llmConfig.provider} response did not include output_text`);
    }

    return text.trim();
}

async function safeReadText(response) {
    try {
        return (await response.text()).trim();
    } catch {
        return "";
    }
}

function extractOpenAIText(payload) {
    if (typeof payload?.output_text === "string" && payload.output_text.trim()) {
        return payload.output_text.trim();
    }

    if (!Array.isArray(payload?.output)) {
        return "";
    }

    const parts = [];
    for (const item of payload.output) {
        if (!Array.isArray(item?.content)) {
            continue;
        }

        for (const contentItem of item.content) {
            if (typeof contentItem?.text === "string" && contentItem.text.trim()) {
                parts.push(contentItem.text.trim());
            }
        }
    }

    return parts.join("\n").trim();
}

async function callCerebrasForJSON({ llmConfig, fetchImpl, prompt }) {
    const payload = await callCerebrasChatCompletions({
        llmConfig,
        fetchImpl,
        messages: [{ role: "user", content: prompt }],
        responseFormat: { type: "json_object" }
    });
    const text = payload?.choices?.[0]?.message?.content;
    if (typeof text !== "string" || !text.trim()) {
        throw new Error("cerebras chat completion did not include JSON content");
    }
    return text.trim();
}

async function callCerebrasForText({ llmConfig, fetchImpl, prompt }) {
    const payload = await callCerebrasChatCompletions({
        llmConfig,
        fetchImpl,
        messages: [{ role: "user", content: prompt }]
    });
    const text = payload?.choices?.[0]?.message?.content;
    if (typeof text !== "string" || !text.trim()) {
        throw new Error("cerebras chat completion did not include text content");
    }
    return text.trim();
}

async function callCerebrasChatCompletions({ llmConfig, fetchImpl, messages, responseFormat }) {
    const response = await fetchImpl(`${llmConfig.baseURL}/chat/completions`, {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${llmConfig.apiKey}`
        },
        body: JSON.stringify({
            model: llmConfig.model,
            messages,
            ...(responseFormat ? { response_format: responseFormat } : {})
        })
    });

    if (!response.ok) {
        throw new Error(`Cerebras request failed with status ${response.status}`);
    }

    return response.json();
}

function resolveLLMConfig(config) {
    const configuredProvider = config.aiProvider || "auto";

    if (configuredProvider === "mock") {
        return { provider: "mock" };
    }

    if (configuredProvider === "openai") {
        return buildOpenAIConfig(config) || {
            provider: "unconfigured",
            detail: "OpenAI is selected but OPENAI_API_KEY is missing."
        };
    }

    if (configuredProvider === "cerebras") {
        return buildCerebrasConfig(config) || {
            provider: "unconfigured",
            detail: "Cerebras is selected but CEREBRAS_API_KEY is missing."
        };
    }

    return buildOpenAIConfig(config) || buildCerebrasConfig(config) || {
        provider: "unconfigured",
        detail: "No AI provider is configured. Set AI_PROVIDER=mock for development or configure OpenAI/Cerebras keys."
    };
}

function buildOpenAIConfig(config) {
    const apiKey = String(config.env.OPENAI_API_KEY || "").trim();
    if (!apiKey) {
        return null;
    }

    return {
        provider: "openai",
        apiKey,
        model: String(config.env.OPENAI_MODEL || "gpt-4.1-mini").trim(),
        baseURL: stripTrailingSlash(String(config.env.OPENAI_BASE_URL || "https://api.openai.com/v1").trim())
    };
}

function buildCerebrasConfig(config) {
    const apiKey = String(config.env.CEREBRAS_API_KEY || "").trim();
    if (!apiKey) {
        return null;
    }

    return {
        provider: "cerebras",
        apiKey,
        model: String(config.env.CEREBRAS_MODEL || "gpt-oss-120b").trim(),
        baseURL: stripTrailingSlash(String(config.env.CEREBRAS_BASE_URL || "https://api.cerebras.ai/v1").trim())
    };
}

function stripTrailingSlash(value) {
    return value.replace(/\/+$/, "");
}

function buildEnrichmentPrompt({ note, focus, relatedNotes, retrievalBundle }) {
    return [
        "You are Thinknote's backend enrichment service.",
        "Return valid JSON only.",
        "Schema:",
        "{",
        '  "headline": "string",',
        '  "growthParagraphs": ["string"],',
        '  "timelineSummary": "string",',
        '  "relatedIdeas": ["string"],',
        '  "prompts": ["string"],',
        '  "sources": [{ "title": "string", "url": "string", "snippet": "string", "publisher": "string" }]',
        "}",
        "Rules:",
        "- Never rewrite or replace the user's raw note text.",
        "- `headline` should be a lightly polished top line, close to the original wording, under 90 characters, and never use an ellipsis.",
        "- `growthParagraphs` should be 1 to 3 appended paragraphs of development.",
        "- `timelineSummary` should be a short phrase describing what changed.",
        `Focus area: ${focus || "general idea development"}`,
        `Note title: ${note.title}`,
        `Note text: ${note.rawText || note.text}`,
        `Related notes: ${JSON.stringify(relatedNotes.slice(0, 3).map(toCompactNote))}`,
        `Retrieved sources: ${JSON.stringify(retrievalBundle.results.map(toCompactSource))}`
    ].join("\n");
}

function buildChatPrompt({ note, message, threadMessages, relatedNotes }) {
    return [
        "You are Thinknote, a concise collaborator for idea development.",
        "Reply in plain text.",
        note ? `Current note: ${JSON.stringify(toCompactNote(note))}` : "No note context provided.",
        `Recent thread messages: ${JSON.stringify(threadMessages.slice(-6).map((item) => ({ role: item.role, text: item.text })))}`,
        `Related notes: ${JSON.stringify(relatedNotes.slice(0, 3).map(toCompactNote))}`,
        `User message: ${message}`
    ].join("\n");
}

function generateMockEnrichment({ note, focus, relatedNotes, retrievalBundle }) {
    const root = note.rawText.length > 180 ? `${note.rawText.slice(0, 180)}...` : note.rawText;
    const sourceTitles = retrievalBundle.results.map((source) => source.title).slice(0, 2);
    const growthParagraphs = [
        `This note points toward a stronger claim: ${root} A useful next step is to name the tension inside the idea, then decide what evidence or example would make it feel real.` +
            (sourceTitles.length > 0 ? ` Nearby references suggest themes from ${sourceTitles.join(" and ")}.` : ""),
        focus
            ? `If you keep developing it through the lens of ${focus}, the note becomes more actionable because it stops being a mood and starts becoming a decision.`
            : "What makes the note valuable is not just the observation itself, but the decision or experiment it could unlock once the idea is made more explicit."
    ].filter(Boolean);

    return {
        provider: "mock",
        headline: normalizeHeadline(note.title, note),
        growthParagraphs,
        timelineSummary: "New growth added",
        relatedIdeas: [
            focus ? `What changes if you push this note further through the lens of ${focus}?` : "What hidden assumption is carrying this thought?",
            relatedNotes[0]
                ? `How does this note reinforce or challenge "${relatedNotes[0].title}"?`
                : "What earlier note might disagree with this idea in a productive way?",
            "If this became a project this week, what is the smallest visible action?"
        ],
        prompts: [
            "What do you believe now that you could not say clearly when you first captured this thought?",
            "Which source, example, or observation would make the idea more grounded?",
            "What unresolved question should stay attached to this note?"
        ],
        sources: retrievalBundle.results.map((source) => ({
            id: source.id || randomUUID(),
            title: source.title,
            url: source.url,
            snippet: source.snippet,
            publisher: source.publisher,
            query: source.query,
            score: source.score,
            retrievedAt: source.retrievedAt
        }))
    };
}

function buildMockChatReply({ note, message, threadMessages, relatedNotes }) {
    const threadCount = threadMessages.length;
    const relatedHint = relatedNotes[0] ? ` It may also connect to "${relatedNotes[0].title}".` : "";

    if (note) {
        return `You are exploring "${note.title}". I would tighten this into one claim, one tension, and one next experiment. Based on "${message}", start by clarifying why it matters now.${relatedHint} We already have ${threadCount} message${threadCount === 1 ? "" : "s"} in this thread, so keep pushing the same line of thought instead of restarting from scratch.`;
    }

    return `A strong next move is to turn your message into a note with three parts: observation, why it matters, and open question. Based on "${message}", begin by naming the tension that makes the idea worth keeping.`;
}

function toCompactNote(note) {
    return {
        id: note.id,
        title: note.title,
        text: note.rawText || note.text
    };
}

function toCompactSource(source) {
    return {
        title: source.title,
        url: source.url,
        snippet: source.snippet,
        publisher: source.publisher
    };
}

function toStringArray(value) {
    return Array.isArray(value) ? value.filter((item) => typeof item === "string") : [];
}

function normalizeSources(value, fallbackSources) {
    if (!Array.isArray(value) || value.length === 0) {
        return fallbackSources.map((source) => ({
            id: source.id || randomUUID(),
            title: source.title,
            url: source.url,
            snippet: source.snippet,
            publisher: source.publisher,
            query: source.query,
            score: source.score,
            retrievedAt: source.retrievedAt
        }));
    }

    return value
        .filter((item) => item && typeof item === "object")
        .map((item, index) => ({
            id: typeof item.id === "string" ? item.id : `source-${index + 1}`,
            title: typeof item.title === "string" ? item.title : fallbackSources[index]?.title || "Untitled source",
            url: typeof item.url === "string" ? item.url : fallbackSources[index]?.url || "",
            snippet: typeof item.snippet === "string" ? item.snippet : fallbackSources[index]?.snippet || "",
            publisher: typeof item.publisher === "string" ? item.publisher : fallbackSources[index]?.publisher || "",
            query: fallbackSources[index]?.query || "",
            score: Number(item.score || fallbackSources[index]?.score || 0),
            retrievedAt: fallbackSources[index]?.retrievedAt || new Date().toISOString()
        }));
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

function normalizeGrowthParagraphs(value) {
    const paragraphs = Array.isArray(value)
        ? value.filter((item) => typeof item === "string").map((item) => item.trim()).filter(Boolean)
        : [];

    return paragraphs.slice(0, 3);
}

function normalizeTimelineSummary(value) {
    if (typeof value !== "string" || !value.trim()) {
        return "New growth added";
    }

    return value.trim().replace(/\s+/g, " ").slice(0, 80);
}
