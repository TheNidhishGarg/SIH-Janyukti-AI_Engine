# Testing the pipeline

Every command below was run on Windows with Git Bash and PowerShell before being
written down. Total time from a clean clone: about 5 minutes, plus a one-time
model download if you enable MiniLM.

---

## 0. Setup (once)

```bash
python -m venv .venv
.venv\Scripts\activate            # PowerShell / cmd
# source .venv/bin/activate       # Git Bash, macOS, Linux

pip install -r requirements.txt
copy .env.example .env            # cp on macOS / Linux
```

`sentence-transformers` in `requirements.txt` pulls PyTorch (~2 GB). If you want
to skip it for now, install everything else and set `USE_LOCAL_EMBEDDINGS=false`
in `.env` — the whole pipeline still runs on the offline engine.

---

## 1. Load data

```bash
python -m app.seed                 # 10 curated Jharkhand departments, 4 partners, 5 challenges
python -m scripts.ingest_openalex  # +19 publication-derived profiles (optional)
```

Expected from the seed: five challenges, each categorised correctly.

```
CH-2026-00001  Water Contamination in Village          -> Water Management        High
CH-2026-00002  Poor Waste Management in Residential...  -> Waste Management        Medium
CH-2026-00003  Frequent Power Outages in Rural Comm...  -> Energy & Infrastructure Medium
CH-2026-00004  Lack of Digital Education Resources      -> Education               Low
CH-2026-00005  Unsafe Roads and Traffic Congestion...   -> Transportation & Safety Medium
```

To start over at any point: delete `janyukti.db` and re-run both commands.
**Stop the server first** — Windows will refuse to delete a file it has open.

---

## 2. Automated tests

```bash
pytest -q
```

**Expected: 47 passed.** No API key, no network, no model download required.

| File | What it covers |
|---|---|
| `test_ml.py` | Categorization across 7 categories, priority rubric, ambient-word regressions |
| `test_duplicate_calibration.py` | Paraphrases clear the threshold, unrelated reports do not, on either backend |
| `test_ingest.py` | Jharkhand scope filter, topic mapping, exclusion list |
| `test_api.py` | Auth, access control, duplicates, matching, admin queue ordering |
| `test_workflow.py` | **One challenge through the entire pipeline against real endpoints** |
| `test_embeddings_local.py` | Skipped unless sentence-transformers is installed |

If you only run one thing, run `pytest tests/test_workflow.py -q`.

---

## 3. The guided walkthrough

Two terminals.

```bash
python main.py                     # terminal 1
python -m scripts.demo_pipeline    # terminal 2
```

This drives all six stages over HTTP as four different users and narrates each
one. It fails loudly at whichever stage breaks, so it doubles as a smoke test.

What you should see:

```
STAGE 1  REPORT
  submitted CH-2026-00006  |  status: Under Review

STAGE 2  AI ANALYZE
  category: Water Management  (95% confidence)
  priority: High  (rubric score 0.89)
      severity 5.0/5   urgency 2.6/5   reach 4.0/5   vulnerability 5.0/5
      rationale: Driven by severity (scored 5/5): illness, contaminat, falling sick.
  DUPLICATE caught -> CH-2026-00006 (score 0.67, semantic 0.78, same location: True)
  unrelated report correctly not flagged

STAGE 3  SMART MATCHING
  #1  0.733  BIT Mesra - Department of Civil & Environmental Engineering
        - Declares Water Management as a focus area
        - Located in Ranchi, same district as the challenge
        - 5 of 5 project slots free

STAGE 4  COLLABORATE     assigned -> accepted -> project with 5 milestones
STAGE 5  TRACK           30% -> 50% -> 70% -> 90% -> 100%
STAGE 6  IMPACT          challenge closed as: Resolved
```

It is safe to run repeatedly — each run tags its challenge with a random ward
suffix so reruns do not collide.

---

## 4. Poking at it by hand

Open `http://localhost:8000/docs`, click **Authorize**, and log in as
`citizen@janyukti.in` / `janyukti123` (also `admin@`, `university@`, `industry@`).

From a terminal — **in PowerShell use `curl.exe`, not `curl`**, which is an alias
for `Invoke-WebRequest` and takes different arguments:

```bash
curl.exe -s -X POST http://localhost:8000/auth/login ^
  -H "Content-Type: application/json" ^
  -d "{\"email\":\"citizen@janyukti.in\",\"password\":\"janyukti123\"}"
```

Worth trying by hand:

| Endpoint | What it shows |
|---|---|
| `GET /ml/status` | Which engine is live, and the duplicate threshold in force |
| `POST /ml/categorize` | Category + confidence for any text you invent |
| `POST /ml/priority` | The four-axis rubric and its rationale |
| `POST /ml/duplicates` | Candidates with semantic/lexical/location breakdown |
| `POST /ml/match` | Ranked departments with reasons, without touching workflow state |
| `GET /admin/queue` | The single call the admin dashboard needs |

Try feeding `/ml/categorize` something deliberately awkward — "the thing near the
temple is broken again" — and confirm it comes back `Other` with
`needs_review: true` rather than a confident wrong answer.

---

## 5. Switching engines

| Setting | Effect |
|---|---|
| `USE_LOCAL_EMBEDDINGS=false` | Hashing fallback, 256-d. Instant start, no download |
| `USE_LOCAL_EMBEDDINGS=true` | MiniLM, 384-d. Better semantics, ~30 s first load |
| `GEMINI_API_KEY=...` | LLM categorization and priority; heuristics stay as fallback |

After switching embedding backends, run `POST /admin/reindex` or re-run the
ingest — vectors from different models are not comparable, and stale ones are
ignored rather than silently mismatched.

Duplicate thresholds are per-backend and calibrated separately (0.50 for MiniLM,
0.35 for the fallback). `GET /ml/status` reports the one actually in force.

---

## Troubleshooting

| Symptom | Cause |
|---|---|
| `Cannot reach http://127.0.0.1:8000` | Server not running, or started on another port |
| `Device or resource busy` deleting the db | Server still holds it — stop it first |
| `curl: A parameter cannot be found that matches '-X'` | PowerShell alias — use `curl.exe` |
| Emulator cannot reach the server | Use `http://10.0.2.2:8000`, not `localhost` |
| Duplicate detection never fires | Check `GET /ml/status` for the live threshold |
| Model downloads on every run | Hugging Face cache is not persisting; set `HF_HOME` |
