"""Industry collaboration module: browse challenges, register interest, fund work."""
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.ids import new_uuid
from app.core.security import get_current_user, require_roles
from app.db import get_db
from app.models import (
    Challenge,
    ChallengeStatus,
    IndustryInterest,
    IndustryProfile,
    InterestStatus,
    Project,
    User,
    UserRole,
)
from app.schemas.challenge import ChallengeOut
from app.schemas.org import IndustryCreate, IndustryOut, InterestCreate, InterestOut
from app.schemas.stats import IndustryStats
from app.services import notifications as notif
from app.services.serializers import challenge_out, interest_out

router = APIRouter(prefix="/industry", tags=["Industry"])


@router.get("/profiles", response_model=list[IndustryOut])
async def list_profiles(db: AsyncSession = Depends(get_db)):
    rows = list((await db.scalars(select(IndustryProfile).order_by(IndustryProfile.name))).all())
    return [IndustryOut.model_validate(r) for r in rows]


@router.post("/profiles", response_model=IndustryOut, status_code=status.HTTP_201_CREATED)
async def create_profile(
    payload: IndustryCreate,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(require_roles(UserRole.admin)),
):
    profile = IndustryProfile(id=new_uuid(), **payload.model_dump())
    db.add(profile)
    await db.commit()
    await db.refresh(profile)
    return IndustryOut.model_validate(profile)


@router.get("/opportunities", response_model=list[ChallengeOut])
async def opportunities(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(UserRole.industry, UserRole.admin)),
    category: str | None = None,
    limit: int = Query(50, ge=1, le=200),
):
    """Challenges worth backing: already validated, not yet delivered.

    Defaults to the caller focus categories, because an unfiltered firehose is
    the reason industry partners stop opening the app.
    """
    stmt = select(Challenge).where(
        Challenge.status.in_(
            [ChallengeStatus.assigned, ChallengeStatus.in_progress, ChallengeStatus.under_review]
        )
    )
    if category:
        stmt = stmt.where(Challenge.category == category)
    elif user.industry is not None and user.industry.focus_categories:
        stmt = stmt.where(Challenge.category.in_(user.industry.focus_categories))

    rows = list((await db.scalars(stmt.order_by(Challenge.created_at.desc()).limit(limit))).all())
    return [challenge_out(c) for c in rows]


@router.post("/interests", response_model=InterestOut, status_code=status.HTTP_201_CREATED)
async def register_interest(
    payload: InterestCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(UserRole.industry, UserRole.admin)),
):
    if not user.industry_id:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "User is not linked to an industry profile")
    if not payload.challenge_id and not payload.project_id:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Provide challenge_id or project_id")

    target_name = payload.challenge_id or payload.project_id
    if payload.challenge_id:
        if not await db.scalar(select(Challenge.id).where(Challenge.id == payload.challenge_id)):
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Challenge not found")
    if payload.project_id:
        if not await db.scalar(select(Project.id).where(Project.id == payload.project_id)):
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Project not found")

    interest = IndustryInterest(
        id=new_uuid(),
        challenge_id=payload.challenge_id,
        project_id=payload.project_id,
        industry_id=user.industry_id,
        created_by_id=user.id,
        support=payload.support,
        message=payload.message,
        funding_amount=payload.funding_amount,
    )
    db.add(interest)

    company = user.industry.name if user.industry else "An industry partner"
    await notif.notify_role(
        db,
        UserRole.admin,
        "Industry interest registered",
        f"{company} offered {', '.join(payload.support) or 'support'} on {target_name}",
        kind="industry",
        target={"type": "challenge", "id": payload.challenge_id} if payload.challenge_id else None,
    )
    await db.commit()
    await db.refresh(interest)
    return interest_out(interest)


@router.get("/interests", response_model=list[InterestOut])
async def list_interests(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    challenge_id: str | None = None,
    project_id: str | None = None,
):
    stmt = select(IndustryInterest)
    if challenge_id:
        stmt = stmt.where(IndustryInterest.challenge_id == challenge_id)
    if project_id:
        stmt = stmt.where(IndustryInterest.project_id == project_id)
    if user.role == UserRole.industry:
        stmt = stmt.where(IndustryInterest.industry_id == user.industry_id)

    rows = list((await db.scalars(stmt.order_by(IndustryInterest.created_at.desc()))).all())
    return [interest_out(i) for i in rows]


@router.post("/interests/{interest_id}/decision", response_model=InterestOut)
async def decide_interest(
    interest_id: str,
    accept: bool,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(require_roles(UserRole.admin, UserRole.university)),
):
    interest = await db.scalar(select(IndustryInterest).where(IndustryInterest.id == interest_id))
    if interest is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Interest not found")

    interest.status = InterestStatus.accepted if accept else InterestStatus.declined
    await notif.notify(
        db,
        interest.created_by_id,
        "Interest accepted" if accept else "Interest declined",
        f"Your offer on {interest.challenge_id or interest.project_id} was reviewed.",
        kind="industry",
    )
    await db.commit()
    await db.refresh(interest)
    return interest_out(interest)


@router.get("/stats", response_model=IndustryStats)
async def stats(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(UserRole.industry, UserRole.admin)),
):
    industry_id = user.industry_id
    base = select(IndustryInterest)
    if industry_id:
        base = base.where(IndustryInterest.industry_id == industry_id)

    rows = list((await db.scalars(base)).all())
    accepted = [i for i in rows if i.status == InterestStatus.accepted]
    return IndustryStats(
        interests_submitted=len(rows),
        accepted=len(accepted),
        projects_supported=len({i.project_id for i in accepted if i.project_id}),
        total_funding=sum(i.funding_amount or 0.0 for i in accepted),
    )
