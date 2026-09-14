"""The AI engine as a service for the Flutter app.

The app keeps its data in Firestore. This module analyses challenge text on
request, maintains a small index of Firestore challenges for duplicate
detection, and never needs write access to Firestore: the app stores the
analysis on the challenge document itself, which is exactly what makes every
existing live stream in the app pick the result up.
"""
from __future__ import annotations

import asyncio
import hashlib
import re
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Iterable

from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.ml import categorizer, matching
from app.ml import priority as priority_mod
from app.ml.duplicates import DuplicateCandidate, find_indexed_duplicates
from app.ml.embeddings import active_model_name, challenge_text, embed, embed_many
from app.ml.matching import MatchCandidate
from app.ml.taxonomy import normalize_category, to_app_category
from app.models import IndexedChallenge

# Stored on every analysis so the app can tell a stale result from a current
# one if the scoring ever changes shape.
ANALYSIS_VERSION = 1

_STATES = {
    name.lower(): name
    for name in (
        "Andhra Pradesh", "Arunachal Pradesh", "Assam", "Bihar", "Chhattisgarh", "Goa",
        "Gujarat", "Haryana", "Himachal Pradesh", "Jharkhand", "Karnataka", "Kerala",
        "Madhya Pradesh", "Maharashtra", "Manipur", "Meghalaya", "Mizoram", "Nagaland",
        "Odisha", "Punjab", "Rajasthan", "Sikkim", "Tamil Nadu", "Telangana", "Tripura",
        "Uttar Pradesh", "Uttarakhand", "West Bengal", "Andaman and Nicobar Islands",
        "Chandigarh", "Dadra and Nagar Haveli and Daman and Diu", "Delhi",
        "Jammu and Kashmir", "Ladakh", "Lakshadweep", "Puducherry",
    )
}
_STATES.update({
    "orissa": "Odisha",
    "nct of delhi": "Delhi",
    "new delhi": "Delhi",
    "pondicherry": "Puducherry",
    "uttaranchal": "Uttarakhand",
})
_PIN = re.compile(r"\b\d{6}\b")


def combine_description(description: str | None, additional_info: str | None = "") -> str:
    """Citizens often put the decisive detail in 'additional information'."""
    description = (description or "").strip()
    extra = (additional_info or "").strip()
    return f"{description}\n{extra}" if extra else description


def split_location(location: str | None) -> tuple[str | None, str | None]:
    """Best-effort (district, state) from a typed or geocoded address.

    Handles "Ranchi, Jharkhand", "Namkum, Ranchi, Jharkhand 834010, India" and
    a bare "Khunti". The state is the last recognised Indian state; the district
    is the part just before it, or the last part when no state is present.
    """
    if not location:
        return None, None
    parts: list[str] = []
    for raw in location.split(","):
        part = _PIN.sub("", raw).strip()
        if part and part.lower() != "india":
            parts.append(part)
    if not parts:
        return None, None
    for i in range(len(parts) - 1, -1, -1):
        state = _STATES.get(parts[i].lower())
        if state:
            return (parts[i - 1] if i > 0 else None), state
    return parts[-1], None


def text_hash(title: str, description: str, category: str, location: str) -> str:
    joined = "\x1f".join((title or "", description or "", category or "", location or ""))
    return hashlib.sha256(joined.encode("utf-8")).hexdigest()


@dataclass
class Analysis:
    analyzed_at: str
    engine: str
    embedding_model: str
    category: str
    app_category: str
    category_confidence: float
    needs_review: bool
    category_matches_citizen: bool
    tags: list[str]
    priority: str
    priority_score: float
    scores: dict
    rationale: str
    district: str | None
    state: str | None
    duplicate: DuplicateCandidate | None
    possible_duplicates: list[DuplicateCandidate] = field(default_factory=list)
    suggested_institutions: list[MatchCandidate] = field(default_factory=list)
    indexed: bool = False
    version: int = ANALYSIS_VERSION


async def analyze_challenge(
    db: AsyncSession,
    *,
    title: str,
    description: str,
    category: str = "",
    location: str = "",
    additional_info: str = "",
    challenge_id: str | None = None,
    status: str = "Under Review",
    submitted_by_uid: str | None = None,
    index: bool = True,
    suggestions_k: int = 3,
) -> Analysis:
    full_description = combine_description(description, additional_info)
    district, state = split_location(location)
    citizen_category = normalize_category(category)

    vector = embed(challenge_text(title, full_description, category, location))

    classified, first_priority = await asyncio.gather(
        categorizer.classify(title, full_description, location),
        priority_mod.score(title, full_description, citizen_category, location),
    )
    # Severity weighting depends on the category, so re-score under the AI's
    # category when it disagrees with the citizen's pick.
    if classified.category == citizen_category:
        scored = first_priority
    else:
        scored = await priority_mod.score(title, full_description, classified.category, location)

    possible, best = await find_indexed_duplicates(
        db,
        title=title,
        description=full_description,
        category=category,
        location=location,
        district=district,
        exclude_id=challenge_id,
        embedding=vector,
    )

    suggestions = await matching.rank_universities(
        db,
        title=title,
        description=full_description,
        category=classified.category,
        location=location,
        district=district,
        state=state,
        tags=classified.tags,
        embedding=vector,
        top_k=suggestions_k,
    )

    indexed = False
    if index and challenge_id:
        await upsert_index(
            db,
            challenge_id=challenge_id,
            title=title,
            description=full_description,
            category=category,
            location=location,
            status=status,
            submitted_by_uid=submitted_by_uid,
            embedding=vector,
            ai_category=classified.category,
            ai_priority=scored.priority,
        )
        indexed = True

    engine = "gemini" if "gemini" in (classified.engine, scored.engine) else "heuristic"
    matches_citizen = (
        classified.category == citizen_category
        or to_app_category(classified.category) == (category or "").strip()
    )

    return Analysis(
        analyzed_at=datetime.now(timezone.utc).isoformat(timespec="seconds"),
        engine=engine,
        embedding_model=active_model_name(),
        category=classified.category,
        app_category=to_app_category(classified.category),
        category_confidence=classified.confidence,
        needs_review=classified.needs_review,
        category_matches_citizen=matches_citizen,
        tags=classified.tags,
        priority=scored.priority,
        priority_score=scored.score,
        scores=scored.scores,
        rationale=scored.rationale,
        district=district,
        state=state,
        duplicate=best,
        possible_duplicates=possible,
        suggested_institutions=suggestions,
        indexed=indexed,
    )


async def upsert_index(
    db: AsyncSession,
    *,
    challenge_id: str,
    title: str,
    description: str,
    category: str,
    location: str,
    status: str | None = None,
    submitted_by_uid: str | None = None,
    embedding: list[float] | None = None,
    ai_category: str | None = None,
    ai_priority: str | None = None,
) -> str:
    """Insert or refresh one index row. Returns created, updated or unchanged.

    `description` must already include any additional information, so that the
    stored text matches what duplicate queries are scored against.
    """
    digest = text_hash(title, description, category, location)
    model = active_model_name()
    district, state = split_location(location)
    row = await db.get(IndexedChallenge, challenge_id)

    if row is None:
        db.add(
            IndexedChallenge(
                id=challenge_id,
                title=title or "",
                description=description or "",
                category=category or "",
                location=location or "",
                district=district,
                state=state,
                status=status or "Under Review",
                submitted_by_uid=submitted_by_uid,
                text_hash=digest,
                embedding=embedding or embed(challenge_text(title, description, category, location)),
                embedding_model=model,
                ai_category=ai_category,
                ai_priority=ai_priority,
            )
        )
        return "created"

    text_changed = row.text_hash != digest or row.embedding_model != model or not row.embedding
    if text_changed:
        row.title = title or ""
        row.description = description or ""
        row.category = category or ""
        row.location = location or ""
        row.district = district
        row.state = state
        row.text_hash = digest
        row.embedding = embedding or embed(challenge_text(title, description, category, location))
        row.embedding_model = model

    status_changed = bool(status) and row.status != status
    if status:
        row.status = status
    if submitted_by_uid:
        row.submitted_by_uid = submitted_by_uid
    if ai_category:
        row.ai_category = ai_category
    if ai_priority:
        row.ai_priority = ai_priority

    return "updated" if text_changed or status_changed else "unchanged"


async def sync_index(db: AsyncSession, items: Iterable, prune: bool = False) -> dict[str, int]:
    """Bring the index in line with a batch of Firestore challenges.

    Items need id, title, description, additional_info, category, location,
    status and submitted_by_uid. Only rows whose text changed are re-embedded,
    in one batch, so re-sending the full challenge list is cheap. With prune,
    index rows absent from the batch are deleted - the caller must send the
    complete list.
    """
    unique = {item.id: item for item in items}  # last occurrence wins
    items = list(unique.values())
    counts = {"received": len(items), "created": 0, "updated": 0, "unchanged": 0, "removed": 0}
    if not items:
        return counts

    ids = [item.id for item in items]
    existing: dict[str, IndexedChallenge] = {}
    for start in range(0, len(ids), 500):
        chunk = ids[start:start + 500]
        rows = (await db.scalars(select(IndexedChallenge).where(IndexedChallenge.id.in_(chunk)))).all()
        existing.update({row.id: row for row in rows})

    model = active_model_name()
    prepared: list[tuple[object, str]] = []
    stale_ids: list[str] = []
    stale_texts: list[str] = []
    for item in items:
        description = combine_description(item.description, item.additional_info)
        prepared.append((item, description))
        row = existing.get(item.id)
        digest = text_hash(item.title, description, item.category, item.location)
        if row is None or row.text_hash != digest or row.embedding_model != model or not row.embedding:
            stale_ids.append(item.id)
            stale_texts.append(challenge_text(item.title, description, item.category, item.location))

    vectors = dict(zip(stale_ids, embed_many(stale_texts))) if stale_texts else {}

    for item, description in prepared:
        outcome = await upsert_index(
            db,
            challenge_id=item.id,
            title=item.title,
            description=description,
            category=item.category,
            location=item.location,
            status=item.status,
            submitted_by_uid=item.submitted_by_uid,
            embedding=vectors.get(item.id),
        )
        counts[outcome] += 1

    if prune:
        result = await db.execute(delete(IndexedChallenge).where(IndexedChallenge.id.notin_(ids)))
        counts["removed"] = result.rowcount or 0

    await db.flush()
    return counts


async def update_index_status(db: AsyncSession, challenge_id: str, status: str) -> bool:
    row = await db.get(IndexedChallenge, challenge_id)
    if row is None:
        return False
    row.status = status
    return True


async def index_size(db: AsyncSession) -> int:
    return await db.scalar(select(func.count()).select_from(IndexedChallenge)) or 0
