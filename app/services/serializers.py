"""ORM -> response-schema conversion.

Kept in one place so the wire shape the Flutter app binds to is defined once
and cannot drift between routes.
"""
from __future__ import annotations

from app.models import Challenge, ChatMessage, IndustryInterest, Match, Project, University
from app.schemas.challenge import (
    AiSuggestionOut,
    AttachmentOut,
    ChallengeDetailOut,
    ChallengeEventOut,
    ChallengeOut,
)
from app.schemas.org import InterestOut, MatchOut, UniversityOut
from app.schemas.project import ChatMessageOut, MilestoneOut, ProjectOut
from app.models.enums import ChallengeStatus


def challenge_out(c: Challenge) -> ChallengeOut:
    uni_name = c.assigned_university.name if c.assigned_university else None
    if c.status == ChallengeStatus.assigned and uni_name:
        label = f"Assigned to {uni_name}"
    else:
        label = c.status.value

    return ChallengeOut(
        id=c.id,
        title=c.title,
        description=c.description,
        category=c.category,
        location=c.location,
        latitude=c.latitude,
        longitude=c.longitude,
        district=c.district,
        state=c.state,
        status=c.status,
        status_label=label,
        priority=c.priority,
        upvotes=c.upvotes,
        people_impacted=c.people_impacted,
        submitted_by_id=c.submitted_by_id,
        submitted_by=c.submitted_by.name if c.submitted_by else "",
        assigned_university_id=c.assigned_university_id,
        assigned_university_name=uni_name,
        created_at=c.created_at,
        updated_at=c.updated_at,
        attachments=[AttachmentOut.model_validate(a) for a in c.attachments],
    )


def challenge_detail_out(c: Challenge) -> ChallengeDetailOut:
    base = challenge_out(c).model_dump()
    ai = None
    if c.ai_analyzed_at:
        ai = AiSuggestionOut(
            category=c.ai_category,
            category_confidence=c.ai_category_confidence,
            priority=c.ai_priority,
            priority_score=c.ai_priority_score,
            scores=c.ai_scores,
            rationale=c.ai_rationale,
            tags=c.ai_tags,
            engine=c.ai_engine,
            analyzed_at=c.ai_analyzed_at,
            duplicate_of=c.duplicate_of_id,
            duplicate_score=c.duplicate_score,
        )
    return ChallengeDetailOut(
        **base,
        ai=ai,
        timeline=[ChallengeEventOut.model_validate(e) for e in c.timeline],
    )


def project_out(p: Project) -> ProjectOut:
    return ProjectOut(
        id=p.id,
        name=p.name,
        description=p.description,
        category=p.category,
        challenge_id=p.challenge_id,
        challenge_title=p.challenge.title if p.challenge else "",
        university_id=p.university_id,
        university=p.university.name if p.university else "",
        mentor=p.mentor,
        status=p.status,
        progress=p.progress,
        active_milestone=p.active_milestone_index,
        people_impacted=p.people_impacted,
        impact_summary=p.impact_summary,
        impact_metrics=p.impact_metrics,
        created_at=p.created_at,
        updated_at=p.updated_at,
        completed_at=p.completed_at,
        milestones=[MilestoneOut.model_validate(m) for m in p.milestones],
    )


def university_out(u: University) -> UniversityOut:
    return UniversityOut(
        id=u.id,
        name=u.name,
        department=u.department,
        display_name=u.display_name,
        city=u.city,
        state=u.state,
        contact_email=u.contact_email,
        expertise_summary=u.expertise_summary,
        expertise_tags=u.expertise_tags or [],
        categories=u.categories or [],
        capacity=u.capacity,
        active_projects=u.active_projects,
        completed_projects=u.completed_projects,
    )


def match_out(m: Match) -> MatchOut:
    u = m.university
    return MatchOut(
        id=m.id,
        university_id=m.university_id,
        name=u.name if u else "",
        department=u.department if u else "",
        city=u.city if u else "",
        state=u.state if u else "",
        score=m.score,
        semantic_score=m.semantic_score,
        category_score=m.category_score,
        capacity_score=m.capacity_score,
        proximity_score=m.proximity_score,
        rank=m.rank,
        reasons=m.reasons or [],
        status=m.status,
        active_projects=u.active_projects if u else 0,
        capacity=u.capacity if u else 0,
    )


def interest_out(i: IndustryInterest) -> InterestOut:
    return InterestOut(
        id=i.id,
        challenge_id=i.challenge_id,
        project_id=i.project_id,
        industry_id=i.industry_id,
        industry_name=i.industry.name if i.industry else "",
        support=i.support or [],
        message=i.message,
        funding_amount=i.funding_amount,
        status=i.status,
        created_at=i.created_at,
    )


def chat_out(m: ChatMessage) -> ChatMessageOut:
    return ChatMessageOut.model_validate(m)
