"""Build university expertise profiles from real OpenAlex publication data.

    python -m scripts.ingest_openalex --dry-run
    python -m scripts.ingest_openalex --radius 500 --max-institutions 30

Why this exists: the profiles in app/seed.py are hand-written. This replaces
them with expertise derived from what institutions have actually published.

Scope. Institutions are filtered by great-circle distance from Ranchi rather
than by state label, for two reasons: OpenAlex populates coordinates for 100%
of Indian institutions but a state for only ~69%, and the state filter silently
drops IIT (ISM) Dhanbad and NIT Jamshedpur - the two largest technical
institutions in Jharkhand. 500 km covers Jharkhand and the neighbouring states
(Bihar, West Bengal, Odisha, Chhattisgarh, and the Jharkhand-adjacent corner of
Uttar Pradesh) while excluding the far side of the country.

Granularity. OpenAlex is institution-level, but matching works on departments.
So each institution is split into up to N rows - one per civic category it
genuinely publishes in - and each row embeds only that category's topics.
Embedding all 25 topics of a large institution into one vector dilutes the
signal until every big university matches every challenge.

Honesty note: the resulting `department` values are derived research-strength
groupings, not verified department names. See DEPARTMENT_LABELS.
"""
from __future__ import annotations

import argparse
import asyncio
import json
import math
import os
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlalchemy import delete, select

from app.core.ids import new_uuid
from app.db import SessionLocal, init_db
from app.ml.category_mapping import DEPARTMENT_LABELS, score_topics
from app.models import University

API = "https://api.openalex.org/institutions"
CACHE = Path(__file__).resolve().parent.parent / "app" / "data" / "openalex_in.json"

# Ranchi: the Jharkhand capital, used as the centre for the distance filter.
CENTRE = (23.3441, 85.3096)
CENTRE_NAME = "Ranchi"

# Reverse-geocoding the state from coordinates is overkill; these bounds are
# only used to label rows whose OpenAlex record has no region string.
STATE_BY_CITY = {
    "ranchi": "Jharkhand", "dhanbad": "Jharkhand", "jamshedpur": "Jharkhand",
    "bokaro": "Jharkhand", "hazaribagh": "Jharkhand", "deoghar": "Jharkhand",
    "dumka": "Jharkhand", "giridih": "Jharkhand", "ramgarh": "Jharkhand",
    "patna": "Bihar", "gaya": "Bihar", "muzaffarpur": "Bihar", "bhagalpur": "Bihar",
    "darbhanga": "Bihar", "nalanda": "Bihar", "rajgir": "Bihar", "samastipur": "Bihar",
    "kolkata": "West Bengal", "calcutta": "West Bengal", "howrah": "West Bengal",
    "kharagpur": "West Bengal", "durgapur": "West Bengal", "asansol": "West Bengal",
    "kalyani": "West Bengal", "burdwan": "West Bengal", "bardhaman": "West Bengal",
    "santiniketan": "West Bengal", "bolpur": "West Bengal", "midnapore": "West Bengal",
    "bhubaneswar": "Odisha", "cuttack": "Odisha", "rourkela": "Odisha",
    "sambalpur": "Odisha", "berhampur": "Odisha", "burla": "Odisha",
    "raipur": "Chhattisgarh", "bhilai": "Chhattisgarh", "bilaspur": "Chhattisgarh",
    "varanasi": "Uttar Pradesh", "prayagraj": "Uttar Pradesh",
    "allahabad": "Uttar Pradesh", "gorakhpur": "Uttar Pradesh",
}


# --- Jharkhand scope -------------------------------------------------------
# Default scope is Jharkhand alone. A challenge assigned across a state border
# needs an inter-state arrangement before anyone can start work, which is a
# governance problem the platform cannot solve; keeping assignments inside one
# state keeps the pilot executable. Use --scope nearby to widen.

JHARKHAND_CITIES = {
    "ranchi", "dhanbad", "jamshedpur", "bokaro", "bokaro steel city",
    "hazaribagh", "hazaribag", "deoghar", "dumka", "giridih", "ramgarh",
    "chaibasa", "daltonganj", "medininagar", "sahibganj", "gumla", "lohardaga",
    "chatra", "koderma", "pakur", "godda", "latehar", "simdega", "khunti",
    "garhwa", "adityapur", "jhumri telaiya", "phusro", "saraikela", "jharia",
    "sindri", "mesra", "rajmahal", "madhupur", "chirkunda", "chakradharpur",
}

# Rough Jharkhand bounding box, used only to reject a same-named city in
# another state (there is a Ramgarh in Rajasthan, a Chatra in Nepal).
JH_BOUNDS = (21.9, 25.4, 83.3, 87.95)  # lat_min, lat_max, lon_min, lon_max


def is_jharkhand(geo: dict) -> bool:
    if (geo.get("region") or "").strip() == "Jharkhand":
        return True
    lat, lon = geo.get("latitude"), geo.get("longitude")
    if lat is None or lon is None:
        return False
    lo_a, hi_a, lo_o, hi_o = JH_BOUNDS
    if not (lo_a <= lat <= hi_a and lo_o <= lon <= hi_o):
        return False
    # OpenAlex leaves region empty for ~31% of Indian institutions, including
    # IIT (ISM) Dhanbad and NIT Jamshedpur, so fall back to the city name.
    return (geo.get("city") or "").strip().lower() in JHARKHAND_CITIES


def _say(text: str = "", end: str = chr(10)) -> None:
    """Print without exploding on a Windows cp1252 console.

    Several institution names carry Devanagari or diacritics; the default
    Windows encoding cannot render them and the resulting UnicodeEncodeError
    would otherwise kill the run after all the work was done.
    """
    stream = sys.stdout
    encoding = stream.encoding or "utf-8"
    try:
        stream.write(text + end)
    except UnicodeEncodeError:
        stream.write(text.encode(encoding, "replace").decode(encoding) + end)


def haversine_km(lat: float, lon: float) -> float:
    r = 6371.0
    p1, p2 = math.radians(CENTRE[0]), math.radians(lat)
    dp = math.radians(lat - CENTRE[0])
    dl = math.radians(lon - CENTRE[1])
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(h))


def fetch_all(refresh: bool = False) -> list[dict]:
    """All Indian education institutions, cached to disk after the first run."""
    if CACHE.exists() and not refresh:
        return json.loads(CACHE.read_text(encoding="utf-8"))

    # OpenAlex asks for a contact address to use its faster "polite pool".
    # Opt in by setting OPENALEX_MAILTO; requests are anonymous without it.
    mailto = os.environ.get("OPENALEX_MAILTO", "").strip()
    rows: list[dict] = []
    cursor = "*"
    _say("Fetching institutions from OpenAlex...")
    while cursor:
        params = {
            "filter": "country_code:in,type:education",
            "per-page": "200",
            "cursor": cursor,
        }
        if mailto:
            params["mailto"] = mailto
        url = f"{API}?{urllib.parse.urlencode(params)}"
        with urllib.request.urlopen(url, timeout=60) as resp:
            payload = json.load(resp)
        batch = payload.get("results", [])
        if not batch:
            break
        rows.extend(batch)
        print(f"  {len(rows)} / {payload['meta']['count']}", end="\r")
        cursor = payload["meta"].get("next_cursor")
        time.sleep(0.2)

    _say(f"  fetched {len(rows)} institutions" + " " * 20)
    CACHE.parent.mkdir(parents=True, exist_ok=True)
    CACHE.write_text(json.dumps(rows), encoding="utf-8")
    return rows


def in_scope(rows: list[dict], radius_km: float, min_works: int, scope: str) -> list[dict]:
    """Institutions in scope with enough published output to profile."""
    out = []
    for r in rows:
        geo = r.get("geo") or {}
        lat, lon = geo.get("latitude"), geo.get("longitude")
        if lat is None or lon is None:
            continue
        if int(r.get("works_count") or 0) < min_works:
            continue
        if scope == "jharkhand":
            if not is_jharkhand(geo):
                continue
        elif haversine_km(lat, lon) > radius_km:
            continue
        r["_km"] = haversine_km(lat, lon)
        out.append(r)
    out.sort(key=lambda r: -int(r.get("works_count") or 0))
    return out


def resolve_state(geo: dict) -> str:
    region = (geo.get("region") or "").strip()
    if region:
        return "Odisha" if region == "Orissa" else region
    return STATE_BY_CITY.get((geo.get("city") or "").strip().lower(), "")


def build_profiles(
    institution: dict,
    max_departments: int,
    min_share: float,
    min_weight: float,
) -> list[dict]:
    """Split one institution into per-category department profiles."""
    scored = score_topics(institution.get("topics") or [])
    if not scored:
        return []

    total = sum(b["weight"] for b in scored.values())
    if total <= 0:
        return []

    geo = institution.get("geo") or {}
    city = (geo.get("city") or "").strip()
    state = resolve_state(geo)
    works = int(institution.get("works_count") or 0)

    ranked = sorted(scored.items(), key=lambda kv: -kv[1]["weight"])
    profiles = []

    for category, bucket in ranked[:max_departments]:
        share = bucket["weight"] / total
        # Two gates: the category must be a real share of what the institution
        # does, AND carry enough absolute output to be credible. Share alone
        # would let a tiny college with three water papers outrank IIT.
        if share < min_share or bucket["weight"] < min_weight:
            continue

        topics = bucket["topics"][:10]
        topic_names = [name for name, _ in topics]
        papers = sum(count for _, count in topics)

        summary = (
            f"Research group at {institution['display_name']} working on "
            f"{category.lower()}. Published work covers "
            f"{', '.join(topic_names[:6]).lower()}. "
            f"Approximately {papers} publications in this area "
            f"({share:.0%} of the institution research output)."
        )

        profiles.append({
            "name": institution["display_name"],
            "department": DEPARTMENT_LABELS.get(category, category),
            "city": city,
            "state": state,
            "category": category,
            "categories": [category],
            "expertise_summary": summary,
            "expertise_tags": [n.lower() for n in topic_names],
            # Capacity from real output scale, bounded so no institution can
            # absorb the entire queue.
            "capacity": max(2, min(8, 2 + papers // 400)),
            "works_count": works,
            "ror": institution.get("ror"),
            "openalex_id": institution.get("id"),
            "distance_km": institution["_km"],
            "share": share,
            "papers": papers,
        })

    return profiles


async def persist(profiles: list[dict], replace: bool) -> tuple[int, int]:
    """Upsert profiles, keyed by (openalex_id, department) so reruns are safe."""
    await init_db()
    created = updated = 0

    async with SessionLocal() as db:
        if replace:
            await db.execute(delete(University).where(University.source == "openalex"))

        for p in profiles:
            existing = await db.scalar(
                select(University).where(
                    University.openalex_id == p["openalex_id"],
                    University.department == p["department"],
                )
            )
            fields = {
                "name": p["name"],
                "department": p["department"],
                "city": p["city"],
                "state": p["state"],
                "expertise_summary": p["expertise_summary"],
                "expertise_tags": p["expertise_tags"],
                "categories": p["categories"],
                "capacity": p["capacity"],
                "works_count": p["works_count"],
                "ror": p["ror"],
                "openalex_id": p["openalex_id"],
                "source": "openalex",
            }
            if existing is None:
                db.add(University(id=new_uuid(), **fields))
                created += 1
            else:
                for k, v in fields.items():
                    setattr(existing, k, v)
                # Expertise text changed, so the cached vector is stale.
                existing.embedding = None
                existing.embedding_model = None
                updated += 1

        await db.flush()

        from app.ml.matching import ensure_university_embeddings

        rows = list((await db.scalars(select(University))).all())
        await ensure_university_embeddings(db, rows)
        await db.commit()

    return created, updated


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--scope", choices=("jharkhand", "nearby"), default="jharkhand",
                    help="jharkhand (default) keeps assignments inside one state; "
                         "nearby widens to --radius km around Ranchi")
    ap.add_argument("--radius", type=float, default=500.0,
                    help=f"max km from {CENTRE_NAME} when --scope nearby (default: 500)")
    ap.add_argument("--min-works", type=int, default=50,
                    help="skip institutions below this publication count")
    ap.add_argument("--max-institutions", type=int, default=0,
                    help="keep the N largest in scope (0 = no limit)")
    ap.add_argument("--max-departments", type=int, default=4,
                    help="max derived department rows per institution")
    ap.add_argument("--min-share", type=float, default=0.04,
                    help="category must be this share of the institution output")
    ap.add_argument("--min-weight", type=float, default=60.0,
                    help="category must carry this much weighted output")
    ap.add_argument("--replace", action="store_true",
                    help="delete existing openalex rows first")
    ap.add_argument("--refresh", action="store_true", help="re-download, ignore cache")
    ap.add_argument("--dry-run", action="store_true", help="print, do not write")
    args = ap.parse_args()

    rows = fetch_all(refresh=args.refresh)
    scoped = in_scope(rows, args.radius, args.min_works, args.scope)
    if args.max_institutions:
        scoped = scoped[: args.max_institutions]

    where = ("in Jharkhand" if args.scope == "jharkhand"
             else f"within {args.radius:.0f} km of {CENTRE_NAME}")
    _say(f"\n{len(scoped)} institutions {where} with >= {args.min_works} works\n")

    profiles: list[dict] = []
    for inst in scoped:
        profiles.extend(
            build_profiles(inst, args.max_departments, args.min_share, args.min_weight)
        )

    by_institution: dict[str, list[dict]] = {}
    for p in profiles:
        by_institution.setdefault(p["name"], []).append(p)

    for name, group in by_institution.items():
        head = group[0]
        label = f"{name} ({head['city'] or '?'}, {head['state'] or '?'})"
        _say(f"{label[:70]:<70} {head['distance_km']:>4.0f} km")
        for p in group:
            _say(f"    {p['category']:<32} {p['share']:>5.0%}  {p['papers']:>5} papers  "
                 f"cap={p['capacity']}")

    print(f"\n{len(profiles)} department profiles from {len(by_institution)} institutions")

    if args.dry_run:
        print("\n(dry run - nothing written)")
        return

    created, updated = asyncio.run(persist(profiles, args.replace))
    print(f"\nWrote {created} new and {updated} updated profiles, embeddings refreshed.")


if __name__ == "__main__":
    main()
