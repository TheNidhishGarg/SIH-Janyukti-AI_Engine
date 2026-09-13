from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field

from app.models import ChallengeStatus, Priority


class AttachmentIn(BaseModel):
    url: str
    kind: str = "image"
    filename: str = ""
    size_bytes: int = 0


class AttachmentOut(AttachmentIn):
    model_config = ConfigDict(from_attributes=True)
    id: str
    created_at: datetime | None = None


class ChallengeCreate(BaseModel):
    """Mirrors the Submit Challenge + Add Details screens in the Flutter app."""

    title: str = Field(min_length=5, max_length=250)
    description: str = Field(min_length=10)
    category: str = "Other"
    location: str = ""
    latitude: float | None = None
    longitude: float | None = None
    district: str | None = None
    state: str | None = None
    people_impacted: int = 0
    attachments: list[AttachmentIn] = Field(default_factory=list)


class ChallengeUpdate(BaseModel):
    title: str | None = None
    description: str | None = None
    category: str | None = None
    location: str | None = None
    district: str | None = None
    state: str | None = None
    people_impacted: int | None = None


class ChallengeEventOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    label: str
    detail: str | None = None
    created_at: datetime


class AiSuggestionOut(BaseModel):
    """The AI engine's read on a challenge, kept separate from the citizen's input."""

    category: str | None = None
    category_confidence: float | None = None
    priority: Priority | None = None
    priority_score: float | None = None
    scores: dict | None = None
    rationale: str | None = None
    tags: list[str] | None = None
    engine: str | None = None
    analyzed_at: datetime | None = None
    duplicate_of: str | None = None
    duplicate_score: float | None = None


class ChallengeOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    title: str
    description: str
    category: str
    location: str
    latitude: float | None = None
    longitude: float | None = None
    district: str | None = None
    state: str | None = None
    status: ChallengeStatus
    # What the Flutter UI prints verbatim, e.g. "Assigned to BIT Mesra".
    status_label: str
    priority: Priority
    upvotes: int = 0
    people_impacted: int = 0
    submitted_by_id: str
    submitted_by: str = ""
    assigned_university_id: str | None = None
    assigned_university_name: str | None = None
    created_at: datetime
    updated_at: datetime
    attachments: list[AttachmentOut] = Field(default_factory=list)


class ChallengeDetailOut(ChallengeOut):
    ai: AiSuggestionOut | None = None
    timeline: list[ChallengeEventOut] = Field(default_factory=list)
