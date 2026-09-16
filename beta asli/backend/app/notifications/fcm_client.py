"""
Firebase Cloud Messaging client wrapper.

Isolates the `firebase_admin.messaging` API so the rest of the app depends
only on this module's simple `send_push` function. This makes it easy to
mock in tests and to swap for another push provider (APNs directly, OneSignal,
etc.) later without touching calling code.
"""

from typing import Optional

from firebase_admin import messaging

from app.auth.firebase import get_firebase_app
from app.utils.exceptions import AppError
from app.utils.logging import get_logger

logger = get_logger(__name__)


class PushNotificationError(AppError):
    status_code = 502
    default_message = "Failed to send push notification"


def send_push(
    device_token: str,
    title: str,
    body: str,
    data: Optional[dict] = None,
) -> str:
    """
    Send a single push notification via FCM.

    Returns the FCM message ID on success. Raises PushNotificationError on
    failure (invalid token, FCM outage, etc.) so callers can decide whether
    to retry, mark the notification failed, or fall back to another channel.
    """
    get_firebase_app()
    message = messaging.Message(
        notification=messaging.Notification(title=title, body=body),
        data={k: str(v) for k, v in (data or {}).items()},
        token=device_token,
    )
    try:
        return messaging.send(message)
    except Exception as exc:  # noqa: BLE001
        logger.error(
            "FCM send failed",
            extra={"extra_fields": {"error": str(exc), "title": title}},
        )
        raise PushNotificationError(f"Could not deliver push notification: {exc}") from exc


def send_multicast(
    device_tokens: list[str], title: str, body: str, data: Optional[dict] = None
) -> messaging.BatchResponse:
    """Send the same notification to multiple devices (e.g. all caregivers)."""
    get_firebase_app()
    message = messaging.MulticastMessage(
        notification=messaging.Notification(title=title, body=body),
        data={k: str(v) for k, v in (data or {}).items()},
        tokens=device_tokens,
    )
    try:
        return messaging.send_multicast(message)
    except Exception as exc:  # noqa: BLE001
        logger.error("FCM multicast send failed", extra={"extra_fields": {"error": str(exc)}})
        raise PushNotificationError(f"Could not deliver multicast notification: {exc}") from exc
