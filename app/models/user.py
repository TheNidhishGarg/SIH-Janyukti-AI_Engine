from datetime import datetime, timezone

from sqlalchemy import JSON, Boolean, DateTime, Enum, ForeignKey, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base
from app.models.enums import UserRole


def _now() -> datetime:
    return datetime.now(timezone.utc)


class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    email: Mapped[str] = mapped_column(String(180), unique=True, index=True, nullable=False)
    phone: Mapped[str | None] = mapped_column(String(20), index=True)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    role: Mapped[UserRole] = mapped_column(Enum(UserRole), nullable=False, index=True)

    # Set when role == university / industry, linking the login to its org profile.
    university_id: Mapped[str | None] = mapped_column(ForeignKey("universities.id"))
    industry_id: Mapped[str | None] = mapped_column(ForeignKey("industry_profiles.id"))

    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    is_verified: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)

    university: Mapped["University | None"] = relationship(back_populates="users", lazy="selectin")
    industry: Mapped["IndustryProfile | None"] = relationship(back_populates="users", lazy="selectin")


class University(Base):
    """A university department/centre profile — the unit smart-matching ranks."""

    __tablename__ = "universities"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    name: Mapped[str] = mapped_column(String(200), nullable=False, index=True)
    department: Mapped[str] = mapped_column(String(200), default="")
    city: Mapped[str] = mapped_column(String(120), default="")
    state: Mapped[str] = mapped_column(String(120), default="")
    contact_email: Mapped[str | None] = mapped_column(String(180))

    # Free-text description of capabilities — the text that gets embedded.
    expertise_summary: Mapped[str] = mapped_column(Text, default="")
    # ["water treatment", "IoT sensors", ...]
    expertise_tags: Mapped[list] = mapped_column(JSON, default=list)
    # Categories from the taxonomy this dept declares it can take on.
    categories: Mapped[list] = mapped_column(JSON, default=list)

    # Capacity signals used by the ranker alongside semantic similarity.
    capacity: Mapped[int] = mapped_column(default=3)
    active_projects: Mapped[int] = mapped_column(default=0)
    completed_projects: Mapped[int] = mapped_column(default=0)

    # Provenance. Rows ingested from OpenAlex carry their ROR/OpenAlex id so the
    # ingest is idempotent and a profile can be traced back to its source.
    source: Mapped[str] = mapped_column(String(40), default="manual")
    ror: Mapped[str | None] = mapped_column(String(120), index=True)
    openalex_id: Mapped[str | None] = mapped_column(String(120), index=True)
    works_count: Mapped[int] = mapped_column(default=0)

    embedding: Mapped[list | None] = mapped_column(JSON)
    embedding_model: Mapped[str | None] = mapped_column(String(120))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)

    users: Mapped[list["User"]] = relationship(back_populates="university")

    @property
    def display_name(self) -> str:
        return f"{self.name} — {self.department}" if self.department else self.name


class IndustryProfile(Base):
    __tablename__ = "industry_profiles"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    name: Mapped[str] = mapped_column(String(200), nullable=False, index=True)
    sector: Mapped[str] = mapped_column(String(120), default="")
    city: Mapped[str] = mapped_column(String(120), default="")
    state: Mapped[str] = mapped_column(String(120), default="")
    website: Mapped[str | None] = mapped_column(String(255))
    # What this company can offer: funding / mentorship / pilot site / equipment.
    support_types: Mapped[list] = mapped_column(JSON, default=list)
    focus_categories: Mapped[list] = mapped_column(JSON, default=list)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)

    users: Mapped[list["User"]] = relationship(back_populates="industry")
