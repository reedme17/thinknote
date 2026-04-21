import { randomUUID } from "node:crypto";

export function createAIOrchestrator({ config, logger, retrieval, fetchImpl = fetch }) {
    const providerName = config.env.OPENAI_API_KEY ? "openai" : "mock";

    return {
        providerName,
        async generateEnrichment({ note, focus = "", includeWeb = true, relatedNotes = [] }) {
            const retrievalBundle = includeWeb ? await retrieval.retrieve({ note, focus, limit: 3 }) : { query: "", results: [] };

            if (config.env.OPENAI_API_KEY) {
                try {
                    return await generateEnrichmentWithOpenAI({
                        note,
                        focus,
                        relatedNotes,
                        retrievalBundle,
                        config,
                        fetchImpl
                    });
                } catch (error) {
                    logger.warn("openai_enrichment_fallback", {
                        detail: error instanceof Error ? error.message : String(error)
                    });
                }
            }

            return generateMockEnrichment({ note, focus, relatedNotes, retrievalBundle });
        },
        async generateChatReply({ note, message, threadMessages = [], relatedNotes = [] }) {
            if (config.env.OPENAI_API_KEY) {
                try {
                    return await generateChatReplyWithOpenAI({
                        note,
                        message,
                        threadMessages,
                        relatedNotes,
                        config,
                        fetchImpl
                    });
                } catch (error) {
                    logger.warn("openai_chat_fallback", {
                        detail: error instanceof Error ? error.message : String(error)
                    });
                }
            }

            return {
                provider: "mock",
                text: buildMockChatReply({ note, message, threadMessages, relatedNotes }),
                sources: []
            };
        }
    };
}

async function generateEnrichmentWithOpenAI({ note, focus, relatedNotes, retrievalBundle, config, fetchImpl }) {
    const content = [
        {
            type: "input_text",
            text: [
                "You are Thinknote's backend enrichment service.",
                "Return valid JSON only.",
                "Schema:",
                "{",
                '  "expansion": "string",',
                '  "relatedIdeas": ["string"],',
                '  "prompts": ["string"],',
                '  "sources": [{ "title": "string", "url": "string", "snippet": "string", "publisher": "string" }]',
                "}",
                `Focus area: ${focus || "general idea development"}`,
                `Note title: ${note.title}`,
                `Note text: ${note.rawText || note.text}`,
                `Related notes: ${JSON.stringify(relatedNotes.slice(0, 3).map(toCompactNote))}`,
                `Retrieved sources: ${JSON.stringify(retrievalBundle.results.map(toCompactSource))}`
            ].join("\n")
        }
    ];

    const json = await callOpenAI({ config, fetchImpl, input: content });
    const parsed = JSON.parse(json);

    return {
        provider: "openai",
        expansion: typeof parsed.expansion === "string" ? parsed.expansion : "",
        relatedIdeas: toStringArray(parsed.relatedIdeas),
        prompts: toStringArray(parsed.prompts),
        sources: normalizeSources(parsed.sources, retrievalBundle.results)
    };
}

async function generateChatReplyWithOpenAI({ note, message, threadMessages, relatedNotes, config, fetchImpl }) {
    const input = [
        {
            type: "input_text",
            text: [
                "You are Thinknote, a concise collaborator for idea development.",
                "Reply in plain text.",
                note ? `Current note: ${JSON.stringify(toCompactNote(note))}` : "No note context provided.",
                `Recent thread messages: ${JSON.stringify(threadMessages.slice(-6).map((item) => ({ role: item.role, text: item.text })))}`,
                `Related notes: ${JSON.stringify(relatedNotes.slice(0, 3).map(toCompactNote))}`,
                `User message: ${message}`
            ].join("\n")
        }
    ];

    const text = await callOpenAI({ config, fetchImpl, input });
    return {
        provider: "openai",
        text,
        sources: []
    };
}

async function callOpenAI({ config, fetchImpl, input }) {
    const response = await fetchImpl(`${config.env.OPENAI_BASE_URL || "https://api.openai.com/v1"}/responses`, {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${config.env.OPENAI_API_KEY}`
        },
        body: JSON.stringify({
            model: config.env.OPENAI_MODEL || "gpt-4.1-mini",
            input,
            text: {
                format: {
                    type: "text"
                }
            }
        })
    });

    if (!response.ok) {
        throw new Error(`OpenAI request failed with status ${response.status}`);
    }

    const payload = await response.json();
    const text = payload.output_text;

    if (typeof text !== "string" || !text.trim()) {
        throw new Error("OpenAI response did not include output_text");
    }

    return text.trim();
}

function generateMockEnrichment({ note, focus, relatedNotes, retrievalBundle }) {
    const root = note.rawText.length > 180 ? `${note.rawText.slice(0, 180)}...` : note.rawText;
    const sourceTitles = retrievalBundle.results.map((source) => source.title).slice(0, 2);

    return {
        provider: "mock",
        expansion:
            `This note points toward a stronger claim: ${root} ` +
            `A useful next step is to name the tension inside the idea, then decide what evidence or example would make it feel real.` +
            (sourceTitles.length > 0 ? ` Nearby references suggest themes from ${sourceTitles.join(" and ")}.` : ""),
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
