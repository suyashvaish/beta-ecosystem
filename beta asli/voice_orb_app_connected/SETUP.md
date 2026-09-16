# Connecting the Flutter app to the Beta backend

## What changed

**Backend** (`beta-backend.zip`) — two files patched:
- `app/services/chat_service.py` — added `begin_turn()` / `stream_reply_and_persist()`
- `app/api/v1/chat_routes.py` — `POST /chat/stream` now sends the `conversation_id`
  as the *first* SSE event (`event: conversation`), before any text chunks, and
  frames each chunk as JSON (`data: {"text": "..."}`) instead of raw text. This was
  a real gap: without it, the app has no way to keep a streamed reply in the same
  conversation as the next message.

**Frontend** — the original `main.dart` was just UI (no networking, no auth). It's
now a real app with STT/TTS and a multi-turn chat UI, not just the orb screen:

```
lib/
├── main.dart                    # Firebase init + auth-state routing
├── firebase_options.dart        # PLACEHOLDER — see step 1 below
├── config/api_config.dart       # backend base URL
├── models/chat_message.dart     # chat message model (role / status / text)
├── services/
│   ├── auth_service.dart        # Firebase Auth + POST /auth/sign-in
│   ├── chat_api_service.dart    # POST /chat/stream, SSE parsing
│   └── settings_service.dart    # persisted settings (backend URL override, etc.)
├── screens/
│   ├── login_screen.dart        # email/password sign in / sign up
│   ├── settings_screen.dart     # settings UI
│   └── voice_home_page.dart     # orb + chat screen — real STT/TTS, a hands-free
│                                 # voice loop, and a real multi-turn chat list
└── widgets/
    ├── voice_orb.dart           # state-aware (idle/listening/processing/
    │                             # speaking/error), reusable at any size
    ├── chat_message_bubble.dart # one row in the chat list
    └── typing_indicator.dart    # animated "..." while a reply is composing
```

Before the first message is sent, the screen shows the big orb ("Tap to talk to
Beta"). Once a conversation starts, it crossfades into a real chat list (user
bubbles + Beta's plain-text replies, streamed in live), and the orb shrinks to a
small live-state badge in the top bar. Real speech-to-text (`speech_to_text`)
and text-to-speech (`flutter_tts`) are wired up: tapping the orb/mic starts
listening, a final result sends the message, and once Beta finishes speaking it
automatically starts listening again for the next turn (a single "didn't catch
that" drops back to idle rather than retrying forever).

## Steps to actually run this

1. **Firebase project** (required — `firebase_options.dart` is a non-functional
   placeholder right now):
   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```
   This overwrites `lib/firebase_options.dart` with real values and drops the
   platform config files (`google-services.json`, `GoogleService-Info.plist`)
   in place. In the Firebase console, enable **Authentication → Sign-in
   method → Email/Password**.

2. **Platform scaffolding** — `files.zip` only contained `main.dart` +
   `pubspec.yaml`, no `android/`/`ios/` folders. If you don't already have
   those from a previous `flutter create`, run `flutter create .` from the
   project root *before* `flutterfire configure`, so there's something for it
   to wire into.

3. **Backend running and reachable:**
   ```bash
   cd beta-backend && docker compose up --build
   ```
   Then set `lib/config/api_config.dart`'s `baseUrl` for your setup (Android
   emulator vs iOS simulator vs physical device — see comments in that file).

4. **Install and run:**
   ```bash
   flutter pub get
   flutter run
   ```

5. Sign up with an email/password on the login screen, then type a message —
   it should stream back and animate the orb.

## Known gaps, not covered by this pass

- The backend's OpenAI-based `/speech` module exists but the app doesn't call
  it — speech-to-text happens on-device via the `speech_to_text` plugin
  instead, so that endpoint is currently dead code (fine to leave, or remove
  if you want one fewer thing to maintain)
- Push notifications (backend has FCM client + models; nothing calls it from
  the app yet) — no local-notifications package either, so medicine alarms
  have nothing to schedule on yet
- Location sharing and health-band/BLE — no code or dependencies on the
  Flutter side yet
- Any of the elderly-care-specific screens (medication, SOS, caregiver) —
  chat/voice is the only screen; **Beta Care doesn't exist as a project at
  all yet** (it's not part of `beta_asli`/this Flutter app - see the chat
  history for what was found there)
