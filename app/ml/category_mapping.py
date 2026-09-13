"""Mapping from OpenAlex research topics onto the JanYukti civic taxonomy.

Built by inspecting the topic vocabulary that actually occurs across the ~200
publishing institutions within 500 km of Ranchi, not written from imagination.
Keys are lowercase substrings matched against an OpenAlex topic display name;
values are (category, weight).

Topic patterns are matched first and carry full weight. Subfield patterns are a
coarser fallback: "Electrical and Electronic Engineering" covers everything from
rural microgrids to antenna design, so it contributes at a heavily reduced
weight and never decides a category on its own.
"""

# --- Topic-name patterns (specific, high confidence) ---
TOPIC_PATTERNS: list[tuple[str, str, float]] = [
    # Water
    ("water quality", "Water Management", 1.0),
    ("water access", "Water Management", 1.0),
    ("water management", "Water Management", 1.0),
    ("water treatment", "Water Management", 1.0),
    ("drinking water", "Water Management", 1.0),
    ("groundwater", "Water Management", 1.0),
    ("watershed", "Water Management", 1.0),
    ("hydrology", "Water Management", 1.0),
    ("irrigation", "Water Management", 0.8),
    ("flood risk", "Water Management", 0.9),
    ("drought", "Water Management", 0.8),
    ("desalination", "Water Management", 0.8),
    ("wastewater", "Water Management", 1.0),
    ("membrane", "Water Management", 0.3),
    # Waste
    ("waste management", "Waste Management", 1.0),
    ("solid waste", "Waste Management", 1.0),
    ("waste disposal", "Waste Management", 1.0),
    ("recycling", "Waste Management", 1.0),
    ("composting", "Waste Management", 0.9),
    ("plastic waste", "Waste Management", 1.0),
    ("e-waste", "Waste Management", 1.0),
    ("landfill", "Waste Management", 1.0),
    ("biosorption", "Waste Management", 0.4),
    # Energy & Infrastructure
    ("microgrid", "Energy & Infrastructure", 1.0),
    ("smart grid", "Energy & Infrastructure", 1.0),
    ("power system", "Energy & Infrastructure", 0.9),
    ("power flow", "Energy & Infrastructure", 0.8),
    ("power quality", "Energy & Infrastructure", 0.8),
    ("frequency control", "Energy & Infrastructure", 0.7),
    ("islanding detection", "Energy & Infrastructure", 0.7),
    ("energy load", "Energy & Infrastructure", 0.8),
    ("power forecasting", "Energy & Infrastructure", 0.8),
    ("solar energy", "Energy & Infrastructure", 1.0),
    ("solar cell", "Energy & Infrastructure", 0.8),
    ("solar power", "Energy & Infrastructure", 1.0),
    ("photovoltaic", "Energy & Infrastructure", 0.9),
    ("renewable energy", "Energy & Infrastructure", 1.0),
    ("energy storage", "Energy & Infrastructure", 0.7),
    ("electrification", "Energy & Infrastructure", 1.0),
    ("geotechnical", "Energy & Infrastructure", 0.7),
    ("structural", "Energy & Infrastructure", 0.5),
    ("concrete", "Energy & Infrastructure", 0.5),
    ("construction", "Energy & Infrastructure", 0.6),
    # Transportation & Safety
    ("transportation", "Transportation & Safety", 1.0),
    ("traffic", "Transportation & Safety", 1.0),
    ("road", "Transportation & Safety", 0.9),
    ("pavement", "Transportation & Safety", 0.9),
    ("vehicle", "Transportation & Safety", 0.6),
    ("driver", "Transportation & Safety", 0.6),
    ("accident", "Transportation & Safety", 0.8),
    ("safety and risk", "Transportation & Safety", 0.6),
    # Education
    ("education", "Education", 1.0),
    ("learning analytics", "Education", 0.9),
    ("e-learning", "Education", 1.0),
    ("curriculum", "Education", 1.0),
    ("pedagog", "Education", 1.0),
    ("literacy", "Education", 0.9),
    ("student", "Education", 0.6),
    ("teaching", "Education", 0.9),
]

TOPIC_PATTERNS += [
    # Healthcare & Sanitation
    ("sanitation", "Healthcare & Sanitation", 1.0),
    ("public health", "Healthcare & Sanitation", 1.0),
    ("epidemiolog", "Healthcare & Sanitation", 0.9),
    ("maternal", "Healthcare & Sanitation", 0.9),
    ("child health", "Healthcare & Sanitation", 0.9),
    ("nutrition", "Healthcare & Sanitation", 0.8),
    ("tuberculosis", "Healthcare & Sanitation", 0.8),
    ("mosquito-borne", "Healthcare & Sanitation", 1.0),
    ("malaria", "Healthcare & Sanitation", 1.0),
    ("infectious disease", "Healthcare & Sanitation", 0.9),
    ("vaccin", "Healthcare & Sanitation", 0.8),
    ("healthcare", "Healthcare & Sanitation", 0.8),
    ("global health", "Healthcare & Sanitation", 0.9),
    ("hygiene", "Healthcare & Sanitation", 1.0),
    ("diarrhea", "Healthcare & Sanitation", 1.0),
    ("mental health", "Healthcare & Sanitation", 0.6),
    # Agriculture & Rural Development
    ("agricultur", "Agriculture & Rural Development", 1.0),
    ("agronom", "Agriculture & Rural Development", 1.0),
    ("crop", "Agriculture & Rural Development", 1.0),
    ("soil fertility", "Agriculture & Rural Development", 1.0),
    ("soil carbon", "Agriculture & Rural Development", 0.8),
    ("fertilization", "Agriculture & Rural Development", 0.9),
    ("pest management", "Agriculture & Rural Development", 0.9),
    ("plant pathogen", "Agriculture & Rural Development", 0.8),
    ("intercropping", "Agriculture & Rural Development", 1.0),
    ("horticultur", "Agriculture & Rural Development", 0.9),
    ("aquaculture", "Agriculture & Rural Development", 0.8),
    ("animal nutrition", "Agriculture & Rural Development", 0.7),
    ("livestock", "Agriculture & Rural Development", 0.9),
    ("food secur", "Agriculture & Rural Development", 0.9),
    ("post-harvest", "Agriculture & Rural Development", 1.0),
    ("smart agriculture", "Agriculture & Rural Development", 1.0),
]

TOPIC_PATTERNS += [
    # Environment & Climate
    ("pollution", "Environment & Climate", 1.0),
    ("air quality", "Environment & Climate", 1.0),
    ("heavy metals in environment", "Environment & Climate", 1.0),
    ("climate", "Environment & Climate", 1.0),
    ("ecolog", "Environment & Climate", 0.8),
    ("biodiversity", "Environment & Climate", 0.9),
    ("environmental toxicolog", "Environment & Climate", 0.9),
    ("ecotoxicolog", "Environment & Climate", 0.9),
    ("forest", "Environment & Climate", 0.8),
    ("emission", "Environment & Climate", 0.7),
    ("remote sensing", "Environment & Climate", 0.5),
    ("sustainab", "Environment & Climate", 0.5),
    ("mining", "Environment & Climate", 0.6),
    ("pollutant removal", "Environment & Climate", 0.8),
    # Employment & Livelihood
    ("livelihood", "Employment & Livelihood", 1.0),
    ("entrepreneur", "Employment & Livelihood", 0.9),
    ("microfinance", "Employment & Livelihood", 1.0),
    ("rural development", "Employment & Livelihood", 0.9),
    ("supply chain", "Employment & Livelihood", 0.5),
    ("labor", "Employment & Livelihood", 0.7),
    ("employment", "Employment & Livelihood", 1.0),
    ("skill development", "Employment & Livelihood", 1.0),
    ("poverty", "Employment & Livelihood", 0.9),
    # Digital Governance
    ("governance", "Digital Governance", 0.9),
    ("e-government", "Digital Governance", 1.0),
    ("public policy", "Digital Governance", 0.8),
    ("information system", "Digital Governance", 0.5),
    ("blockchain", "Digital Governance", 0.4),
    ("digital transformation", "Digital Governance", 0.8),
    ("data privacy", "Digital Governance", 0.4),
]


# Topics that keep matching on a shared word but have no civic application.
# Checked before anything else - a hit here drops the topic entirely.
EXCLUDE_PATTERNS: tuple[str, ...] = (
    "space plasma", "particle collision", "high-energy particle",
    "semiconductor", "microwave engineering", "waveguide", "antenna",
    "photonic", "fiber optic", "vlsi", "steganography", "machining",
    "perovskite", "quantum", "nuclear", "astronom", "cosmolog",
    "sarcoma", "tumor", "cancer", "transplantation", "surgical",
    "cryptograph", "watermarking", "image encryption",
)

# --- Subfield fallback (coarse, deliberately weak) ---
SUBFIELD_PATTERNS: list[tuple[str, str, float]] = [
    ("water science and technology", "Water Management", 0.6),
    ("waste management and disposal", "Waste Management", 0.6),
    ("environmental engineering", "Water Management", 0.3),
    ("environmental engineering", "Environment & Climate", 0.4),
    ("pollution", "Environment & Climate", 0.5),
    ("environmental chemistry", "Environment & Climate", 0.4),
    ("ecology", "Environment & Climate", 0.35),
    ("health, toxicology and mutagenesis", "Environment & Climate", 0.3),
    ("renewable energy", "Energy & Infrastructure", 0.3),
    ("energy engineering", "Energy & Infrastructure", 0.5),
    ("civil and structural engineering", "Energy & Infrastructure", 0.35),
    ("civil and structural engineering", "Transportation & Safety", 0.3),
    ("transportation", "Transportation & Safety", 0.6),
    ("safety, risk, reliability and quality", "Transportation & Safety", 0.3),
    ("safety research", "Transportation & Safety", 0.4),
    ("urban studies", "Transportation & Safety", 0.3),
    ("public health, environmental and occupational health", "Healthcare & Sanitation", 0.5),
    ("epidemiology", "Healthcare & Sanitation", 0.45),
    ("infectious diseases", "Healthcare & Sanitation", 0.4),
    ("nutrition and dietetics", "Healthcare & Sanitation", 0.35),
    ("pediatrics", "Healthcare & Sanitation", 0.3),
    ("obstetrics and gynecology", "Healthcare & Sanitation", 0.25),
    ("health informatics", "Healthcare & Sanitation", 0.3),
    ("soil science", "Agriculture & Rural Development", 0.5),
    ("food science", "Agriculture & Rural Development", 0.4),
    ("general agricultural and biological sciences", "Agriculture & Rural Development", 0.45),
    ("education", "Education", 0.6),
    ("developmental and educational psychology", "Education", 0.4),
    ("library and information sciences", "Education", 0.25),
    ("information systems", "Digital Governance", 0.2),
    ("computer networks and communications", "Digital Governance", 0.1),
    ("computer science applications", "Digital Governance", 0.15),
]

# Department label for each derived research-strength grouping. These are NOT
# verified department names - they describe the cluster of research an
# institution actually publishes in for that civic category.
DEPARTMENT_LABELS: dict[str, str] = {
    "Water Management": "Water Resources & Environmental Engineering",
    "Waste Management": "Waste Management & Environmental Science",
    "Energy & Infrastructure": "Energy Systems & Infrastructure Engineering",
    "Education": "Education & Learning Technologies",
    "Transportation & Safety": "Transportation & Civil Infrastructure",
    "Healthcare & Sanitation": "Public Health & Community Medicine",
    "Agriculture & Rural Development": "Agricultural Sciences & Rural Technology",
    "Environment & Climate": "Environmental Science & Climate Studies",
    "Employment & Livelihood": "Rural Management & Livelihoods",
    "Digital Governance": "Computing & Digital Governance",
}


def score_topics(topics: list[dict]) -> dict[str, dict]:
    """Aggregate an OpenAlex topic list into per-category research strength.

    Returns {category: {"weight": float, "topics": [(name, count), ...]}}.
    Weight is publication-count weighted, so an institution with 400 papers on
    microgrids outranks one with 12.
    """
    out: dict[str, dict] = {}

    for t in topics:
        name = (t.get("display_name") or "").lower()
        subfield = ((t.get("subfield") or {}).get("display_name") or "").lower()
        count = int(t.get("count") or 0)
        if count <= 0:
            continue
        if any(x in name for x in EXCLUDE_PATTERNS):
            continue

        matched: dict[str, float] = {}
        for pattern, category, weight in TOPIC_PATTERNS:
            if pattern in name:
                matched[category] = max(matched.get(category, 0.0), weight)

        # Subfield is only consulted when the specific topic name said nothing.
        if not matched:
            for pattern, category, weight in SUBFIELD_PATTERNS:
                if pattern in subfield:
                    matched[category] = max(matched.get(category, 0.0), weight)

        for category, weight in matched.items():
            bucket = out.setdefault(category, {"weight": 0.0, "topics": []})
            bucket["weight"] += count * weight
            bucket["topics"].append((t.get("display_name"), count))

    for bucket in out.values():
        bucket["topics"].sort(key=lambda x: -x[1])
    return out
