# Why STT/TTS is not working — root-cause analysis and fixes

## Summary

The voice pipeline in `lib/screens/voice_home_page.dart` was reviewed end
to end. The reported failures — `doneNoResult`, `error_no_match`,
"permanent recognition errors", and recognition timeouts despite audio
levels — are caused by four distinct bugs, not one. None of them are in
the backend; all are in the app layer. `lib/services/voice_controller.dart`
on this branch is the fixed pipeline; integration steps are at the end.

## Root cause 1 — No runtime microphone permission request

Symptom: permanent recognition errors, `initialize()` failing every time,
or `listen()` throwing.

Android 6+ requires `RECORD_AUDIO` to be granted at runtime. The manifest
has the line, but nothing in the app ever calls
`Permission.microphone.request()`. Worse: if the OS dialog was denied once,
Android remembers and `speech_to_text`'s own permission path fails
silently from then on — matching the "permanent errors".

Fix: `VoiceController.initialize()` requests the permission explicitly,
distinguishes `isPermanentlyDenied` (tells the user to fix it in Settings),
and blocks STT init until the grant is real.

## Root cause 2 — The hands-free loop dies on every empty result

Symptom: `doneNoResult`, then the assistant stops listening and never
comes back.

In `_handleSpeechStatus`, when the recognizer ended without speech
(`done`/`notListening`), the old code only cleared the audio level —
it never re-armed listening, even while `_voiceSessionActive` was true.
Every `doneNoResult` or `error_no_match` (extremely common with background
noise, or when the user pauses before speaking) silently killed the
session.

Fix: on an empty result during a hands-free session, the controller
restarts listening automatically — bounded to 2 consecutive empty results
so a dead mic cannot loop forever, with a 350ms gap before re-listening
(immediate re-listen calls are a known source of permanent recognizer
errors on Android).

## Root cause 3 — The audio level was fake

Symptom: orb pulses and shows levels, but recognition never happens;
timeouts "despite audio levels".

`_bumpForSpeech()` and `_bumpForChunk()` are random number generators —
`0.15 + _rand.nextDouble() * 0.35` — fired on every partial result and
stream chunk, then decayed by a ticker. The orb animation has no
connection to the microphone at all. It was pulsing on fake data, which
is exactly why "audio levels" were visible while the recognizer
captured nothing.

Fix: the level now comes from `SpeechToText.initialize()`'s
`onSoundLevelChange` callback — real dB readings from the device mic.

## Root cause 4 — TTS resolving without actually speaking

Symptom: "TTS FINISHED" in the logs, no audible speech.

`awaitSpeakCompletion(true)` + `await _tts.speak(text)` resolving is not
proof that audio played. On devices with a missing or broken TTS engine
(and on most emulators, which ship without one), `speak()` resolves
immediately and nothing is audible. The old code had no
start/completion/error handlers, so it logged "TTS FINISHED" on a silent
failure every time.

Fix: `VoiceController.speak()` registers start/completion/error handlers,
and only treats the response as spoken once the platform start event
actually fires, with a 5s timeout that surfaces a real, actionable error
("Check that your device has a TTS engine enabled") instead of a silent
pass-through.

## Secondary issues also fixed

- `pauseFor: 5s` to 3s: elderly users pause mid-sentence; a 5s pause
  window plus the `listenFor: 30s` cap produced many of the
  `error_speech_timeout` hits. 3s keeps turns flowing while still being
  forgiving.
- `error_no_match` / `error_speech_timeout` are expected events (nothing
  intelligible captured), not faults. They now restart listening instead
  of dropping to a generic error state.
- Network failure during recognition (Android's recognizer is a Google
  network service) is now reported as a real connectivity error.

## How to wire VoiceController into voice_home_page.dart

Minimal changes — the chat/stream/UI code stays exactly as it is:

1. Replace the `SpeechToText _speech` + `FlutterTts _tts` fields with one
   `VoiceController _voice`.

2. Delete these now-dead helpers (they contained bugs 2 and 3):
   `_initializeVoice`, `_handleSpeechStatus`, `_handleSpeechError`,
   `_startListening`, `_handleSpeechResult`, `_stopListening`,
   `_speakAssistantResponse`, `_bumpForSpeech`, `_bumpForChunk`,
   `_startAudioDecay` and the `_decayTicker`.

3. In `initState()`:

   ```dart
   _voice = VoiceController(
     onStateChanged: (s) => setState(() {
       _state = switch (s) {
         VoiceState.idle => _AssistantState.idle,
         VoiceState.listening => _AssistantState.idle, // shows 'Listening...' caption
         VoiceState.processing => _AssistantState.thinking,
         VoiceState.speaking => _AssistantState.speaking,
         VoiceState.error => _AssistantState.error,
       };
     }),
     onLevelChanged: (level) => _setAudioLevel(level),
     onPartialTranscript: (t) { /* update _inputController */ },
     onFinalTranscript: (t) => _sendMessage(text: t, viaVoice: true),
     onError: (m) => setState(() => _errorMessage = m),
   );
   ```

4. Orb tap: `await _voice.startListening(handsFree: true);`
   (instead of `_startListening(userInitiated: true)`).

5. After the stream completes (`ChatStreamDone`):

   ```dart
   final bool spoke = await _voice.speak(response);
   if (spoke && viaVoice) {
     await _voice.startListening(handsFree: true); // re-arm the loop
   }
   ```

6. `dispose()`: `await _voice.dispose();`

## Device-side checklist (do this before debugging further)

| Check | Why |
|---|---|
| Test on a physical Android device | Emulators usually have no speech recognition service and no TTS engine — this alone explains most "not working" reports |
| Settings, Apps, Beta, Permissions: Microphone Allow | Clears the "permanently denied" state |
| Settings, Text-to-speech output: install/enable Google TTS | Fixes silent `speak()` |
| Working internet connection | Android's recognizer is a network service; offline means guaranteed `error_no_match`/network errors |

## What was NOT changed

Per the project instructions: the backend, the SSE chat stream
(`chat_api_service.dart`), auth, and all UI animation code remain
untouched. The backend `/speech` endpoints were only hardened with
input limits; the app still does STT on-device.
