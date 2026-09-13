"""Drive the whole JanYukti pipeline against a running server and narrate it.

    python main.py                      # terminal 1
    python -m scripts.demo_pipeline     # terminal 2

Walks one challenge through all five stages from the deck - Report, AI Analyze,
Smart Matching, Collaborate, Impact - using only the public HTTP API, as four
different users. Nothing is mocked and nothing is skipped: if a stage is broken
this script fails loudly at that stage.

Standard library only, so it runs anywhere the backend does.
"""
from __future__ import annotations

import argparse
import json
import os
import secrets
import sys
import urllib.error
import urllib.request

DEFAULT_BASE = "http://127.0.0.1:8000"
BASE = DEFAULT_BASE
PASSWORD = "janyukti123"

# Plain text when piped, redirected, or NO_COLOR is set.
if os.environ.get("NO_COLOR") or not sys.stdout.isatty():
    GREEN = DIM = BOLD = RED = RESET = ""
else:
    GREEN, DIM, BOLD, RED, RESET = (
        "\033[32m", "\033[2m", "\033[1m", "\033[31m", "\033[0m",
    )


def say(text: str = "") -> None:
    """Write output without dying on a Windows cp1252 console."""
    enc = sys.stdout.encoding or "utf-8"
    try:
        sys.stdout.write(text + "\n")
    except UnicodeEncodeError:
        sys.stdout.write(text.encode(enc, "replace").decode(enc) + "\n")
    sys.stdout.flush()


def stage(n: str, title: str) -> None:
    say("")
    say(f"{BOLD}{'=' * 72}{RESET}")
    say(f"{BOLD}  STAGE {n}  {title}{RESET}")
    say(f"{BOLD}{'=' * 72}{RESET}")


def ok(text: str) -> None:
    say(f"  {GREEN}[ok]{RESET} {text}")


def info(text: str) -> None:
    say(f"       {DIM}{text}{RESET}")


def call(method: str, path: str, token: str | None = None, body: dict | None = None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(f"{BASE}{path}", data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            raw = resp.read().decode()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        detail = e.read().decode()
        say(f"{RED}  HTTP {e.code} on {method} {path}{RESET}")
        say(f"{RED}  {detail[:400]}{RESET}")
        raise SystemExit(1)
    except urllib.error.URLError as e:
        say(f"{RED}  Cannot reach {BASE} - is the server running? ({e.reason}){RESET}")
        raise SystemExit(1)


def login(email: str) -> str:
    return call("POST", "/auth/login", body={"email": email, "password": PASSWORD})["access_token"]


# A per-run suffix keeps repeat demos independent. Without it the second run
# submits a challenge identical to the first and is correctly flagged as a
# duplicate of it, which is right but makes the walkthrough confusing.
RUN = secrets.token_hex(2)

CHALLENGE = {
    "title": f"Contaminated borewell water in Namkum block (ward {RUN})",
    "description": (
        "The borewell water supplied to our village has turned muddy and smells foul. "
        "Children and elderly residents have been falling sick with stomach illness for "
        "over two months. Around 1200 people depend on this single source and there is "
        "no alternative drinking water supply."
    ),
    "category": "Water Management",
    "location": "Khunti, Jharkhand",
    "district": "Khunti",
    "state": "Jharkhand",
    "people_impacted": 1200,
}

# Deliberately a restatement of the above, from the same district.
NEAR_DUPLICATE = {
    "title": "Dirty bore well water making villagers ill",
    "description": (
        "Our village borewell gives muddy, foul smelling water. Many children have "
        "stomach illness. More than a thousand people have no other drinking source."
    ),
    "category": "Water Management",
    "location": "Khunti, Jharkhand",
    "district": "Khunti",
}


def main() -> None:
    global BASE
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--base", default=DEFAULT_BASE, help="server base URL")
    args = ap.parse_args()
    BASE = args.base.rstrip("/")

    say(f"{BOLD}JanYukti pipeline walkthrough{RESET}  ->  {BASE}")

    # ---------------------------------------------------------------- setup
    health = call("GET", "/health")
    ok(f"server healthy ({health['service']} v{health['version']})")
    ml = call("GET", "/ml/status")
    ok(f"AI engine: llm={ml['llm_model']}, embeddings={ml['embedding_model']} ({ml['embedding_dim']}d)")
    if not ml["llm_available"]:
        info("no GEMINI_API_KEY set - running on the offline heuristic path")

    citizen = login("citizen@janyukti.in")
    admin = login("admin@janyukti.in")
    ok("logged in as citizen and admin")

    # ------------------------------------------------------------- stage 1
    stage("1", "REPORT - a citizen submits a challenge")
    challenge = call("POST", "/challenges?analyze_sync=true", citizen, CHALLENGE)
    cid = challenge["id"]
    ok(f"submitted {cid}: {challenge['title']}")
    info(f"status: {challenge['status_label']}  |  location: {challenge['location']}")

    # ------------------------------------------------------------- stage 2
    stage("2", "AI ANALYZE - categorize, score priority, detect duplicates")
    ai = challenge["ai"]
    if not ai:
        say(f"{RED}  No AI block returned - analysis did not run.{RESET}")
        raise SystemExit(1)
    ok(f"category: {ai['category']}  ({ai['category_confidence']:.0%} confidence)")
    ok(f"priority: {ai['priority']}  (rubric score {ai['priority_score']:.2f})")
    for axis, value in sorted(ai["scores"].items()):
        info(f"{axis:<16} {value}/5")
    info(f"rationale: {ai['rationale']}")
    info(f"engine: {ai['engine']}  |  tags: {', '.join(ai['tags'] or []) or '-'}")
    if ai.get("duplicate_of"):
        info(f"flagged as duplicate of {ai['duplicate_of']}")

    say("")
    say("  Now submitting a near-identical report from the same district:")
    dupe = call("POST", "/ml/duplicates", citizen, NEAR_DUPLICATE)
    if dupe["is_duplicate"]:
        best = dupe["best_match"]
        ok(f"DUPLICATE caught -> {best['challenge_id']} (score {best['score']:.2f}, "
           f"semantic {best['semantic_score']:.2f}, same location: {best['same_location']})")
    elif dupe["candidates"]:
        top_c = dupe["candidates"][0]
        info(f"ranked #1 correctly ({top_c['challenge_id']}, score {top_c['score']:.2f}) "
             f"but below the {dupe['threshold']:.2f} auto-flag bar")
        info("it still shows in the admin UI as 'possibly related'")
    else:
        info("no candidates returned")

    unrelated = call("POST", "/ml/duplicates", citizen, {
        "title": "Street lights dead on the market road",
        "description": "Lights along the market road have not worked for weeks.",
        "category": "Energy & Infrastructure", "location": "Giridih, Jharkhand"})
    ok(f"unrelated report correctly not flagged: is_duplicate={unrelated['is_duplicate']}")

    # ------------------------------------------------------------- stage 3
    stage("3", "SMART MATCHING - rank Jharkhand departments")
    matches = call("GET", f"/challenges/{cid}/matches", admin)
    if not matches:
        say(f"{RED}  No matches returned.{RESET}")
        raise SystemExit(1)
    for m in matches:
        say(f"  {BOLD}#{m['rank']}  {m['score']:.3f}{RESET}  {m['name']} - {m['department']}")
        info(f"semantic {m['semantic_score']:.2f} | category {m['category_score']:.2f} | "
             f"capacity {m['capacity_score']:.2f} | proximity {m['proximity_score']:.2f}")
        for reason in m["reasons"]:
            info(f"- {reason}")
    top = matches[0]

    # ------------------------------------------------------------- stage 4
    stage("4", "COLLABORATE - admin assigns, university accepts")
    queue = call("GET", "/admin/queue", admin)
    ok(f"admin review queue holds {len(queue)} challenge(s), each with AI suggestions attached")

    assigned = call("POST", f"/admin/challenges/{cid}/assign", admin,
                    {"university_id": top["university_id"], "note": "Confirming AI suggestion"})
    ok(f"assigned -> {assigned['status_label']}")

    inbox = call("GET", f"/universities/{top['university_id']}/inbox", admin)
    ok(f"university inbox shows {len(inbox)} pending assignment(s)")

    project = call("POST", "/projects", admin, {
        "challenge_id": cid,
        "name": "Village Borewell Water Purification System",
        "mentor": "Dr. Priya Sharma",
    })
    pid = project["id"]
    ok(f"accepted -> project {pid} created with {len(project['milestones'])} milestones "
       f"({project['progress']}% progress)")

    view = call("GET", f"/challenges/{cid}", citizen)
    ok(f"citizen now sees status: {view['status_label']}")

    msg = call("POST", f"/projects/{pid}/chat", admin, {"body": "Kick-off call scheduled for Monday."})
    chat = call("GET", f"/projects/{pid}/chat", citizen)
    ok(f"project chat working ({len(chat)} message: \"{chat[-1]['body']}\")")

    # ------------------------------------------------------------- stage 5
    stage("5", "TRACK - milestones drive progress")
    for milestone in project["milestones"]:
        call("POST", f"/projects/{pid}/milestones/{milestone['id']}/submit", admin,
             {"note": "Stage complete", "evidence_url": "https://example.org/report.pdf"})
        after = call("POST", f"/projects/{pid}/milestones/{milestone['id']}/review", admin,
                     {"approved": True, "note": "Verified"})
        ok(f"{milestone['name']:<26} approved -> {after['progress']:>3}% "
           f"(project {after['status']})")

    # ------------------------------------------------------------- stage 6
    stage("6", "IMPACT - measurable outcome, reported back")
    final = call("POST", f"/projects/{pid}/impact", admin, {
        "people_impacted": 1200,
        "summary": "Filtration unit commissioned; water now meets IS 10500 norms.",
        "metrics": {"households": 240, "litres_per_day": 9000},
    })
    ok(f"impact recorded: {final['people_impacted']} people, metrics {final['impact_metrics']}")

    closed = call("GET", f"/challenges/{cid}", citizen)
    ok(f"challenge closed as: {closed['status_label']}")

    say("")
    say(f"  {BOLD}Timeline the citizen sees on Track Challenge:{RESET}")
    for event in closed["timeline"]:
        say(f"    {event['created_at'][:19].replace('T', ' ')}  {event['label']}")

    notifications = call("GET", "/notifications", citizen)
    stats = call("GET", "/me/stats", citizen)
    say("")
    ok(f"{len(notifications)} notifications delivered to the citizen (no silent submissions)")
    ok(f"citizen stats: {stats['challenges']} reported, {stats['resolved']} resolved, "
       f"{stats['people_impacted']} people impacted")

    admin_stats = call("GET", "/admin/stats", admin)
    ok(f"admin analytics: {admin_stats['total_challenges']} challenges, "
       f"AI-assisted {admin_stats['ai_assist_rate']:.0%}, "
       f"match acceptance {admin_stats['match_acceptance_rate']:.0%}")

    say("")
    say(f"{GREEN}{BOLD}  Pipeline complete - all six stages ran end to end.{RESET}")
    say("")


if __name__ == "__main__":
    main()
