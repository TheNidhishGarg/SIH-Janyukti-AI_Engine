"""Guards the duplicate threshold against silent drift, on either backend.

The scoring formula mixes semantic similarity, lexical overlap and location.
Changing any weight - or the embedding backend - moves the score distribution.
This test fails if true paraphrases and unrelated reports stop separating
cleanly around the configured threshold.
"""
import pytest

from app.ml.duplicates import (
    LEXICAL_WEIGHT,
    SAME_LOCATION_BONUS,
    SEMANTIC_WEIGHT,
    default_threshold,
    jaccard,
)
from app.ml.embeddings import challenge_text, cosine_similarity, embed

PARAPHRASES = [
    (("Contaminated borewell water in Namkum block",
      "The borewell water has turned muddy and smells foul. Children falling sick "
      "with stomach illness. 1200 people depend on it."),
     ("Dirty bore well water making villagers ill",
      "Our village borewell gives muddy, foul smelling water. Many children have "
      "stomach illness. No other drinking source.")),
    (("Garbage not collected in our colony",
      "Waste piles up on the roadside for weeks, no segregation, foul smell and mosquitoes."),
     ("No waste pickup in residential area",
      "Trash is dumped in the open near homes, nobody collects it, it stinks and breeds mosquitoes.")),
    (("Frequent power cuts in our village",
      "Electricity goes out for hours every day, students cannot study, shops lose business."),
     ("Daily long electricity outages",
      "Power supply fails for many hours daily. Children cannot study at night and "
      "small businesses suffer.")),
    (("Unsafe road crossing outside school",
      "Speeding vehicles and heavy traffic make it dangerous for children to cross."),
     ("Dangerous traffic near school gate",
      "Cars speed past the school. Students struggle to cross the busy road safely.")),
]

UNRELATED = [
    (("Contaminated borewell water", "Muddy foul water causing illness among children."),
     ("Frequent power cuts in our village", "Electricity goes out for hours every day.")),
    (("Garbage not collected in our colony", "Waste piles up on the roadside, no segregation."),
     ("Unsafe road crossing outside school", "Speeding vehicles make it dangerous to cross.")),
    (("No computers in the school", "Students lack digital learning resources and internet."),
     ("Crops failing due to poor irrigation", "Farmers cannot water fields, harvest failed.")),
    # Same domain, genuinely different problem - must never be merged.
    (("Water contamination in village", "Drinking water is polluted and causing health issues."),
     ("Irrigation canal is broken", "Farmers cannot get water to their fields, the canal collapsed.")),
]


def _score(a, b) -> float:
    """Mirror find_duplicates scoring for a same-location pair."""
    semantic = cosine_similarity(embed(challenge_text(*a)), embed(challenge_text(*b)))
    lexical = jaccard(f"{a[0]} {a[1]}", f"{b[0]} {b[1]}")
    return max(0.0, min(1.0, SEMANTIC_WEIGHT * semantic + LEXICAL_WEIGHT * lexical
                        + SAME_LOCATION_BONUS))


@pytest.mark.parametrize("a,b", PARAPHRASES)
def test_paraphrases_clear_the_threshold(a, b):
    assert _score(a, b) >= default_threshold()


@pytest.mark.parametrize("a,b", UNRELATED)
def test_unrelated_reports_stay_below_the_threshold(a, b):
    assert _score(a, b) < default_threshold()


def test_separation_has_headroom():
    """A shrinking gap means the threshold is about to start misfiring."""
    lo = min(_score(a, b) for a, b in PARAPHRASES)
    hi = max(_score(a, b) for a, b in UNRELATED)
    assert lo - hi > 0.08, f"separation collapsed: unrelated max {hi:.3f}, paraphrase min {lo:.3f}"
