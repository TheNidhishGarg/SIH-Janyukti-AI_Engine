"""Project workspace: accept, milestones, chat, impact."""
from pydantic import BaseModel, Field
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import get_current_user, require_roles
from app.db import get_db
from app.models import Challenge, ChatMessage, Milestone, Project, User, UserRole
from app.schemas.common import Page
from app.schemas.project import (
    ChatMessageIn,
    ChatMessageOut,
    ImpactReport,
    MilestoneCreate,
    MilestoneOut,
    MilestoneReview,
    MilestoneSubmit,
    ProjectCreate,
    ProjectOut,
    ProjectUpdate,
)
from app.core.ids import new_uuid
from app.services import project_service as svc
from app.services.serializers import chat_out, project_out

router = APIRouter(prefix="/projects", tags=["Projects"])


class DeclineRequest(BaseModel):
    reason: str = Field(min_length=3, max_length=500)


async def _get_project(project_id: str, db: AsyncSession) -> Project:
    p = await db.scalar(select(Project).where(Project.id == project_id))
    if p is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Project not found")
    return p


def _assert_member(project: Project, user: User) -> None:
    """Only the owning university, the reporting citizen, and admins may write."""
    if user.role == UserRole.admin:
        return
    if user.role == UserRole.university and user.university_id == project.university_id:
        return
    if project.challenge and project.challenge.submitted_by_id == user.id:
        return
    if user.role == UserRole.industry:
        return  # read/chat access for interested industry partners
    raise HTTPException(status.HTTP_403_FORBIDDEN, "You are not part of this project")


@router.post("", response_model=ProjectOut, status_code=status.HTTP_201_CREATED)
async def accept_challenge(
    payload: ProjectCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(UserRole.university, UserRole.admin)),
):
    """Replaces AppStore.accept() + createProject(): university takes the challenge on."""
    challenge = await db.scalar(select(Challenge).where(Challenge.id == payload.challenge_id))
    if challenge is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Challenge not found")

    project = await svc.accept_assignment(
        db,
        challenge,
        user,
        name=payload.name,
        description=payload.description,
        mentor=payload.mentor,
        milestone_names=payload.milestones or None,
    )
    await db.commit()
    await db.refresh(project)
    return project_out(project)


@router.get("", response_model=Page[ProjectOut])
async def list_projects(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    university_id: str | None = None,
    category: str | None = None,
    mine: bool = Query(False, description="Scope to the caller organisation or reports"),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
):
    stmt = select(Project)
    if university_id:
        stmt = stmt.where(Project.university_id == university_id)
    if category:
        stmt = stmt.where(Project.category == category)
    if mine:
        if user.role == UserRole.university:
            stmt = stmt.where(Project.university_id == user.university_id)
        elif user.role == UserRole.citizen:
            stmt = stmt.join(Challenge, Challenge.id == Project.challenge_id).where(
                Challenge.submitted_by_id == user.id
            )

    total = await db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    rows = list(
        (
            await db.scalars(
                stmt.order_by(Project.created_at.desc())
                .offset((page - 1) * page_size)
                .limit(page_size)
            )
        ).all()
    )
    return Page[ProjectOut](
        items=[project_out(p) for p in rows],
        total=total,
        page=page,
        page_size=page_size,
        has_more=page * page_size < total,
    )


@router.get("/{project_id}", response_model=ProjectOut)
async def get_project(
    project_id: str, db: AsyncSession = Depends(get_db), _: User = Depends(get_current_user)
):
    return project_out(await _get_project(project_id, db))


@router.patch("/{project_id}", response_model=ProjectOut)
async def update_project(
    project_id: str,
    payload: ProjectUpdate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(UserRole.university, UserRole.admin)),
):
    project = await _get_project(project_id, db)
    _assert_member(project, user)
    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(project, field, value)
    await db.commit()
    await db.refresh(project)
    return project_out(project)


async def _get_milestone(project: Project, milestone_id: str) -> Milestone:
    m = next((m for m in project.milestones if m.id == milestone_id), None)
    if m is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Milestone not found on this project")
    return m


@router.get("/{project_id}/milestones", response_model=list[MilestoneOut])
async def list_milestones(
    project_id: str, db: AsyncSession = Depends(get_db), _: User = Depends(get_current_user)
):
    project = await _get_project(project_id, db)
    return [MilestoneOut.model_validate(m) for m in project.milestones]


@router.post("/{project_id}/milestones", response_model=MilestoneOut, status_code=status.HTTP_201_CREATED)
async def add_milestone(
    project_id: str,
    payload: MilestoneCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(UserRole.university, UserRole.admin)),
):
    project = await _get_project(project_id, db)
    _assert_member(project, user)
    milestone = Milestone(
        id=new_uuid(),
        project_id=project.id,
        name=payload.name,
        description=payload.description,
        due_date=payload.due_date,
        order_index=len(project.milestones),
    )
    db.add(milestone)
    await db.commit()
    await db.refresh(milestone)
    return MilestoneOut.model_validate(milestone)


@router.post("/{project_id}/milestones/{milestone_id}/submit", response_model=ProjectOut)
async def submit_milestone(
    project_id: str,
    milestone_id: str,
    payload: MilestoneSubmit,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(UserRole.university, UserRole.admin)),
):
    """Replaces AppStore.advance(): the university reports a stage complete."""
    project = await _get_project(project_id, db)
    _assert_member(project, user)
    milestone = await _get_milestone(project, milestone_id)
    await svc.submit_milestone(db, project, milestone, user, payload.evidence_url, payload.note)
    await db.commit()
    await db.refresh(project)
    return project_out(project)


@router.post("/{project_id}/milestones/{milestone_id}/review", response_model=ProjectOut)
async def review_milestone(
    project_id: str,
    milestone_id: str,
    payload: MilestoneReview,
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(require_roles(UserRole.admin)),
):
    """Admin approves a submitted milestone, or sends it back for rework."""
    project = await _get_project(project_id, db)
    milestone = await _get_milestone(project, milestone_id)
    await svc.review_milestone(db, project, milestone, payload.approved, admin, payload.note)
    await db.commit()
    await db.refresh(project)
    return project_out(project)


@router.post("/{project_id}/impact", response_model=ProjectOut)
async def report_impact(
    project_id: str,
    payload: ImpactReport,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(UserRole.university, UserRole.admin)),
):
    project = await _get_project(project_id, db)
    _assert_member(project, user)
    await svc.report_impact(db, project, payload.people_impacted, payload.summary, payload.metrics, user)
    await db.commit()
    await db.refresh(project)
    return project_out(project)


@router.get("/{project_id}/chat", response_model=list[ChatMessageOut])
async def get_chat(
    project_id: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    after: str | None = Query(None, description="Return only messages newer than this message id"),
    limit: int = Query(100, ge=1, le=500),
):
    project = await _get_project(project_id, db)
    _assert_member(project, user)

    stmt = select(ChatMessage).where(ChatMessage.project_id == project_id)
    if after:
        cursor = await db.scalar(select(ChatMessage).where(ChatMessage.id == after))
        if cursor is not None:
            stmt = stmt.where(ChatMessage.created_at > cursor.created_at)

    rows = list((await db.scalars(stmt.order_by(ChatMessage.created_at).limit(limit))).all())
    return [chat_out(m) for m in rows]


@router.post("/{project_id}/chat", response_model=ChatMessageOut, status_code=status.HTTP_201_CREATED)
async def post_chat(
    project_id: str,
    payload: ChatMessageIn,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Replaces AppStore.send()."""
    project = await _get_project(project_id, db)
    _assert_member(project, user)
    msg = await svc.post_chat(db, project, user, payload.body, payload.attachment_url)
    await db.commit()
    await db.refresh(msg)
    return chat_out(msg)
