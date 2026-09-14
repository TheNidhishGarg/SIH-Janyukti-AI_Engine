"""Tests for the /ai routes the Flutter app calls.

The session database is shared across the whole run, so every test uses its own
district and document ids rather than assuming an empty duplicate index. The
prune test runs last because it deliberately empties the index.
"""
import uuid

import pytest

from app.ml.ai_service import split_location

BOREWELL = {
    "title": "Contaminated borewell water in our village",
    "description": (
        "The borewell water has turned muddy and smells foul. Children and elderly "
        "residents have been falling sick with stomach illness for two months."
    ),
    "additionalInfo": "Around 1200 people depend on this single source.",
    "category": "Water Management",
    "location": "Namkum, Khunti, Jharkhand 835210, India",
}

GARBAGE = {
    "title": "Garbage not collected in our colony",
    "description": "Waste piles up on the roadside for weeks, no segregation, foul smell and mosquitoes.",
    "category": "Waste Management",
    "location": "Gumla, Jharkhand",
}

GARBAGE_PARAPHRASE = {
    "title": "No waste pickup in residential area",
    "description": "Trash is dumped in the open near homes, nobody collects it, it stinks and breeds mosquitoes.",
    "category": "Waste Management",
    "location": "Gumla, Jharkhand",
}


def _doc_id() -> str:
    return f"fs-{uuid.uuid4().hex[:16]}"


@pytest.mark.parametrize(
    "location,expected",
    [
        ("Ranchi, Jharkhand", ("Ranchi", "Jharkhand")),
        ("Namkum, Ranchi, Jharkhand 834010, India", ("Ranchi", "Jharkhand")),
        ("Khunti", ("Khunti", None)),
        ("Bhubaneswar, Orissa", ("Bhubaneswar", "Odisha")),
        ("", (None, None)),
    ],
)
def test_split_location(location, expected):
    assert split_location(location) == expected


@pytest.mark.asyncio
async def test_status_is_public_and_camel_case(client):
    r = await client.get("/ai/status")
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["authMode"] == "off"
    assert "Agriculture" in body["appCategories"]
    assert body["universityProfiles"] > 0
    assert {"embeddingModel", "duplicateThreshold", "indexedChallenges"} <= body.keys()


@pytest.mark.asyncio
async def test_analyze_returns_storable_analysis(client):
    doc_id = _doc_id()
    r = await client.post("/ai/analyze", json={**BOREWELL, "challengeId": doc_id})
    assert r.status_code == 200, r.text
    a = r.json()

    assert a["category"] == "Water Management"
    assert a["appCategory"] == "Water Management"
    assert a["categoryMatchesCitizen"] is True
    assert a["priority"] == "High"
    assert set(a["scores"]) == {"severity", "urgency", "reach", "vulnerability"}
    assert a["rationale"]
    assert a["district"] == "Khunti" and a["state"] == "Jharkhand"
    assert a["indexed"] is True
    assert a["duplicate"] is None

    suggestion = a["suggestedInstitutions"][0]
    assert {"institution", "department", "scorePercent", "reasons", "source"} <= suggestion.keys()


@pytest.mark.asyncio
async def test_reanalysing_a_challenge_never_flags_itself(client):
    doc_id = _doc_id()
    body = {
        "title": "Transformer keeps failing in our village",
        "description": "Electricity goes out for hours every day since the transformer burned out.",
        "category": "Infrastructure",
        "location": "Latehar, Jharkhand",
        "challengeId": doc_id,
    }
    first = await client.post("/ai/analyze", json=body)
    second = await client.post("/ai/analyze", json=body)
    assert first.status_code == second.status_code == 200
    assert second.json()["duplicate"] is None
    assert second.json()["appCategory"] == "Infrastructure"


@pytest.mark.asyncio
async def test_second_report_of_same_problem_is_flagged(client):
    original = _doc_id()
    r = await client.post("/ai/analyze", json={**GARBAGE, "challengeId": original})
    assert r.status_code == 200

    r = await client.post("/ai/analyze", json={**GARBAGE_PARAPHRASE, "challengeId": _doc_id()})
    duplicate = r.json()["duplicate"]
    assert duplicate is not None, r.json()["possibleDuplicates"]
    assert duplicate["challengeId"] == original
    assert duplicate["sameLocation"] is True


@pytest.mark.asyncio
async def test_duplicate_preview_does_not_write_to_the_index(client):
    before = (await client.get("/ai/status")).json()["indexedChallenges"]
    r = await client.post(
        "/ai/duplicates",
        json={
            "title": "Unsafe road crossing outside school",
            "description": "Speeding vehicles make it dangerous for children to cross.",
            "location": "Simdega, Jharkhand",
        },
    )
    assert r.status_code == 200, r.text
    assert {"isDuplicate", "threshold", "candidates"} <= r.json().keys()
    after = (await client.get("/ai/status")).json()["indexedChallenges"]
    assert after == before


@pytest.mark.asyncio
async def test_rejected_challenges_stop_matching(client):
    body = {
        "title": "No teachers in the primary school",
        "description": "The government primary school has had no mathematics teacher for a year.",
        "category": "Education",
        "location": "Godda, Jharkhand",
    }
    original = _doc_id()
    await client.post("/ai/analyze", json={**body, "challengeId": original})

    flagged = await client.post("/ai/duplicates", json=body)
    assert flagged.json()["isDuplicate"] is True

    r = await client.patch(f"/ai/index/{original}", json={"status": "Rejected"})
    assert r.status_code == 200 and r.json()["indexed"] is True

    after = await client.post("/ai/duplicates", json=body)
    assert after.json()["isDuplicate"] is False


@pytest.mark.asyncio
async def test_status_update_for_unknown_challenge_is_not_an_error(client):
    r = await client.patch("/ai/index/never-indexed", json={"status": "Assigned"})
    assert r.status_code == 200
    assert r.json()["indexed"] is False


@pytest.mark.asyncio
async def test_match_links_registered_organisations_to_profiles(client):
    organizations = [
        {
            "id": "org-unprofiled",
            "name": "Sunrise Degree College",
            "city": "Dumka",
            "state": "Jharkhand",
            "type": "Institute / College",
        },
        {
            "id": "org-bit",
            "name": "Birla Institute of Technology, Mesra",
            "city": "Ranchi",
            "state": "Jharkhand",
            "type": "Deemed University",
        },
    ]
    r = await client.post(
        "/ai/match",
        json={
            "title": "Contaminated drinking water in the village",
            "description": "The drinking water is polluted and people are falling sick.",
            "category": "Water Management",
            "location": "Ranchi, Jharkhand",
            "organizations": organizations,
        },
    )
    assert r.status_code == 200, r.text
    body = r.json()
    registered = body["registered"]

    assert [o["organizationId"] for o in registered] == ["org-bit", "org-unprofiled"]
    top, other = registered
    assert top["rank"] == 1 and top["profileLinked"] is True
    assert top["profileDepartment"]
    assert other["profileLinked"] is False
    assert top["score"] > other["score"]

    # A registered institution must not also be suggested as one to invite.
    assert all("BIT Mesra" not in d["institution"] for d in body["directory"])


@pytest.mark.asyncio
async def test_required_auth_mode_verifies_firebase_tokens(client, monkeypatch):
    import app.core.firebase_auth as firebase_auth
    from app.config import settings

    monkeypatch.setattr(settings, "FIREBASE_AUTH_MODE", "required")
    monkeypatch.setattr(settings, "FIREBASE_PROJECT_ID", "janyukti-test")
    body = {"title": "Broken street lights", "description": "The lights have been dead for weeks."}

    missing = await client.post("/ai/duplicates", json=body)
    assert missing.status_code == 401

    def reject(token):
        raise ValueError("bad signature")

    monkeypatch.setattr(firebase_auth, "verify_id_token", reject)
    forged = await client.post("/ai/duplicates", json=body, headers={"Authorization": "Bearer forged"})
    assert forged.status_code == 401

    monkeypatch.setattr(firebase_auth, "verify_id_token", lambda token: {"sub": "uid-123"})
    valid = await client.post("/ai/duplicates", json=body, headers={"Authorization": "Bearer good"})
    assert valid.status_code == 200, valid.text

    # Status stays public so the app can check reachability before sign-in.
    assert (await client.get("/ai/status")).status_code == 200


@pytest.mark.asyncio
async def test_sync_is_incremental_and_prunes(client):
    ids = [_doc_id() for _ in range(3)]
    items = [
        {
            "id": doc_id,
            "title": f"Broken hand pump number {n}",
            "description": "The hand pump near the weekly market has been broken for weeks.",
            "category": "Water Management",
            "location": "Pakur, Jharkhand",
            "status": "Under Review",
        }
        for n, doc_id in enumerate(ids)
    ]

    first = (await client.post("/ai/index/sync", json={"challenges": items})).json()
    assert (first["created"], first["updated"], first["unchanged"]) == (3, 0, 0)

    again = (await client.post("/ai/index/sync", json={"challenges": items})).json()
    assert again["unchanged"] == 3

    items[0]["description"] += " Nobody has come to repair it."
    items[1]["status"] = "Assigned"
    changed = (await client.post("/ai/index/sync", json={"challenges": items})).json()
    assert (changed["updated"], changed["unchanged"]) == (2, 1)

    refused = await client.post("/ai/index/sync", json={"challenges": [], "prune": True})
    assert refused.status_code == 400

    pruned = (await client.post("/ai/index/sync", json={"challenges": items[:1], "prune": True})).json()
    assert pruned["removed"] >= 2
    assert (await client.get("/ai/status")).json()["indexedChallenges"] == 1
