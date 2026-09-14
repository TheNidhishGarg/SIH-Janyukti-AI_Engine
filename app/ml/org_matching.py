"""Rank the universities that have registered on JanYukti for a challenge.

An admin can only assign work to an institution with an account - that is what
lets the university see the challenge on its own dashboard. Registered
organisations in Firestore carry a name, a city and a university type, but no
expertise. The expertise lives in the backend's department profiles (curated
and publication-derived). So each registered organisation is linked by name to
the profiles of the same institution and ranked on the best of them.

Institutions with a strong profile that have not registered yet come back as a
separate directory list: useful for outreach, never assignable.
"""
from __future__ import annotations

from dataclasses import dataclass, field

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.ml.embeddings import (
    challenge_text,
    cosine_similarity,
    cosine_similarity_matrix,
    embed,
    embed_many,
)
from app.ml.institutions import institution_key, same_institution
from app.ml.matching import (
    WEIGHTS,
    MatchCandidate,
    _proximity_score,
    ensure_university_embeddings,
    score_university,
)
from app.models import University

# An organisation with no expertise profile can only be ranked on location and
# a thin name-based signal. The discount keeps it below any institution whose
# research actually matches the problem, while still ordering unprofiled
# organisations sensibly among themselves.
UNPROFILED_DISCOUNT = 0.6
NEUTRAL_CAPACITY = 0.5

SOURCE_LABELS = {
    "openalex": "publication record",
    "curated": "curated profile",
    "manual": "profile",
}


@dataclass
class OrganizationInput:
    id: str
    name: str
    city: str = ""
    state: str = ""
    type: str = ""


@dataclass
class OrganizationSuggestion:
    organization_id: str
    name: str
    city: str
    state: str
    score: float
    semantic_score: float
    category_score: float
    capacity_score: float
    proximity_score: float
    reasons: list[str] = field(default_factory=list)
    profile_linked: bool = False
    profile_id: str | None = None
    profile_institution: str | None = None
    profile_department: str | None = None
    profile_source: str | None = None
    rank: int = 0


@dataclass
class DirectorySuggestion:
    profile_id: str
    institution: str
    department: str
    city: str
    state: str
    score: float
    reasons: list[str] = field(default_factory=list)
    source: str = "manual"


async def _score_profiles(
    db: AsyncSession,
    query_vec: list[float],
    category: str,
    tags: list[str],
    district: str | None,
    state: str | None,
) -> list[tuple[MatchCandidate, University]]:
    universities = list((await db.scalars(select(University))).all())
    if not universities:
        return []
    await ensure_university_embeddings(db, universities)
    sims = cosine_similarity_matrix(query_vec, [u.embedding or [] for u in universities])
    return [
        (score_university(u, float(sim), category, tags, district, state), u)
        for u, sim in zip(universities, sims)
    ]


async def rank_organizations(
    db: AsyncSession,
    *,
    title: str,
    description: str,
    category: str = "",
    location: str = "",
    district: str | None = None,
    state: str | None = None,
    tags: list[str] | None = None,
    organizations: list[OrganizationInput],
    top_k: int = 5,
    directory_k: int = 3,
    embedding: list[float] | None = None,
) -> tuple[list[OrganizationSuggestion], list[DirectorySuggestion]]:
    """Return (registered organisations ranked, unregistered institutions worth inviting)."""
    tags = tags or []
    query_vec = embedding or embed(challenge_text(title, description, category, location))
    scored = await _score_profiles(db, query_vec, category, tags, district, state)

    suggestions: list[OrganizationSuggestion] = []
    unprofiled: list[OrganizationInput] = []

    for org in organizations:
        linked = [(c, u) for c, u in scored if same_institution(org.name, u.name)]
        if not linked:
            unprofiled.append(org)
            continue

        best, profile = max(linked, key=lambda pair: pair[0].score)
        source = profile.source or "manual"
        reasons = list(best.reasons)
        reasons.append(
            f"Expertise from {profile.department or profile.name} "
            f"({SOURCE_LABELS.get(source, 'profile')})"
        )
        suggestions.append(
            OrganizationSuggestion(
                organization_id=org.id,
                name=org.name,
                city=org.city or profile.city,
                state=org.state or profile.state,
                score=best.score,
                semantic_score=best.semantic_score,
                category_score=best.category_score,
                capacity_score=best.capacity_score,
                proximity_score=best.proximity_score,
                reasons=reasons[:5],
                profile_linked=True,
                profile_id=profile.id,
                profile_institution=profile.name,
                profile_department=profile.department,
                profile_source=source,
            )
        )

    if unprofiled:
        texts = [
            ". ".join(p for p in (o.name, o.type, f"{o.city}, {o.state}".strip(", ")) if p)
            for o in unprofiled
        ]
        for org, vec in zip(unprofiled, embed_many(texts)):
            semantic = cosine_similarity(query_vec, vec)
            proximity, proximity_reason = _proximity_score(org, district, state)
            raw = (
                WEIGHTS["semantic"] * semantic
                + WEIGHTS["proximity"] * proximity
                + WEIGHTS["capacity"] * NEUTRAL_CAPACITY
            )
            reasons = [proximity_reason] if proximity_reason else []
            reasons.append("No expertise profile on record yet, so ranked mainly on location")
            suggestions.append(
                OrganizationSuggestion(
                    organization_id=org.id,
                    name=org.name,
                    city=org.city,
                    state=org.state,
                    score=round(UNPROFILED_DISCOUNT * raw, 4),
                    semantic_score=round(semantic, 4),
                    category_score=0.0,
                    capacity_score=NEUTRAL_CAPACITY,
                    proximity_score=round(proximity, 4),
                    reasons=reasons,
                )
            )

    suggestions.sort(key=lambda s: s.score, reverse=True)
    suggestions = suggestions[:top_k]
    for rank, suggestion in enumerate(suggestions, start=1):
        suggestion.rank = rank

    directory: list[DirectorySuggestion] = []
    seen: set[str] = set()
    for candidate, profile in sorted(scored, key=lambda pair: pair[0].score, reverse=True):
        if len(directory) >= directory_k:
            break
        if any(same_institution(profile.name, org.name) for org in organizations):
            continue
        key = institution_key(profile.name)
        if key in seen:
            continue
        seen.add(key)
        directory.append(
            DirectorySuggestion(
                profile_id=profile.id,
                institution=profile.name,
                department=profile.department,
                city=profile.city,
                state=profile.state,
                score=candidate.score,
                reasons=list(candidate.reasons[:3]),
                source=profile.source or "manual",
            )
        )

    return suggestions, directory
