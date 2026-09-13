from datetime import datetime, timezone
from typing import TYPE_CHECKING

from sqlalchemy import JSON, Boolean, DateTime, Enum, Float, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base
from app.models.enums import InterestStatus, MatchStatus


if TYPE_CHECKING:
    from app.models.user import IndustryProfile, University


def _now() -> datetime:
    return datetime.now(timezone.utc)


class Match(Base):
    """One AI-suggested challenge-to-university pairing with its score breakdown.

    Persisted rather than recomputed per request, so the admin screen can show
    exactly what the model recommended and whether the admin overrode it.
    """

    __tablename__ = "matches"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    challenge_id: Mapped[str] = mapped_column(ForeignKey("challenges.id"), index=True)
    university_id: Mapped[str] = mapped_column(ForeignKey("universities.id"), index=True)

    score: Mapped[float] = mapped_column(Float, default=0.0)           # final 0-1 rank score
    semantic_score: Mapped[float] = mapped_column(Float, default=0.0)  # cosine similarity
    category_score: Mapped[float] = mapped_column(Float, default=0.0)  # taxonomy overlap
    proximity_score: Mapped[float] = mapped_column(Float, default=0.0) # same district/state
    capacity_score: Mapped[float] = mapped_column(Float, default=0.0)  # free capacity
    rank: Mapped[int] = mapped_column(Integer, default=0)
    reasons: Mapped[list | None] = mapped_column(JSON)                 # why this match

    status: Mapped[MatchStatus] = mapped_column(Enum(MatchStatus), default=MatchStatus.suggested)
    # True when an admin picked a university the ranker did not put first.
    was_override: Mapped[bool] = mapped_column(Boolean, default=False)
    decided_by_id: Mapped[str | None] = mapped_column(ForeignKey("users.id"))
    decided_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    decline_reason: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)

    university: Mapped["University"] = relationship(lazy="selectin")  # noqa: F821


class IndustryInterest(Base):
    __tablename__ = "industry_interests"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    challenge_id: Mapped[str | None] = mapped_column(ForeignKey("challenges.id"), index=True)
    project_id: Mapped[str | None] = mapped_column(ForeignKey("projects.id"), index=True)
    industry_id: Mapped[str] = mapped_column(ForeignKey("industry_profiles.id"), index=True)
    created_by_id: Mapped[str] = mapped_column(ForeignKey("users.id"))

    support: Mapped[list] = mapped_column(JSON, default=list)  # Funding, Mentorship, Pilot Site...
    message: Mapped[str] = mapped_column(Text, default="")
    funding_amount: Mapped[float | None] = mapped_column(Float)
    status: Mapped[InterestStatus] = mapped_column(Enum(InterestStatus), default=InterestStatus.pending)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)

    industry: Mapped["IndustryProfile"] = relationship(lazy="selectin")  # noqa: F821


class Notification(Base):
    __tablename__ = "notifications"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    body: Mapped[str] = mapped_column(Text, default="")
    kind: Mapped[str] = mapped_column(String(40), default="info")
    # Lets the app deep-link, e.g. {"type": "challenge", "id": "CH-2026-00124"}
    target: Mapped[dict | None] = mapped_column(JSON)
    is_read: Mapped[bool] = mapped_column(Boolean, default=False, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now, index=True)
