"""End-to-end: one challenge travels the whole pipeline, live, with no mocks.

This is the run to show a judge - it is the deck's five-stage flow
(Report -> AI Analyze -> Smart Matching -> Collaborate -> Impact) executed
against real endpoints.
"""
import pytest

NEW_CHALLENGE = {
    "title": "Contaminated borewell water in Namkum block",
    "description": (
        "The borewell water supplied to our village has turned muddy and smells foul. "
        "Children and elderly residents have been falling sick with stomach illness "
        "for over two months. Around 1200 people depend on this single source and "
        "there is no alternative drinking water supply."
    ),
    "category": "Water Management",
    "location": "Khunti, Jharkhand",
    "district": "Khunti",
    "state": "Jharkhand",
    "people_impacted": 1200,
}


@pytest.mark.asyncio
async def test_full_lifecycle(client, citizen, admin, university):
    # --- 1. REPORT -------------------------------------------------------
    r = await client.post(
        "/challenges?analyze_sync=true", json=NEW_CHALLENGE, headers=citizen
    )
    assert r.status_code == 201, r.text
    challenge = r.json()
    cid = challenge["id"]
    assert cid.startswith("CH-")

    # --- 2. AI ANALYZE ---------------------------------------------------
    ai = challenge["ai"]
    assert ai is not None, "analysis should be attached when analyze_sync=true"
    assert ai["category"] == "Water Management"
    assert ai["priority"] == "High", f"severe health impact should score High, got {ai}"
    assert set(ai["scores"]) == {"severity", "urgency", "reach", "vulnerability"}
    assert ai["rationale"]
    assert challenge["status"] == "Under Review"

    # --- 3. SMART MATCHING ----------------------------------------------
    r = await client.get(f"/challenges/{cid}/matches", headers=admin)
    assert r.status_code == 200, r.text
    matches = r.json()
    assert matches, "the matcher must return ranked universities"
    top = matches[0]
    assert top["rank"] == 1
    assert top["score"] >= matches[-1]["score"], "results must be sorted by score"
    assert top["reasons"], "every suggestion must be explainable"
    # A water contamination report in Ranchi should surface a water/environment
    # department, not an unrelated one.
    assert any(
        kw in (top["department"] + top["name"]).lower()
        for kw in ("civil", "environmental", "community medicine")
    ), f"unexpected top match: {top['name']} / {top['department']}"

    # --- 4a. ADMIN ASSIGNS (confirming the AI suggestion) ----------------
    r = await client.post(
        f"/admin/challenges/{cid}/assign",
        json={"university_id": top["university_id"]},
        headers=admin,
    )
    assert r.status_code == 200, r.text
    assigned = r.json()
    assert assigned["status"] == "Assigned"
    assert assigned["status_label"].startswith("Assigned to ")

    # --- 4b. UNIVERSITY ACCEPTS -> project workspace ---------------------
    uni_id = top["university_id"]
    r = await client.get(f"/universities/{uni_id}/inbox", headers=admin)
    assert r.status_code == 200
    assert any(c["id"] == cid for c in r.json())

    r = await client.post(
        "/projects",
        json={
            "challenge_id": cid,
            "name": "Village Borewell Water Purification System",
            "mentor": "Dr. Priya Sharma",
        },
        headers=admin,
    )
    assert r.status_code == 201, r.text
    project = r.json()
    pid = project["id"]
    assert len(project["milestones"]) == 5
    assert project["progress"] > 0, "first milestone starts in progress"

    r = await client.get(f"/challenges/{cid}", headers=citizen)
    assert r.json()["status"] == "In Progress", "citizen must see live status"

    # --- 5. MILESTONES ---------------------------------------------------
    progress_history = [project["progress"]]
    for milestone in project["milestones"]:
        r = await client.post(
            f"/projects/{pid}/milestones/{milestone['id']}/submit",
            json={"note": "Stage complete", "evidence_url": "https://example.org/report.pdf"},
            headers=admin,
        )
        assert r.status_code == 200, r.text

        r = await client.post(
            f"/projects/{pid}/milestones/{milestone['id']}/review",
            json={"approved": True, "note": "Verified"},
            headers=admin,
        )
        assert r.status_code == 200, r.text
        progress_history.append(r.json()["progress"])

    assert progress_history == sorted(progress_history), "progress must never go backwards"
    final = r.json()
    assert final["progress"] == 100
    assert final["status"] == "Completed"

    # --- 6. IMPACT -------------------------------------------------------
    r = await client.post(
        f"/projects/{pid}/impact",
        json={
            "people_impacted": 1200,
            "summary": "Filtration unit commissioned; water now meets IS 10500 norms.",
            "metrics": {"households": 240, "litres_per_day": 9000},
        },
        headers=admin,
    )
    assert r.status_code == 200, r.text
    assert r.json()["people_impacted"] == 1200

    r = await client.get(f"/challenges/{cid}", headers=citizen)
    assert r.json()["status"] == "Resolved"

    # --- Timeline and notifications reached the citizen -------------------
    timeline = (await client.get(f"/challenges/{cid}", headers=citizen)).json()["timeline"]
    labels = [e["label"] for e in timeline]
    assert "Submitted" in labels
    assert any(l.startswith("Assigned to") for l in labels)
    assert "Impact reported" in labels

    r = await client.get("/notifications", headers=citizen)
    assert r.status_code == 200
    assert len(r.json()) >= 3, "a silent submission is the failure mode we are avoiding"

    r = await client.get("/me/stats", headers=citizen)
    stats = r.json()
    assert stats["resolved"] >= 1
    assert stats["people_impacted"] >= 1200
