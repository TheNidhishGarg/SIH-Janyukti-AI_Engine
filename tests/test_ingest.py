"""Tests for the OpenAlex ingestion mapping and scope filter."""
import pytest

from app.ml.category_mapping import EXCLUDE_PATTERNS, score_topics
from scripts.ingest_openalex import is_jharkhand


def _topic(name, subfield, count):
    return {"display_name": name, "subfield": {"display_name": subfield}, "count": count}


def test_jharkhand_scope_accepts_region_and_city():
    # Region present.
    assert is_jharkhand({"region": "Jharkhand", "latitude": 23.4, "longitude": 85.4})
    # Region missing - this is IIT (ISM) Dhanbad and NIT Jamshedpur, which the
    # plain state filter silently drops.
    assert is_jharkhand({"region": None, "city": "Dhanbad", "latitude": 23.79, "longitude": 86.43})
    assert is_jharkhand({"region": None, "city": "Jamshedpur", "latitude": 22.80, "longitude": 86.20})


def test_jharkhand_scope_rejects_other_states():
    assert not is_jharkhand({"region": "West Bengal", "latitude": 22.57, "longitude": 88.36})
    assert not is_jharkhand({"region": None, "city": "Patna", "latitude": 25.59, "longitude": 85.13})
    # A same-named city outside the state bounding box must not sneak through.
    assert not is_jharkhand({"region": None, "city": "Ramgarh", "latitude": 27.5, "longitude": 75.2})
    assert not is_jharkhand({"region": None, "city": "Ranchi"})  # no coordinates


def test_excluded_topics_never_score():
    """Astrophysics and semiconductors are not civic energy expertise."""
    noise = [
        _topic("Solar and Space Plasma Dynamics", "Astronomy and Astrophysics", 500),
        _topic("Semiconductor materials and devices", "Electrical and Electronic Engineering", 700),
        _topic("Microwave Engineering and Waveguides", "Electrical and Electronic Engineering", 600),
    ]
    assert score_topics(noise) == {}
    assert "space plasma" in EXCLUDE_PATTERNS


def test_real_civic_topics_map_correctly():
    scored = score_topics([
        _topic("Microgrid Control and Optimization", "Electrical and Electronic Engineering", 500),
        _topic("Water Quality and Pollution Assessment", "Water Science and Technology", 300),
        _topic("Crop Yield and Soil Fertility", "Soil Science", 400),
    ])
    assert "Energy & Infrastructure" in scored
    assert "Water Management" in scored
    assert "Agriculture & Rural Development" in scored


def test_topic_name_beats_subfield_fallback():
    """A specific topic must not also collect its coarse subfield weight."""
    scored = score_topics([
        _topic("Irrigation Practices and Water Management", "Soil Science", 100),
    ])
    # Matched on the topic name as Water, so the Soil Science subfield fallback
    # to Agriculture must not fire for the same topic.
    assert "Water Management" in scored
    assert "Agriculture & Rural Development" not in scored


def test_publication_count_weights_strength():
    heavy = score_topics([_topic("Microgrid Control and Optimization", "x", 1000)])
    light = score_topics([_topic("Microgrid Control and Optimization", "x", 10)])
    assert heavy["Energy & Infrastructure"]["weight"] > light["Energy & Infrastructure"]["weight"]
