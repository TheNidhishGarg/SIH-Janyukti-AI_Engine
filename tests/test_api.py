"""API-surface tests: auth, duplicate detection, matching, and access control."""
import pytest


@pytest.mark.asyncio
async def test_login_rejects_bad_password(client):
    r = await client.post(
        "/auth/login", json={"email": "citizen@janyukti.in", "password": "wrong"}
    )
    assert r.status_code == 401


@pytest.mark.asyncio
async def test_unknown_email_gives_same_error_as_bad_password(client):
    """Identical responses, so the endpoint cannot be used to enumerate accounts."""
    a = await client.post("/auth/login", json={"email": "nobody@x.in", "password": "janyukti123"})
    b = await client.post("/auth/login", json={"email": "citizen@janyukti.in", "password": "x"})
    assert a.status_code == b.status_code == 401
    assert a.json() == b.json()


@pytest.mark.asyncio
async def test_protected_route_requires_token(client):
    assert (await client.get("/challenges")).status_code == 401
    assert (await client.get("/auth/me")).status_code == 401


@pytest.mark.asyncio
async def test_citizen_cannot_reach_admin_routes(client, citizen):
    r = await client.get("/admin/queue", headers=citizen)
    assert r.status_code == 403


@pytest.mark.asyncio
async def test_duplicate_detection_catches_a_restatement(client, citizen):
    """Near-identical resubmission of a seeded challenge must be flagged."""
    r = await client.post(
        "/ml/duplicates",
        json={
            "title": "Water Contamination in Village",
            "description": (
                "The drinking water in our village is polluted and causing health "
                "issues for people. A safe water treatment solution is needed."
            ),
            "category": "Water Management",
            "location": "Ranchi, Jharkhand",
            "threshold": 0.6,
        },
        headers=citizen,
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["is_duplicate"] is True
    assert body["best_match"]["title"] == "Water Contamination in Village"
    assert body["best_match"]["same_location"] is True


@pytest.mark.asyncio
async def test_unrelated_report_is_not_a_duplicate(client, citizen):
    r = await client.post(
        "/ml/duplicates",
        json={
            "title": "Streetlights not working on the main road",
            "description": "The street lights along the market road have been dead for weeks.",
            "category": "Energy & Infrastructure",
            "location": "Giridih, Jharkhand",
        },
        headers=citizen,
    )
    assert r.json()["is_duplicate"] is False


@pytest.mark.asyncio
async def test_same_problem_different_district_is_not_merged(client, citizen):
    """Two villages with the same problem are two challenges, not one."""
    r = await client.post(
        "/ml/duplicates",
        json={
            "title": "Water Contamination in Village",
            "description": (
                "The drinking water in our village is polluted and causing health "
                "issues for people. A safe water treatment solution is needed."
            ),
            "category": "Water Management",
            "location": "Palamu, Jharkhand",
            "threshold": 0.85,
        },
        headers=citizen,
    )
    assert r.json()["is_duplicate"] is False


@pytest.mark.asyncio
async def test_matching_routes_by_domain(client, citizen):
    cases = [
        ("Solar power needed for village", "Frequent electricity outages, no reliable grid supply, need solar microgrid.", ("electrical",)),
        ("School road is unsafe", "Traffic congestion and speeding vehicles endanger students crossing the road.", ("geography", "civil")),
        ("No digital learning tools", "Government school students lack computers and internet for digital education.", ("computer",)),
    ]
    for title, description, expected_keywords in cases:
        r = await client.post(
            "/ml/match",
            json={"title": title, "description": description, "location": "Ranchi, Jharkhand"},
            headers=citizen,
        )
        assert r.status_code == 200, r.text
        ranked = r.json()
        assert ranked
        top = ranked[0]
        haystack = f"{top['name']} {top['department']}".lower()
        assert any(k in haystack for k in expected_keywords), f"{title!r} -> {haystack}"
        assert top["reasons"]


@pytest.mark.asyncio
async def test_ml_status_reports_active_engine(client):
    r = await client.get("/ml/status")
    assert r.status_code == 200
    body = r.json()
    assert body["llm_available"] is False       # no key configured in tests
    assert body["embedding_dim"] > 0
    assert "Water Management" in body["categories"]


@pytest.mark.asyncio
async def test_admin_queue_carries_ai_suggestions(client, admin):
    r = await client.get("/admin/queue", headers=admin)
    assert r.status_code == 200, r.text
    queue = r.json()
    assert queue, "seeded challenges should be awaiting review"
    item = queue[0]
    assert item["challenge"]["ai"]["category"]
    assert item["matches"], "the queue must arrive with matches attached"


@pytest.mark.asyncio
async def test_admin_stats_aggregate(client, admin):
    r = await client.get("/admin/stats", headers=admin)
    assert r.status_code == 200, r.text
    stats = r.json()
    assert stats["total_challenges"] >= 5
    assert stats["universities"] == 10
    assert stats["ai_assist_rate"] > 0
    assert stats["by_category"]


@pytest.mark.asyncio
async def test_industry_interest_flow(client, industry, admin):
    r = await client.get("/industry/opportunities", headers=industry)
    assert r.status_code == 200, r.text
    opportunities = r.json()
    assert opportunities, "industry should see backable challenges"

    r = await client.post(
        "/industry/interests",
        json={
            "challenge_id": opportunities[0]["id"],
            "support": ["Funding", "Pilot Site"],
            "message": "We can fund a pilot and host it at our Jamshedpur site.",
            "funding_amount": 500000,
        },
        headers=industry,
    )
    assert r.status_code == 201, r.text
    interest = r.json()
    assert interest["status"] == "Pending"

    r = await client.post(f"/industry/interests/{interest['id']}/decision?accept=true", headers=admin)
    assert r.status_code == 200
    assert r.json()["status"] == "Accepted"


@pytest.mark.asyncio
async def test_challenge_id_format_matches_frontend(client, citizen):
    r = await client.get("/challenges?mine=true", headers=citizen)
    assert r.status_code == 200
    for item in r.json()["items"]:
        assert item["id"].startswith("CH-")
        assert len(item["id"].split("-")[-1]) == 5  # CH-2026-00124


@pytest.mark.asyncio
async def test_admin_queue_orders_high_priority_first(client, admin):
    """The enum stores member names, so a naive sort would put Low above Medium."""
    r = await client.get("/admin/queue", headers=admin)
    rank = {"High": 0, "Medium": 1, "Low": 2}
    order = [rank[i["challenge"]["priority"]] for i in r.json()]
    assert order == sorted(order), f"queue not ordered by severity: {order}"
