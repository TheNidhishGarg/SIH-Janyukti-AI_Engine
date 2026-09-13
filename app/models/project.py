from datetime import datetime, timezone
from typing import TYPE_CHECKING

from sqlalchemy import JSON, DateTime, Enum, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base
from app.models.enums import MilestoneStatus, ProjectStatus


if TYPE_CHECKING:
    from app.models.challenge import Challenge
    from app.models.user import University


def _now() -> datetime:
    return datetime.now(timezone.utc)


DEFAULT_MILESTONES = [
    "Problem Analysis",
    "Research & Feasibility",
    "Prototype Development",
    "Field Testing",
    "Deployment",
]


class Project(Base):
    __tablename__ = "projects"

    id: Mapped[str] = mapped_column(String(24), primary_key=True)  # PR-2026-00007
    name: Mapped[str] = mapped_column(String(250), nullable=False)
    description: Mapped[str] = mapped_column(Text, default="")
    category: Mapped[str] = mapped_column(String(120), default="Other", index=True)

    challenge_id: Mapped[str] = mapped_column(ForeignKey("challenges.id"), index=True)
    university_id: Mapped[str] = mapped_column(ForeignKey("universities.id"), index=True)
    mentor: Mapped[str] = mapped_column(String(160), default="")

    status: Mapped[ProjectStatus] = mapped_column(Enum(ProjectStatus), default=ProjectStatus.active)
    progress: Mapped[int] = mapped_column(Integer, default=0)  # 0-100, derived from milestones

    # Impact metrics reported at completion - feed the analytics dashboard.
    people_impacted: Mapped[int] = mapped_column(Integer, default=0)
    impact_summary: Mapped[str | None] = mapped_column(Text)
    impact_metrics: Mapped[dict | None] = mapped_column(JSON)

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now, index=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now, onupdate=_now)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    challenge: Mapped["Challenge"] = relationship(lazy="selectin")  # noqa: F821
    university: Mapped["University"] = relationship(lazy="selectin")  # noqa: F821
    milestones: Mapped[list["Milestone"]] = relationship(
        back_populates="project",
        lazy="selectin",
        cascade="all, delete-orphan",
        order_by="Milestone.order_index",
    )

    @property
    def active_milestone_index(self) -> int:
        for i, m in enumerate(self.milestones):
            if m.status != MilestoneStatus.approved:
                return i
        return max(len(self.milestones) - 1, 0)


class Milestone(Base):
    __tablename__ = "milestones"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    project_id: Mapped[str] = mapped_column(ForeignKey("projects.id"), index=True)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[str] = mapped_column(Text, default="")
    order_index: Mapped[int] = mapped_column(Integer, default=0)
    status: Mapped[MilestoneStatus] = mapped_column(Enum(MilestoneStatus), default=MilestoneStatus.pending)

    due_date: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    submitted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    approved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    evidence_url: Mapped[str | None] = mapped_column(String(600))
    review_note: Mapped[str | None] = mapped_column(Text)

    project: Mapped["Project"] = relationship(back_populates="milestones")


class ChatMessage(Base):
    """Per-project workspace chat, replacing the frontend List[str] mock."""

    __tablename__ = "chat_messages"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    project_id: Mapped[str] = mapped_column(ForeignKey("projects.id"), index=True)
    sender_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    sender_name: Mapped[str] = mapped_column(String(120), default="")
    sender_role: Mapped[str] = mapped_column(String(20), default="citizen")
    body: Mapped[str] = mapped_column(Text, nullable=False)
    attachment_url: Mapped[str | None] = mapped_column(String(600))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now, index=True)
