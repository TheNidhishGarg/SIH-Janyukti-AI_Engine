"""Resolve institution names that refer to the same place.

The same university reaches the backend under several spellings: the curated
seed says "BIT Mesra", OpenAlex says "Birla Institute of Technology, Mesra",
and a university admin registering in the app might type "BIT, Mesra Ranchi".
Matching a registered Firestore organisation to its expertise profiles only
works if all three collapse to one key.

Known Jharkhand institutions resolve through an explicit alias table, because
acronyms like "RIMS" or "XLRI" cannot be recovered from the full name by any
string rule. Everything else falls back to token overlap.
"""
from __future__ import annotations

import re

# canonical key -> accepted variants (already normalised: lowercase, no punctuation)
_ALIASES: dict[str, tuple[str, ...]] = {
    "birla institute of technology mesra": (
        "bit mesra", "bit ranchi", "bit mesra ranchi", "birla institute of technology",
    ),
    "indian institute of technology ism dhanbad": (
        "iit ism dhanbad", "iit ism", "iit dhanbad", "ism dhanbad",
        "indian institute of technology dhanbad", "indian school of mines",
        "indian school of mines dhanbad",
        "indian institute of technology indian school of mines dhanbad",
    ),
    "national institute of technology jamshedpur": ("nit jamshedpur", "nit jsr"),
    "ranchi university": ("ru ranchi",),
    "central university of jharkhand": ("cuj", "cu jharkhand"),
    "birsa agricultural university": ("bau ranchi", "birsa agriculture university"),
    "rajendra institute of medical sciences": ("rims", "rims ranchi"),
    "xavier institute of social service": ("xiss", "xiss ranchi"),
    "xavier school of management": (
        "xlri", "xlri jamshedpur", "xavier labour relations institute",
    ),
    "indian institute of management ranchi": ("iim ranchi",),
    "birsa institute of technology sindri": ("bit sindri",),
    "jharkhand university of technology": ("jut", "jut ranchi"),
    "vinoba bhave university": ("vbu", "vbu hazaribagh"),
    "sido kanhu murmu university": ("skmu", "skmu dumka"),
    "jharkhand rai university": ("jru",),
    "national university of study and research in law": ("nusrl", "nusrl ranchi"),
    "binod bihari mahto koyalanchal university": ("bbmku",),
    "nilamber pitamber university": ("npu", "npu medininagar"),
    "indian institute of information technology ranchi": ("iiit ranchi",),
    "national institute of advanced manufacturing technology": (
        "niamt", "nifft", "nifft ranchi",
        "national institute of foundry and forge technology",
    ),
}

_VARIANT_TO_KEY: dict[str, str] = {}
for _key, _variants in _ALIASES.items():
    _VARIANT_TO_KEY[_key] = _key
    for _variant in _variants:
        _VARIANT_TO_KEY[_variant] = _key

_STOPWORDS = {"of", "the", "and", "for", "in", "at"}
_PUNCT = re.compile(r"[^a-z0-9 ]+")
_SPACES = re.compile(r"\s+")


def normalize(name: str | None) -> str:
    """'IIT (ISM) Dhanbad' -> 'iit ism dhanbad'."""
    if not name:
        return ""
    text = name.lower().replace("&", " and ")
    text = _PUNCT.sub(" ", text)
    return _SPACES.sub(" ", text).strip()


def institution_key(name: str | None) -> str:
    """Canonical key for an institution name; unknown names key to themselves."""
    normalized = normalize(name)
    if not normalized:
        return ""
    if normalized in _VARIANT_TO_KEY:
        return _VARIANT_TO_KEY[normalized]
    # Registrations often append the city: "BIT Mesra Ranchi", "RIMS, Ranchi".
    for variant, key in _VARIANT_TO_KEY.items():
        if len(variant) >= 4 and (
            normalized.startswith(variant + " ") or normalized.endswith(" " + variant)
        ):
            return key
    return normalized


def _tokens(key: str) -> set[str]:
    return {t for t in key.split() if t not in _STOPWORDS}


def similarity(a: str | None, b: str | None) -> float:
    """0-1 confidence that two names denote the same institution."""
    ka, kb = institution_key(a), institution_key(b)
    if not ka or not kb:
        return 0.0
    if ka == kb:
        return 1.0
    ta, tb = _tokens(ka), _tokens(kb)
    if not ta or not tb:
        return 0.0
    overlap = len(ta & tb)
    jaccard = overlap / len(ta | tb)
    # "Ranchi University" inside "Ranchi University Department of Geography".
    smaller = min(len(ta), len(tb))
    containment = overlap / smaller if smaller >= 2 else 0.0
    return round(max(jaccard, 0.9 * containment), 3)


SAME_INSTITUTION_THRESHOLD = 0.75


def same_institution(a: str | None, b: str | None) -> bool:
    return similarity(a, b) >= SAME_INSTITUTION_THRESHOLD
