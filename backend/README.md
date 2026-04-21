# Thinknote Backend

This is a minimal local backend for Thinknote.

It provides:

- note creation and retrieval
- note editing with revision history
- automatic and manual note enrichment
- related-note linking
- multi-turn AI chat threads
- local JSON persistence with durable job state
- optional OpenAI integration
- pluggable retrieval integration for grounded sources

## Run

1. Copy `.env.example` to `.env`
2. Add `OPENAI_API_KEY` if you want real model responses
3. Start the server

```bash
cd backend
npm run dev
```

The server runs on `http://localhost:8787` by default.

## Endpoints

- `GET /health`
- `GET /api/notes`
- `POST /api/notes`
- `GET /api/notes/:id`
- `PATCH /api/notes/:id`
- `GET /api/notes/:id/related`
- `GET /api/notes/:id/threads`
- `POST /api/notes/:id/enrich`
- `GET /api/jobs`
- `GET /api/jobs/:id`
- `GET /api/threads`
- `POST /api/threads`
- `GET /api/threads/:id`
- `POST /api/threads/:id/messages`
- `POST /api/chat`

## Behavior

- New notes auto-enqueue a background enrichment job unless `AUTO_ENRICH_ON_CREATE=false`.
- Jobs persist `queued`, `running`, `retrying`, `completed`, and `failed` states.
- Enrichment writes:
  - AI expansion
  - source references
  - related-note links
  - prompts
  - timeline events
  - revision history
- If `SEARCH_API_URL` is configured, the backend will call that retrieval API using `{ query, limit }`.
- If no search API is configured, the backend falls back to an embedded corpus so the product loop still works locally.

## Search API Contract

The optional search API can be any service that accepts:

- `POST` body: `{ "query": "string", "limit": 3 }`
- or `GET` query params: `?q=...&limit=...`

And returns either:

```json
{
  "results": [
    {
      "title": "string",
      "url": "string",
      "snippet": "string",
      "publisher": "string",
      "content": "string",
      "score": 0.92
    }
  ]
}
```

or a raw JSON array of the same result objects.

## Tests

```bash
cd backend
npm test
```

## Example

Create a note:

```bash
curl -X POST http://localhost:8787/api/notes \
  -H "Content-Type: application/json" \
  -d '{"text":"I want Thinknote to help users revisit unfinished thoughts."}'
```

Enrich a note:

```bash
curl -X POST http://localhost:8787/api/notes/NOTE_ID/enrich \
  -H "Content-Type: application/json" \
  -d '{"focus":"product strategy","includeWeb":true}'
```

Chat:

```bash
curl -X POST http://localhost:8787/api/chat \
  -H "Content-Type: application/json" \
  -d '{"message":"Help me turn this into a sharper thesis."}'
```
