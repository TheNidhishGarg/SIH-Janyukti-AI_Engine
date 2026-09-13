"""Direct access to the AI engine, decoupled from the challenge lifecycle.

Two reasons this exists: the app can preview AI output before a citizen hits
submit (showing the detected category and any likely duplicate while they are
still typing), and the models can be evaluated without touching workflow state.
"""
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.core.security import get_current_user
from app.db import get_db
from app.ml import categorizer, duplicates, llm, matching, pipeline
from app.ml import priority as priority_mod
from app.ml.embeddings import active_model_name, embedding_dim
from app.ml.taxonomy import CATEGORIES
from app.models import User
from app.schemas.ml import (
    AnalysisOut,
    AnalyzeRequest,
    CategoryOut,
    DuplicateCheckOut,
    DuplicateCheckRequest,
    MatchRequest,
    MlStatusOut,
    PriorityOut,
)
from app.schemas.org import MatchOut

router = APIRouter(prefix="/ml", tags=["AI Engine"])


@router.get("/status", response_model=MlStatusOut)
async def status():
    """Which engine is actually live - useful when demoing with no API key."""
    return MlStatusOut(
        llm_available=llm.is_available(),
        llm_model=settings.GEMINI_MODEL if llm.is_available() else "heuristic-fallback",
        embedding_model=active_model_name(),
        embedding_dim=embedding_dim(),
        using_local_embeddings=settings.USE_LOCAL_EMBEDDINGS,
        duplicate_threshold=duplicates.default_threshold(),
        categories=CATEGORIES,
    )


@router.get("/categories", response_model=list[str])
async def categories():
    return CATEGORIES


@router.post("/categorize", response_model=CategoryOut)
async def categorize(payload: AnalyzeRequest, _: User = Depends(get_current_user)):
    result = await categorizer.classify(payload.title, payload.description, payload.location)
    return CategoryOut(
        category=result.category,
        confidence=result.confidence,
        tags=result.tags,
        engine=result.engine,
        needs_review=result.needs_review,
    )


@router.post("/priority", response_model=PriorityOut)
async def score_priority(payload: AnalyzeRequest, _: User = Depends(get_current_user)):
    result = await priority_mod.score(
        payload.title, payload.description, payload.category or "Other", payload.location
    )
    return PriorityOut(
        priority=result.priority,
        score=result.score,
        scores=result.scores,
        rationale=result.rationale,
        engine=result.engine,
    )


@router.post("/duplicates", response_model=DuplicateCheckOut)
async def check_duplicates(
    payload: DuplicateCheckRequest,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_user),
):
    threshold = payload.threshold or duplicates.default_threshold()
    candidates, best = await duplicates.find_duplicates(
        db,
        title=payload.title,
        description=payload.description,
        category=payload.category,
        location=payload.location,
        district=payload.district,
        exclude_id=payload.exclude_id,
        threshold=threshold,
    )
    return DuplicateCheckOut(
        is_duplicate=best is not None,
        threshold=threshold,
        best_match=best.__dict__ if best else None,
        candidates=[c.__dict__ for c in candidates],
    )


@router.post("/match", response_model=list[MatchOut])
async def match_universities(
    payload: MatchRequest,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_user),
):
    ranked = await matching.rank_universities(
        db,
        title=payload.title,
        description=payload.description,
        category=payload.category,
        location=payload.location,
        district=payload.district,
        state=payload.state,
        tags=payload.tags,
        top_k=payload.top_k,
    )
    await db.commit()  # persists any embeddings backfilled during ranking
    return [
        MatchOut(
            university_id=c.university_id,
            name=c.name,
            department=c.department,
            city=c.city,
            state=c.state,
            score=c.score,
            semantic_score=c.semantic_score,
            category_score=c.category_score,
            capacity_score=c.capacity_score,
            proximity_score=c.proximity_score,
            rank=i,
            reasons=c.reasons,
            active_projects=c.active_projects,
            capacity=c.capacity,
        )
        for i, c in enumerate(ranked, start=1)
    ]


@router.post("/analyze", response_model=AnalysisOut)
async def analyze(
    payload: AnalyzeRequest,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_user),
):
    """Run the full engine without persisting anything."""
    result = await pipeline.analyze(
        db,
        title=payload.title,
        description=payload.description,
        category_hint=payload.category,
        location=payload.location,
        district=payload.district,
        state=payload.state,
        run_matching=payload.run_matching,
    )
    await db.commit()
    return AnalysisOut(**result.to_dict())
