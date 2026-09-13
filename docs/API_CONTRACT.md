# JanYukti API Contract

Base URL (local): `http://localhost:8000` — interactive docs at `/docs`.

All request and response bodies are JSON in `snake_case`. All timestamps are
ISO-8601 UTC. Authenticated endpoints take `Authorization: Bearer <token>`.

For an Android emulator, the host machine is `http://10.0.2.2:8000`.
For a physical device on the same Wi-Fi, use the machine's LAN IP.

---

## Mapping from the current Flutter mock

Every method on `AppStore` (`lib/shared/mock_data/app_store.dart`) has exactly one
endpoint behind it. This table is the migration checklist.

| `AppStore` method / field | Endpoint | Notes |
|---|---|---|
| `AuthApi.demoLogin()` | `POST /auth/login` | Returns a JWT; store it |
| OTP screen | `POST /auth/otp/request` then `POST /auth/otp/verify` | Dev OTP is `123456` |
| `challenges` list | `GET /challenges?mine=true` | Paginated |
| `addChallenge(t, d, cat, l)` | `POST /challenges` | Server generates `CH-2026-00001` |
| `assign(c, u)` | `POST /admin/challenges/{id}/assign` | Admin only |
| `accept(c)` + `createProject(n, m)` | `POST /projects` | One call; creates 5 milestones |
| `projects` list | `GET /projects?mine=true` | |
| `advance(p)` | `POST /projects/{id}/milestones/{mid}/submit` | Then admin `/review` |
| `chats` list | `GET /projects/{id}/chat` | |
| `send(m)` | `POST /projects/{id}/chat` | |
| Home screen counters | `GET /me/stats` | `challenges`, `in_progress`, `people_impacted` |

---

## Field mapping for existing Dart models

`Challenge` (`lib/models/challenge_model.dart`) maps directly:

| Dart field | JSON field | Change needed |
|---|---|---|
| `id` | `id` | none |
| `title` | `title` | none |
| `category` | `category` | none |
| `location` | `location` | none |
| `description` | `description` | none |
| `status` | `status_label` | use `status_label`, which renders `Assigned to BIT Mesra` exactly as the mock did. `status` is the raw enum, better for logic |
| `priority` | `priority` | none — `High` / `Medium` / `Low` |
| `submittedBy` | `submitted_by` | none |

`Project` (`lib/models/project_model.dart`):

| Dart field | JSON field | Change needed |
|---|---|---|
| `name` | `name` | none |
| `university` | `university` | none (name string) |
| `category` | `category` | none |
| `progress` | `progress` | none (0-100) |
| `mentor` | `mentor` | none |
| `milestones` | `milestones` | now objects `{id, name, status, ...}`, not `List<String>` — read `.name` for display |
| `activeMilestone` | `active_milestone` | none (index) |

---

## Auth

### `POST /auth/register`
```json
{ "name": "Aarav Kumar", "email": "aarav@example.com", "password": "secret123",
  "role": "citizen" }
```
`role` is one of `citizen` | `university` | `industry` | `admin`.
University and industry accounts must also send `university_id` / `industry_id`
(from `GET /universities` and `GET /industry/profiles`).

### `POST /auth/login`
```json
{ "email": "citizen@janyukti.in", "password": "janyukti123" }
```
returns `200`
```json
{ "access_token": "eyJ...", "token_type": "bearer", "expires_in": 604800,
  "user": { "id": "...", "name": "Aarav Kumar", "role": "citizen" } }
```

### `POST /auth/otp/request` then `POST /auth/otp/verify`
Development only (`DEBUG=true`). `otp/verify` creates the account on first use,
so the existing phone-first OTP screen works end to end. Swap for a real SMS
gateway before production.

### `GET /auth/me`
Returns the current user. Use it on app start to validate a stored token.

---

## Challenges

### `POST /challenges` — submit
```json
{ "title": "Water contamination in our village",
  "description": "The drinking water is polluted and causing illness...",
  "category": "Water Management",
  "location": "Ranchi, Jharkhand",
  "district": "Ranchi", "state": "Jharkhand",
  "people_impacted": 1200,
  "attachments": [ { "url": "https://...", "kind": "image" } ] }
```
Returns `201` immediately; the AI engine runs in the background and the
challenge moves `Submitted` to `Under Review` a moment later.

Add `?analyze_sync=true` to wait for the analysis and get it in the response —
slower, but the right choice for a live demo where you want the AI result on
screen instantly.

### `GET /challenges`
Query: `mine`, `status`, `category`, `priority`, `district`,
`assigned_university_id`, `search`, `page`, `page_size`.
Returns `{ items, total, page, page_size, has_more }`.

### `GET /challenges/{id}` — detail, with AI block and timeline
```json
{ "id": "CH-2026-00001", "status": "In Progress",
  "status_label": "In Progress", "priority": "High",
  "ai": { "category": "Water Management", "category_confidence": 0.86,
          "priority": "High", "priority_score": 0.78,
          "scores": { "severity": 4.5, "urgency": 3.8, "reach": 4.0, "vulnerability": 3.5 },
          "rationale": "Driven by severity (scored 5/5): contaminat, disease.",
          "tags": ["water", "contaminat"], "engine": "heuristic",
          "duplicate_of": null, "duplicate_score": null },
  "timeline": [ { "label": "Submitted", "created_at": "..." },
                { "label": "AI analysis complete", "detail": "...", "created_at": "..." } ] }
```
`timeline` drives the Track Challenge screen directly.

### `GET /challenges/{id}/matches`
Ranked universities with the score breakdown (admin / university only).

### Other
- `PATCH /challenges/{id}` — edit, before review begins
- `POST /challenges/{id}/upvote`
- `POST /challenges/{id}/analyze` — admin re-runs the engine

---

## Admin

- `GET /admin/queue` — the one call the admin dashboard needs. Each item is
  `{ challenge: <detail incl. ai>, matches: [<ranked universities>] }`.
- `POST /admin/challenges/{id}/assign` — `{ "university_id": "...", "note": "..." }`.
  Whether this confirmed or overrode the top AI pick is recorded, and surfaces
  in `match_acceptance_rate`.
- `POST /admin/challenges/{id}/duplicate` — `{ "duplicate_of": "CH-..." }` to
  confirm, `{ "duplicate_of": null }` to clear a false positive.
- `POST /admin/challenges/{id}/priority` — human override of the AI rubric.
- `POST /admin/challenges/{id}/reject` — `{ "reason": "..." }`.
- `GET /admin/stats` — analytics dashboard aggregates.
- `POST /admin/reindex` — re-embed all universities after switching embedding backends.

---

## Projects

- `POST /projects` — `{ challenge_id, name, mentor, milestones? }`.
  University accepting an assignment. Creates the 5-stage lifecycle by default.
- `GET /projects?mine=true`, `GET /projects/{id}`
- `POST /projects/{id}/milestones/{mid}/submit` — `{ evidence_url, note }`
- `POST /projects/{id}/milestones/{mid}/review` — `{ approved, note }` (admin)
- `POST /projects/{id}/impact` — `{ people_impacted, summary, metrics }`
- `GET /projects/{id}/chat?after={message_id}` — poll for new messages
- `POST /projects/{id}/chat` — `{ body }`

`progress` is always derived from milestone state; never send it.

---

## Universities and Industry

- `GET /universities` — public directory (`category`, `state`, `search`)
- `GET /universities/{id}/inbox` — assignments awaiting accept/decline
- `POST /universities/{id}/decline/{challenge_id}` — `{ "reason": "..." }`
- `GET /universities/{id}/stats`
- `GET /industry/opportunities` — backable challenges, filtered to the partner focus areas
- `POST /industry/interests` — `{ challenge_id, support: ["Funding"], message, funding_amount }`
- `GET /industry/stats`

---

## AI Engine (direct)

Useful for previewing AI output before the citizen submits, and for demoing the
models on their own.

- `GET /ml/status` — which engine is live (LLM vs heuristic), embedding model, dim
- `GET /ml/categories` — the taxonomy, for the category dropdown
- `POST /ml/categorize` — `{ category, confidence, tags, needs_review }`
- `POST /ml/priority` — `{ priority, score, scores, rationale }`
- `POST /ml/duplicates` — `{ is_duplicate, best_match, candidates }`
- `POST /ml/match` — ranked universities
- `POST /ml/analyze` — all of the above in one call, persisting nothing

Suggested UX: call `POST /ml/duplicates` when the citizen leaves the description
field. If a match comes back, show "Someone nearby already reported this —
follow it instead?" That prevents the duplicate rather than cleaning it up later.

---

## Notifications

- `GET /notifications?unread_only=true`
- `GET /notifications/unread-count` — badge count
- `POST /notifications/{id}/read`, `POST /notifications/read-all`

Each notification carries `target: { "type": "challenge", "id": "CH-..." }` for deep linking.

---

## Uploads

`POST /uploads` (multipart, field `file`) returns `{ url, kind, filename, size_bytes }`.
Feed the returned `url` straight into `attachments` on `POST /challenges`.
Uses Cloudinary when `CLOUDINARY_URL` is set, local disk otherwise.

---

## Errors

All errors return `{ "detail": "message" }`.

| Code | Meaning |
|---|---|
| 401 | Missing, invalid, or expired token |
| 403 | Authenticated but wrong role |
| 404 | Not found |
| 409 | Conflicting state (e.g. project already exists for that challenge) |
| 413 / 415 | Upload too large / wrong type |
| 422 | Request body failed validation (FastAPI shape) |
