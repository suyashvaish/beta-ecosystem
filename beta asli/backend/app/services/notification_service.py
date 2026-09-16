"""
Notification service.

Provides higher-level operations used by API routes and future elderly-care
modules (medication reminders, emergency SOS, wellness check-ins). Persists
every notification to the database first (source of truth + audit trail),
then attempts delivery via FCM. Delivery failures don't lose the record —
they just mark it `failed` so it can be retried or escalated.
"""

import uuid
from datetime import datetime
from typing import Optional, Sequence

from sqlalchemy.ext.asyncio import AsyncSession

from app.models.notification import Notification, NotificationType
from app.notifications.fcm_client import PushNotificationError, send_push
from app.repositories.notification_repository import NotificationRepository
from app.utils.logging import get_logger

logger = get_logger(__name__)


class NotificationService:
    def __init__(self, db: AsyncSession):
        self.db = db
        self.repo = NotificationRepository(db)

    async def create_notification(
        self,
        user_id: uuid.UUID,
        notification_type: NotificationType,
        title: str,
        body: str,
        scheduled_for: Optional[datetime] = None,
        device_token: Optional[str] = None,
    ) -> Notification:
        notification = await self.repo.create(
            user_id=user_id,
            notification_type=notification_type,
            title=title,
            body=body,
            scheduled_for=scheduled_for,
        )

        # Send immediately unless it's scheduled for the future.
        if scheduled_for is None and device_token:
            await self._deliver(notification, device_token)

        return notification

    async def _deliver(self, notification: Notification, device_token: str) -> None:
        try:
            send_push(
                device_token=device_token,
                title=notification.title,
                body=notification.body,
                data={"notification_type": notification.notification_type.value},
            )
            await self.repo.mark_sent(notification)
        except PushNotificationError:
            await self.repo.mark_failed(notification)

    async def send_emergency_alert(
        self, user_id: uuid.UUID, message: str, caregiver_tokens: Sequence[str]
    ) -> Notification:
        """
        Emergency SOS: highest-priority notification, fanned out to all
        registered caregiver devices in addition to being logged for the user.
        """
        notification = await self.repo.create(
            user_id=user_id,
            notification_type=NotificationType.emergency,
            title="Emergency Alert",
            body=message,
        )
        for token in caregiver_tokens:
            try:
                send_push(
                    device_token=token,
                    title="🚨 Emergency Alert",
                    body=message,
                    data={"notification_type": NotificationType.emergency.value},
                )
            except PushNotificationError:
                logger.error(
                    "Failed to notify caregiver device during emergency",
                    extra={"extra_fields": {"user_id": str(user_id)}},
                )
        await self.repo.mark_sent(notification)
        return notification

    async def process_due_notifications(self, device_token_resolver) -> int:
        """
        Deliver all notifications whose `scheduled_for` time has passed.

        `device_token_resolver` is a callable(user_id) -> Optional[str],
        injected so this service doesn't need to know how device tokens are
        stored (kept generic since that's outside the current model set).
        Intended to be invoked periodically by a scheduler/cron job.
        """
        due = await self.repo.get_due(before=datetime.utcnow())
        delivered = 0
        for notification in due:
            token = await device_token_resolver(notification.user_id)
            if token:
                await self._deliver(notification, token)
                delivered += 1
            else:
                await self.repo.mark_failed(notification)
        return delivered
