"""Seed the database with demo accounts, university profiles, and sample challenges.

Run with:  python -m app.seed

University profiles are real Jharkhand institutions with plausible department
expertise, matching the names already hardcoded in the Flutter mock data (BIT
Mesra, Ranchi University, IIT ISM) so the existing screens line up with real
records. The expertise text is written the way a department would describe
itself, because that text is exactly what the matcher embeds.
"""
from __future__ import annotations

import asyncio
import logging

from sqlalchemy import select

from app.core.ids import new_uuid
from app.core.security import hash_password
from app.db import SessionLocal, init_db
from app.models import IndustryProfile, University, User, UserRole

logging.basicConfig(level=logging.INFO, format="%(message)s")
log = logging.getLogger("seed")

DEMO_PASSWORD = "janyukti123"

UNIVERSITIES = [
    {
        "name": "BIT Mesra",
        "department": "Department of Civil & Environmental Engineering",
        "city": "Ranchi",
        "state": "Jharkhand",
        "contact_email": "civil@bitmesra.ac.in",
        "expertise_summary": (
            "Water quality testing and treatment, groundwater contamination studies, "
            "low-cost filtration and purification systems, rainwater harvesting design, "
            "wastewater treatment, and rural drinking water supply schemes. Runs a "
            "water testing laboratory and has delivered village-scale treatment pilots."
        ),
        "expertise_tags": [
            "water treatment", "water quality", "groundwater", "filtration",
            "rainwater harvesting", "wastewater", "environmental engineering",
        ],
        "categories": ["Water Management", "Environment & Climate", "Healthcare & Sanitation"],
        "capacity": 5,
    },
    {
        "name": "BIT Mesra",
        "department": "Department of Computer Science & Engineering",
        "city": "Ranchi",
        "state": "Jharkhand",
        "contact_email": "cse@bitmesra.ac.in",
        "expertise_summary": (
            "Digital learning platforms, offline-first mobile applications for "
            "low-connectivity regions, e-governance portals, data analytics "
            "dashboards, machine learning, and IoT sensor networks. Experience "
            "building multilingual education tools for government schools."
        ),
        "expertise_tags": [
            "digital learning", "mobile apps", "e-governance", "machine learning",
            "iot", "data analytics", "offline first", "edtech",
        ],
        "categories": ["Education", "Digital Governance"],
        "capacity": 6,
    },
    {
        "name": "Ranchi University",
        "department": "University Department of Environmental Science",
        "city": "Ranchi",
        "state": "Jharkhand",
        "contact_email": "envsci@ranchiuniversity.ac.in",
        "expertise_summary": (
            "Solid waste management, municipal waste segregation and composting, "
            "plastic waste recycling, landfill impact assessment, air and noise "
            "pollution monitoring, and community environmental awareness programmes."
        ),
        "expertise_tags": [
            "solid waste", "waste segregation", "composting", "recycling",
            "pollution monitoring", "air quality", "community awareness",
        ],
        "categories": ["Waste Management", "Environment & Climate"],
        "capacity": 4,
    },
    {
        "name": "Ranchi University",
        "department": "Department of Geography & Urban Planning",
        "city": "Ranchi",
        "state": "Jharkhand",
        "contact_email": "geography@ranchiuniversity.ac.in",
        "expertise_summary": (
            "Urban traffic studies, road safety audits near schools and markets, "
            "GIS mapping, pedestrian infrastructure planning, public transport "
            "route optimisation, and land use analysis for growing towns."
        ),
        "expertise_tags": [
            "traffic management", "road safety", "gis", "urban planning",
            "pedestrian infrastructure", "public transport",
        ],
        "categories": ["Transportation & Safety", "Energy & Infrastructure"],
        "capacity": 3,
    },
    {
        "name": "IIT (ISM) Dhanbad",
        "department": "Department of Electrical Engineering",
        "city": "Dhanbad",
        "state": "Jharkhand",
        "contact_email": "ee@iitism.ac.in",
        "expertise_summary": (
            "Rural electrification, solar microgrids and off-grid photovoltaic "
            "systems, distribution network reliability, load forecasting, battery "
            "storage, and power quality analysis for areas with frequent outages."
        ),
        "expertise_tags": [
            "solar", "microgrid", "rural electrification", "power distribution",
            "renewable energy", "battery storage", "load forecasting",
        ],
        "categories": ["Energy & Infrastructure", "Environment & Climate"],
        "capacity": 5,
    },
]

UNIVERSITIES += [
    {
        "name": "IIT (ISM) Dhanbad",
        "department": "Department of Environmental Science & Engineering",
        "city": "Dhanbad",
        "state": "Jharkhand",
        "contact_email": "ese@iitism.ac.in",
        "expertise_summary": (
            "Mining-affected land and water remediation, acid mine drainage, "
            "industrial effluent treatment, heavy metal contamination in soil and "
            "groundwater, and air quality modelling in coalfield regions."
        ),
        "expertise_tags": [
            "mine remediation", "water contamination", "heavy metals",
            "effluent treatment", "air quality", "soil contamination",
        ],
        "categories": ["Environment & Climate", "Water Management"],
        "capacity": 4,
    },
    {
        "name": "Birsa Agricultural University",
        "department": "Faculty of Agricultural Engineering",
        "city": "Ranchi",
        "state": "Jharkhand",
        "contact_email": "agengg@bauranchi.org",
        "expertise_summary": (
            "Micro-irrigation and watershed management, soil health testing, "
            "climate-resilient cropping for rainfed regions, post-harvest storage, "
            "farm mechanisation for small holdings, and farmer training programmes."
        ),
        "expertise_tags": [
            "irrigation", "watershed", "soil health", "crop science",
            "post harvest", "farm mechanisation", "agri extension",
        ],
        "categories": ["Agriculture & Rural Development", "Water Management"],
        "capacity": 4,
    },
    {
        "name": "Rajendra Institute of Medical Sciences",
        "department": "Department of Community Medicine",
        "city": "Ranchi",
        "state": "Jharkhand",
        "contact_email": "communitymed@rimsranchi.org",
        "expertise_summary": (
            "Public health surveillance, waterborne and vector-borne disease "
            "outbreak investigation, sanitation and hygiene interventions, maternal "
            "and child nutrition programmes, and rural health camp delivery."
        ),
        "expertise_tags": [
            "public health", "epidemiology", "waterborne disease", "sanitation",
            "nutrition", "maternal health", "health camps",
        ],
        "categories": ["Healthcare & Sanitation", "Water Management"],
        "capacity": 3,
    },
    {
        "name": "Xavier Institute of Social Service",
        "department": "Rural Management Programme",
        "city": "Ranchi",
        "state": "Jharkhand",
        "contact_email": "rm@xiss.ac.in",
        "expertise_summary": (
            "Livelihood generation, self-help group mobilisation, skill development "
            "for rural youth, microfinance linkage, tribal community development, "
            "and social impact assessment of development projects."
        ),
        "expertise_tags": [
            "livelihood", "self help group", "skill development", "microfinance",
            "tribal development", "impact assessment",
        ],
        "categories": ["Employment & Livelihood", "Education"],
        "capacity": 4,
    },
    {
        "name": "NIT Jamshedpur",
        "department": "Department of Civil Engineering",
        "city": "Jamshedpur",
        "state": "Jharkhand",
        "contact_email": "civil@nitjsr.ac.in",
        "expertise_summary": (
            "Road and highway design, structural safety assessment of bridges and "
            "public buildings, urban drainage and stormwater systems, construction "
            "materials, and traffic engineering for industrial towns."
        ),
        "expertise_tags": [
            "road design", "structural safety", "drainage", "traffic engineering",
            "construction", "bridges",
        ],
        "categories": ["Transportation & Safety", "Energy & Infrastructure"],
        "capacity": 4,
    },
]

INDUSTRIES = [
    {
        "name": "Tata Steel Foundation",
        "sector": "Steel & CSR",
        "city": "Jamshedpur",
        "state": "Jharkhand",
        "support_types": ["Funding", "Pilot Site", "Mentorship"],
        "focus_categories": [
            "Water Management", "Education", "Healthcare & Sanitation",
            "Employment & Livelihood",
        ],
    },
    {
        "name": "Jharkhand Renewables Pvt Ltd",
        "sector": "Renewable Energy",
        "city": "Ranchi",
        "state": "Jharkhand",
        "support_types": ["Equipment", "Technical Mentorship", "Pilot Site"],
        "focus_categories": ["Energy & Infrastructure", "Environment & Climate"],
    },
    {
        "name": "GreenCycle Waste Solutions",
        "sector": "Waste Management",
        "city": "Dhanbad",
        "state": "Jharkhand",
        "support_types": ["Equipment", "Operations Partner"],
        "focus_categories": ["Waste Management", "Environment & Climate"],
    },
    {
        "name": "EduReach Technologies",
        "sector": "EdTech",
        "city": "Ranchi",
        "state": "Jharkhand",
        "support_types": ["Funding", "Product Engineering", "Mentorship"],
        "focus_categories": ["Education", "Digital Governance"],
    },
]

# The five challenges already hardcoded in the Flutter AppStore, so the seeded
# backend reproduces exactly what the prototype screens show today.
CHALLENGES = [
    {
        "title": "Water Contamination in Village",
        "description": (
            "The drinking water in our village is polluted and causing health issues "
            "for people. Children have fallen sick repeatedly over the last three "
            "months. A safe and sustainable water treatment solution is needed."
        ),
        "category": "Water Management",
        "location": "Ranchi, Jharkhand",
    },
    {
        "title": "Poor Waste Management in Residential Areas",
        "description": (
            "Several residential areas in the city lack proper waste collection and "
            "segregation facilities. Garbage is often dumped in open spaces and near "
            "roads, causing foul odors, blocked drainage systems, and an increased "
            "risk of diseases. The community needs an effective waste collection, "
            "recycling, and awareness system."
        ),
        "category": "Waste Management",
        "location": "Dhanbad, Jharkhand",
    },
    {
        "title": "Frequent Power Outages in Rural Communities",
        "description": (
            "Villages in the surrounding region experience frequent and long-duration "
            "power cuts. Students struggle to study, small businesses lose "
            "productivity, and essential services are affected. A reliable and "
            "sustainable solution is needed to improve electricity availability and "
            "explore alternative energy sources."
        ),
        "category": "Energy & Infrastructure",
        "location": "Hazaribagh, Jharkhand",
    },
    {
        "title": "Lack of Digital Education Resources",
        "description": (
            "Many government school students do not have access to digital learning "
            "resources, computers, or reliable internet connectivity. Teachers also "
            "face difficulties in providing modern and interactive learning "
            "experiences. The challenge is to develop an affordable and accessible "
            "digital education solution for students and schools."
        ),
        "category": "Education",
        "location": "Bokaro, Jharkhand",
    },
    {
        "title": "Unsafe Roads and Traffic Congestion Near Schools",
        "description": (
            "Roads near several schools experience heavy traffic congestion during "
            "morning and afternoon hours. Students face difficulties crossing roads "
            "due to speeding vehicles, inadequate pedestrian crossings, and poor "
            "traffic management. A smart and practical solution is needed to improve "
            "road safety and traffic flow."
        ),
        "category": "Transportation & Safety",
        "location": "Jamshedpur, Jharkhand",
    },
]


async def seed(with_challenges: bool = True, analyze: bool = True) -> None:
    await init_db()

    async with SessionLocal() as db:
        if await db.scalar(select(University.id).limit(1)):
            log.info("Database already seeded. Delete janyukti.db to reseed.")
            return

        unis: list[University] = []
        for spec in UNIVERSITIES:
            # "curated" marks a profile written from what a department publicly
            # does, as opposed to the publication-derived "openalex" rows added
            # by scripts/ingest_openalex.py. Both are real Jharkhand
            # institutions; only the evidence behind the text differs.
            u = University(id=new_uuid(), source="curated", **spec)
            db.add(u)
            unis.append(u)

        inds: list[IndustryProfile] = []
        for spec in INDUSTRIES:
            p = IndustryProfile(id=new_uuid(), **spec)
            db.add(p)
            inds.append(p)
        await db.flush()

        # One demo login per role, so every screen in the app is reachable.
        accounts = [
            ("Aarav Kumar", "citizen@janyukti.in", UserRole.citizen, None, None),
            ("Dr. Priya Sharma", "university@janyukti.in", UserRole.university, unis[0].id, None),
            ("Rahul Verma", "industry@janyukti.in", UserRole.industry, None, inds[0].id),
            ("JanYukti Admin", "admin@janyukti.in", UserRole.admin, None, None),
        ]
        users = []
        for name, email, role, uni_id, ind_id in accounts:
            user = User(
                id=new_uuid(),
                name=name,
                email=email,
                password_hash=hash_password(DEMO_PASSWORD),
                role=role,
                university_id=uni_id,
                industry_id=ind_id,
                is_verified=True,
            )
            db.add(user)
            users.append(user)
        await db.flush()

        citizen = users[0]

        # Embed the university profiles now rather than on the first request, so
        # the first match call in a demo is not also paying for a model load.
        from app.ml.matching import ensure_university_embeddings

        await ensure_university_embeddings(db, unis)
        await db.commit()

        log.info("Seeded %d university departments, %d industry partners, %d users",
                 len(unis), len(inds), len(users))

        if not with_challenges:
            return

        from app.schemas.challenge import ChallengeCreate
        from app.services import challenge_service as svc

        for spec in CHALLENGES:
            challenge = await svc.create_challenge(db, ChallengeCreate(**spec), citizen)
            if analyze:
                await svc.run_analysis(db, challenge)
                log.info(
                    "  %s  %-46s -> %-26s %s",
                    challenge.id,
                    challenge.title[:46],
                    challenge.ai_category,
                    challenge.ai_priority.value if challenge.ai_priority else "-",
                )
            await db.commit()

        log.info("")
        log.info("Demo accounts (password: %s)", DEMO_PASSWORD)
        for name, email, role, _u, _i in accounts:
            log.info("  %-9s %s", role.value, email)


if __name__ == "__main__":
    asyncio.run(seed())
