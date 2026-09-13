"""Admin workflow: the review queue, assign/override, and duplicate decisions."""
from pydantic import BaseModel, Field
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import case, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import require_roles
from app.db import get_db
from app.models import (
    Challenge,
    ChallengeStatus,
    IndustryProfile,
    Match,
    MatchStatus,
    Priority,
    Project,
    University,
    User,
    UserRole,
)
from app.schemas.challenge import ChallengeDetailOut
from app.schemas.common import Message
from app.schemas.org import MatchOut
from app.schemas.stats import AdminStats
from app.services import challenge_service as svc
from app.services import notifications as notif
from app.services.serializers import challenge_detail_out, match_out

router = APIRouter(prefix="/admin", tags=["Admin"])
admin_only = require_roles(UserRole.admin)


class AssignRequest(BaseModel):
    university_id: str
    note: str | None = None


class DuplicateDecision(BaseModel):
    """duplicate_of=None clears a false positive and returns the item to review."""

    duplicate_of: str | None = None


class RejectRequest(BaseModel):
    reason: str = Field(min_length=3, max_length=500)


class PriorityOverride(BaseModel):
    priority: Priority
    reason: str | None = None


class QueueItem(BaseModel):
    challenge: ChallengeDetailOut
    matches: list[MatchOut]


async def _get(challenge_id: str, db: AsyncSession) -> Challenge:
    c = await db.scalar(select(Challenge).where(Challenge.id == challenge_id))
    if c is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Challenge not found")
    return c


@router.get("/queue", response_model=list[QueueItem])
async def review_queue(
    db: AsyncSession = Depends(get_db),
    _: User = Depends(admin_only),
    include_duplicates: bool = Query(True),
    limit: int = Query(50, ge=1, le=200),
):
    """Everything awaiting an admin decision, each with its AI suggestions attached.

    This is the single call the admin dashboard needs: challenge, AI category,
    AI priority, duplicate flag, and the ranked university matches in one shot.
    """
    statuses = [ChallengeStatus.submitted, ChallengeStatus.under_review]
    if include_duplicates:
        statuses.append(ChallengeStatus.duplicate)

    # The enum stores its member name, so a plain ORDER BY sorts alphabetically
    # and puts Low above Medium. Rank explicitly instead.
    # Written as explicit comparisons rather than case(value=...), because the
    # latter binds the enum members untyped and never matches.
    priority_rank = case(
        (Challenge.priority == Priority.high, 0),
        (Challenge.priority == Priority.medium, 1),
        (Challenge.priority == Priority.low, 2),
        else_=3,
    )
    challenges = list(
        (
            await db.scalars(
                select(Challenge)
                .where(Challenge.status.in_(statuses))
                .order_by(priority_rank, Challenge.created_at.desc())
                .limit(limit)
            )
        ).all()
    )
    if not challenges:
        return []

    ids = [c.id for c in challenges]
    matches = list(
        (await db.scalars(select(Match).where(Match.challenge_id.in_(ids)).order_by(Match.rank))).all()
    )
    by_challenge: dict[str, list[Match]] = {}
    for m in matches:
        by_challenge.setdefault(m.challenge_id, []).append(m)

    return [
        QueueItem(
            challenge=challenge_detail_out(c),
            matches=[match_out(m) for m in by_challenge.get(c.id, [])],
        )
        for c in challenges
    ]


@router.post("/challenges/{challenge_id}/assign", response_model=ChallengeDetailOut)
async def assign(
    challenge_id: str,
    payload: AssignRequest,
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(admin_only),
):
    """Confirm the AI suggestion, or override it with a different university."""
    challenge = await _get(challenge_id, db)
    await svc.assign_challenge(db, challenge, payload.university_id, admin, payload.note)
    await db.commit()
    await db.refresh(challenge)
    return challenge_detail_out(challenge)


@router.post("/challenges/{challenge_id}/duplicate", response_model=ChallengeDetailOut)
async def resolve_duplicate(
    challenge_id: str,
    payload: DuplicateDecision,
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(admin_only),
):
    challenge = await _get(challenge_id, db)
    await svc.mark_duplicate(db, challenge, payload.duplicate_of, admin)
    await db.commit()
    await db.refresh(challenge)
    return challenge_detail_out(challenge)


@router.post("/challenges/{challenge_id}/priority", response_model=ChallengeDetailOut)
async def override_priority(
    challenge_id: str,
    payload: PriorityOverride,
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(admin_only),
):
    """Human override of the AI rubric. ai_priority is preserved for comparison."""
    challenge = await _get(challenge_id, db)
    challenge.priority = payload.priority
    await notif.log_event(
        db, challenge, f"Priority set to {payload.priority.value}", payload.reason, admin.id
    )
    await db.commit()
    await db.refresh(challenge)
    return challenge_detail_out(challenge)


@router.post("/challenges/{challenge_id}/reject", response_model=ChallengeDetailOut)
async def reject(
    challenge_id: str,
    payload: RejectRequest,
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(admin_only),
):
    challenge = await _get(challenge_id, db)
    challenge.status = ChallengeStatus.rejected
    await notif.log_event(db, challenge, "Rejected", payload.reason, admin.id)
    await notif.notify(
        db,
        challenge.submitted_by_id,
        "Challenge not taken forward",
        payload.reason,
        kind="challenge",
        target={"type": "challenge", "id": challenge.id},
    )
    await db.commit()
    await db.refresh(challenge)
    return challenge_detail_out(challenge)


@router.get("/stats", response_model=AdminStats)
async def admin_stats(db: AsyncSession = Depends(get_db), _: User = Depends(admin_only)):
    """Aggregates behind the analytics dashboard on slide 3 of the deck."""

    async def count(stmt) -> int:
        return await db.scalar(select(func.count()).select_from(stmt.subquery())) or 0

    async def group(column) -> dict:
        rows = (await db.execute(select(column, func.count()).group_by(column))).all()
        out: dict[str, int] = {}
        for key, n in rows:
            if key is None:
                continue
            out[key.value if hasattr(key, "value") else str(key)] = n
        return out

    total = await count(select(Challenge))
    analyzed = await count(select(Challenge).where(Challenge.ai_analyzed_at.is_not(None)))

    decided = list(
        (
            await db.scalars(
                select(Match).where(Match.status.in_([MatchStatus.assigned, MatchStatus.accepted]))
            )
        ).all()
    )
    kept = sum(1 for m in decided if not m.was_override)

    return AdminStats(
        total_challenges=total,
        pending_review=await count(
            select(Challenge).where(
                Challenge.status.in_([ChallengeStatus.submitted, ChallengeStatus.under_review])
            )
        ),
        assigned=await count(select(Challenge).where(Challenge.status == ChallengeStatus.assigned)),
        in_progress=await count(
            select(Challenge).where(Challenge.status == ChallengeStatus.in_progress)
        ),
        resolved=await count(
            select(Challenge).where(
                Challenge.status.in_([ChallengeStatus.resolved, ChallengeStatus.solution_deployed])
            )
        ),
        duplicates_flagged=await count(
            select(Challenge).where(Challenge.status == ChallengeStatus.duplicate)
        ),
        total_projects=await count(select(Project)),
        universities=await count(select(University)),
        industries=await count(select(IndustryProfile)),
        citizens=await count(select(User).where(User.role == UserRole.citizen)),
        people_impacted=await db.scalar(select(func.coalesce(func.sum(Project.people_impacted), 0))) or 0,
        by_category=await group(Challenge.category),
        by_priority=await group(Challenge.priority),
        by_status=await group(Challenge.status),
        by_district=await group(Challenge.district),
        ai_assist_rate=round(analyzed / total, 3) if total else 0.0,
        match_acceptance_rate=round(kept / len(decided), 3) if decided else 0.0,
    )


@router.post("/reindex", response_model=Message)
async def reindex(db: AsyncSession = Depends(get_db), _: User = Depends(admin_only)):
    """Re-embed every university profile.

    Needed after switching embedding backends (e.g. first run with
    sentence-transformers installed), since vectors from different models are
    not comparable.
    """
    from app.ml.embeddings import active_model_name
    from app.ml.matching import ensure_university_embeddings

    universities = list((await db.scalars(select(University))).all())
    for u in universities:
        u.embedding = None
    await ensure_university_embeddings(db, universities)
    await db.commit()
    return Message(message=f"Re-embedded {len(universities)} universities using {active_model_name()}")
