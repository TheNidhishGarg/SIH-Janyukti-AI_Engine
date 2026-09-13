"""Model behaviour tests - these run entirely offline on the heuristic engine."""
import pytest

from app.ml import categorizer, duplicates
from app.ml import priority as priority_mod


@pytest.mark.parametrize(
    "title,description,expected",
    [
        (
            "Water Contamination in Village",
            "The drinking water in our village is polluted and causing health issues.",
            "Water Management",
        ),
        (
            "Garbage dumped near homes",
            "Waste is not collected and there is no segregation, garbage piles up on roads.",
            "Waste Management",
        ),
        (
            "Frequent power cuts",
            "Our village faces long electricity outages every day, the transformer keeps failing.",
            "Energy & Infrastructure",
        ),
        (
            "No computers in our school",
            "Government school students have no digital learning resources and teachers lack training.",
            "Education",
        ),
        (
            "Dangerous crossing outside school",
            "Heavy traffic congestion and speeding vehicles make the road unsafe for pedestrians.",
            "Transportation & Safety",
        ),
        (
            "No toilets in the settlement",
            "Open defecation is common, there is no sanitation facility and sewage flows openly.",
            "Healthcare & Sanitation",
        ),
        (
            "Crop failure due to poor irrigation",
            "Farmers cannot irrigate their fields, soil quality is degrading and the harvest failed.",
            "Agriculture & Rural Development",
        ),
    ],
)
def test_heuristic_categorization(title, description, expected):
    result = categorizer.classify_heuristic(title, description)
    assert result.category == expected, f"got {result.category} ({result.confidence})"
    assert 0.0 <= result.confidence <= 1.0


def test_low_confidence_flags_review():
    """Text with no domain signal must not be silently filed as a real category."""
    result = categorizer.classify_heuristic("Something", "Please look into this matter soon.")
    assert result.category == "Other"
    assert result.needs_review is True


def test_priority_rubric_ranks_severity():
    severe = priority_mod.score_heuristic(
        "Contaminated water causing disease outbreak",
        "Children in the entire village are falling sick from poisoned drinking water. "
        "Urgent action needed, over 2000 people affected.",
        "Water Management",
    )
    minor = priority_mod.score_heuristic(
        "Street light flickering",
        "One street light near my house flickers at night.",
        "Energy & Infrastructure",
    )
    assert severe.score > minor.score
    assert severe.priority == "High"
    assert minor.priority in ("Low", "Medium")
    # The rubric must be legible, not just a number.
    assert set(severe.scores) == {"severity", "urgency", "reach", "vulnerability"}
    assert severe.rationale


def test_priority_uses_explicit_headcount():
    with_count = priority_mod.score_heuristic(
        "Water shortage", "Affects 15000 residents of the town.", "Water Management"
    )
    assert with_count.scores["reach"] == 5.0


def test_jaccard_overlap():
    assert duplicates.jaccard("water contamination village", "water contamination village") == 1.0
    assert duplicates.jaccard("water contamination", "traffic congestion school") == 0.0


@pytest.mark.asyncio
async def test_embedding_fallback_is_deterministic():
    from app.ml.embeddings import cosine_similarity, embed

    a = embed("The drinking water in our village is contaminated")
    b = embed("The drinking water in our village is contaminated")
    c = embed("Traffic congestion near the school gate")
    assert a == b
    assert cosine_similarity(a, b) > cosine_similarity(a, c)


@pytest.mark.parametrize(
    "title,description,expected",
    [
        # Regression: "school" is a location marker here, not the subject.
        # This previously classified as Education with 0.86 confidence.
        (
            "Open drain overflowing near primary school",
            "Sewage from a broken drain floods the lane outside the primary school. "
            "Children wade through it daily and many have fallen sick with skin infections.",
            "Healthcare & Sanitation",
        ),
        (
            "Garbage piling up outside the village school",
            "Waste is dumped in the open ground and never collected, attracting stray animals.",
            "Waste Management",
        ),
        (
            "Students cannot cross the road safely",
            "Speeding vehicles and traffic congestion make the crossing dangerous at school hours.",
            "Transportation & Safety",
        ),
    ],
)
def test_location_words_do_not_hijack_the_category(title, description, expected):
    result = categorizer.classify_heuristic(title, description)
    assert result.category == expected, f"got {result.category} ({result.confidence})"


def test_sanitation_hazard_to_children_scores_high():
    result = priority_mod.score_heuristic(
        "Open drain overflowing near primary school",
        "Sewage floods the lane. Children wade through it daily and have fallen sick "
        "with skin infections.",
        "Healthcare & Sanitation",
    )
    assert result.priority == "High"
    assert result.scores["severity"] >= 4.0
    assert result.scores["vulnerability"] >= 3.5
