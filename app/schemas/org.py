from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field

from app.models import InterestStatus, MatchStatus


class UniversityCreate(BaseModel):
    name: str = Field(min_length=2, max_length=200)
    department: str = ""
    city: str = ""
    state: str = ""
    contact_email: str | None = None
    expertise_summary: str = ""
    expertise_tags: list[str] = Field(default_factory=list)
    categories: list[str] = Field(default_factory=list)
    capacity: int = 3


class UniversityUpdate(BaseModel):
    name: str | None = None
    department: str | None = None
    city: str | None = None
    state: str | None = None
    contact_email: str | None = None
    expertise_summary: str | None = None
    expertise_tags: list[str] | None = None
    categories: list[str] | None = None
    capacity: int | None = None


class UniversityOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    name: str
    department: str = ""
    display_name: str = ""
    city: str = ""
    state: str = ""
    contact_email: str | None = None
    expertise_summary: str = ""
    expertise_tags: list[str] = Field(default_factory=list)
    categories: list[str] = Field(default_factory=list)
    capacity: int = 0
    active_projects: int = 0
    completed_projects: int = 0


class IndustryCreate(BaseModel):
    name: str = Field(min_length=2, max_length=200)
    sector: str = ""
    city: str = ""
    state: str = ""
    website: str | None = None
    support_types: list[str] = Field(default_factory=list)
    focus_categories: list[str] = Field(default_factory=list)


class IndustryOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    name: str
    sector: str = ""
    city: str = ""
    state: str = ""
    website: str | None = None
    support_types: list[str] = Field(default_factory=list)
    focus_categories: list[str] = Field(default_factory=list)


class InterestCreate(BaseModel):
    """Mirrors the Flutter IndustryInterest model (support list + message)."""

    challenge_id: str | None = None
    project_id: str | None = None
    support: list[str] = Field(default_factory=list)
    message: str = ""
    funding_amount: float | None = None


class InterestOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    challenge_id: str | None = None
    project_id: str | None = None
    industry_id: str
    industry_name: str = ""
    support: list[str] = Field(default_factory=list)
    message: str = ""
    funding_amount: float | None = None
    status: InterestStatus
    created_at: datetime


class MatchOut(BaseModel):
    """One ranked university suggestion, with the score breakdown behind it."""

    model_config = ConfigDict(from_attributes=True)

    id: str | None = None
    university_id: str
    name: str
    department: str = ""
    city: str = ""
    state: str = ""
    score: float
    semantic_score: float = 0.0
    category_score: float = 0.0
    capacity_score: float = 0.0
    proximity_score: float = 0.0
    rank: int = 0
    reasons: list[str] = Field(default_factory=list)
    status: MatchStatus | None = None
    active_projects: int = 0
    capacity: int = 0


class NotificationOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    title: str
    body: str = ""
    kind: str = "info"
    target: dict | None = None
    is_read: bool = False
    created_at: datetime
