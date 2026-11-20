<!--
Family Talk (Feature C UI) - walkie-talkie voice notes.

AndroidManifest additions needed by the `record` and `just_audio`
plugins: raw microphone recording (RECORD_AUDIO) and plain-HTTP
playback while the backend runs on the LAN in development
(usesCleartextTraffic, dev only - remove for release).
-->

<!-- Runtime mic permission for voice-note recording (Family Talk) -->
<uses-permission android:name="android.permission.RECORD_AUDIO" />

