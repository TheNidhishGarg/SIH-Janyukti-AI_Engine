"""Near-duplicate detection over previously submitted challenges.

Semantic similarity alone over-fires: two unrelated villages both reporting
"dirty drinking water" are genuinely different challenges. So the final score
blends embedding cosine with lexical overlap and a location gate - duplicates
in civic reporting are almost always same-place-same-problem.

Scoring is independent of storage. `rank_candidates` works on anything with the
right attributes, so the same logic serves the backend's own Challenge table
and the index of challenges that live in the app's Firestore database.
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Iterable

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.ml.embeddings import active_model_name, challenge_text, cosine_similarity_matrix, embed
from app.models import Challenge, ChallengeStatus, IndexedChallenge

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
# Anything scoring above this is listed as "possibly related" for an admin.
REPORTING_FLOOR = 0.35

# Statuses whose challenges should never be offered as the original report.
EXCLUDED_STATUSES = ("rejected", "duplicate")


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
    from app.ml.embeddings import FALLBACK_MODEL_NAME

    if active_model_name() == FALLBACK_MODEL_NAME:
        return FALLBACK_THRESHOLD
    return settings.DUPLICATE_SIMILARITY_THRESHOLD


def rank_candidates(
    candidates: Iterable,
    title: str,
    description: str,
    category: str = "",
    location: str = "",
    district: str | None = None,
    embedding: list[float] | None = None,
    top_k: int = 5,
    threshold: float | None = None,
) -> tuple[list[DuplicateCandidate], DuplicateCandidate | None]:
    """Score candidate challenges against a new report.

    Candidates need id, title, description, location, district, status,
    embedding, embedding_model and created_at attributes. Returns everything
    above the reporting floor, plus the best candidate if it clears the
    threshold. The first list is what an admin sees as "possibly related",
    which is useful well below the auto-flag bar.
    """
    threshold = default_threshold() if threshold is None else threshold
    candidates = list(candidates)
    if not candidates:
        return [], None

    query_vec = embedding or embed(challenge_text(title, description, category, location))
    query_loc = _location_key(location, district)

    # Only compare against vectors from the same embedding backend; mixing
    # MiniLM and hashing vectors would produce meaningless similarities.
    model_name = active_model_name()
    comparable = [c for c in candidates if c.embedding and c.embedding_model == model_name]

    sims: dict[str, float] = {}
    if comparable:
        matrix = cosine_similarity_matrix(query_vec, [c.embedding for c in comparable])
        sims = {c.id: float(s) for c, s in zip(comparable, matrix)}

    results: list[DuplicateCandidate] = []
    for cand in candidates:
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
        if combined < REPORTING_FLOOR:
            continue

        status = getattr(cand.status, "value", cand.status) or ""
        results.append(
            DuplicateCandidate(
                challenge_id=cand.id,
                title=cand.title,
                score=round(combined, 4),
                semantic_score=round(semantic, 4),
                lexical_score=round(lexical, 4),
                same_location=same_location,
                status=str(status),
                created_at=cand.created_at.isoformat() if cand.created_at else None,
            )
        )

    results.sort(key=lambda r: r.score, reverse=True)
    results = results[:top_k]
    best = results[0] if results and results[0].score >= threshold else None
    return results, best


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
    """Duplicates among challenges stored in the backend's own database."""
    stmt = select(Challenge).where(
        Challenge.status.notin_([ChallengeStatus.rejected, ChallengeStatus.duplicate])
    )
    if exclude_id:
        stmt = stmt.where(Challenge.id != exclude_id)
    existing = list((await db.scalars(stmt)).all())
    return rank_candidates(
        existing, title, description, category, location, district, embedding, top_k, threshold
    )


async def find_indexed_duplicates(
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
    """Duplicates among challenges indexed from the app's Firestore database."""
    stmt = select(IndexedChallenge).where(
        func.lower(IndexedChallenge.status).notin_(EXCLUDED_STATUSES)
    )
    if exclude_id:
        stmt = stmt.where(IndexedChallenge.id != exclude_id)
    existing = list((await db.scalars(stmt)).all())
    return rank_candidates(
        existing, title, description, category, location, district, embedding, top_k, threshold
    )
