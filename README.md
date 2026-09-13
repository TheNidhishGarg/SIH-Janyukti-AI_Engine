# JanYukti Backend

Backend and AI engine for **SIH26043** — a platform that crowdsources societal
challenges and routes them to university and industry partners.

Team **HexaMinds**. Pairs with the Flutter app at
[Adityashahi4465/janyukti](https://github.com/Adityashahi4465/janyukti).

---

## Quick start

```bash
python -m venv .venv
.venv\Scripts\activate          # Windows
# source .venv/bin/activate     # macOS / Linux

pip install -r requirements.txt
copy .env.example .env          # cp on macOS / Linux

python -m app.seed              # curated: 10 Jharkhand departments, 4 partners, 5 challenges
python -m scripts.ingest_openalex   # optional: +19 publication-derived profiles
python main.py                  # http://localhost:8000/docs
```

**No API key is needed.** Without `GEMINI_API_KEY` the engine runs on its
offline heuristic path, and every feature — categorization, priority scoring,
duplicate detection, smart matching — still works. See
[docs/AI_ENGINE.md](docs/AI_ENGINE.md).

### Demo accounts

Password for all four: `janyukti123`

| Role | Email |
|---|---|
| Citizen | `citizen@janyukti.in` |
| University | `university@janyukti.in` |
| Industry | `industry@janyukti.in` |
| Admin | `admin@janyukti.in` |

### Tests

```bash
pytest -q
```

47 tests, all offline — no API key, no network, no model download.
`tests/test_workflow.py` runs one challenge through the entire pipeline against
real endpoints and is the single best thing to run in front of a judge.

---

## What this implements

The five stages from the deck, each backed by real code:

| Stage | Implementation |
|---|---|
| **1. Report** | `POST /challenges` — validation, attachments, geotagging, audit trail |
| **2. AI Analyze** | Categorization, priority scoring, duplicate detection — `app/ml/` |
| **3. Smart Matching** | Semantic + category + capacity + proximity ranking of departments |
| **4. Collaborate** | Admin assign/override, university accept, milestones, chat, industry interest |
| **5. Impact** | Milestone-derived progress, impact reporting, analytics aggregates |

58 endpoints. Full contract in [docs/API_CONTRACT.md](docs/API_CONTRACT.md).

---

## Layout

```
main.py                  FastAPI app, middleware, router registration
app/
  config.py              Settings (env-driven)
  db.py                  Async SQLAlchemy engine + session
  seed.py                Curated Jharkhand institution profiles, partners, challenges
  ml/category_mapping.py OpenAlex research topics -> civic taxonomy
  core/
    security.py          Password hashing, JWT, role dependencies
    ids.py               CH-2026-00124 style identifiers
  models/                SQLAlchemy ORM
  schemas/               Pydantic request/response contracts
  ml/                    ← the AI engine
    taxonomy.py          Categories + weighted keyword lexicon
    embeddings.py        sentence-transformers, with a hashing fallback
    llm.py               Gemini wrapper, returns None on any failure
    categorizer.py       Category + confidence + tags
    priority.py          Four-axis rubric scoring
    duplicates.py        Semantic + lexical + location duplicate detection
    matching.py          University ranking with explainable scores
    pipeline.py          Orchestrates all four, persists the result
  services/              Business logic (challenge, project, notifications)
  routes/                HTTP layer
scripts/
  ingest_openalex.py     Real expertise profiles from publication data
  demo_pipeline.py       Narrated end-to-end walkthrough over HTTP
docs/
  TESTING.md             Verified step-by-step test + demo walkthrough
  API_CONTRACT.md        Endpoint reference + Flutter field mapping
  AI_ENGINE.md           How each model works and why
  INTEGRATION.md         Step-by-step Flutter wiring
  flutter/               Drop-in Dart API clients
tests/                   26 tests, fully offline
```

---

## Configuration

Everything is environment-driven; see `.env.example`. The settings that matter:

| Variable | Default | Effect |
|---|---|---|
| `DATABASE_URL` | SQLite file | Point at `postgresql+asyncpg://...` for deployment |
| `GEMINI_API_KEY` | *(empty)* | Enables the LLM path; heuristics are used without it |
| `USE_LOCAL_EMBEDDINGS` | `true` | `false` skips the model download, uses the hashing fallback |
| `DUPLICATE_SIMILARITY_THRESHOLD` | `0.85` | Lower catches more duplicates, at the cost of false positives |
| `MATCH_TOP_K` | `5` | How many universities the matcher returns |
| `CLOUDINARY_URL` | *(empty)* | Uploads go to local disk when unset |
| `JWT_SECRET` | dev value | **Must** be changed for deployment |

---

## Deployment notes

Before this goes anywhere public:

1. Set a real `JWT_SECRET` (32+ chars) and `CORS_ORIGINS` (not `*`).
2. Switch `DATABASE_URL` to PostgreSQL and uncomment `asyncpg` in
   `requirements.txt`. SQLite serialises writes and will not hold up.
3. Replace the dev OTP in `app/routes/auth.py` with a real SMS gateway. It is
   already gated behind `DEBUG`, but the gate is the only thing protecting it.
4. Add rate limiting on `POST /challenges` and the `/ml/*` routes.
5. Run behind `uvicorn --workers N` or gunicorn with uvicorn workers.

At current scale, duplicate detection and matching load every candidate row and
compare in NumPy. That is fine into the low tens of thousands of challenges; past
that, move the vectors into pgvector and let the database do the search.
