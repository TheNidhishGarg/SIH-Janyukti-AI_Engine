"""University directory + the university-side inbox."""
from pydantic import BaseModel, Field
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.ids import new_uuid
from app.core.security import get_current_user, require_roles
from app.db import get_db
from app.models import (
    Challenge,
    ChallengeStatus,
    Milestone,
    MilestoneStatus,
    Project,
    ProjectStatus,
    University,
    User,
    UserRole,
)
from app.schemas.challenge import ChallengeOut
from app.schemas.org import UniversityCreate, UniversityOut, UniversityUpdate
from app.schemas.stats import UniversityStats
from app.services import challenge_service as svc
from app.services.serializers import challenge_out, university_out

router = APIRouter(prefix="/universities", tags=["Universities"])


class DeclineRequest(BaseModel):
    reason: str = Field(min_length=3, max_length=500)


@router.get("", response_model=list[UniversityOut])
async def list_universities(
    db: AsyncSession = Depends(get_db),
    category: str | None = None,
    state: str | None = None,
    search: str | None = Query(None, min_length=2),
):
    """Public directory. Open so the role-selection screen can populate its picker."""
    stmt = select(University)
    if state:
        stmt = stmt.where(University.state == state)
    if search:
        like = f"%{search}%"
        stmt = stmt.where(University.name.ilike(like) | University.department.ilike(like))

    rows = list((await db.scalars(stmt.order_by(University.name))).all())
    if category:
        rows = [u for u in rows if category in (u.categories or [])]
    return [university_out(u) for u in rows]


@router.post("", response_model=UniversityOut, status_code=status.HTTP_201_CREATED)
async def create_university(
    payload: UniversityCreate,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(require_roles(UserRole.admin)),
):
    uni = University(id=new_uuid(), **payload.model_dump())
    db.add(uni)
    await db.commit()
    await db.refresh(uni)
    return university_out(uni)


@router.get("/{university_id}", response_model=UniversityOut)
async def get_university(university_id: str, db: AsyncSession = Depends(get_db)):
    uni = await db.scalar(select(University).where(University.id == university_id))
    if uni is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "University not found")
    return university_out(uni)


@router.patch("/{university_id}", response_model=UniversityOut)
async def update_university(
    university_id: str,
    payload: UniversityUpdate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(UserRole.university, UserRole.admin)),
):
    uni = await db.scalar(select(University).where(University.id == university_id))
    if uni is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "University not found")
    if user.role == UserRole.university and user.university_id != university_id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "You can only edit your own profile")

    changes = payload.model_dump(exclude_unset=True)
    for field, value in changes.items():
        setattr(uni, field, value)

    # Expertise edits change what the matcher sees, so drop the stale vector.
    if {"name", "department", "expertise_summary", "expertise_tags", "categories"} & changes.keys():
        uni.embedding = None
        uni.embedding_model = None

    await db.commit()
    await db.refresh(uni)
    return university_out(uni)


@router.get("/{university_id}/inbox", response_model=list[ChallengeOut])
async def inbox(
    university_id: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(UserRole.university, UserRole.admin)),
):
    """Challenges assigned to this university and awaiting an accept/decline."""
    if user.role == UserRole.university and user.university_id != university_id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Not your university")
    rows = list(
        (
            await db.scalars(
                select(Challenge)
                .where(
                    Challenge.assigned_university_id == university_id,
                    Challenge.status == ChallengeStatus.assigned,
                )
                .order_by(Challenge.created_at.desc())
            )
        ).all()
    )
    return [challenge_out(c) for c in rows]


@router.post("/{university_id}/decline/{challenge_id}", response_model=ChallengeOut)
async def decline(
    university_id: str,
    challenge_id: str,
    payload: DeclineRequest,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(UserRole.university, UserRole.admin)),
):
    """Decline an assignment; the challenge returns to the admin queue."""
    if user.role == UserRole.university and user.university_id != university_id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Not your university")
    challenge = await db.scalar(select(Challenge).where(Challenge.id == challenge_id))
    if challenge is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Challenge not found")

    await svc.decline_assignment(db, challenge, university_id, payload.reason, user)
    await db.commit()
    await db.refresh(challenge)
    return challenge_out(challenge)


@router.get("/{university_id}/stats", response_model=UniversityStats)
async def stats(
    university_id: str,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_user),
):
    async def count(stmt) -> int:
        return await db.scalar(select(func.count()).select_from(stmt.subquery())) or 0

    return UniversityStats(
        assigned=await count(
            select(Challenge).where(
                Challenge.assigned_university_id == university_id,
                Challenge.status == ChallengeStatus.assigned,
            )
        ),
        active_projects=await count(
            select(Project).where(
                Project.university_id == university_id, Project.status == ProjectStatus.active
            )
        ),
        completed_projects=await count(
            select(Project).where(
                Project.university_id == university_id, Project.status == ProjectStatus.completed
            )
        ),
        pending_milestones=await count(
            select(Milestone)
            .join(Project, Project.id == Milestone.project_id)
            .where(
                Project.university_id == university_id,
                Milestone.status.in_([MilestoneStatus.pending, MilestoneStatus.in_progress]),
            )
        ),
        people_impacted=await db.scalar(
            select(func.coalesce(func.sum(Project.people_impacted), 0)).where(
                Project.university_id == university_id
            )
        ) or 0,
    )
