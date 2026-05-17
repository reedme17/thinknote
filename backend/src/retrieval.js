const fallbackCorpus = [
    {
        title: "Building a second brain for unfinished ideas",
        url: "https://example.org/second-brain-ideas",
        publisher: "Idea Systems Journal",
        snippet:
            "People revisit incomplete thoughts more often when notes preserve uncertainty, tension, and next questions instead of only polished summaries.",
        content:
            "Incomplete thoughts become more valuable when a system captures why the idea matters, what remains unresolved, and what adjacent questions deserve future attention."
    },
    {
        title: "Knowledge gardens and personal note networks",
        url: "https://example.org/knowledge-gardens",
        publisher: "Personal Knowledge Review",
        snippet:
            "Knowledge gardens work best when notes are linked by theme, contradiction, and complement rather than stored as isolated documents.",
        content:
            "A living note system benefits from semantic links, clusters, and evolving context. Users discover value when the garden reveals patterns between separate notes."
    },
    {
        title: "Prompting users with questions instead of summaries",
        url: "https://example.org/reflection-prompts",
        publisher: "Designing for Thought",
        snippet:
            "Reflection prompts should deepen a note by surfacing assumptions, evidence gaps, and actionable next steps.",
        content:
            "The strongest prompts create movement. They turn a vague observation into a claim, a tension, and a next action, while preserving the author's original language."
    }
];

export function createRetrievalClient({ config, logger, fetchImpl = fetch }) {
    const usesRemoteSearch = Boolean(config.env.SEARCH_API_URL);
    const usesEmbeddedCorpus = config.searchProvider === "embedded";
    const providerName = usesRemoteSearch ? "remote_search_api" : usesEmbeddedCorpus ? "embedded_corpus" : "none";

    return {
        providerName,
        async retrieve({ note, focus = "", limit = 3 }) {
            const query = buildQuery(note, focus);
            const startedAt = Date.now();

            try {
                const results = usesRemoteSearch
                    ? await fetchRemoteResults({ config, query, limit, fetchImpl })
                    : usesEmbeddedCorpus
                      ? searchFallbackCorpus(query, limit)
                      : [];

                const normalized = results.map((result, index) => ({
                    id: `src-${index + 1}-${slugify(result.title)}`,
                    title: result.title,
                    url: result.url,
                    snippet: result.snippet,
                    publisher: result.publisher || hostFromUrl(result.url),
                    query,
                    score: Number(result.score || Math.max(0, 1 - index * 0.1).toFixed(2)),
                    retrievedAt: new Date().toISOString(),
                    content: result.content || result.snippet
                }));

                logger.info("retrieval_completed", {
                    provider: providerName,
                    latencyMs: Date.now() - startedAt,
                    resultCount: normalized.length
                });

                return { query, results: normalized };
            } catch (error) {
                logger.warn("retrieval_failed", {
                    provider: providerName,
                    detail: error instanceof Error ? error.message : String(error)
                });
                throw error;
            }
        }
    };
}

async function fetchRemoteResults({ config, query, limit, fetchImpl }) {
    const method = String(config.env.SEARCH_API_METHOD || "POST").toUpperCase();
    const headers = {
        "Content-Type": "application/json"
    };

    if (config.env.SEARCH_API_KEY) {
        headers.Authorization = `Bearer ${config.env.SEARCH_API_KEY}`;
    }

    let url = config.env.SEARCH_API_URL;
    const options = { method, headers };

    if (method === "GET") {
        const searchUrl = new URL(url);
        searchUrl.searchParams.set("q", query);
        searchUrl.searchParams.set("limit", String(limit));
        url = searchUrl.toString();
    } else {
        options.body = JSON.stringify({ query, limit });
    }

    const response = await fetchImpl(url, options);
    if (!response.ok) {
        throw new Error(`Search API returned ${response.status}`);
    }

    const payload = await response.json();
    const rawResults = Array.isArray(payload) ? payload : Array.isArray(payload.results) ? payload.results : [];

    return rawResults.map((item) => ({
        title: item.title || "Untitled source",
        url: item.url || "",
        snippet: item.snippet || item.description || "",
        publisher: item.publisher || item.source || "",
        content: item.content || item.snippet || item.description || "",
        score: item.score
    }));
}

function searchFallbackCorpus(query, limit) {
    const queryTerms = tokenize(query);
    return fallbackCorpus
        .map((entry) => ({
            ...entry,
            score: scoreEntry(entry, queryTerms)
        }))
        .sort((left, right) => right.score - left.score)
        .slice(0, limit);
}

function scoreEntry(entry, queryTerms) {
    const haystack = tokenize([entry.title, entry.snippet, entry.content].join(" "));
    let score = 0;

    for (const term of queryTerms) {
        if (haystack.includes(term)) {
            score += 1;
        }
    }

    return score / Math.max(1, queryTerms.length);
}

function buildQuery(note, focus) {
    return [note.title, note.rawText || note.text, focus].filter(Boolean).join(" ");
}

function tokenize(text) {
    return String(text || "")
        .toLowerCase()
        .split(/[^a-z0-9]+/)
        .filter((part) => part.length >= 3);
}

function hostFromUrl(url) {
    try {
        return new URL(url).hostname.replace(/^www\./, "");
    } catch {
        return "";
    }
}

function slugify(value) {
    return String(value || "")
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, "-")
        .replace(/^-|-$/g, "") || "source";
}
