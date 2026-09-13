"""Runs only when sentence-transformers is installed.

Guards the property the whole ML layer depends on: vectors are only ever
compared against vectors from the same backend.
"""
import pytest

st = pytest.importorskip("sentence_transformers")


@pytest.fixture
def local_embeddings(monkeypatch):
    from app.config import settings

    monkeypatch.setattr(settings, "USE_LOCAL_EMBEDDINGS", True)
    import app.ml.embeddings as emb

    monkeypatch.setattr(emb, "_model", None)
    monkeypatch.setattr(emb, "_model_failed", False)
    return emb


def test_minilm_loads_and_separates_domains(local_embeddings):
    emb = local_embeddings
    assert emb.embedding_dim() == 384
    assert emb.active_model_name().endswith("all-MiniLM-L6-v2")

    water = emb.embed("The drinking water in our village is contaminated and unsafe")
    water2 = emb.embed("Our village borewell water is polluted and causing illness")
    traffic = emb.embed("Traffic congestion and speeding vehicles near the school gate")

    assert emb.cosine_similarity(water, water2) > 0.6
    assert emb.cosine_similarity(water, water2) > emb.cosine_similarity(water, traffic)
