from datetime import datetime, timezone

from sqlalchemy import JSON, DateTime, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base


def _now() -> datetime:
    return datetime.now(timezone.utc)


class IndexedChallenge(Base):
    """Search index over challenges that live in the app's Firestore database.

    Firestore stays the system of record. The backend keeps only what duplicate
    detection needs - the text, where it happened, its status, and a cached
    embedding - keyed by the Firestore document id. text_hash lets a bulk sync
    skip re-embedding documents whose text has not changed.
    """

    __tablename__ = "ai_challenge_index"

    id: Mapped[str] = mapped_column(String(128), primary_key=True)
    title: Mapped[str] = mapped_column(String(300), default="")
    description: Mapped[str] = mapped_column(Text, default="")
    category: Mapped[str] = mapped_column(String(120), default="")
    location: Mapped[str] = mapped_column(String(250), default="")
    district: Mapped[str | None] = mapped_column(String(120), index=True)
    state: Mapped[str | None] = mapped_column(String(120))
    status: Mapped[str] = mapped_column(String(60), default="Under Review", index=True)
    submitted_by_uid: Mapped[str | None] = mapped_column(String(128), index=True)

    text_hash: Mapped[str] = mapped_column(String(64), default="")
    embedding: Mapped[list | None] = mapped_column(JSON)
    embedding_model: Mapped[str | None] = mapped_column(String(120))

    ai_category: Mapped[str | None] = mapped_column(String(120))
    ai_priority: Mapped[str | None] = mapped_column(String(20))

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_now, onupdate=_now
    )
