from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field

from app.models import MilestoneStatus, ProjectStatus


class MilestoneOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    name: str
    description: str = ""
    order_index: int
    status: MilestoneStatus
    due_date: datetime | None = None
    submitted_at: datetime | None = None
    approved_at: datetime | None = None
    evidence_url: str | None = None
    review_note: str | None = None


class MilestoneCreate(BaseModel):
    name: str = Field(min_length=2, max_length=200)
    description: str = ""
    due_date: datetime | None = None


class MilestoneSubmit(BaseModel):
    evidence_url: str | None = None
    note: str | None = None


class MilestoneReview(BaseModel):
    approved: bool
    note: str | None = None


class ProjectCreate(BaseModel):
    """Created when a university accepts an assigned challenge."""

    challenge_id: str
    name: str = Field(min_length=3, max_length=250)
    description: str = ""
    mentor: str = ""
    # Defaults to the standard 5-stage lifecycle when omitted.
    milestones: list[str] = Field(default_factory=list)


class ProjectUpdate(BaseModel):
    name: str | None = None
    description: str | None = None
    mentor: str | None = None
    status: ProjectStatus | None = None


class ImpactReport(BaseModel):
    people_impacted: int = Field(ge=0)
    summary: str = ""
    metrics: dict = Field(default_factory=dict)


class ProjectOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    name: str
    description: str = ""
    category: str
    challenge_id: str
    challenge_title: str = ""
    university_id: str
    university: str = ""          # university name, matching the Dart Project.university field
    mentor: str = ""
    status: ProjectStatus
    progress: int = 0
    active_milestone: int = 0
    people_impacted: int = 0
    impact_summary: str | None = None
    impact_metrics: dict | None = None
    created_at: datetime
    updated_at: datetime
    completed_at: datetime | None = None
    milestones: list[MilestoneOut] = Field(default_factory=list)


class ChatMessageIn(BaseModel):
    body: str = Field(min_length=1, max_length=4000)
    attachment_url: str | None = None


class ChatMessageOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    project_id: str
    sender_id: str
    sender_name: str
    sender_role: str
    body: str
    attachment_url: str | None = None
    created_at: datetime
