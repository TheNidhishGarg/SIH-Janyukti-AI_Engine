"""Challenge categorization: LLM-first, weighted-lexicon fallback.

Returns (category, confidence, tags, engine). Confidence is calibrated so the
admin UI can show "AI suggests X (62%)" and flag low-confidence items for
manual review rather than silently mis-filing them.
"""
from __future__ import annotations

from dataclasses import dataclass, field

from app.ml import llm
from app.ml.taxonomy import AMBIENT_TERMS, CATEGORIES, CATEGORY_KEYWORDS, normalize_category

# Below this, the admin dashboard surfaces the item as "needs manual review".
LOW_CONFIDENCE_THRESHOLD = 0.45


@dataclass
class CategoryResult:
    category: str
    confidence: float
    tags: list[str] = field(default_factory=list)
    engine: str = "heuristic"
    needs_review: bool = False


_PROMPT = """You are the classification engine for JanYukti, an Indian civic \
platform where citizens report local problems.

Classify the challenge below into EXACTLY ONE category from this list:
{categories}

Also extract 3-6 short lowercase topical tags (domain nouns, not sentiment).

Challenge title: {title}
Challenge description: {description}
Reported location: {location}

Respond with JSON only:
{{"category": "<one category, copied verbatim from the list>",
  "confidence": <float 0-1, how certain you are>,
  "tags": ["tag1", "tag2", "tag3"]}}"""


def classify_heuristic(title: str, description: str) -> CategoryResult:
    """Weighted keyword scoring over the taxonomy lexicon.

    Title matches count double: a citizen's title is usually the crispest
    statement of what the problem actually is.
    """
    text = f"{title} {description}".lower()
    title_text = title.lower()

    scores: dict[str, float] = {}
    hits: dict[str, list[str]] = {}
    for category, lexicon in CATEGORY_KEYWORDS.items():
        total = 0.0
        matched: list[str] = []
        for keyword, weight in lexicon.items():
            if keyword in text:
                occurrences = text.count(keyword)
                # Diminishing returns: 5 mentions is not 5x the signal of one.
                total += weight * (1 + 0.3 * min(occurrences - 1, 3))
                # Content words in the title count double; location markers do
                # not, so "sewage near the primary school" is not an Education
                # problem just because "school" leads the title.
                if keyword in title_text and keyword not in AMBIENT_TERMS:
                    total += weight
                matched.append(keyword)
        if total > 0:
            scores[category] = total
            hits[category] = matched

    if not scores:
        return CategoryResult("Other", 0.0, [], "heuristic", needs_review=True)

    ranked = sorted(scores.items(), key=lambda kv: kv[1], reverse=True)
    best, best_score = ranked[0]
    runner_up = ranked[1][1] if len(ranked) > 1 else 0.0

    # Confidence blends absolute evidence with the margin over second place, so
    # an ambiguous "water + waste" report scores lower than a clear-cut one.
    evidence = min(best_score / 8.0, 1.0)
    margin = (best_score - runner_up) / best_score if best_score else 0.0
    confidence = round(min(0.95, 0.45 * evidence + 0.55 * (0.4 + 0.6 * margin) * evidence + 0.1), 3)

    tags = sorted(set(hits[best]), key=lambda k: -CATEGORY_KEYWORDS[best][k])[:6]
    return CategoryResult(
        category=best,
        confidence=confidence,
        tags=tags,
        engine="heuristic",
        needs_review=confidence < LOW_CONFIDENCE_THRESHOLD,
    )


async def classify(title: str, description: str, location: str = "") -> CategoryResult:
    data = await llm.generate_json(
        _PROMPT.format(
            categories="\n".join(f"- {c}" for c in CATEGORIES),
            title=title,
            description=description,
            location=location or "not specified",
        )
    )

    if data and data.get("category"):
        category = normalize_category(str(data["category"]))
        try:
            confidence = float(data.get("confidence", 0.7))
        except (TypeError, ValueError):
            confidence = 0.7
        confidence = max(0.0, min(1.0, confidence))
        tags = [str(t).strip().lower() for t in (data.get("tags") or []) if str(t).strip()][:6]

        # Cross-check against the lexicon. Agreement is a confidence boost;
        # disagreement is a reason to route the item to a human, not to guess.
        fallback = classify_heuristic(title, description)
        if fallback.category != "Other" and fallback.category != category:
            confidence = min(confidence, 0.6)
        elif fallback.category == category:
            confidence = min(1.0, confidence + 0.1)

        return CategoryResult(
            category=category,
            confidence=round(confidence, 3),
            tags=tags or fallback.tags,
            engine="gemini",
            needs_review=confidence < LOW_CONFIDENCE_THRESHOLD,
        )

    return classify_heuristic(title, description)
