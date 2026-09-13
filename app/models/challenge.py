from datetime import datetime, timezone
from typing import TYPE_CHECKING

from sqlalchemy import JSON, DateTime, Enum, Float, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base
from app.models.enums import ChallengeStatus, Priority


if TYPE_CHECKING:
    from app.models.user import University, User


def _now() -> datetime:
    return datetime.now(timezone.utc)


class Challenge(Base):
    __tablename__ = "challenges"

    # Human-readable ID the Flutter app already renders, e.g. "CH-2026-00124".
    id: Mapped[str] = mapped_column(String(24), primary_key=True)

    title: Mapped[str] = mapped_column(String(250), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=False)
    location: Mapped[str] = mapped_column(String(200), default="")
    latitude: Mapped[float | None] = mapped_column(Float)
    longitude: Mapped[float | None] = mapped_column(Float)
    district: Mapped[str | None] = mapped_column(String(120), index=True)
    state: Mapped[str | None] = mapped_column(String(120), index=True)

    # Category the citizen picked; ai_category is what the model inferred.
    category: Mapped[str] = mapped_column(String(120), default="Other", index=True)
    status: Mapped[ChallengeStatus] = mapped_column(
        Enum(ChallengeStatus), default=ChallengeStatus.submitted, index=True
    )
    priority: Mapped[Priority] = mapped_column(Enum(Priority), default=Priority.medium, index=True)

    submitted_by_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    assigned_university_id: Mapped[str | None] = mapped_column(ForeignKey("universities.id"), index=True)

    upvotes: Mapped[int] = mapped_column(Integer, default=0)
    people_impacted: Mapped[int] = mapped_column(Integer, default=0)

    # --- AI engine output (nullable until analysis runs) ---
    ai_category: Mapped[str | None] = mapped_column(String(120))
    ai_category_confidence: Mapped[float | None] = mapped_column(Float)
    ai_priority: Mapped[Priority | None] = mapped_column(Enum(Priority))
    ai_priority_score: Mapped[float | None] = mapped_column(Float)
    ai_rationale: Mapped[str | None] = mapped_column(Text)
    # {"impact": 4, "urgency": 5, "reach": 3, "severity": 4}
    ai_scores: Mapped[dict | None] = mapped_column(JSON)
    ai_tags: Mapped[list | None] = mapped_column(JSON)
    ai_engine: Mapped[str | None] = mapped_column(String(60))  # "gemini" | "heuristic"
    ai_analyzed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    duplicate_of_id: Mapped[str | None] = mapped_column(ForeignKey("challenges.id"))
    duplicate_score: Mapped[float | None] = mapped_column(Float)

    embedding: Mapped[list | None] = mapped_column(JSON)
    embedding_model: Mapped[str | None] = mapped_column(String(120))

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now, index=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now, onupdate=_now)

    submitted_by: Mapped["User"] = relationship(lazy="selectin")  # noqa: F821
    assigned_university: Mapped["University | None"] = relationship(lazy="selectin")  # noqa: F821
    attachments: Mapped[list["Attachment"]] = relationship(
        back_populates="challenge", lazy="selectin", cascade="all, delete-orphan"
    )
    timeline: Mapped[list["ChallengeEvent"]] = relationship(
        back_populates="challenge", lazy="selectin", cascade="all, delete-orphan",
        order_by="ChallengeEvent.created_at",
    )

    @property
    def status_label(self) -> str:
        """Matches the string the Flutter UI shows, e.g. 'Assigned to BIT Mesra'."""
        if self.status == ChallengeStatus.assigned and self.assigned_university:
            return f"Assigned to {self.assigned_university.name}"
        return self.status.value


class Attachment(Base):
    __tablename__ = "attachments"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    challenge_id: Mapped[str] = mapped_column(ForeignKey("challenges.id"), index=True)
    url: Mapped[str] = mapped_column(String(600), nullable=False)
    kind: Mapped[str] = mapped_column(String(20), default="image")  # image | video | document
    filename: Mapped[str] = mapped_column(String(255), default="")
    size_bytes: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)

    challenge: Mapped["Challenge"] = relationship(back_populates="attachments")


class ChallengeEvent(Base):
    """Append-only audit trail — powers the 'Track Challenge' timeline screen."""

    __tablename__ = "challenge_events"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    challenge_id: Mapped[str] = mapped_column(ForeignKey("challenges.id"), index=True)
    label: Mapped[str] = mapped_column(String(160), nullable=False)
    detail: Mapped[str | None] = mapped_column(Text)
    actor_id: Mapped[str | None] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)

    challenge: Mapped["Challenge"] = relationship(back_populates="timeline")
