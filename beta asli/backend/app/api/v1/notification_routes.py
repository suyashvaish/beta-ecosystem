"""
Notification endpoints: create reminders, emergency alerts, scheduled notifications.

SECURITY: caregiver push tokens are never accepted from clients. Emergency
alerts are fanned out to tokens resolved server-side from registered
caregivers - accepting client-supplied tokens would let any user push
arbitrary alerts to arbitrary devices.
"""

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user
from app.database import get_db
from app.models.user import User
from app.repositories.notification_repository import NotificationRepository
from app.repositories.caregiver_repository import CaregiverRepository
from app.schemas.notification import NotificationCreateRequest, NotificationResponse
from app.services.notification_service import NotificationService

router = APIRouter(prefix="/notifications", tags=["notifications"])


async def _registered_caregiver_tokens(db: AsyncSession, user_id) -> list[str]:
    repo = CaregiverRepository(db)
    caregivers = await repo.list_for_cared_for_user(user_id)
    tokens: list[str] = []
    for caregiver in caregivers:
        token = getattr(caregiver, "fcm_device_token", None)
        if token:
            tokens.append(token)
    return tokens


@router.post("", response_model=NotificationResponse)
async def create_notification(
    payload: NotificationCreateRequest,
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
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Trigger an emergency SOS notification fanned out to caregiver devices."""
    caregiver_tokens = await _registered_caregiver_tokens(db, current_user.id)
    service = NotificationService(db)
    return await service.send_emergency_alert(
        user_id=current_user.id, message=message, caregiver_tokens=caregiver_tokens
    )