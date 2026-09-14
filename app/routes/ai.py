"""AI service endpoints consumed by the Flutter app.

These sit beside the original /challenges, /projects and /admin routes rather
than replacing them. The app keeps its data in Firestore, so here the backend is
an analysis service: it reads challenge text, answers in camelCase ready to be
stored on the Firestore document, and keeps only a small duplicate index.
"""
from dataclasses import asdict

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.core.firebase_auth import FirebaseUser, get_firebase_user
from app.db import get_db
from app.ml import ai_service, categorizer, llm
from app.ml.duplicates import default_threshold, find_indexed_duplicates
from app.ml.embeddings import active_model_name, challenge_text, embed, embedding_dim
from app.ml.org_matching import OrganizationInput, rank_organizations
from app.ml.taxonomy import APP_CATEGORIES, CATEGORIES
from app.models import University
from app.schemas.ai import (
    AiStatusOut,
    AnalysisOut,
    AnalyzeRequest,
    DuplicateCheckOut,
    DuplicateOut,
    DuplicatePreviewRequest,
    IndexStatusOut,
    InstitutionSuggestionOut,
    MatchOut,
    MatchRequest,
    OrganizationSuggestionOut,
    StatusUpdate,
    SyncOut,
    SyncRequest,
)

router = APIRouter(prefix="/ai", tags=["AI Service"])


def _duplicate_out(candidate) -> DuplicateOut:
    return DuplicateOut(**asdict(candidate))


def _analysis_out(result: ai_service.Analysis) -> AnalysisOut:
    return AnalysisOut(
        version=result.version,
        analyzed_at=result.analyzed_at,
        engine=result.engine,
        embedding_model=result.embedding_model,
        category=result.category,
        app_category=result.app_category,
        category_confidence=result.category_confidence,
        needs_review=result.needs_review,
        category_matches_citizen=result.category_matches_citizen,
        tags=result.tags,
        priority=result.priority,
        priority_score=result.priority_score,
        scores=result.scores,
        rationale=result.rationale,
        district=result.district,
        state=result.state,
        duplicate=_duplicate_out(result.duplicate) if result.duplicate else None,
        possible_duplicates=[_duplicate_out(c) for c in result.possible_duplicates],
        suggested_institutions=[
            InstitutionSuggestionOut(
                profile_id=s.university_id,
                institution=s.name,
                department=s.department,
                city=s.city,
                state=s.state,
                score=s.score,
                score_percent=round(s.score * 100),
                reasons=s.reasons,
                source=s.source,
            )
            for s in result.suggested_institutions
        ],
        indexed=result.indexed,
    )


@router.get("/status", response_model=AiStatusOut)
async def ai_status(db: AsyncSession = Depends(get_db)):
    """Unauthenticated, so the app can check the backend is reachable at startup."""
    profiles = await db.scalar(select(func.count()).select_from(University)) or 0
    return AiStatusOut(
        llm_available=llm.is_available(),
        llm_model=settings.GEMINI_MODEL if llm.is_available() else "heuristic",
        embedding_model=active_model_name(),
        embedding_dim=embedding_dim(),
        duplicate_threshold=default_threshold(),
        categories=CATEGORIES,
        app_categories=APP_CATEGORIES,
        indexed_challenges=await ai_service.index_size(db),
        university_profiles=profiles,
        auth_mode=settings.FIREBASE_AUTH_MODE,
    )


@router.post("/analyze", response_model=AnalysisOut)
async def analyze(
    payload: AnalyzeRequest,
    db: AsyncSession = Depends(get_db),
    user: FirebaseUser = Depends(get_firebase_user),
):
    """Categorise, score, check for duplicates and suggest institutions.

    Send the Firestore document id as challengeId after the challenge is saved;
    the app then writes the response onto that document as its `ai` field.
    """
    result = await ai_service.analyze_challenge(
        db,
        title=payload.title,
        description=payload.description,
        additional_info=payload.additional_info,
        category=payload.category,
        location=payload.location,
        challenge_id=payload.challenge_id,
        status=payload.status,
        submitted_by_uid=user.uid or payload.submitted_by_uid,
        index=payload.index,
    )
    await db.commit()
    return _analysis_out(result)


@router.post("/duplicates", response_model=DuplicateCheckOut)
async def preview_duplicates(
    payload: DuplicatePreviewRequest,
    db: AsyncSession = Depends(get_db),
    _: FirebaseUser = Depends(get_firebase_user),
):
    """Check a draft before it is submitted. Nothing is written to the index."""
    threshold = payload.threshold if payload.threshold is not None else default_threshold()
    description = ai_service.combine_description(payload.description, payload.additional_info)
    district, _state = ai_service.split_location(payload.location)
    candidates, best = await find_indexed_duplicates(
        db,
        title=payload.title,
        description=description,
        category=payload.category,
        location=payload.location,
        district=district,
        exclude_id=payload.exclude_challenge_id,
        threshold=threshold,
    )
    return DuplicateCheckOut(
        is_duplicate=best is not None,
        threshold=threshold,
        best_match=_duplicate_out(best) if best else None,
        candidates=[_duplicate_out(c) for c in candidates],
    )


@router.post("/match", response_model=MatchOut)
async def match_organizations(
    payload: MatchRequest,
    db: AsyncSession = Depends(get_db),
    _: FirebaseUser = Depends(get_firebase_user),
):
    """Rank the registered university organisations the admin can assign to.

    The app sends the approved organisations it reads from Firestore; the
    backend links each to the expertise profiles of the same institution.
    """
    description = ai_service.combine_description(payload.description, payload.additional_info)
    district, state = ai_service.split_location(payload.location)
    classified = await categorizer.classify(payload.title, description, payload.location)
    vector = embed(challenge_text(payload.title, description, payload.category, payload.location))

    registered, directory = await rank_organizations(
        db,
        title=payload.title,
        description=description,
        category=classified.category,
        location=payload.location,
        district=district,
        state=state,
        tags=classified.tags,
        organizations=[OrganizationInput(**org.model_dump()) for org in payload.organizations],
        top_k=payload.top_k,
        directory_k=payload.directory_k,
        embedding=vector,
    )
    await db.commit()  # persists any university embeddings backfilled while ranking

    return MatchOut(
        category=classified.category,
        registered=[
            OrganizationSuggestionOut(**asdict(s), score_percent=round(s.score * 100))
            for s in registered
        ],
        directory=[
            InstitutionSuggestionOut(**asdict(d), score_percent=round(d.score * 100))
            for d in directory
        ],
    )


@router.post("/index/sync", response_model=SyncOut)
async def sync_index(
    payload: SyncRequest,
    db: AsyncSession = Depends(get_db),
    _: FirebaseUser = Depends(get_firebase_user),
):
    """Index challenges created before the AI service existed, or edited since."""
    if payload.prune and not payload.challenges:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            "Refusing to prune the whole index with an empty challenge list",
        )
    counts = await ai_service.sync_index(db, payload.challenges, prune=payload.prune)
    await db.commit()
    return SyncOut(**counts, embedding_model=active_model_name())


@router.patch("/index/{challenge_id}", response_model=IndexStatusOut)
async def update_index_status(
    challenge_id: str,
    payload: StatusUpdate,
    db: AsyncSession = Depends(get_db),
    _: FirebaseUser = Depends(get_firebase_user),
):
    """Keep status in step, so rejected and duplicate challenges stop matching."""
    indexed = await ai_service.update_index_status(db, challenge_id, payload.status)
    await db.commit()
    return IndexStatusOut(challenge_id=challenge_id, status=payload.status, indexed=indexed)
