from pydantic import BaseModel, Field


class CitizenStats(BaseModel):
    """Powers the three counters on the Flutter citizen home screen."""

    challenges: int = 0
    in_progress: int = 0
    people_impacted: int = 0
    resolved: int = 0


class UniversityStats(BaseModel):
    assigned: int = 0
    active_projects: int = 0
    completed_projects: int = 0
    pending_milestones: int = 0
    people_impacted: int = 0


class IndustryStats(BaseModel):
    interests_submitted: int = 0
    accepted: int = 0
    projects_supported: int = 0
    total_funding: float = 0.0


class AdminStats(BaseModel):
    total_challenges: int = 0
    pending_review: int = 0
    assigned: int = 0
    in_progress: int = 0
    resolved: int = 0
    duplicates_flagged: int = 0
    total_projects: int = 0
    universities: int = 0
    industries: int = 0
    citizens: int = 0
    people_impacted: int = 0
    by_category: dict[str, int] = Field(default_factory=dict)
    by_priority: dict[str, int] = Field(default_factory=dict)
    by_status: dict[str, int] = Field(default_factory=dict)
    by_district: dict[str, int] = Field(default_factory=dict)
    ai_assist_rate: float = 0.0      # share of challenges an AI analysis ran on
    match_acceptance_rate: float = 0.0  # share of AI top picks admins kept
