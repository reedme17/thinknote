import { randomUUID } from "node:crypto";

const ENRICHMENT_TEXT_FORMAT = {
    type: "json_schema",
    name: "thinknote_enrichment",
    strict: true,
    schema: {
        type: "object",
        additionalProperties: false,
        required: ["headline", "growthParagraphs", "timelineSummary", "relatedIdeas", "prompts", "sources", "followUpContext"],
        properties: {
            headline: { type: "string" },
            growthParagraphs: {
                type: "array",
                maxItems: 3,
                items: { type: "string" }
            },
            timelineSummary: { type: "string" },
            relatedIdeas: {
                type: "array",
                items: { type: "string" }
            },
            prompts: {
                type: "array",
                items: { type: "string" }
            },
            sources: {
                type: "array",
                items: {
                    type: "object",
                    additionalProperties: false,
                    required: ["title", "url", "snippet", "publisher"],
                    properties: {
                        title: { type: "string" },
                        url: { type: "string" },
                        snippet: { type: "string" },
                        publisher: { type: "string" }
                    }
                }
            },
            followUpContext: {
                anyOf: [
                    { type: "null" },
                    {
                        type: "object",
                        additionalProperties: false,
                        required: ["prefix", "highlight", "suffix"],
                        properties: {
                            prefix: { type: "string" },
                            highlight: { type: "string" },
                            suffix: { type: "string" }
                        }
                    }
                ]
            }
        }
    }
};

export function createAIOrchestrator({ config, logger, retrieval, fetchImpl = fetch }) {
    const llmConfig = resolveLLMConfig(config);
    const providerName = llmConfig.provider;

    return {
        providerName,
        async generateEnrichment({ note, focus = "", includeWeb = true, relatedNotes = [], followUpGuidance = "" }) {
            const retrievalBundle = includeWeb ? await retrieval.retrieve({ note, focus, limit: 3 }) : { query: "", results: [] };

            if (llmConfig.provider === "mock") {
                return generateMockEnrichment({ note, focus, relatedNotes, retrievalBundle, followUpGuidance });
            }

            if (llmConfig.provider === "unconfigured") {
                throw new Error(llmConfig.detail);
            }

            return generateEnrichmentWithLLM({
                note,
                focus,
                relatedNotes,
                retrievalBundle,
                followUpGuidance,
                llmConfig,
                logger,
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
                logger,
                fetchImpl
            });
        }
    };
}

async function generateEnrichmentWithLLM({ note, focus, relatedNotes, retrievalBundle, followUpGuidance, llmConfig, logger, fetchImpl }) {
    const prompt = buildEnrichmentPrompt({ note, focus, relatedNotes, retrievalBundle, followUpGuidance });
    const completion = llmConfig.provider === "cerebras"
        ? { text: await callCerebrasForJSON({ llmConfig, fetchImpl, prompt }), model: llmConfig.model }
        : await callOpenAIResponses({
              llmConfig,
              logger,
              fetchImpl,
              input: prompt,
              textFormat: ENRICHMENT_TEXT_FORMAT,
              maxOutputTokens: llmConfig.enrichmentMaxOutputTokens
          });
    const parsed = JSON.parse(stripJSONFence(completion.text));

    return {
        provider: formatProviderName(llmConfig.provider, completion.model),
        headline: normalizeHeadline(parsed.headline, note),
        growthParagraphs: normalizeGrowthParagraphs(parsed.growthParagraphs),
        timelineSummary: normalizeTimelineSummary(parsed.timelineSummary),
        relatedIdeas: toStringArray(parsed.relatedIdeas),
        prompts: toStringArray(parsed.prompts),
        sources: normalizeSources(parsed.sources, retrievalBundle.results),
        followUpContext: normalizeFollowUpContext(parsed.followUpContext, followUpGuidance)
    };
}

async function generateChatReplyWithLLM({ note, message, threadMessages, relatedNotes, llmConfig, logger, fetchImpl }) {
    const prompt = buildChatPrompt({ note, message, threadMessages, relatedNotes });
    const completion = llmConfig.provider === "cerebras"
        ? { text: await callCerebrasForText({ llmConfig, fetchImpl, prompt }), model: llmConfig.model }
        : await callOpenAIResponses({
              llmConfig,
              logger,
              fetchImpl,
              input: prompt,
              maxOutputTokens: llmConfig.chatMaxOutputTokens
          });

    return {
        provider: formatProviderName(llmConfig.provider, completion.model),
        text: completion.text,
        sources: []
    };
}

async function callOpenAIResponses({ llmConfig, logger, fetchImpl, input, textFormat = { type: "text" }, maxOutputTokens }) {
    const models = llmConfig.models?.length ? llmConfig.models : [llmConfig.model];
    let lastError = null;

    for (const [index, model] of models.entries()) {
        const body = {
            model,
            input,
            text: {
                format: textFormat
            },
            ...(maxOutputTokens ? { max_output_tokens: maxOutputTokens } : {})
        };

        try {
            const payload = await requestWithRetries({
                provider: "openai",
                model,
                url: `${llmConfig.baseURL}/responses`,
                requestOptions: {
                    method: "POST",
                    headers: {
                        "Content-Type": "application/json",
                        Authorization: `Bearer ${llmConfig.apiKey}`
                    },
                    body: JSON.stringify(body)
                },
                fetchImpl,
                logger,
                timeoutMs: llmConfig.requestTimeoutMs,
                maxRetries: llmConfig.requestMaxRetries,
                retryBaseMs: llmConfig.retryBaseMs,
                retryMaxMs: llmConfig.retryMaxMs
            });

            const text = extractOpenAIText(payload);

            if (typeof text !== "string" || !text.trim()) {
                throw new AIProviderError(`openai response from ${model} did not include output_text`, {
                    provider: "openai",
                    model,
                    retryable: true
                });
            }

            return { text: text.trim(), model };
        } catch (error) {
            const normalized = normalizeProviderError(error, "openai", model);
            if (!normalized.retryable || index >= models.length - 1) {
                throw normalized;
            }

            lastError = normalized;
            logger?.warn("ai_model_routing_next", {
                provider: "openai",
                failedModel: model,
                nextModel: models[index + 1],
                detail: normalized.message
            });
        }
    }

    throw lastError || new AIProviderError("openai request failed before selecting a model", { provider: "openai", retryable: true });
}

async function requestWithRetries({
    provider,
    model,
    url,
    requestOptions,
    fetchImpl,
    logger,
    timeoutMs,
    maxRetries,
    retryBaseMs,
    retryMaxMs
}) {
    let lastError = null;

    for (let attempt = 0; attempt <= maxRetries; attempt += 1) {
        try {
            const response = await fetchWithTimeout(fetchImpl, url, requestOptions, timeoutMs, provider, model);
            if (response.ok) {
                return response.json();
            }

            const detail = await safeReadText(response);
            const error = new AIProviderError(`${provider}${model ? ` ${model}` : ""} request failed with status ${response.status}${detail ? `: ${detail}` : ""}`, {
                provider,
                model,
                status: response.status,
                detail,
                retryAfterMs: parseRetryAfterMs(response.headers)
            });

            if (!error.retryable || attempt >= maxRetries) {
                throw error;
            }

            lastError = error;
            await waitBeforeRetry({ error, attempt, logger, retryBaseMs, retryMaxMs });
        } catch (error) {
            const normalized = normalizeProviderError(error, provider, model);
            if (!normalized.retryable || attempt >= maxRetries) {
                throw normalized;
            }

            lastError = normalized;
            await waitBeforeRetry({ error: normalized, attempt, logger, retryBaseMs, retryMaxMs });
        }
    }

    throw lastError || new AIProviderError(`${provider} request failed`, { provider, model, retryable: true });
}

async function fetchWithTimeout(fetchImpl, url, requestOptions, timeoutMs, provider = "openai", model = null) {
    const controller = typeof AbortController === "function" ? new AbortController() : null;
    const timeout = controller
        ? setTimeout(() => {
              controller.abort();
          }, timeoutMs)
        : null;

    try {
        return await fetchImpl(url, {
            ...requestOptions,
            ...(controller ? { signal: controller.signal } : {})
        });
    } catch (error) {
        if (error?.name === "AbortError") {
            throw new AIProviderError(`${provider}${model ? ` ${model}` : ""} request timed out`, { provider, model, retryable: true });
        }
        throw error;
    } finally {
        if (timeout) {
            clearTimeout(timeout);
        }
    }
}

async function waitBeforeRetry({ error, attempt, logger, retryBaseMs, retryMaxMs }) {
    const delayMs = retryDelayMs({ error, attempt, retryBaseMs, retryMaxMs });
    logger?.warn("ai_provider_retrying", {
        provider: error.provider || "openai",
        status: error.status || null,
        attempt: attempt + 1,
        delayMs,
        detail: error.message
    });
    await sleep(delayMs);
}

function retryDelayMs({ error, attempt, retryBaseMs, retryMaxMs }) {
    if (Number.isFinite(error.retryAfterMs) && error.retryAfterMs >= 0) {
        return Math.min(error.retryAfterMs, retryMaxMs);
    }

    const exponential = retryBaseMs * 2 ** attempt;
    const jitter = Math.floor(Math.random() * retryBaseMs);
    return Math.min(exponential + jitter, retryMaxMs);
}

function normalizeProviderError(error, provider, model = null) {
    if (error instanceof AIProviderError) {
        return error;
    }

    const message = error instanceof Error ? error.message : String(error);
    return new AIProviderError(`${provider}${model ? ` ${model}` : ""} request failed: ${message}`, {
        provider,
        model,
        retryable: true
    });
}

function parseRetryAfterMs(headers) {
    const value = typeof headers?.get === "function" ? headers.get("retry-after") : null;
    if (!value) {
        return null;
    }

    const seconds = Number(value);
    if (Number.isFinite(seconds)) {
        return Math.max(0, seconds * 1000);
    }

    const dateMs = Date.parse(value);
    return Number.isNaN(dateMs) ? null : Math.max(0, dateMs - Date.now());
}

function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

class AIProviderError extends Error {
    constructor(message, { provider, model = null, status = null, detail = "", retryable = isRetryableStatus(status), retryAfterMs = null } = {}) {
        super(message);
        this.name = "AIProviderError";
        this.provider = provider;
        this.model = model;
        this.status = status;
        this.detail = detail;
        this.retryable = retryable;
        this.retryAfterMs = retryAfterMs;
    }
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
    return stripJSONFence(text);
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
        models: normalizeModelList(config.env.OPENAI_MODEL || "gpt-4.1-mini", config.env.OPENAI_FALLBACK_MODELS),
        baseURL: stripTrailingSlash(String(config.env.OPENAI_BASE_URL || "https://api.openai.com/v1").trim()),
        requestTimeoutMs: normalizePositiveInteger(config.env.AI_REQUEST_TIMEOUT_MS, 30000),
        requestMaxRetries: normalizeNonNegativeInteger(config.env.AI_REQUEST_MAX_RETRIES, 2),
        retryBaseMs: normalizePositiveInteger(config.env.AI_REQUEST_RETRY_BASE_MS, 500),
        retryMaxMs: normalizePositiveInteger(config.env.AI_REQUEST_RETRY_MAX_MS, 8000),
        enrichmentMaxOutputTokens: normalizePositiveInteger(config.env.OPENAI_ENRICHMENT_MAX_OUTPUT_TOKENS, 900),
        chatMaxOutputTokens: normalizePositiveInteger(config.env.OPENAI_CHAT_MAX_OUTPUT_TOKENS, 700)
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

function normalizeModelList(primaryModel, fallbackModels) {
    const models = [
        String(primaryModel || "").trim(),
        ...String(fallbackModels || "")
            .split(",")
            .map((model) => model.trim())
    ].filter(Boolean);

    return [...new Set(models)];
}

function formatProviderName(provider, model) {
    if (!model || provider !== "openai") {
        return provider;
    }

    return `${provider}:${model}`;
}

function normalizePositiveInteger(value, fallback) {
    const parsed = Number(value);
    if (!Number.isFinite(parsed) || parsed < 1) {
        return fallback;
    }
    return Math.floor(parsed);
}

function normalizeNonNegativeInteger(value, fallback) {
    const parsed = Number(value);
    if (!Number.isFinite(parsed) || parsed < 0) {
        return fallback;
    }
    return Math.floor(parsed);
}

function stripJSONFence(text) {
    const trimmed = String(text || "").trim();
    const fenced = trimmed.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/i);
    return (fenced ? fenced[1] : trimmed).trim();
}

function isRetryableStatus(status) {
    return [408, 409, 429, 500, 502, 503, 504].includes(status);
}

function buildEnrichmentPrompt({ note, focus, relatedNotes, retrievalBundle, followUpGuidance }) {
    const hasFollowUpGuidance = typeof followUpGuidance === "string" && followUpGuidance.trim().length > 0;
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
        '  "sources": [{ "title": "string", "url": "string", "snippet": "string", "publisher": "string" }],',
        '  "followUpContext": null | { "prefix": "string", "highlight": "string", "suffix": "string" }',
        "}",
        "Rules:",
        "- Never rewrite or replace the user's raw note text.",
        "- `headline` should be a lightly polished top line, close to the original wording, under 90 characters, and never use an ellipsis.",
        "- `growthParagraphs` should be 1 to 3 appended paragraphs of development.",
        "- `timelineSummary` should be a short phrase describing what changed.",
        "- `prompts` should contain 2 to 3 concrete open-ended follow-up questions that deepen the note instead of repeating it.",
        "- Only return an empty `prompts` array if the note is too trivial or too complete to extend meaningfully.",
        hasFollowUpGuidance
            ? "- This note has a pending user follow-up. Treat it as steering guidance for the next section of the same article, not as a chat reply."
            : "- If there is no follow-up guidance, `followUpContext` must be null.",
        hasFollowUpGuidance
            ? "- When follow-up guidance is present, `followUpContext` must be a natural bridge into the next section. `highlight` must quote or closely paraphrase the user's follow-up in concise form. `prefix` and `suffix` must make the sentence read naturally around that highlighted phrase."
            : "- Do not fabricate a follow-up bridge if none was provided.",
        hasFollowUpGuidance
            ? "- When follow-up guidance is present, `growthParagraphs` must feel like the next section of the article. Do not answer in Q&A format and do not mention 'the user' or 'this question' mechanically."
            : "- Keep the development in essay form.",
        `Focus area: ${focus || "general idea development"}`,
        `Note title: ${note.title}`,
        `Note text: ${note.rawText || note.text}`,
        hasFollowUpGuidance ? `Follow-up guidance: ${followUpGuidance}` : "Follow-up guidance: none",
        `Related notes: ${JSON.stringify(relatedNotes.slice(0, 3).map(toCompactNote))}`,
        `Retrieved sources: ${JSON.stringify(retrievalBundle.results.map(toCompactSource))}`
    ].join("\n");
}

function buildChatPrompt({ note, message, threadMessages, relatedNotes }) {
    return [
        "You are Thinknote, a concise collaborator for idea development.",
        "Reply in plain text.",
        "Keep the response focused and natural.",
        "If multiple paragraphs help, use 1 to 3 short paragraphs separated by a blank line.",
        "Do not use bullets, numbering, or markdown headings.",
        note ? `Current note: ${JSON.stringify(toCompactNote(note))}` : "No note context provided.",
        `Recent thread messages: ${JSON.stringify(threadMessages.slice(-6).map((item) => ({ role: item.role, text: item.text })))}`,
        `Related notes: ${JSON.stringify(relatedNotes.slice(0, 3).map(toCompactNote))}`,
        `User message: ${message}`
    ].join("\n");
}

function generateMockEnrichment({ note, focus, relatedNotes, retrievalBundle, followUpGuidance }) {
    const root = note.rawText.length > 180 ? `${note.rawText.slice(0, 180)}...` : note.rawText;
    const sourceTitles = retrievalBundle.results.map((source) => source.title).slice(0, 2);
    const trimmedFollowUp = typeof followUpGuidance === "string" ? followUpGuidance.trim() : "";
    const hasFollowUpGuidance = trimmedFollowUp.length > 0;
    const growthParagraphs = hasFollowUpGuidance
        ? [
              `That follow-up opens a nearby line of thought inside the original note: ${root} Instead of restarting from zero, the stronger move is to let the new angle reframe what the note is really trying to decide.` +
                  (sourceTitles.length > 0 ? ` Nearby references suggest themes from ${sourceTitles.join(" and ")}.` : ""),
              focus
                  ? `Seen through the lens of ${focus}, the follow-up becomes a steering constraint for the next section. The idea grows by shifting emphasis, not by abandoning the original thread.`
                  : "The next paragraph should therefore carry the same voice and argument, while making the newly surfaced tension explicit enough to feel like a deliberate continuation."
          ].filter(Boolean)
        : [
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
        })),
        followUpContext: hasFollowUpGuidance
            ? {
                  prefix: "A related question here is ",
                  highlight: trimmedFollowUp.replace(/\s+/g, " ").trim(),
                  suffix: ", and that shift in emphasis changes what the next paragraph needs to explain."
              }
            : null
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

function normalizeFollowUpContext(value, followUpGuidance = "") {
    const fallbackHighlight = typeof followUpGuidance === "string" ? followUpGuidance.trim().replace(/\s+/g, " ") : "";
    if (!value || typeof value !== "object") {
        return fallbackHighlight
            ? {
                  prefix: "A related question here is ",
                  highlight: fallbackHighlight,
                  suffix: ", which pushes the note into a slightly different but connected direction."
              }
            : null;
    }

    const prefix = typeof value.prefix === "string" ? value.prefix : "";
    const highlight = typeof value.highlight === "string" ? value.highlight : fallbackHighlight;
    const suffix = typeof value.suffix === "string" ? value.suffix : "";
    const compactHighlight = highlight.trim().replace(/\s+/g, " ");

    if (!compactHighlight) {
        return null;
    }

    return {
        prefix: prefix.trim() ? prefix.replace(/\s+/g, " ").trim() + " " : "",
        highlight: compactHighlight,
        suffix: suffix.trim() ? " " + suffix.replace(/\s+/g, " ").trim() : ""
    };
}
