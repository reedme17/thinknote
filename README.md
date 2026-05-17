# thinknote

Thinknote is an iOS idea-capture app with AI-assisted note growth.

## App Runtime Configuration

The iOS app no longer requires source edits to switch backends.

Runtime overrides:

- `THINKNOTE_ENVIRONMENT=local|staging|production`
- `THINKNOTE_API_BASE_URL=https://...` to force an explicit backend URL

Default environment routing:

- Simulator defaults to `local` and points at `http://127.0.0.1:8787`
- Staging points at `https://thinknote-8zt0.onrender.com`
- Production points at `https://thinknote-8zt0.onrender.com`

The bundle also carries these defaults in [Info.plist](/Users/tyan/thinknote/Info.plist), so the environment can be changed through scheme variables or future build configuration without touching Swift source.

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

For local development without a live provider, set `AI_PROVIDER=mock` in `backend/.env`.
