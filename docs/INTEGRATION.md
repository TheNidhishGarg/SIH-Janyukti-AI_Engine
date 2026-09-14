# Running JanYukti end to end (Flutter app + AI backend)

Firestore remains the app's database. The backend is the AI service the app
calls at `/ai/*`; results are written back onto Firestore challenge documents.

## 1. Backend
    .venv\Scripts\activate
    python -m app.seed
    python -m scripts.ingest_openalex
    python main.py                      # http://localhost:8000/docs

`.env`: `FIREBASE_PROJECT_ID=janyukti-1cbba`, `FIREBASE_AUTH_MODE=off` for local
demos (`required` verifies Firebase ID tokens).

## 2. Flutter app (frontend/)
    flutter pub get
    flutter run                                          # emulator -> http://10.0.2.2:8000
    flutter run --dart-define=AI_API_URL=http://<LAN-IP>:8000   # physical phone

## 3. Firestore rules
`frontend/firestore.rules` now covers `challenges`, `projects` (+ `messages`) and
`industryInterests`. Untested against the emulator; deploy with
`firebase deploy --only firestore:rules` and try one full flow before a demo.

## Demo flow
1. Citizen submits -> duplicate warning if similar -> AI category/priority appear on success screen.
2. Admin opens the challenge -> AI analysis, priority override, ranked registered universities -> assign.
3. University (approved account) sees it -> accept -> project with 5 milestones.
4. University completes milestones -> citizen tracking updates live -> report impact -> Resolved.
5. Industry browses projects -> expresses interest -> project chat.
