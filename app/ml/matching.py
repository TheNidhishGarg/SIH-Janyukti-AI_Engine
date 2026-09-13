"""Smart matching: rank university departments against a challenge.

Four signals, deliberately kept separate and returned to the caller so the
admin screen can explain a recommendation instead of asserting it. The
Elsevier finding cited in our deck - that mismatched scope/capacity is the top
cause of failed university-industry collaborations - is why capacity is a
scoring term and not an afterthought.
"""
from __future__ import annotations

from dataclasses import dataclass, field

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.ml.embeddings import (
    active_model_name,
    challenge_text,
    cosine_similarity_matrix,
    embed,
    embed_many,
    university_text,
)
from app.models import University

WEIGHTS = {
    "semantic": 0.50,   # does the department's expertise text match the problem
    "category": 0.25,   # does it declare this category
    "capacity": 0.15,   # can it actually take the work on
    "proximity": 0.10,  # is it near the affected community
}


@dataclass
class MatchCandidate:
    university_id: str
    name: str
    department: str
    score: float
    semantic_score: float
    category_score: float
    capacity_score: float
    proximity_score: float
    reasons: list[str] = field(default_factory=list)
    city: str = ""
    state: str = ""
    active_projects: int = 0
    capacity: int = 0


def _category_score(challenge_category: str, uni: University, tags: list[str]) -> tuple[float, str | None]:
    cats = [c.lower() for c in (uni.categories or [])]
    target = (challenge_category or "").lower()
    if target and target in cats:
        return 1.0, f"Declares {challenge_category} as a focus area"

    # Partial credit for a shared domain root, e.g. "Water Management" vs
    # "Water & Sanitation Engineering".
    root = target.split(" &")[0].split(" ")[0] if target else ""
    if root and any(root in c for c in cats):
        return 0.6, f"Works in a related domain to {challenge_category}"

    uni_tags = {t.lower() for t in (uni.expertise_tags or [])}
    overlap = uni_tags & {t.lower() for t in tags}
    if overlap:
        return 0.45, f"Expertise overlap: {', '.join(sorted(overlap)[:3])}"
    return 0.0, None


def _capacity_score(uni: University) -> tuple[float, str | None]:
    capacity = max(uni.capacity or 0, 0)
    if capacity == 0:
        return 0.0, "No declared capacity"
    free = capacity - (uni.active_projects or 0)
    if free <= 0:
        return 0.0, f"At full capacity ({uni.active_projects}/{capacity} projects)"
    ratio = free / capacity
    # A track record of completed projects is worth a modest bump.
    track_record = min((uni.completed_projects or 0) * 0.05, 0.2)
    return round(min(1.0, ratio + track_record), 3), f"{free} of {capacity} project slots free"


def _proximity_score(uni: University, district: str | None, state: str | None) -> tuple[float, str | None]:
    uni_city = (uni.city or "").strip().lower()
    uni_state = (uni.state or "").strip().lower()
    d = (district or "").strip().lower()
    s = (state or "").strip().lower()

    if d and uni_city and d == uni_city:
        return 1.0, f"Located in {uni.city}, same district as the challenge"
    if s and uni_state and s == uni_state:
        return 0.6, f"Located in the same state ({uni.state})"
    if not d and not s:
        return 0.5, None  # unknown location should not punish anyone
    return 0.2, None


async def ensure_university_embeddings(db: AsyncSession, universities: list[University]) -> None:
    """Backfill or refresh embeddings whose model no longer matches the active one."""
    model_name = active_model_name()
    stale = [u for u in universities if not u.embedding or u.embedding_model != model_name]
    if not stale:
        return

    texts = [
        university_text(u.name, u.department, u.expertise_summary, u.expertise_tags or [], u.categories or [])
        for u in stale
    ]
    for uni, vec in zip(stale, embed_many(texts)):
        uni.embedding = vec
        uni.embedding_model = model_name
    await db.flush()


async def rank_universities(
    db: AsyncSession,
    title: str,
    description: str,
    category: str = "",
    location: str = "",
    district: str | None = None,
    state: str | None = None,
    tags: list[str] | None = None,
    embedding: list[float] | None = None,
    top_k: int | None = None,
) -> list[MatchCandidate]:
    top_k = top_k or settings.MATCH_TOP_K
    tags = tags or []

    universities = list((await db.scalars(select(University))).all())
    if not universities:
        return []

    await ensure_university_embeddings(db, universities)

    query_vec = embedding or embed(challenge_text(title, description, category, location))
    sims = cosine_similarity_matrix(query_vec, [u.embedding or [] for u in universities])

    candidates: list[MatchCandidate] = []
    for uni, semantic in zip(universities, sims):
        semantic = float(semantic)
        cat_score, cat_reason = _category_score(category, uni, tags)
        cap_score, cap_reason = _capacity_score(uni)
        prox_score, prox_reason = _proximity_score(uni, district, state)

        total = (
            WEIGHTS["semantic"] * semantic
            + WEIGHTS["category"] * cat_score
            + WEIGHTS["capacity"] * cap_score
            + WEIGHTS["proximity"] * prox_score
        )

        reasons = [r for r in (cat_reason, prox_reason, cap_reason) if r]
        if semantic >= 0.5:
            reasons.insert(0, f"Strong expertise match ({semantic:.0%} similarity)")
        elif semantic >= 0.3:
            reasons.insert(0, f"Partial expertise match ({semantic:.0%} similarity)")

        candidates.append(
            MatchCandidate(
                university_id=uni.id,
                name=uni.name,
                department=uni.department,
                score=round(min(1.0, total), 4),
                semantic_score=round(semantic, 4),
                category_score=round(cat_score, 4),
                capacity_score=round(cap_score, 4),
                proximity_score=round(prox_score, 4),
                reasons=reasons[:4],
                city=uni.city,
                state=uni.state,
                active_projects=uni.active_projects or 0,
                capacity=uni.capacity or 0,
            )
        )

    candidates.sort(key=lambda c: c.score, reverse=True)
    return candidates[:top_k]
