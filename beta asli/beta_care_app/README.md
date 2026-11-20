# Beta Care

The family-side app of the Beta ecosystem: sign in with your own
account, pick the elder you care for, and talk to them with
walkie-talkie voice notes and text messages (Family Talk, Feature C).

Shares the backend and the Firebase project (`beta-ai-bbc28`) with the
elder-side **Beta Asli** app in `../voice_orb_app_connected/`.

## Setup

```bash
flutter create . --org com.example --project-name beta_care_app \
  --platforms android,ios
flutter pub get
```

(`flutter create .` generates the missing `android/` and `ios/` folders
once; lib/, pubspec.yaml and firebase_options.dart are already here.)

## Run (development)

The backend must be running on the LAN first (from `../backend/`):

```bash
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Then, with your Mac's IP:

```bash
flutter run --dart-define=API_BASE_URL=http://<mac-ip>:8000
```

## Joining a circle

Family members join an elder's circle by invite code:

- The elder's side (Beta Asli) or an existing caregiver creates an
  invitation via `POST /care-circles/invitations`
- The new caregiver accepts via `POST /care-circles/invitations/accept`
  with `invite_code` + `accepting_name`

Until an app screen exists for invites, accept from a terminal:

```bash
curl -X POST http://<mac-ip>:8000/api/v1/care-circles/invitations/accept \
  -H "Authorization: Bearer <your-id-token>" \
  -H "Content-Type: application/json" \
  -d '{"invite_code": "CODE", "accepting_name": "Suyash"}'
```

Once accepted, `GET /care-circles/my-elders` returns the elder and the
Family Talk screen becomes usable.

## Android dev note

Like the Asli app, the generated AndroidManifest needs cleartext
traffic enabled for the LAN backend in development. See the note in
`../voice_orb_app_connected/android/app/src/main/AndroidManifest.xml`
and the `android:usesCleartextTraffic="true"` line - remove before any
release build.