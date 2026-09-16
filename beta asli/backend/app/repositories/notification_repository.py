"""Data access for the Notification model."""

import uuid
from datetime import datetime
from typing import Optional, Sequence

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.notification import Notification, NotificationStatus, NotificationType


class NotificationRepository:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def create(
        self,
        user_id: uuid.UUID,
        notification_type: NotificationType,
        title: str,
        body: str,
        scheduled_for: Optional[datetime] = None,
    ) -> Notification:
        notification = Notification(
            user_id=user_id,
            notification_type=notification_type,
            title=title,
            body=body,
            scheduled_for=scheduled_for,
        )
        self.db.add(notification)
        await self.db.flush()
        await self.db.refresh(notification)
        return notification

    async def list_for_user(self, user_id: uuid.UUID) -> Sequence[Notification]:
        result = await self.db.execute(
            select(Notification)
            .where(Notification.user_id == user_id)
            .order_by(Notification.created_at.desc())
        )
        return result.scalars().all()

    async def get_due(self, before: datetime) -> Sequence[Notification]:
        result = await self.db.execute(
            select(Notification).where(
                Notification.status == NotificationStatus.pending,
                Notification.scheduled_for <= before,
            )
        )
        return result.scalars().all()

    async def mark_sent(self, notification: Notification) -> None:
        notification.status = NotificationStatus.sent
        notification.sent_at = datetime.utcnow()
        await self.db.flush()

    async def mark_failed(self, notification: Notification) -> None:
        notification.status = NotificationStatus.failed
        await self.db.flush()
