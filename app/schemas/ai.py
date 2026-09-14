"""Request and response shapes for the /ai routes used by the Flutter app.

Everything is camelCase on the wire, because the app stores these objects
directly on Firestore documents whose existing fields are camelCase.
"""
from pydantic import BaseModel, ConfigDict, Field
from pydantic.alias_generators import to_camel


class CamelModel(BaseModel):
    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True)


class ChallengeText(CamelModel):
    title: str = Field(min_length=1, max_length=300)
    description: str = Field(min_length=1, max_length=10000)
    additional_info: str = Field(default="", max_length=10000)
    category: str = Field(default="", max_length=120)
    location: str = Field(default="", max_length=300)


class AnalyzeRequest(ChallengeText):
    # The Firestore document id. When present the challenge is added to the
    # duplicate index and never reported as a duplicate of itself.
    challenge_id: str | None = Field(default=None, max_length=128)
    status: str = Field(default="Under Review", max_length=60)
    # Only used when Firebase auth is off; a verified token's uid wins.
    submitted_by_uid: str | None = Field(default=None, max_length=128)
    index: bool = True


class DuplicatePreviewRequest(ChallengeText):
    exclude_challenge_id: str | None = Field(default=None, max_length=128)
    threshold: float | None = Field(default=None, ge=0.0, le=1.0)


class DuplicateOut(CamelModel):
    challenge_id: str
    title: str
    score: float
    semantic_score: float
    lexical_score: float
    same_location: bool
    status: str


class DuplicateCheckOut(CamelModel):
    is_duplicate: bool
    threshold: float
    best_match: DuplicateOut | None = None
    candidates: list[DuplicateOut] = Field(default_factory=list)


class InstitutionSuggestionOut(CamelModel):
    profile_id: str
    institution: str
    department: str = ""
    city: str = ""
    state: str = ""
    score: float
    score_percent: int
    reasons: list[str] = Field(default_factory=list)
    source: str = ""


class AnalysisOut(CamelModel):
    version: int
    analyzed_at: str
    engine: str
    embedding_model: str
    category: str
    app_category: str
    category_confidence: float
    needs_review: bool
    category_matches_citizen: bool
    tags: list[str] = Field(default_factory=list)
    priority: str
    priority_score: float
    scores: dict[str, float] = Field(default_factory=dict)
    rationale: str = ""
    district: str | None = None
    state: str | None = None
    duplicate: DuplicateOut | None = None
    possible_duplicates: list[DuplicateOut] = Field(default_factory=list)
    suggested_institutions: list[InstitutionSuggestionOut] = Field(default_factory=list)
    indexed: bool = False


class OrganizationIn(CamelModel):
    id: str = Field(min_length=1, max_length=128)
    name: str = Field(min_length=1, max_length=300)
    city: str = ""
    state: str = ""
    type: str = ""


class MatchRequest(ChallengeText):
    challenge_id: str | None = Field(default=None, max_length=128)
    organizations: list[OrganizationIn] = Field(default_factory=list, max_length=500)
    top_k: int = Field(default=5, ge=1, le=20)
    directory_k: int = Field(default=3, ge=0, le=10)


class OrganizationSuggestionOut(CamelModel):
    organization_id: str
    name: str
    city: str = ""
    state: str = ""
    score: float
    score_percent: int
    semantic_score: float
    category_score: float
    capacity_score: float
    proximity_score: float
    reasons: list[str] = Field(default_factory=list)
    profile_linked: bool
    profile_id: str | None = None
    profile_institution: str | None = None
    profile_department: str | None = None
    profile_source: str | None = None
    rank: int


class MatchOut(CamelModel):
    category: str
    registered: list[OrganizationSuggestionOut] = Field(default_factory=list)
    directory: list[InstitutionSuggestionOut] = Field(default_factory=list)


class IndexItem(CamelModel):
    id: str = Field(min_length=1, max_length=128)
    title: str = ""
    description: str = ""
    additional_info: str = ""
    category: str = ""
    location: str = ""
    status: str = "Under Review"
    submitted_by_uid: str | None = None


class SyncRequest(CamelModel):
    challenges: list[IndexItem] = Field(default_factory=list, max_length=2000)
    # Delete index rows missing from this batch. Only send true with the
    # complete challenge list, as the admin dashboard has.
    prune: bool = False


class SyncOut(CamelModel):
    received: int
    created: int
    updated: int
    unchanged: int
    removed: int
    embedding_model: str


class StatusUpdate(CamelModel):
    status: str = Field(min_length=1, max_length=60)


class IndexStatusOut(CamelModel):
    challenge_id: str
    status: str
    indexed: bool


class AiStatusOut(CamelModel):
    llm_available: bool
    llm_model: str
    embedding_model: str
    embedding_dim: int
    duplicate_threshold: float
    categories: list[str]
    app_categories: list[str]
    indexed_challenges: int
    university_profiles: int
    auth_mode: str
