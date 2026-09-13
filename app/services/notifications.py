"""Notification fan-out.

The arXiv crowdsourcing finding in our deck is blunt: submissions that go
silent kill participation. So every state change in the workflow writes both a
timeline event on the challenge and a notification to the people affected.
"""
from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.ids import new_uuid
from app.models import Challenge, ChallengeEvent, Notification, User, UserRole


async def notify(
    db: AsyncSession,
    user_id: str,
    title: str,
    body: str = "",
    kind: str = "info",
    target: dict | None = None,
) -> Notification:
    n = Notification(
        id=new_uuid(), user_id=user_id, title=title, body=body, kind=kind, target=target
    )
    db.add(n)
    return n


async def notify_many(
    db: AsyncSession,
    user_ids: list[str],
    title: str,
    body: str = "",
    kind: str = "info",
    target: dict | None = None,
) -> None:
    for uid in dict.fromkeys(u for u in user_ids if u):
        await notify(db, uid, title, body, kind, target)


async def notify_role(
    db: AsyncSession, role: UserRole, title: str, body: str = "", kind: str = "info",
    target: dict | None = None,
) -> None:
    ids = list((await db.scalars(select(User.id).where(User.role == role, User.is_active))).all())
    await notify_many(db, ids, title, body, kind, target)


async def university_user_ids(db: AsyncSession, university_id: str) -> list[str]:
    return list(
        (await db.scalars(select(User.id).where(User.university_id == university_id))).all()
    )


async def log_event(
    db: AsyncSession,
    challenge: Challenge,
    label: str,
    detail: str | None = None,
    actor_id: str | None = None,
) -> ChallengeEvent:
    ev = ChallengeEvent(
        id=new_uuid(),
        challenge_id=challenge.id,
        label=label,
        detail=detail,
        actor_id=actor_id,
    )
    db.add(ev)
    return ev
