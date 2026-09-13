"""Category taxonomy plus the keyword lexicon used by the offline fallback.

The first five categories are exactly the ones the Flutter app already shows in
its dropdown and mock data, so existing screens keep working unchanged.
"""

CATEGORIES: list[str] = [
    "Water Management",
    "Waste Management",
    "Energy & Infrastructure",
    "Education",
    "Transportation & Safety",
    "Healthcare & Sanitation",
    "Agriculture & Rural Development",
    "Environment & Climate",
    "Employment & Livelihood",
    "Digital Governance",
    "Other",
]

# Weighted keyword lexicon. Used when no LLM key is configured, and as a sanity
# check on LLM output. Weights let strong signals ("contaminat") outrank weak
# generic ones ("supply").
CATEGORY_KEYWORDS: dict[str, dict[str, float]] = {
    "Water Management": {
        "water": 2.0, "drinking water": 3.0, "contaminat": 3.0, "borewell": 2.5,
        "groundwater": 2.5, "tap": 1.5, "pipeline": 1.5, "well": 1.5, "tank": 1.0,
        "rainwater": 2.0, "flood": 1.5, "drought": 2.0, "purif": 2.5, "tubewell": 2.5,
        "pani": 2.0, "jal": 2.0, "supply": 0.5, "leak": 1.5,
    },
    "Waste Management": {
        "waste": 3.0, "garbage": 3.0, "trash": 2.5, "dump": 2.5, "litter": 2.0,
        "segregat": 2.5, "recycl": 2.5, "landfill": 2.5, "plastic": 2.0,
        "kachra": 2.5, "compost": 2.0, "collection": 1.0, "dustbin": 2.5,
    },
    "Energy & Infrastructure": {
        "power": 2.5, "electricity": 3.0, "outage": 3.0, "power cut": 3.0,
        "solar": 2.5, "grid": 2.0, "transformer": 2.5, "street light": 2.5,
        "bijli": 2.5, "generator": 1.5, "voltage": 2.0, "bridge": 2.0,
        "building": 1.0, "drainage": 1.5, "load shedding": 3.0,
    },
    "Education": {
        "education": 3.0, "digital learning": 3.0, "teacher": 2.5, "classroom": 2.5,
        "literacy": 2.5, "dropout": 2.5, "shiksha": 2.5, "curriculum": 2.5,
        "textbook": 2.5, "syllabus": 2.5, "teaching": 2.5, "computer lab": 2.5,
        "enrolment": 2.5, "library": 2.0, "tuition": 2.0, "exam": 1.5,
        "learning": 2.0, "college": 1.5, "school": 1.0, "student": 0.8,
    },
    "Transportation & Safety": {
        "road": 2.5, "traffic": 3.0, "congestion": 2.5, "accident": 2.5,
        "pedestrian": 2.5, "bus": 2.0, "transport": 2.5, "pothole": 3.0,
        "crossing": 2.0, "speeding": 2.5, "vehicle": 1.5, "signal": 1.5,
        "footpath": 2.0, "sadak": 2.5,
    },
    "Healthcare & Sanitation": {
        "health": 2.5, "hospital": 3.0, "clinic": 2.5, "doctor": 2.5,
        "disease": 2.5, "toilet": 3.0, "sanitation": 3.0, "sewage": 3.0,
        "open defecation": 3.0, "medicine": 2.0, "malaria": 2.5, "dengue": 2.5,
        "nutrition": 2.0, "maternal": 2.5, "swasthya": 2.5, "hygiene": 2.5,
        "drain": 2.5, "drainage": 2.5, "infection": 2.5, "fallen sick": 2.5,
        "falling sick": 2.5, "stagnant": 2.5, "mosquito": 2.5, "filth": 2.5,
        "foul": 2.0, "odor": 2.0, "odour": 2.0, "illness": 2.5, "epidemic": 3.0,
    },
    "Agriculture & Rural Development": {
        "farmer": 3.0, "crop": 3.0, "irrigation": 2.5, "soil": 2.5,
        "harvest": 2.5, "fertilizer": 2.5, "pesticide": 2.5, "livestock": 2.5,
        "mandi": 2.0, "kisan": 3.0, "khet": 2.5, "yield": 2.0, "seed": 1.5,
    },
    "Environment & Climate": {
        "pollution": 2.5, "air quality": 3.0, "deforestation": 3.0, "forest": 2.0,
        "tree": 1.5, "emission": 2.5, "climate": 2.5, "wildlife": 2.5,
        "biodiversity": 2.5, "noise": 2.0, "smog": 2.5, "mining": 2.0,
    },
    "Employment & Livelihood": {
        "job": 2.5, "unemploy": 3.0, "livelihood": 3.0, "skill": 2.0,
        "training": 1.5, "wage": 2.5, "migrant": 2.5, "artisan": 2.5,
        "self help group": 2.5, "shg": 2.0, "msme": 2.0, "rozgar": 3.0,
    },
    "Digital Governance": {
        "aadhaar": 2.5, "certificate": 2.0, "ration": 2.5, "pension": 2.5,
        "subsidy": 2.5, "portal": 2.0, "corruption": 2.0, "panchayat": 2.0,
        "grievance": 2.0, "documentation": 1.5, "scheme": 1.5,
    },
}

# Terms that describe WHERE a problem is rather than WHAT it is. They still
# contribute to scoring, but they never earn the title-position bonus. Without
# this, "open drain outside the primary school" classifies as Education.
AMBIENT_TERMS: set[str] = {
    "school", "student", "college", "village", "city", "town", "road",
    "residential area", "community", "public", "district", "region",
    "households", "area", "areas", "near", "building",
}


# Severity multiplier applied by the priority rubric: some domains carry a
# higher baseline risk to life even when the wording is calm.
CATEGORY_SEVERITY_WEIGHT: dict[str, float] = {
    "Water Management": 1.15,
    "Healthcare & Sanitation": 1.20,
    "Transportation & Safety": 1.10,
    "Waste Management": 1.05,
    "Energy & Infrastructure": 1.05,
    "Environment & Climate": 1.05,
    "Education": 1.00,
    "Agriculture & Rural Development": 1.00,
    "Employment & Livelihood": 1.00,
    "Digital Governance": 0.95,
    "Other": 1.00,
}


def normalize_category(value: str | None) -> str:
    """Map free-text (or LLM output) onto a taxonomy member."""
    if not value:
        return "Other"
    cleaned = value.strip().lower()
    for cat in CATEGORIES:
        if cat.lower() == cleaned:
            return cat
    for cat in CATEGORIES:
        if cleaned in cat.lower() or cat.lower().split(" &")[0] in cleaned:
            return cat
    return "Other"
