"""Text embedding with a graceful fallback chain.

1. sentence-transformers (all-MiniLM-L6-v2, 384-d) when installed and enabled.
2. A deterministic hashed character-n-gram vectorizer otherwise.

The fallback exists so the whole AI pipeline - duplicate detection and smart
matching included - still runs on a laptop with no model download and no API
key. Vectors from the two backends are NOT comparable, so every stored vector
records which model produced it and stale ones are re-encoded on read.
"""
from __future__ import annotations

import hashlib
import logging
import math
import re
import threading

import numpy as np

from app.config import settings

log = logging.getLogger(__name__)

FALLBACK_MODEL_NAME = "hashing-ngram-256"
FALLBACK_DIM = 256

_model = None
_model_lock = threading.Lock()
_model_failed = False


def _load_model():
    """Lazily load sentence-transformers; never raise, just fall back."""
    global _model, _model_failed
    if _model is not None or _model_failed or not settings.USE_LOCAL_EMBEDDINGS:
        return _model
    with _model_lock:
        if _model is not None or _model_failed:
            return _model
        try:
            from sentence_transformers import SentenceTransformer

            log.info("Loading embedding model %s", settings.EMBEDDING_MODEL)
            _model = SentenceTransformer(settings.EMBEDDING_MODEL)
        except Exception as exc:  # noqa: BLE001 - any failure means fallback
            log.warning("sentence-transformers unavailable (%s); using %s", exc, FALLBACK_MODEL_NAME)
            _model_failed = True
    return _model


def active_model_name() -> str:
    model = _load_model()
    return settings.EMBEDDING_MODEL if model is not None else FALLBACK_MODEL_NAME


def embedding_dim() -> int:
    model = _load_model()
    if model is not None:
        # Renamed in newer sentence-transformers; support both.
        getter = getattr(model, "get_embedding_dimension", None) or getattr(
            model, "get_sentence_embedding_dimension"
        )
        return int(getter())
    return FALLBACK_DIM


_TOKEN_RE = re.compile(r"[a-z0-9]+")


def _hash_embed(text: str) -> np.ndarray:
    """Deterministic bag-of-(word + char-trigram) vector, L2-normalised.

    Character trigrams give it partial robustness to typos and to the
    Hindi-transliterated spellings common in citizen submissions.
    """
    vec = np.zeros(FALLBACK_DIM, dtype=np.float32)
    tokens = _TOKEN_RE.findall(text.lower())
    if not tokens:
        return vec

    features: list[tuple[str, float]] = [(t, 1.0) for t in tokens]
    padded = " ".join(tokens)
    features += [(padded[i : i + 3], 0.4) for i in range(len(padded) - 2)]

    for feat, weight in features:
        digest = hashlib.md5(feat.encode("utf-8")).digest()
        idx = int.from_bytes(digest[:4], "big") % FALLBACK_DIM
        sign = 1.0 if digest[4] % 2 == 0 else -1.0
        vec[idx] += sign * weight

    # Sublinear scaling keeps long descriptions from dominating short ones.
    vec = np.sign(vec) * np.log1p(np.abs(vec))
    return _l2_normalize(vec)


def _l2_normalize(vec: np.ndarray) -> np.ndarray:
    norm = float(np.linalg.norm(vec))
    return vec / norm if norm > 0 else vec


def embed(text: str) -> list[float]:
    return embed_many([text])[0]


def embed_many(texts: list[str]) -> list[list[float]]:
    if not texts:
        return []
    model = _load_model()
    if model is not None:
        try:
            arr = model.encode(texts, normalize_embeddings=True, show_progress_bar=False)
            return [np.asarray(v, dtype=np.float32).tolist() for v in arr]
        except Exception as exc:  # noqa: BLE001
            log.warning("Encoding failed (%s); falling back to %s", exc, FALLBACK_MODEL_NAME)
    return [_hash_embed(t).tolist() for t in texts]


def cosine_similarity(a: list[float] | None, b: list[float] | None) -> float:
    """Cosine similarity clamped to [0, 1]; 0.0 when either side is missing."""
    if not a or not b or len(a) != len(b):
        return 0.0
    va, vb = np.asarray(a, dtype=np.float32), np.asarray(b, dtype=np.float32)
    denom = float(np.linalg.norm(va) * np.linalg.norm(vb))
    if denom == 0.0:
        return 0.0
    sim = float(np.dot(va, vb) / denom)
    if math.isnan(sim):
        return 0.0
    return max(0.0, min(1.0, sim))


def cosine_similarity_matrix(query: list[float], corpus: list[list[float]]) -> np.ndarray:
    """Vectorised similarity of one query against many candidates."""
    if not corpus or not query:
        return np.zeros(len(corpus), dtype=np.float32)
    q = np.asarray(query, dtype=np.float32)
    m = np.asarray(corpus, dtype=np.float32)
    q_norm = np.linalg.norm(q)
    m_norms = np.linalg.norm(m, axis=1)
    denom = m_norms * q_norm
    denom[denom == 0] = 1e-9
    return np.clip((m @ q) / denom, 0.0, 1.0)


def challenge_text(title: str, description: str, category: str = "", location: str = "") -> str:
    """Single canonical string per challenge, so every vector is built the same way."""
    parts = [title.strip(), description.strip()]
    if category:
        parts.append(f"Category: {category}")
    if location:
        parts.append(f"Location: {location}")
    return ". ".join(p for p in parts if p)


def university_text(name: str, department: str, expertise_summary: str, tags: list, categories: list) -> str:
    parts = [
        f"{name} {department}".strip(),
        expertise_summary.strip(),
        "Expertise: " + ", ".join(tags) if tags else "",
        "Focus areas: " + ", ".join(categories) if categories else "",
    ]
    return ". ".join(p for p in parts if p)
