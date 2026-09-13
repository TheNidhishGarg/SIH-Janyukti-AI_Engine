# Wiring the Flutter app to this backend

Written for whoever owns the Flutter repo. Nothing here changes a screen — the
UI stays as it is; only the data source moves from `AppStore` to HTTP.

---

## Step 0 — Run the backend

```bash
pip install -r requirements.txt
python -m app.seed
python main.py
```

Open `http://localhost:8000/docs` and confirm you can log in as
`citizen@janyukti.in` / `janyukti123`.

**Reaching it from the app:**

| Target | Base URL |
|---|---|
| Android emulator | `http://10.0.2.2:8000` |
| iOS simulator | `http://localhost:8000` |
| Physical device | `http://<your-laptop-LAN-IP>:8000` |
| Flutter web | `http://localhost:8000` |

Override at build time:
`flutter run --dart-define=API_BASE_URL=http://192.168.1.5:8000`

Android blocks cleartext HTTP by default. For local development add to
`android/app/src/main/AndroidManifest.xml`, on the `<application>` tag:

```xml
android:usesCleartextTraffic="true"
```

---

## Step 1 — Dependencies

```yaml
# pubspec.yaml
dependencies:
  http: ^1.2.0
  shared_preferences: ^2.2.0
```

---

## Step 2 — Copy the API clients

Copy everything from `docs/flutter/` into `lib/apis/`. These replace the five
stub files one-for-one, plus two new ones:

| File | Replaces |
|---|---|
| `api_client.dart` | *(new)* — base URL, token, error handling |
| `auth_api.dart` | the `demoLogin()` stub |
| `challenge_api.dart` | the `ChallengeApi` stub |
| `project_api.dart` | the `ProjectApi` stub |
| `admin_api.dart` | the `AdminApi` stub |
| `industry_api.dart` | the `IndustryApi` stub |
| `university_api.dart` | *(new)* — university inbox |
| `notification_api.dart` | *(new)* — notification bell |

---

## Step 3 — One change to the Challenge model

The backend sends `status_label` — the exact string the UI already renders
("Assigned to BIT Mesra"). `ChallengeJson.fromJson` in `challenge_api.dart`
already maps it onto the existing `status` field, so **no widget changes are
needed**. Keep `status` as a plain `String`.

The one real change is `Project.milestones`: it was `List<String>`, and is now a
list of objects with `{id, name, status}`. You need `id` to submit a milestone.
Display code becomes `milestone.name` instead of the bare string.

---

## Step 4 — Point AppStore at the API

Keep `AppStore` as your state holder — it is `ChangeNotifier`, which is fine.
Change where the data comes from:

```dart
class AppStore extends ChangeNotifier {
  final _challengeApi = ChallengeApi();
  final _projectApi = ProjectApi();

  List<Challenge> challenges = [];
  List<ProjectItem> projects = [];
  bool loading = false;
  String? error;

  Future<void> loadChallenges() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      challenges = await _challengeApi.list(mine: true);
    } on ApiException catch (e) {
      error = e.message;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Was: addChallenge(t, d, cat, l) building a local object.
  Future<Challenge> addChallenge(String t, String d, String cat, String l) async {
    final result = await _challengeApi.submit(
      title: t, description: d, category: cat, location: l,
      analyzeSync: true,   // demo: AI result comes back with the response
    );
    challenges.insert(0, result.challenge);
    notifyListeners();
    return result.challenge;
  }
}
```

Every screen already calls `StoreScope.of(context)`, so they keep working. Add a
loading state and an error state to the list views — that is the only new UI
work, and it is the difference between a demo that feels real and one that
freezes on a slow network.

---

## Step 5 — Login

```dart
// On app start, before routing:
final user = await AuthApi().restoreSession();
// null means no valid token; send them to the welcome screen.

// In the login screen, replacing demoLogin():
try {
  final user = await AuthApi().login(emailController.text, passwordController.text);
  // route by user.role: citizen / university / industry / admin
} on ApiException catch (e) {
  showSnack(e.message);   // "Incorrect email or password"
}
```

The token is persisted in `SharedPreferences` and attached to every request
automatically. On a 401 anywhere, clear it and route back to login.

---

## Step 6 — Two AI touches worth adding

These are small and they are what make the AI visible to a judge.

**A. Live duplicate check.** On the Add Details screen, when the description
field loses focus:

```dart
final dupe = await ChallengeApi().checkDuplicate(
  title: titleController.text,
  description: descController.text,
  location: selectedLocation,
);
if (dupe != null) {
  // "Someone nearby already reported this: <dupe['title']>. Follow it instead?"
}
```

Preventing the duplicate beats cleaning it up later, and it visibly demonstrates
the duplicate model on screen.

**B. Category dropdown from the server.** Replace the hardcoded list with
`ChallengeApi().categories()` so the taxonomy stays in one place.

---

## Step 7 — The admin screen is where the AI shows

`GET /admin/queue` returns everything in one call: the challenge, its AI
analysis, and the ranked universities.

```dart
final queue = await AdminApi().queue();

for (final item in queue) {
  item.ai?.category;      // "Water Management"
  item.ai?.confidence;    // 0.86  -> show as a percentage
  item.ai?.priority;      // "High"
  item.ai?.rationale;     // "Driven by severity (5/5): contaminat, disease."
  item.ai?.duplicateOf;   // non-null -> show a duplicate banner

  for (final match in item.matches) {
    match.name;           // "BIT Mesra"
    match.department;     // "Department of Civil & Environmental Engineering"
    match.matchPercent;   // 78
    match.reasons;        // ["Strong expertise match (71% similarity)", ...]
    match.activeProjects; // 2 of
    match.capacity;       // 5
  }
}

// Assign, confirming or overriding the top suggestion:
await AdminApi().assign(challengeId, selectedUniversityId);
```

**Show `match.reasons` in the UI.** A ranked list with no explanation looks like
a guess; the same list with "3 of 5 project slots free, located in Ranchi" looks
like a system. It is also the honest thing to do — the admin is confirming a
recommendation, not obeying one.

---

## Step 8 — Track Challenge screen

`GET /challenges/{id}` returns `timeline`, which maps straight onto the existing
vertical stepper:

```dart
final detail = await ChallengeApi().get('CH-2026-00001');
for (final event in detail.timeline) {
  event.label;   // "Submitted" / "AI analysis complete" / "Assigned to BIT Mesra"
  event.detail;  // longer explanation, or null
  event.at;      // DateTime
}
```

No more hardcoded dates.

---

## Demo script (5 minutes, live)

1. **Citizen** submits a water contamination report with a photo.
2. The submit response already carries the AI read: category, priority **with
   its rubric**, and the ranked universities. Show the rationale line.
3. **Admin** opens the queue, sees the suggestion, and assigns — either
   confirming or overriding. Show a `reasons` list on screen.
4. **University** sees it in the inbox, accepts, and the project workspace
   appears with five milestones.
5. University submits a milestone, admin approves, and **progress moves on the
   citizen screen in real time**.
6. Report impact. The challenge closes as Resolved and the citizen's
   "people impacted" counter updates.
7. Submit a **near-duplicate** of step 1 and watch it get caught.

Step 7 is the one judges remember. `tests/test_workflow.py` runs steps 1 to 6
automatically if you would rather show a green test run than click through.
