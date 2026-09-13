from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import get_current_user
from app.db import get_db
from app.models import Challenge, ChallengeStatus, Notification, Project, User
from app.schemas.common import Message
from app.schemas.org import NotificationOut
from app.schemas.stats import CitizenStats

router = APIRouter(tags=["Notifications"])


@router.get("/notifications", response_model=list[NotificationOut])
async def list_notifications(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    unread_only: bool = Query(False),
    limit: int = Query(50, ge=1, le=200),
):
    stmt = select(Notification).where(Notification.user_id == user.id)
    if unread_only:
        stmt = stmt.where(Notification.is_read.is_(False))
    rows = list((await db.scalars(stmt.order_by(Notification.created_at.desc()).limit(limit))).all())
    return [NotificationOut.model_validate(n) for n in rows]


@router.get("/notifications/unread-count", response_model=dict)
async def unread_count(db: AsyncSession = Depends(get_db), user: User = Depends(get_current_user)):
    n = await db.scalar(
        select(func.count())
        .select_from(Notification)
        .where(Notification.user_id == user.id, Notification.is_read.is_(False))
    )
    return {"unread": n or 0}


@router.post("/notifications/{notification_id}/read", response_model=Message)
async def mark_read(
    notification_id: str, db: AsyncSession = Depends(get_db), user: User = Depends(get_current_user)
):
    n = await db.scalar(
        select(Notification).where(
            Notification.id == notification_id, Notification.user_id == user.id
        )
    )
    if n is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Notification not found")
    n.is_read = True
    await db.commit()
    return Message(message="Marked as read")


@router.post("/notifications/read-all", response_model=Message)
async def mark_all_read(db: AsyncSession = Depends(get_db), user: User = Depends(get_current_user)):
    await db.execute(
        update(Notification)
        .where(Notification.user_id == user.id, Notification.is_read.is_(False))
        .values(is_read=True)
    )
    await db.commit()
    return Message(message="All notifications marked as read")


@router.get("/me/stats", response_model=CitizenStats)
async def my_stats(db: AsyncSession = Depends(get_db), user: User = Depends(get_current_user)):
    """The three counters on the citizen home screen: Challenges / In Progress / People Impacted."""

    async def count(*conditions) -> int:
        return (
            await db.scalar(
                select(func.count())
                .select_from(Challenge)
                .where(Challenge.submitted_by_id == user.id, *conditions)
            )
            or 0
        )

    impacted = await db.scalar(
        select(func.coalesce(func.sum(Project.people_impacted), 0))
        .select_from(Project)
        .join(Challenge, Challenge.id == Project.challenge_id)
        .where(Challenge.submitted_by_id == user.id)
    )

    return CitizenStats(
        challenges=await count(),
        in_progress=await count(
            Challenge.status.in_([ChallengeStatus.in_progress, ChallengeStatus.assigned])
        ),
        resolved=await count(
            Challenge.status.in_([ChallengeStatus.resolved, ChallengeStatus.solution_deployed])
        ),
        people_impacted=impacted or 0,
    )
