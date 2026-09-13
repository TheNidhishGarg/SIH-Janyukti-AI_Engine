"""Priority scoring on an explicit four-axis rubric.

Axes (each 1-5): severity, urgency, reach, vulnerability. A transparent rubric
matters more than raw accuracy here - an admin overriding "High" needs to see
which axis drove it, and a black-box number gives them nothing to argue with.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field

from app.ml import llm
from app.ml.taxonomy import CATEGORY_SEVERITY_WEIGHT

AXES = ("severity", "urgency", "reach", "vulnerability")
AXIS_WEIGHTS = {"severity": 0.35, "urgency": 0.30, "reach": 0.20, "vulnerability": 0.15}

HIGH_CUTOFF = 0.62
MEDIUM_CUTOFF = 0.38


@dataclass
class PriorityResult:
    priority: str                      # High | Medium | Low
    score: float                       # 0-1 weighted rubric score
    scores: dict = field(default_factory=dict)   # per-axis 1-5
    rationale: str = ""
    engine: str = "heuristic"


# Phrases that reliably move an axis, with the axis they move and by how much.
_SIGNALS: dict[str, tuple[str, float]] = {
    # severity
    "death": ("severity", 2.0), "died": ("severity", 2.0), "fatal": ("severity", 2.0),
    "disease": ("severity", 1.2), "illness": ("severity", 1.0), "health issue": ("severity", 1.2),
    "contaminat": ("severity", 1.5), "poison": ("severity", 1.8), "accident": ("severity", 1.3),
    "injur": ("severity", 1.3), "collapse": ("severity", 1.5), "unsafe": ("severity", 1.0),
    "outbreak": ("severity", 1.8), "hospital": ("severity", 0.8), "toxic": ("severity", 1.5),
    "fallen sick": ("severity", 1.3), "falling sick": ("severity", 1.3),
    "infection": ("severity", 1.3), "sewage": ("severity", 1.2),
    "open defecation": ("severity", 1.3), "epidemic": ("severity", 2.0),
    # urgency
    "urgent": ("urgency", 1.5), "immediate": ("urgency", 1.5), "emergency": ("urgency", 2.0),
    "daily": ("urgency", 0.8), "every day": ("urgency", 0.8), "worsen": ("urgency", 1.2),
    "months": ("urgency", 0.6), "years": ("urgency", 0.9), "frequent": ("urgency", 0.8),
    "monsoon": ("urgency", 0.7), "spreading": ("urgency", 1.2),
    # reach
    "village": ("reach", 1.0), "community": ("reach", 0.8), "entire": ("reach", 1.2),
    "several": ("reach", 0.8), "many": ("reach", 0.6), "district": ("reach", 1.5),
    "residential area": ("reach", 1.0), "households": ("reach", 1.0), "town": ("reach", 1.2),
    "city": ("reach", 1.3), "region": ("reach", 1.3), "public": ("reach", 0.6),
    # vulnerability
    "children": ("vulnerability", 1.5), "student": ("vulnerability", 1.0),
    "school": ("vulnerability", 0.8), "elderly": ("vulnerability", 1.5),
    "women": ("vulnerability", 1.0), "pregnant": ("vulnerability", 1.8),
    "infant": ("vulnerability", 1.8), "disabled": ("vulnerability", 1.5),
    "poor": ("vulnerability", 1.0), "tribal": ("vulnerability", 1.2),
    "rural": ("vulnerability", 0.8), "farmer": ("vulnerability", 0.8),
}

_NUMBER_RE = re.compile(r"\b(\d[\d,]{2,})\b")

_PROMPT = """You are the triage engine for JanYukti, an Indian civic platform.
Score this citizen-reported challenge on four axes, each an INTEGER 1-5.

severity      1 = minor inconvenience, 5 = risk to life or health
urgency       1 = can wait a year, 5 = needs action this week
reach         1 = a single household, 5 = an entire district
vulnerability 1 = general population, 5 = children, elderly, pregnant women, or marginalised groups

Category: {category}
Title: {title}
Description: {description}
Location: {location}

Be conservative: reserve 5 for genuinely extreme cases. Respond with JSON only:
{{"severity": <1-5>, "urgency": <1-5>, "reach": <1-5>, "vulnerability": <1-5>,
  "rationale": "<one sentence, max 25 words, naming the dominant axis>"}}"""


def _bucket(score: float) -> str:
    if score >= HIGH_CUTOFF:
        return "High"
    if score >= MEDIUM_CUTOFF:
        return "Medium"
    return "Low"


def _combine(axis_scores: dict[str, float], category: str) -> float:
    """Weighted mean of the 1-5 axes, normalised to 0-1, then category-weighted."""
    weighted = sum(AXIS_WEIGHTS[a] * axis_scores[a] for a in AXES)
    normalized = (weighted - 1.0) / 4.0  # 1..5 -> 0..1
    adjusted = normalized * CATEGORY_SEVERITY_WEIGHT.get(category, 1.0)
    return round(max(0.0, min(1.0, adjusted)), 3)


def score_heuristic(title: str, description: str, category: str = "Other") -> PriorityResult:
    text = f"{title} {description}".lower()

    # Everything starts mid-scale; signals push each axis up from there.
    axes = {a: 2.0 for a in AXES}
    fired: dict[str, list[str]] = {a: [] for a in AXES}

    for phrase, (axis, weight) in _SIGNALS.items():
        if phrase in text:
            axes[axis] += weight
            fired[axis].append(phrase)

    # An explicit headcount ("affects 2,000 people") is stronger reach evidence
    # than any adjective.
    for raw in _NUMBER_RE.findall(text):
        try:
            n = int(raw.replace(",", ""))
        except ValueError:
            continue
        if n >= 10000:
            axes["reach"] = max(axes["reach"], 5.0)
        elif n >= 1000:
            axes["reach"] = max(axes["reach"], 4.0)
        elif n >= 100:
            axes["reach"] = max(axes["reach"], 3.0)

    axes = {a: max(1.0, min(5.0, v)) for a, v in axes.items()}
    score = _combine(axes, category)

    dominant = max(AXES, key=lambda a: AXIS_WEIGHTS[a] * axes[a])
    evidence = ", ".join(fired[dominant][:3]) or "no strong signals"
    rationale = f"Driven by {dominant} (scored {axes[dominant]:.0f}/5): {evidence}."

    return PriorityResult(
        priority=_bucket(score),
        score=score,
        scores={a: round(v, 2) for a, v in axes.items()},
        rationale=rationale,
        engine="heuristic",
    )


async def score(title: str, description: str, category: str = "Other", location: str = "") -> PriorityResult:
    data = await llm.generate_json(
        _PROMPT.format(
            category=category,
            title=title,
            description=description,
            location=location or "not specified",
        )
    )

    if data and all(a in data for a in AXES):
        try:
            axes = {a: max(1.0, min(5.0, float(data[a]))) for a in AXES}
        except (TypeError, ValueError):
            return score_heuristic(title, description, category)

        combined = _combine(axes, category)
        return PriorityResult(
            priority=_bucket(combined),
            score=combined,
            scores={a: round(v, 2) for a, v in axes.items()},
            rationale=str(data.get("rationale", "")).strip()[:300],
            engine="gemini",
        )

    return score_heuristic(title, description, category)
