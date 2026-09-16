"""Schemas for notification endpoints."""

import uuid
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field

from app.models.notification import NotificationStatus, NotificationType


class NotificationCreateRequest(BaseModel):
    notification_type: NotificationType
    title: str = Field(..., max_length=255)
    body: str
    scheduled_for: Optional[datetime] = None


class NotificationResponse(BaseModel):
    id: uuid.UUID
    notification_type: NotificationType
    title: str
    body: str
    status: NotificationStatus
    scheduled_for: Optional[datetime]
    sent_at: Optional[datetime]
    created_at: datetime

    model_config = {"from_attributes": True}
