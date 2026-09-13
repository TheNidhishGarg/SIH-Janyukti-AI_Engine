"""Near-duplicate detection over previously submitted challenges.

Semantic similarity alone over-fires: two unrelated villages both reporting
"dirty drinking water" are genuinely different challenges. So the final score
blends embedding cosine with lexical overlap and a location gate - duplicates
in civic reporting are almost always same-place-same-problem.
"""
from __future__ import annotations

import re
from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.ml.embeddings import challenge_text, cosine_similarity_matrix, embed
from app.models import Challenge, ChallengeStatus

_WORD_RE = re.compile(r"[a-z0-9]{3,}")
_STOPWORDS = {
    "the", "and", "for", "are", "our", "this", "that", "with", "from", "have",
    "has", "not", "but", "they", "there", "their", "been", "which", "also",
    "need", "needed", "issue", "problem", "people", "area", "areas", "many",
    "due", "very", "some", "more", "can", "all", "into", "near", "were",
}

# The configured threshold is calibrated for MiniLM, where a paraphrase of the
# same report scores ~0.85. The hashing fallback is a weaker semantic model, so
# applying the MiniLM bar to it means duplicate detection never fires at all.
# Each backend therefore gets its own default.
#
# 0.35 comes from measuring four true-paraphrase pairs (0.372-0.440) against
# four unrelated pairs (0.082-0.236) on this backend; see
# tests/test_duplicate_calibration.py, which fails if that separation closes.
# It sits nearer the false-positive side on purpose: wrongly telling a citizen
# their genuine new report is a duplicate is worse than missing one, because an
# admin reviews flagged items anyway.
FALLBACK_THRESHOLD = 0.35

SEMANTIC_WEIGHT = 0.65
LEXICAL_WEIGHT = 0.35
# A same-location match needs less textual evidence to count as a duplicate.
SAME_LOCATION_BONUS = 0.08
DIFFERENT_LOCATION_PENALTY = 0.12


@dataclass
class DuplicateCandidate:
    challenge_id: str
    title: str
    score: float
    semantic_score: float
    lexical_score: float
    same_location: bool
    status: str
    created_at: str | None = None


def _keywords(text: str) -> set[str]:
    return {w for w in _WORD_RE.findall(text.lower()) if w not in _STOPWORDS}


def jaccard(a: str, b: str) -> float:
    ka, kb = _keywords(a), _keywords(b)
    if not ka or not kb:
        return 0.0
    return len(ka & kb) / len(ka | kb)


def _location_key(location: str | None, district: str | None) -> str:
    if district:
        return district.strip().lower()
    if not location:
        return ""
    # "Ranchi, Jharkhand" -> "ranchi"
    return location.split(",")[0].strip().lower()


def default_threshold() -> float:
    """Duplicate cutoff for whichever embedding backend is actually loaded."""
    from app.ml.embeddings import FALLBACK_MODEL_NAME, active_model_name

    if active_model_name() == FALLBACK_MODEL_NAME:
        return FALLBACK_THRESHOLD
    return settings.DUPLICATE_SIMILARITY_THRESHOLD


async def find_duplicates(
    db: AsyncSession,
    title: str,
    description: str,
    category: str = "",
    location: str = "",
    district: str | None = None,
    exclude_id: str | None = None,
    embedding: list[float] | None = None,
    top_k: int = 5,
    threshold: float | None = None,
) -> tuple[list[DuplicateCandidate], DuplicateCandidate | None]:
    """Return (candidates above a reporting floor, the best one above threshold).

    The second element is what the pipeline acts on; the first is what the admin
    UI lists as "possibly related", which is useful well below the auto-flag bar.
    """
    threshold = default_threshold() if threshold is None else threshold

    stmt = select(Challenge).where(
        Challenge.status.notin_([ChallengeStatus.rejected, ChallengeStatus.duplicate])
    )
    if exclude_id:
        stmt = stmt.where(Challenge.id != exclude_id)
    existing = list((await db.scalars(stmt)).all())
    if not existing:
        return [], None

    query_text = challenge_text(title, description, category, location)
    query_vec = embedding or embed(query_text)
    query_loc = _location_key(location, district)

    # Only compare against vectors from the same embedding backend; mixing
    # MiniLM and hashing vectors would produce meaningless similarities.
    from app.ml.embeddings import active_model_name

    model_name = active_model_name()
    comparable = [c for c in existing if c.embedding and c.embedding_model == model_name]

    sims: dict[str, float] = {}
    if comparable:
        matrix = cosine_similarity_matrix(query_vec, [c.embedding for c in comparable])
        sims = {c.id: float(s) for c, s in zip(comparable, matrix)}

    results: list[DuplicateCandidate] = []
    for cand in existing:
        semantic = sims.get(cand.id, 0.0)
        lexical = jaccard(f"{title} {description}", f"{cand.title} {cand.description}")

        combined = SEMANTIC_WEIGHT * semantic + LEXICAL_WEIGHT * lexical

        cand_loc = _location_key(cand.location, cand.district)
        same_location = bool(query_loc) and query_loc == cand_loc
        if same_location:
            combined += SAME_LOCATION_BONUS
        elif query_loc and cand_loc:
            combined -= DIFFERENT_LOCATION_PENALTY

        combined = max(0.0, min(1.0, combined))
        if combined >= 0.35:  # reporting floor for "possibly related"
            results.append(
                DuplicateCandidate(
                    challenge_id=cand.id,
                    title=cand.title,
                    score=round(combined, 4),
                    semantic_score=round(semantic, 4),
                    lexical_score=round(lexical, 4),
                    same_location=same_location,
                    status=cand.status.value,
                    created_at=cand.created_at.isoformat() if cand.created_at else None,
                )
            )

    results.sort(key=lambda r: r.score, reverse=True)
    results = results[:top_k]
    best = results[0] if results and results[0].score >= threshold else None
    return results, best
