"""
Firebase Admin SDK wrapper.

Centralizes Firebase initialization and token verification so the rest of
the app never touches the `firebase_admin` package directly. This keeps
the dependency isolated and easy to mock in tests, and easy to swap for
a different identity provider later if needed.
"""

from functools import lru_cache
from typing import Any, Dict

import firebase_admin
from firebase_admin import auth as firebase_auth
from firebase_admin import credentials

from app.config.settings import get_settings
from app.utils.exceptions import AuthenticationError
from app.utils.logging import get_logger

settings = get_settings()
logger = get_logger(__name__)


@lru_cache
def get_firebase_app() -> firebase_admin.App:
    """Initialize (once) and return the Firebase Admin app instance."""
    try:
        cred = credentials.Certificate(settings.FIREBASE_CREDENTIALS_PATH)
        return firebase_admin.initialize_app(
            cred, {"projectId": settings.FIREBASE_PROJECT_ID} if settings.FIREBASE_PROJECT_ID else None
        )
    except ValueError:
        # App already initialized (can happen with reload/hot-restart)
        return firebase_admin.get_app()
    except FileNotFoundError as exc:
        logger.error("Firebase credentials file not found", extra={"extra_fields": {{"path": settings.FIREBASE_CREDENTIALS_PATH}}})
        raise AuthenticationError("Firebase credentials are not configured correctly") from exc


def verify_id_token(id_token: str) -> Dict[str, Any]:
    """
    Verify a Firebase ID token and return its decoded claims.

    Raises AuthenticationError on any invalid/expired/revoked token so
    callers only need to handle a single exception type.

    Client responses are intentionally generic: raw Firebase SDK messages
    can leak internal details (project ids, error hints) and are logged
    server-side instead.
    """
    app = get_firebase_app()
    try:
        decoded_token = firebase_auth.verify_id_token(id_token, app=app, check_revoked=True)
        # Only trust an email the user has verified with Firebase.
        # An unverified email claim must not provision a local identity.
        if decoded_token.get("email") is not None and not decoded_token.get("email_verified", False):
            raise AuthenticationError("Email address is not verified")
        return decoded_token
    except AuthenticationError:
        raise
    except firebase_auth.ExpiredIdTokenError as exc:
        logger.warning(
            "Firebase ExpiredIdTokenError",
            extra={"extra_fields": {"error": str(exc)}},
        )
        raise AuthenticationError("Token has expired") from exc
    except firebase_auth.RevokedIdTokenError as exc:
        logger.error(
            "Firebase RevokedIdTokenError",
            extra={"extra_fields": {"error": str(exc)}},
        )
        raise AuthenticationError("Session has expired, please sign in again") from exc
    except firebase_auth.InvalidIdTokenError as exc:
        logger.error(
            "Firebase InvalidIdTokenError",
            extra={"extra_fields": {"error": str(exc)}},
        )
        raise AuthenticationError("Invalid authentication token") from exc
    except Exception as exc:
        logger.error(
            "Firebase token verification failed",
            extra={"extra_fields": {
                "error_type": type(exc).__name__,
                "error": str(exc),
            }},
        )
        raise AuthenticationError("Authentication failed") from exc


def revoke_refresh_tokens(firebase_uid: str) -> None:
    """Revoke all refresh tokens for a user — used on logout."""
    get_firebase_app()
    firebase_auth.revoke_refresh_tokens(firebase_uid)