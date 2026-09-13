# The AI Engine

Four models sit behind stage 2 and 3 of the JanYukti pipeline. This document
covers what each one does, how it scores, and why it is built that way.

## Design principle: two paths, always

Every model has an LLM path and an offline path:

| | LLM path | Offline path |
|---|---|---|
| Categorization | Gemini structured JSON | Weighted keyword lexicon |
| Priority | Gemini rubric scoring | Signal-phrase rubric |
| Embeddings | sentence-transformers MiniLM (384-d) | Hashed n-gram vectors (256-d) |
| Duplicates | same algorithm, different vectors | |
| Matching | same algorithm, different vectors | |

The offline path is not a stub. It is measured: on the seeded dataset it
classifies **5/5 challenges correctly with no API key and no model download**,
and the test suite asserts correct routing across seven categories.

Two reasons this matters for a hackathon:

1. **The demo cannot fail.** No API quota, no network at the venue, no 2 GB
   torch download minutes before judging.
2. **It bounds the LLM.** The lexicon cross-checks the Gemini answer; when they
   disagree, confidence is capped and the item is routed for human review
   instead of being silently mis-filed.

`GET /ml/status` reports which path is live.

---

## 1. Categorization

`app/ml/categorizer.py` — output `{category, confidence, tags, engine, needs_review}`

The taxonomy (`app/ml/taxonomy.py`) has 11 categories. The first five are exactly
the ones already in the Flutter dropdown, so nothing in the app breaks.

**Offline scoring.** Each category owns a weighted keyword lexicon, including
Hindi transliterations common in citizen submissions (`pani`, `bijli`, `kisan`,
`kachra`, `sadak`, `rozgar`).

- A keyword in the **title** counts double. A citizen title is usually the
  crispest statement of the problem.
- Repeated mentions have **diminishing returns**; five mentions is not five times
  the evidence of one.
- Confidence blends **absolute evidence** with the **margin over second place**,
  so an ambiguous "water and waste" report scores lower than a clear-cut one.

**Confidence is load-bearing.** Below `0.45` the result carries
`needs_review: true`, and the admin dashboard surfaces it for manual filing.
A classifier that is wrong silently is worse than one that admits uncertainty.

---

## 2. Priority scoring

`app/ml/priority.py` — output `{priority, score, scores, rationale, engine}`

Four axes, each 1-5:

| Axis | Weight | 1 | 5 |
|---|---|---|---|
| `severity` | 0.35 | Minor inconvenience | Risk to life or health |
| `urgency` | 0.30 | Can wait a year | Needs action this week |
| `reach` | 0.20 | One household | An entire district |
| `vulnerability` | 0.15 | General population | Children, elderly, pregnant women, marginalised groups |

Weighted mean, normalised to 0-1, then multiplied by a category severity weight
(health and water carry a higher baseline risk than, say, a portal outage).
Buckets: 0.62 and above is High, 0.38 and above is Medium, else Low.

**Why a visible rubric rather than a single number.** An admin overriding a
"High" needs something to argue with. `scores` and `rationale` come back on every
challenge, so the dashboard can say *High - driven by severity (5/5):
contamination, disease* rather than *High, trust us*.

The offline path moves axes on signal phrases (`outbreak` adds 1.8 to severity,
`children` adds 1.5 to vulnerability) and overrides `reach` outright on an
explicit headcount: "affects 2,000 people" is stronger evidence than any adjective.

---

## 3. Duplicate detection

`app/ml/duplicates.py` — output `{is_duplicate, threshold, best_match, candidates}`

```
score = 0.65 * cosine(embeddings) + 0.35 * jaccard(keywords)
        + 0.08 if same district
        - 0.12 if different districts
```

**Why not cosine alone.** Two villages 200 km apart both reporting "dirty
drinking water" are semantically near-identical and are *not* duplicates. In
civic reporting, a real duplicate is almost always same-place-same-problem, so
location is a first-class term rather than a post-filter. The test suite asserts
both directions: a restatement of the same Ranchi report is caught; the same
wording from Palamu is not.

Two thresholds, deliberately:

- **0.35** — reporting floor. Everything above shows as "possibly related" in
  the admin UI, which is useful well below the auto-flag bar.
- **0.85** (`DUPLICATE_SIMILARITY_THRESHOLD`) — auto-flag. The challenge is
  marked `Duplicate` and an admin confirms or clears it.

Confirming a duplicate **transfers the upvote to the original** rather than
discarding the report. Ten people reporting the same pothole is a signal about
priority, not noise.

Vectors are only compared against others from the **same embedding backend** —
MiniLM and hashed vectors are not comparable, and mixing them would produce
confident nonsense. `POST /admin/reindex` re-embeds after a backend switch.

---

## 4. Smart matching

`app/ml/matching.py` — ranked universities, each with a score breakdown and reasons.

```
score = 0.50 * semantic     cosine(challenge, department expertise text)
      + 0.25 * category     declared focus area overlap
      + 0.15 * capacity     free project slots, plus a completed-project bonus
      + 0.10 * proximity    same district > same state > elsewhere
```

**Why capacity is a scoring term and not an afterthought.** The Elsevier finding
cited on slide 6 of the deck is that 72% of university-industry collaborations
are only "partially successful", with mismatched scope and timelines the top
cause. A department already at capacity is the single most predictable way to
reproduce that failure. So a full department is ranked down even when it is the
best semantic match, and the UI says so.

**Every suggestion is explainable.** `reasons` comes back as human-readable
strings: *Strong expertise match (71% similarity)*, *3 of 5 project slots free*,
*Located in Ranchi, same district as the challenge*. The admin is confirming a
recommendation, not obeying one.

**Override tracking.** When an admin picks a university the ranker did not put
first, that is recorded on the `Match` row. `GET /admin/stats` exposes
`match_acceptance_rate`, the share of AI top picks admins kept. That number is
the honest measure of whether the matcher is any good, and it improves with real
usage data rather than with claims.

---

## Embeddings

`app/ml/embeddings.py`

Primary: `all-MiniLM-L6-v2`, 384-d, normalised.

Fallback: a deterministic hashed vectorizer, 256-d, over word unigrams **plus
character trigrams**. The trigrams give it partial robustness to typos and to
the transliterated spellings common in citizen text — `sadak` and `sadaak` share
most of their trigrams. Sublinear (log) scaling stops long descriptions from
dominating short ones.

Model loading is lazy, thread-safe, and never raises: any failure logs a warning
and falls through. A missing model degrades the system; it does not stop it.

---

## Known limits

Being explicit about these is more useful than overclaiming:

- **The lexicon is hand-built.** It generalises to unseen phrasings only as far
  as the keywords reach. The LLM path covers the gap; with a real labelled
  corpus, this should become a trained classifier.
- **No ground-truth evaluation set yet.** Accuracy claims here are against the
  seeded examples and the test suite, not a held-out benchmark. Building a
  labelled set of real citizen reports is the highest-value next step.
- **Matching is cold-start.** Expertise profiles are self-declared and there is
  no outcome feedback loop yet. `match_acceptance_rate` is the hook where one
  would attach: re-weight the scoring terms against what admins actually chose.
- **Linear scan.** Duplicate detection and matching load all candidates and
  compare in NumPy. Fine into the low tens of thousands of rows; past that, move
  to pgvector.

---

## Where university profiles come from

Two layers, both **Jharkhand-only**. Assignments that cross a state border need
an inter-state arrangement before anyone can start work, which is a governance
problem the platform cannot solve, so the pilot keeps everything inside one
state. `scripts/ingest_openalex.py --scope nearby` widens the radius if a
multi-state rollout is ever in scope.

| Layer | Source | Rows | Evidence behind the text |
|---|---|---|---|
| `curated` | `app/seed.py` | 10 | What a department publicly does |
| `openalex` | `scripts/ingest_openalex.py` | 19 | Publication record, via the OpenAlex API |

### The research-derived layer

```bash
python -m scripts.ingest_openalex --dry-run     # preview
python -m scripts.ingest_openalex               # write + re-embed
```

OpenAlex is free and needs no API key. Set `OPENALEX_MAILTO` to opt into its
faster "polite pool"; requests are anonymous otherwise.

Three decisions worth knowing about:

**Scope is geographic, not by state label.** OpenAlex populates a region string
for only ~69% of Indian institutions, and the missing ones include **IIT (ISM)
Dhanbad and NIT Jamshedpur** — the two largest technical institutions in the
state. Coordinates are present for 100%, so scope is decided by a Jharkhand
bounding box plus a city list, with the region string as a shortcut. That
recovers 18 institutions where filtering on `region == "Jharkhand"` finds 10.

**Institutions are split into per-category departments.** OpenAlex is
institution-level, but matching works on departments. Embedding all 25 topics of
a large university into one vector dilutes it until every big name matches every
challenge. So each institution becomes up to four rows — one per civic category
it genuinely publishes in — and each row embeds only that category's topics.

**Topic names decide; subfields are a weak fallback.** An early version had
Jadavpur, IIT Dhanbad, IIT BHU and IISER Kolkata all at *100% Energy &
Infrastructure*, which is obviously wrong. Three leaks caused it: the
`Electrical and Electronic Engineering` subfield (39k publications of antennas,
VLSI and photonics) contributing at scale, the pattern `solar` matching **Solar
and Space Plasma Dynamics**, and wireless-sensor `energy harvesting`. The fix
was an explicit `EXCLUDE_PATTERNS` list plus dropping the EEE fallback entirely.
After it, BHU reads 68% Agriculture (it does run the Institute of Agricultural
Sciences) and IIT Kharagpur 46% Water.

### Why both layers exist

Publication count measures research strength. It does not measure whether a
department can run a village waste-segregation pilot — a polytechnic with zero
indexed papers often can. Ranking on publications alone would systematically
exclude exactly the institutions best suited to applied civic work, and it
leaves **Waste Management, Transportation & Safety and Education with no
coverage at all** in Jharkhand, because that work happens in classrooms and
field projects rather than in journals.

So the curated layer is not a placeholder to be deleted later. It is how
teaching-and-fieldwork capacity enters a system that would otherwise only see
research output. Both layers carry a `source` column; the admin UI should show it.

### Honest limits of this data

- `department` values on `openalex` rows are **derived research-strength
  groupings, not verified department names**. "Water Resources & Environmental
  Engineering" describes a publication cluster, not a real organisational unit.
  Verify before contacting anyone.
- The curated layer's expertise text is written from public descriptions, not
  audited. Same caveat.
- Capacity is inferred from publication volume on `openalex` rows and assigned
  by hand on curated ones. Neither reflects a department's actual willingness or
  free time. Real capacity has to come from the universities themselves.
