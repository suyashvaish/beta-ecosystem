# Beta AI Assistant — Backend

A production-ready FastAPI backend powering **Beta**, an AI voice assistant, built to
grow into a full elderly-care AI platform. Serves a cross-platform Flutter client.

## Tech Stack

- **Language:** Python 3.12+
- **Framework:** FastAPI + Uvicorn (ASGI)
- **Database:** PostgreSQL + [pgvector](https://github.com/pgvector/pgvector) (semantic memory)
- **ORM:** SQLAlchemy 2.x (async) + Alembic migrations
- **Validation:** Pydantic v2
- **Auth:** Firebase Authentication
- **AI:** OpenAI Responses API (provider-swappable — see `app/ai/`)
- **Deployment:** Docker + Docker Compose

## Architecture

```
app/
├── api/v1/         # FastAPI routers (HTTP layer only)
├── auth/           # Firebase integration + current-user dependency
├── config/         # Settings (env-driven, pydantic-settings)
├── database/       # Async engine, session, declarative base
├── models/         # SQLAlchemy ORM models
├── schemas/        # Pydantic request/response schemas
├── repositories/    # All direct DB queries, one per aggregate
├── services/       # Business logic orchestration (chat, notifications)
├── ai/             # LLM provider abstraction (OpenAI today, swappable)
├── memory/         # Short-term / long-term / semantic memory orchestration
├── speech/         # STT/TTS provider abstraction (placeholders)
├── tools/          # Elderly-care domain service
├── notifications/  # Firebase Cloud Messaging client
├── utils/          # Logging, exceptions, rate limiting
└── main.py         # App entrypoint
```

Each layer only depends on the layer(s) below it — API routes never touch the
database directly, services never import FastAPI, etc. This keeps business
logic testable and the AI/speech providers swappable without touching callers.

## Local Development

### 1. Prerequisites
- Python 3.12+
- PostgreSQL 16+ with the `pgvector` extension (or use Docker Compose — see below)
- A Firebase project + service-account JSON (Console → Project Settings → Service Accounts)
- An OpenAI API key

### 2. Setup

```bash
cp .env.example .env
# edit .env with your real DATABASE_URL, OPENAI_API_KEY, FIREBASE_PROJECT_ID, SECRET_KEY
# place your Firebase service-account file at ./firebase-credentials.json

python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### 3. Run database migrations

```bash
alembic upgrade head
```

### 4. Run the server

```bash
uvicorn app.main:app --reload
```

API docs available at `http://localhost:8000/docs` (Swagger) and `/redoc`.

### 5. Run tests

```bash
SECRET_KEY=test DATABASE_URL=sqlite+aiosqlite:///:memory: OPENAI_API_KEY=sk-test \
  FIREBASE_PROJECT_ID=test pytest -q
```

Unit tests run against an in-memory SQLite database with a fake AI provider — no
external services required. (pgvector's cosine-distance search is Postgres-only,
so that specific query is exercised via integration tests against real Postgres,
not the fast unit suite.)

## Docker Deployment

```bash
cp .env.example .env   # fill in real secrets
# place firebase-credentials.json in the project root
docker compose up --build
```

This starts:
- `db` — Postgres 16 with pgvector pre-installed, with a healthcheck
- `migrate` — runs `alembic upgrade head` once, then exits
- `app` — the FastAPI server, waits for `migrate` to succeed before starting

The API will be available at `http://localhost:8000`.

## API Overview

All endpoints are versioned under `/api/v1`. Authenticated endpoints expect
`Authorization: Bearer <firebase-id-token>`.

| Area | Endpoints |
|---|---|
| Auth | `POST /auth/sign-in`, `POST /auth/verify`, `GET /auth/profile`, `POST /auth/logout` |
| Users | `GET /users/me`, `PATCH /users/me` |
| Chat | `POST /chat`, `POST /chat/stream` (SSE), `GET /chat/conversations`, `GET /chat/conversations/{id}` |
| Memory | `POST /memories`, `GET /memories`, `DELETE /memories/{id}` |
| Notifications | `POST /notifications`, `GET /notifications`, `POST /notifications/emergency` |
| Speech | `POST /speech/transcribe`, `POST /speech/synthesize` |
| Elderly Care | `POST /elderly-care/medication-reminders`, `/appointment-reminders`, `/sos`, `/fall-detection-events`, `/wellness-check-ins`, `/caregivers` |

Full interactive documentation is generated automatically at `/docs`.

## Extending the AI / Speech Providers

- **Swap the LLM provider:** implement `app.ai.base.AIProvider` and update
  `app.ai.factory.get_ai_provider()`. No route or service code changes needed.
- **Wire up real STT/TTS:** implement `SpeechToTextProvider` / `TextToSpeechProvider`
  in `app/speech/`, update `app/speech/factory.py`.
- **Add hardware-based fall detection:** call
  `ElderlyCareService.record_fall_detection_event()` from your ingestion endpoint
  or message-queue consumer — it already persists the event and raises SOS.

## Security Notes

- No passwords are stored locally — all credential verification is delegated to Firebase.
- Rate limiting is applied per-client-IP (in-memory; swap for Redis in a multi-instance deployment).
- All domain errors flow through a single exception handler (`app/main.py`) so
  internal details never leak into HTTP responses.
- Secrets are never logged (see `app/utils/logging.py` redaction logic).

## Production Checklist

- [ ] Set `ENVIRONMENT=production`, `DEBUG=false`
- [ ] Set a strong random `SECRET_KEY`
- [ ] Restrict `ALLOWED_ORIGINS` to your actual Flutter/web origins
- [ ] Point `DATABASE_URL` at a managed Postgres instance with pgvector enabled
- [ ] Mount real Firebase credentials, don't commit them
- [ ] Put a Redis-backed rate limiter in front of the in-memory one if scaling horizontally
- [ ] Wire up real STT/TTS and monitor OpenAI usage/costs
