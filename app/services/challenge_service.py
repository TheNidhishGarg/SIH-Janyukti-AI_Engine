"""Challenge lifecycle: submit -> analyze -> assign -> accept/decline.

These are the operations the Flutter AppStore fakes today (addChallenge,
assign, accept); each one here is the real version, with the AI stage and the
audit trail wired in.
"""
from __future__ import annotations

import logging
from datetime import datetime, timezone

from fastapi import HTTPException, status as http
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.ids import new_uuid, next_challenge_id
from app.db import SessionLocal
from app.ml import pipeline
from app.models import (
    Attachment,
    Challenge,
    ChallengeStatus,
    Match,
    MatchStatus,
    Priority,
    University,
    User,
    UserRole,
)
from app.schemas.challenge import ChallengeCreate
from app.services import notifications as notif

log = logging.getLogger(__name__)


def _district_from_location(location: str | None) -> str | None:
    """Best-effort split: "Ranchi, Jharkhand" yields "Ranchi".

    The client can always send district/state explicitly instead.
    """
    if not location:
        return None
    return location.split(",")[0].strip() or None


def _state_from_location(location: str | None) -> str | None:
    if not location or "," not in location:
        return None
    return location.rsplit(",", 1)[-1].strip() or None


async def create_challenge(db: AsyncSession, payload: ChallengeCreate, user: User) -> Challenge:
    challenge = Challenge(
        id=await next_challenge_id(db),
        title=payload.title.strip(),
        description=payload.description.strip(),
        category=payload.category or "Other",
        location=payload.location or "",
        latitude=payload.latitude,
        longitude=payload.longitude,
        district=payload.district or _district_from_location(payload.location),
        state=payload.state or _state_from_location(payload.location),
        people_impacted=payload.people_impacted,
        submitted_by_id=user.id,
        status=ChallengeStatus.submitted,
        priority=Priority.medium,
    )
    db.add(challenge)
    await db.flush()

    for a in payload.attachments:
        db.add(
            Attachment(
                id=new_uuid(),
                challenge_id=challenge.id,
                url=a.url,
                kind=a.kind,
                filename=a.filename,
                size_bytes=a.size_bytes,
            )
        )

    await notif.log_event(db, challenge, "Submitted", f"Reported by {user.name}", user.id)
    await notif.notify(
        db,
        user.id,
        "Challenge submitted",
        f"{challenge.id} has been received and is being analysed.",
        kind="challenge",
        target={"type": "challenge", "id": challenge.id},
    )
    await db.flush()
    return challenge


async def run_analysis(db: AsyncSession, challenge: Challenge, actor_id: str | None = None) -> Challenge:
    """Run the AI engine over a challenge and persist the result."""
    result = await pipeline.analyze(
        db,
        title=challenge.title,
        description=challenge.description,
        category_hint=challenge.category,
        location=challenge.location,
        district=challenge.district,
        state=challenge.state,
        exclude_id=challenge.id,
    )
    await pipeline.apply_analysis(db, challenge, result)

    detail = (
        f"Category: {result.category} ({result.category_confidence:.0%}), "
        f"Priority: {result.priority}. Engine: {result.engine}."
    )
    await notif.log_event(db, challenge, "AI analysis complete", detail, actor_id)

    if result.duplicate_of:
        await notif.log_event(
            db,
            challenge,
            "Flagged as possible duplicate",
            f"Similar to {result.duplicate_of} (score {result.duplicate_score:.2f})",
        )
        await notif.notify(
            db,
            challenge.submitted_by_id,
            "Possible duplicate detected",
            f"{challenge.id} looks similar to {result.duplicate_of}. An admin will confirm.",
            kind="challenge",
            target={"type": "challenge", "id": challenge.id},
        )
    else:
        await notif.notify_role(
            db,
            UserRole.admin,
            "New challenge needs review",
            f"{challenge.id}: {challenge.title}",
            kind="challenge",
            target={"type": "challenge", "id": challenge.id},
        )

    await db.flush()
    return challenge


async def run_analysis_background(challenge_id: str) -> None:
    """Background-task entrypoint: owns its own session and never raises.

    Submission must not fail or hang because the LLM is slow, so the citizen
    gets an immediate 201 and the analysis lands a moment later.
    """
    try:
        async with SessionLocal() as db:
            challenge = await db.scalar(select(Challenge).where(Challenge.id == challenge_id))
            if challenge is None:
                return
            await run_analysis(db, challenge)
            await db.commit()
    except Exception:  # noqa: BLE001 - a failed analysis must not kill the worker
        log.exception("Background analysis failed for %s", challenge_id)


async def assign_challenge(
    db: AsyncSession,
    challenge: Challenge,
    university_id: str,
    admin: User,
    note: str | None = None,
) -> Challenge:
    """Admin confirms or overrides the top-ranked AI match."""
    university = await db.scalar(select(University).where(University.id == university_id))
    if university is None:
        raise HTTPException(http.HTTP_404_NOT_FOUND, "University not found")
    if challenge.status in (ChallengeStatus.resolved, ChallengeStatus.rejected):
        raise HTTPException(http.HTTP_409_CONFLICT, f"Challenge is already {challenge.status.value}")

    matches = list(
        (
            await db.scalars(
                select(Match).where(Match.challenge_id == challenge.id).order_by(Match.rank)
            )
        ).all()
    )
    top = matches[0] if matches else None
    was_override = bool(top and top.university_id != university_id)

    chosen = next((m for m in matches if m.university_id == university_id), None)
    if chosen is None:
        # Admin picked a university the ranker never surfaced. Record it anyway
        # so match-acceptance metrics stay honest.
        chosen = Match(
            id=new_uuid(),
            challenge_id=challenge.id,
            university_id=university_id,
            rank=0,
            reasons=["Manually selected by administrator"],
        )
        db.add(chosen)
        was_override = True

    chosen.status = MatchStatus.assigned
    chosen.was_override = was_override
    chosen.decided_by_id = admin.id
    chosen.decided_at = datetime.now(timezone.utc)

    for m in matches:
        if m.id != chosen.id and m.status == MatchStatus.suggested:
            m.status = MatchStatus.declined

    challenge.assigned_university_id = university_id
    challenge.status = ChallengeStatus.assigned

    label = f"Assigned to {university.name}"
    await notif.log_event(
        db,
        challenge,
        label,
        note or ("Admin override of AI suggestion" if was_override else "Confirmed AI suggestion"),
        admin.id,
    )
    await notif.notify(
        db,
        challenge.submitted_by_id,
        label,
        f"{challenge.id} has been assigned to {university.name}.",
        kind="challenge",
        target={"type": "challenge", "id": challenge.id},
    )
    await notif.notify_many(
        db,
        await notif.university_user_ids(db, university_id),
        "New challenge assigned",
        f"{challenge.id}: {challenge.title}",
        kind="assignment",
        target={"type": "challenge", "id": challenge.id},
    )
    await db.flush()
    return challenge


async def decline_assignment(
    db: AsyncSession, challenge: Challenge, university_id: str, reason: str, user: User
) -> Challenge:
    match = await db.scalar(
        select(Match).where(
            Match.challenge_id == challenge.id,
            Match.university_id == university_id,
            Match.status == MatchStatus.assigned,
        )
    )
    if match is None:
        raise HTTPException(http.HTTP_404_NOT_FOUND, "No active assignment for this university")

    match.status = MatchStatus.declined
    match.decline_reason = reason
    match.decided_by_id = user.id
    match.decided_at = datetime.now(timezone.utc)

    # Back to the admin queue rather than silently stalling.
    challenge.assigned_university_id = None
    challenge.status = ChallengeStatus.under_review

    await notif.log_event(db, challenge, "Assignment declined", reason, user.id)
    await notif.notify_role(
        db,
        UserRole.admin,
        "Assignment declined",
        f"{challenge.id} was declined: {reason}",
        kind="challenge",
        target={"type": "challenge", "id": challenge.id},
    )
    await db.flush()
    return challenge


async def mark_duplicate(
    db: AsyncSession, challenge: Challenge, duplicate_of: str | None, admin: User
) -> Challenge:
    """Admin confirms a duplicate flag, or clears a false positive."""
    if duplicate_of:
        original = await db.scalar(select(Challenge).where(Challenge.id == duplicate_of))
        if original is None:
            raise HTTPException(http.HTTP_404_NOT_FOUND, "Original challenge not found")
        if original.id == challenge.id:
            raise HTTPException(http.HTTP_400_BAD_REQUEST, "A challenge cannot duplicate itself")

        challenge.duplicate_of_id = duplicate_of
        challenge.status = ChallengeStatus.duplicate
        # Merge the signal rather than discarding it: the original gets the vote.
        original.upvotes += 1

        await notif.log_event(db, challenge, "Confirmed duplicate", f"Merged into {duplicate_of}", admin.id)
        await notif.notify(
            db,
            challenge.submitted_by_id,
            "Challenge merged",
            f"{challenge.id} was merged into {duplicate_of}, which is already being worked on.",
            kind="challenge",
            target={"type": "challenge", "id": duplicate_of},
        )
    else:
        challenge.duplicate_of_id = None
        challenge.duplicate_score = None
        challenge.status = ChallengeStatus.under_review
        await notif.log_event(db, challenge, "Duplicate flag cleared", None, admin.id)

    await db.flush()
    return challenge
