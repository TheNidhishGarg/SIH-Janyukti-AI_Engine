"""Schemas for the standalone /ml endpoints.

These let the AI engine be demoed and evaluated on its own - useful both for
the judges' walkthrough and for regression-testing model changes.
"""
from pydantic import BaseModel, Field


class AnalyzeRequest(BaseModel):
    title: str = Field(min_length=3)
    description: str = Field(min_length=5)
    category: str = ""
    location: str = ""
    district: str | None = None
    state: str | None = None
    run_matching: bool = True


class CategoryOut(BaseModel):
    category: str
    confidence: float
    tags: list[str] = Field(default_factory=list)
    engine: str
    needs_review: bool = False


class PriorityOut(BaseModel):
    priority: str
    score: float
    scores: dict = Field(default_factory=dict)
    rationale: str = ""
    engine: str


class DuplicateCandidateOut(BaseModel):
    challenge_id: str
    title: str
    score: float
    semantic_score: float
    lexical_score: float
    same_location: bool
    status: str
    created_at: str | None = None


class DuplicateCheckRequest(BaseModel):
    title: str
    description: str
    category: str = ""
    location: str = ""
    district: str | None = None
    exclude_id: str | None = None
    threshold: float | None = Field(default=None, ge=0.0, le=1.0)


class DuplicateCheckOut(BaseModel):
    is_duplicate: bool
    threshold: float
    best_match: DuplicateCandidateOut | None = None
    candidates: list[DuplicateCandidateOut] = Field(default_factory=list)


class MatchRequest(BaseModel):
    title: str
    description: str
    category: str = ""
    location: str = ""
    district: str | None = None
    state: str | None = None
    tags: list[str] = Field(default_factory=list)
    top_k: int | None = Field(default=None, ge=1, le=25)


class AnalysisOut(BaseModel):
    category: str
    category_confidence: float
    priority: str
    priority_score: float
    scores: dict = Field(default_factory=dict)
    rationale: str = ""
    tags: list[str] = Field(default_factory=list)
    engine: str
    needs_review: bool = False
    duplicate_of: str | None = None
    duplicate_score: float | None = None
    duplicate_candidates: list[DuplicateCandidateOut] = Field(default_factory=list)
    matches: list[dict] = Field(default_factory=list)
    embedding_model: str = ""


class MlStatusOut(BaseModel):
    llm_available: bool
    llm_model: str
    embedding_model: str
    embedding_dim: int
    using_local_embeddings: bool
    duplicate_threshold: float
    categories: list[str]
