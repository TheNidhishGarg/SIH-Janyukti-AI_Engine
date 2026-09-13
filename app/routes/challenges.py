"""Challenge endpoints - the citizen-facing core of the platform."""
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import get_current_user, require_roles
from app.db import get_db
from app.models import Challenge, ChallengeStatus, Match, Priority, User, UserRole
from app.schemas.challenge import ChallengeCreate, ChallengeDetailOut, ChallengeOut, ChallengeUpdate
from app.schemas.common import Message, Page
from app.schemas.org import MatchOut
from app.services import challenge_service as svc
from app.services.serializers import challenge_detail_out, challenge_out, match_out

router = APIRouter(prefix="/challenges", tags=["Challenges"])


async def _get_challenge(challenge_id: str, db: AsyncSession) -> Challenge:
    challenge = await db.scalar(select(Challenge).where(Challenge.id == challenge_id))
    if challenge is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Challenge not found")
    return challenge


@router.post("", response_model=ChallengeDetailOut, status_code=status.HTTP_201_CREATED)
async def create_challenge(
    payload: ChallengeCreate,
    background: BackgroundTasks,
    analyze_sync: bool = Query(
        False,
        description="Run the AI engine inline instead of in the background. "
        "Slower, but the response already carries the analysis - handy for demos.",
    ),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Replaces AppStore.addChallenge(). Returns immediately; AI analysis follows."""
    challenge = await svc.create_challenge(db, payload, user)

    if analyze_sync:
        await svc.run_analysis(db, challenge)
        await db.commit()
    else:
        await db.commit()
        background.add_task(svc.run_analysis_background, challenge.id)

    await db.refresh(challenge)
    return challenge_detail_out(challenge)


@router.get("", response_model=Page[ChallengeOut])
async def list_challenges(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    mine: bool = Query(False, description="Only challenges submitted by the caller"),
    status_filter: ChallengeStatus | None = Query(None, alias="status"),
    category: str | None = None,
    priority: Priority | None = None,
    district: str | None = None,
    assigned_university_id: str | None = None,
    search: str | None = Query(None, min_length=2),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
):
    stmt = select(Challenge)

    if mine:
        stmt = stmt.where(Challenge.submitted_by_id == user.id)
    # A university only ever sees its own assignments through this endpoint.
    if user.role == UserRole.university and not mine:
        stmt = stmt.where(Challenge.assigned_university_id == user.university_id)

    if status_filter:
        stmt = stmt.where(Challenge.status == status_filter)
    if category:
        stmt = stmt.where(Challenge.category == category)
    if priority:
        stmt = stmt.where(Challenge.priority == priority)
    if district:
        stmt = stmt.where(Challenge.district == district)
    if assigned_university_id:
        stmt = stmt.where(Challenge.assigned_university_id == assigned_university_id)
    if search:
        like = f"%{search}%"
        stmt = stmt.where(Challenge.title.ilike(like) | Challenge.description.ilike(like))

    total = await db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    rows = list(
        (
            await db.scalars(
                stmt.order_by(Challenge.created_at.desc())
                .offset((page - 1) * page_size)
                .limit(page_size)
            )
        ).all()
    )

    return Page[ChallengeOut](
        items=[challenge_out(c) for c in rows],
        total=total,
        page=page,
        page_size=page_size,
        has_more=page * page_size < total,
    )


@router.get("/{challenge_id}", response_model=ChallengeDetailOut)
async def get_challenge(
    challenge_id: str,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_user),
):
    return challenge_detail_out(await _get_challenge(challenge_id, db))


@router.get("/{challenge_id}/matches", response_model=list[MatchOut])
async def get_matches(
    challenge_id: str,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(require_roles(UserRole.admin, UserRole.university)),
):
    """The ranked university suggestions the admin screen shows."""
    await _get_challenge(challenge_id, db)
    rows = list(
        (await db.scalars(select(Match).where(Match.challenge_id == challenge_id).order_by(Match.rank))).all()
    )
    return [match_out(m) for m in rows]


@router.post("/{challenge_id}/analyze", response_model=ChallengeDetailOut)
async def reanalyze(
    challenge_id: str,
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(require_roles(UserRole.admin)),
):
    """Re-run the AI engine, e.g. after the description was edited."""
    challenge = await _get_challenge(challenge_id, db)
    await svc.run_analysis(db, challenge, actor_id=admin.id)
    await db.commit()
    await db.refresh(challenge)
    return challenge_detail_out(challenge)


@router.patch("/{challenge_id}", response_model=ChallengeDetailOut)
async def update_challenge(
    challenge_id: str,
    payload: ChallengeUpdate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    challenge = await _get_challenge(challenge_id, db)
    if user.role != UserRole.admin and challenge.submitted_by_id != user.id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "You can only edit your own challenges")
    if user.role != UserRole.admin and challenge.status != ChallengeStatus.submitted:
        raise HTTPException(
            status.HTTP_409_CONFLICT, "Challenges can only be edited before review begins"
        )

    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(challenge, field, value)
    await db.commit()
    await db.refresh(challenge)
    return challenge_detail_out(challenge)


@router.post("/{challenge_id}/upvote", response_model=Message)
async def upvote(
    challenge_id: str,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_user),
):
    challenge = await _get_challenge(challenge_id, db)
    challenge.upvotes += 1
    await db.commit()
    return Message(message=f"{challenge.id} now has {challenge.upvotes} upvotes")
