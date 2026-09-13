"""Human-readable ID generation.

The Flutter app already renders IDs like "CH-2025-00124" on the Track Challenge
screen, so challenges and projects keep that shape instead of raw UUIDs.
"""
import uuid
from datetime import datetime, timezone

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession


def new_uuid() -> str:
    return str(uuid.uuid4())


async def next_challenge_id(db: AsyncSession) -> str:
    from app.models import Challenge

    return await _next_sequential_id(db, Challenge, "CH")


async def next_project_id(db: AsyncSession) -> str:
    from app.models import Project

    return await _next_sequential_id(db, Project, "PR")


async def _next_sequential_id(db: AsyncSession, model, prefix: str) -> str:
    year = datetime.now(timezone.utc).year
    pattern = f"{prefix}-{year}-%"
    count = await db.scalar(select(func.count()).select_from(model).where(model.id.like(pattern)))
    seq = (count or 0) + 1

    # Counting can collide if a row was deleted; walk forward until the id is free.
    while True:
        candidate = f"{prefix}-{year}-{seq:05d}"
        exists = await db.scalar(select(model.id).where(model.id == candidate))
        if not exists:
            return candidate
        seq += 1
