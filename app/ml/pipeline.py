"""The AI Engine stage: one call that runs every model over a challenge.

Categorization and priority scoring are independent, so they run concurrently;
duplicate detection and matching both need the embedding, which is computed
once and reused by all three. Persisting happens in `apply_analysis` so the
analysis can also be previewed without writing anything.
"""
from __future__ import annotations

import asyncio
import logging
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone

from sqlalchemy import delete
from sqlalchemy.ext.asyncio import AsyncSession

from app.ml import categorizer, duplicates, matching
from app.ml import priority as priority_mod
from app.ml.embeddings import active_model_name, challenge_text, embed
from app.models import Challenge, ChallengeStatus, Match, MatchStatus, Priority
from app.core.ids import new_uuid

log = logging.getLogger(__name__)


@dataclass
class AnalysisResult:
    category: str
    category_confidence: float
    priority: str
    priority_score: float
    scores: dict
    rationale: str
    tags: list[str]
    engine: str
    needs_review: bool
    duplicate_of: str | None
    duplicate_score: float | None
    duplicate_candidates: list[dict] = field(default_factory=list)
    matches: list[dict] = field(default_factory=list)
    embedding: list[float] = field(default_factory=list)
    embedding_model: str = ""

    def to_dict(self) -> dict:
        data = asdict(self)
        data.pop("embedding", None)  # 384 floats are not useful to the client
        return data


async def analyze(
    db: AsyncSession,
    title: str,
    description: str,
    category_hint: str = "",
    location: str = "",
    district: str | None = None,
    state: str | None = None,
    exclude_id: str | None = None,
    run_matching: bool = True,
) -> AnalysisResult:
    text = challenge_text(title, description, category_hint, location)
    embedding = embed(text)
    model_name = active_model_name()

    cat_result, prio_pre = await asyncio.gather(
        categorizer.classify(title, description, location),
        # Scored again below with the final category; this first pass only
        # exists so the two LLM calls overlap instead of running back to back.
        priority_mod.score(title, description, category_hint or "Other", location),
    )

    # If the model disagreed with the citizen's own category pick, re-run the
    # rubric under the inferred one, since severity weighting is category-aware.
    if cat_result.category != (category_hint or "Other"):
        prio_result = await priority_mod.score(title, description, cat_result.category, location)
    else:
        prio_result = prio_pre

    dup_candidates, best_dup = await duplicates.find_duplicates(
        db,
        title=title,
        description=description,
        category=cat_result.category,
        location=location,
        district=district,
        exclude_id=exclude_id,
        embedding=embedding,
    )

    match_dicts: list[dict] = []
    if run_matching:
        ranked = await matching.rank_universities(
            db,
            title=title,
            description=description,
            category=cat_result.category,
            location=location,
            district=district,
            state=state,
            tags=cat_result.tags,
            embedding=embedding,
        )
        match_dicts = [asdict(m) for m in ranked]

    engine = "gemini" if "gemini" in (cat_result.engine, prio_result.engine) else "heuristic"

    return AnalysisResult(
        category=cat_result.category,
        category_confidence=cat_result.confidence,
        priority=prio_result.priority,
        priority_score=prio_result.score,
        scores=prio_result.scores,
        rationale=prio_result.rationale,
        tags=cat_result.tags,
        engine=engine,
        needs_review=cat_result.needs_review,
        duplicate_of=best_dup.challenge_id if best_dup else None,
        duplicate_score=best_dup.score if best_dup else None,
        duplicate_candidates=[asdict(c) for c in dup_candidates],
        matches=match_dicts,
        embedding=embedding,
        embedding_model=model_name,
    )


async def apply_analysis(
    db: AsyncSession,
    challenge: Challenge,
    result: AnalysisResult,
    overwrite_category: bool = False,
) -> Challenge:
    """Write an analysis onto a challenge and persist its suggested matches.

    The citizen's own category is preserved by default - the AI suggestion
    lives in ai_category so the admin can compare the two side by side.
    """
    challenge.ai_category = result.category
    challenge.ai_category_confidence = result.category_confidence
    challenge.ai_priority = Priority(result.priority)
    challenge.ai_priority_score = result.priority_score
    challenge.ai_scores = result.scores
    challenge.ai_rationale = result.rationale
    challenge.ai_tags = result.tags
    challenge.ai_engine = result.engine
    challenge.ai_analyzed_at = datetime.now(timezone.utc)
    challenge.embedding = result.embedding
    challenge.embedding_model = result.embedding_model

    # AI priority becomes the working priority unless an admin has overridden it.
    challenge.priority = Priority(result.priority)

    if overwrite_category or not challenge.category or challenge.category == "Other":
        challenge.category = result.category

    if result.duplicate_of:
        challenge.duplicate_of_id = result.duplicate_of
        challenge.duplicate_score = result.duplicate_score
        challenge.status = ChallengeStatus.duplicate
    else:
        challenge.status = ChallengeStatus.under_review

    # Replace any previous suggestions; admin-decided matches are left alone.
    await db.execute(
        delete(Match).where(
            Match.challenge_id == challenge.id,
            Match.status == MatchStatus.suggested,
        )
    )

    for rank, m in enumerate(result.matches, start=1):
        db.add(
            Match(
                id=new_uuid(),
                challenge_id=challenge.id,
                university_id=m["university_id"],
                score=m["score"],
                semantic_score=m["semantic_score"],
                category_score=m["category_score"],
                proximity_score=m["proximity_score"],
                capacity_score=m["capacity_score"],
                rank=rank,
                reasons=m["reasons"],
            )
        )

    await db.flush()
    return challenge
