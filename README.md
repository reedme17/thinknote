# thinknote

Thinknote is an iOS idea-capture app with AI-assisted note growth.

## Local Backend

A minimal local backend now exists in [backend](/Users/tyan/thinknote/backend/README.md).

It supports:

- note creation
- note retrieval
- note enrichment
- AI chat
- optional OpenAI-backed responses

### Start

```bash
cd backend
cp .env.example .env
npm run dev
```

If `OPENAI_API_KEY` is empty, the backend still works with mock AI responses.
