"""Project lifecycle: accept an assignment, run milestones, report impact.

Progress is always derived from approved milestones, never set directly, so
the number the citizen sees cannot drift from the evidence behind it.
"""
from __future__ import annotations

from datetime import datetime, timezone

from fastapi import HTTPException, status as http
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.ids import new_uuid, next_project_id
from app.models import (
    DEFAULT_MILESTONES,
    Challenge,
    ChallengeStatus,
    ChatMessage,
    Match,
    MatchStatus,
    Milestone,
    MilestoneStatus,
    Project,
    ProjectStatus,
    University,
    User,
    UserRole,
)
from app.services import notifications as notif


def recompute_progress(project: Project) -> int:
    total = len(project.milestones)
    if total == 0:
        return 0
    approved = sum(1 for m in project.milestones if m.status == MilestoneStatus.approved)
    in_flight = sum(
        1
        for m in project.milestones
        if m.status in (MilestoneStatus.in_progress, MilestoneStatus.submitted)
    )
    # Work under way counts for half a milestone, so the bar moves as soon as a
    # team starts rather than jumping only on approval.
    project.progress = int(round((approved + 0.5 * in_flight) / total * 100))
    return project.progress


async def accept_assignment(
    db: AsyncSession,
    challenge: Challenge,
    user: User,
    name: str,
    description: str = "",
    mentor: str = "",
    milestone_names: list[str] | None = None,
) -> Project:
    """University accepts an assigned challenge, creating the project workspace."""
    university_id = user.university_id
    if user.role == UserRole.admin:
        university_id = challenge.assigned_university_id
    if not university_id:
        raise HTTPException(http.HTTP_400_BAD_REQUEST, "User is not linked to a university")
    if challenge.assigned_university_id != university_id:
        raise HTTPException(http.HTTP_403_FORBIDDEN, "This challenge is not assigned to your university")

    existing = await db.scalar(select(Project).where(Project.challenge_id == challenge.id))
    if existing is not None:
        raise HTTPException(
            http.HTTP_409_CONFLICT, f"Project {existing.id} already exists for this challenge"
        )

    project = Project(
        id=await next_project_id(db),
        name=name.strip(),
        description=description,
        category=challenge.category,
        challenge_id=challenge.id,
        university_id=university_id,
        mentor=mentor,
        status=ProjectStatus.active,
    )
    db.add(project)
    await db.flush()

    names = milestone_names or DEFAULT_MILESTONES
    for i, mname in enumerate(names):
        db.add(
            Milestone(
                id=new_uuid(),
                project_id=project.id,
                name=mname,
                order_index=i,
                # The first stage starts immediately; the rest queue behind it.
                status=MilestoneStatus.in_progress if i == 0 else MilestoneStatus.pending,
            )
        )
    await db.flush()
    await db.refresh(project)
    recompute_progress(project)

    challenge.status = ChallengeStatus.in_progress
    match = await db.scalar(
        select(Match).where(
            Match.challenge_id == challenge.id,
            Match.university_id == university_id,
        )
    )
    if match is not None:
        match.status = MatchStatus.accepted

    university = await db.scalar(select(University).where(University.id == university_id))
    if university is not None:
        university.active_projects += 1

    uni_name = university.name if university else "The university"
    await notif.log_event(db, challenge, "In Progress", f"{uni_name} accepted the challenge", user.id)
    await notif.notify(
        db,
        challenge.submitted_by_id,
        "Work has started",
        f"{challenge.id} is now in progress as project {project.id}.",
        kind="project",
        target={"type": "project", "id": project.id},
    )
    await notif.notify_role(
        db,
        UserRole.admin,
        "Challenge accepted",
        f"{challenge.id} accepted; project {project.id} created.",
        kind="project",
        target={"type": "project", "id": project.id},
    )
    await db.flush()
    return project


async def submit_milestone(
    db: AsyncSession,
    project: Project,
    milestone: Milestone,
    user: User,
    evidence_url: str | None = None,
    note: str | None = None,
) -> Milestone:
    if milestone.status == MilestoneStatus.approved:
        raise HTTPException(http.HTTP_409_CONFLICT, "Milestone is already approved")

    milestone.status = MilestoneStatus.submitted
    milestone.submitted_at = datetime.now(timezone.utc)
    if evidence_url:
        milestone.evidence_url = evidence_url
    if note:
        milestone.description = note

    recompute_progress(project)

    await notif.notify_role(
        db,
        UserRole.admin,
        "Milestone submitted for review",
        f"{project.id}: {milestone.name}",
        kind="milestone",
        target={"type": "project", "id": project.id},
    )
    if project.challenge:
        await notif.notify(
            db,
            project.challenge.submitted_by_id,
            "Progress update",
            f"{milestone.name} was completed on {project.name}.",
            kind="milestone",
            target={"type": "project", "id": project.id},
        )
    await db.flush()
    return milestone


async def review_milestone(
    db: AsyncSession,
    project: Project,
    milestone: Milestone,
    approved: bool,
    reviewer: User,
    note: str | None = None,
) -> Milestone:
    milestone.review_note = note
    if approved:
        milestone.status = MilestoneStatus.approved
        milestone.approved_at = datetime.now(timezone.utc)
        # Pull the next stage into flight so the timeline always shows one live step.
        nxt = next(
            (
                m
                for m in sorted(project.milestones, key=lambda x: x.order_index)
                if m.order_index > milestone.order_index and m.status == MilestoneStatus.pending
            ),
            None,
        )
        if nxt is not None:
            nxt.status = MilestoneStatus.in_progress
    else:
        milestone.status = MilestoneStatus.rejected

    recompute_progress(project)

    if all(m.status == MilestoneStatus.approved for m in project.milestones):
        project.status = ProjectStatus.completed
        project.completed_at = datetime.now(timezone.utc)
        project.progress = 100
        if project.challenge:
            project.challenge.status = ChallengeStatus.solution_deployed
        university = await db.scalar(select(University).where(University.id == project.university_id))
        if university is not None:
            university.active_projects = max(0, university.active_projects - 1)
            university.completed_projects += 1

    verb = "approved" if approved else "sent back"
    if project.challenge:
        await notif.log_event(
            db, project.challenge, f"Milestone {verb}: {milestone.name}", note, reviewer.id
        )
        await notif.notify(
            db,
            project.challenge.submitted_by_id,
            "Milestone approved" if approved else "Milestone needs rework",
            f"{project.name}: {milestone.name}",
            kind="milestone",
            target={"type": "project", "id": project.id},
        )
    await db.flush()
    return milestone


async def report_impact(
    db: AsyncSession,
    project: Project,
    people_impacted: int,
    summary: str,
    metrics: dict,
    user: User,
) -> Project:
    project.people_impacted = people_impacted
    project.impact_summary = summary
    project.impact_metrics = metrics

    if project.challenge:
        project.challenge.people_impacted = people_impacted
        if project.status == ProjectStatus.completed:
            project.challenge.status = ChallengeStatus.resolved
        await notif.log_event(
            db,
            project.challenge,
            "Impact reported",
            f"{people_impacted} people impacted. {summary}"[:400],
            user.id,
        )
        await notif.notify(
            db,
            project.challenge.submitted_by_id,
            "Impact reported",
            f"{project.name} reported reaching {people_impacted} people.",
            kind="impact",
            target={"type": "project", "id": project.id},
        )
    await db.flush()
    return project


async def post_chat(
    db: AsyncSession, project: Project, user: User, body: str, attachment_url: str | None = None
) -> ChatMessage:
    msg = ChatMessage(
        id=new_uuid(),
        project_id=project.id,
        sender_id=user.id,
        sender_name=user.name,
        sender_role=user.role.value,
        body=body.strip(),
        attachment_url=attachment_url,
    )
    db.add(msg)
    await db.flush()
    return msg
