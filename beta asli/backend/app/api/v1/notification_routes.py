"""Notification endpoints: create reminders, emergency alerts, scheduled notifications."""

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user
from app.database import get_db
from app.models.notification import NotificationType
from app.models.user import User
from app.repositories.notification_repository import NotificationRepository
from app.schemas.notification import NotificationCreateRequest, NotificationResponse
from app.services.notification_service import NotificationService

router = APIRouter(prefix="/notifications", tags=["notifications"])


@router.post("", response_model=NotificationResponse)
async def create_notification(
    payload: NotificationCreateRequest,
    device_token: str | None = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    service = NotificationService(db)
    return await service.create_notification(
        user_id=current_user.id,
        notification_type=payload.notification_type,
        title=payload.title,
        body=payload.body,
        scheduled_for=payload.scheduled_for,
        device_token=device_token,
    )


@router.get("", response_model=list[NotificationResponse])
async def list_notifications(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    repo = NotificationRepository(db)
    return await repo.list_for_user(current_user.id)


@router.post("/emergency", response_model=NotificationResponse)
async def send_emergency_alert(
    message: str,
    caregiver_tokens: list[str],
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Trigger an emergency SOS notification fanned out to caregiver devices."""
    service = NotificationService(db)
    return await service.send_emergency_alert(
        user_id=current_user.id, message=message, caregiver_tokens=caregiver_tokens
    )
