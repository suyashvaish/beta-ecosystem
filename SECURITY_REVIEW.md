# Security review notes

Findings from the 2026-11 security review will be fixed on this branch.

1. CORS wildcard + credentials (settings.py, main.py)
2. Client-supplied push tokens (elderly_care_routes.py, notification_routes.py)
3. email_verified not checked (auth dependencies)
4. Error detail leakage (firebase.py)
5. STT/TTS input limits (speech_routes.py)

Details tracked in the pull request.
