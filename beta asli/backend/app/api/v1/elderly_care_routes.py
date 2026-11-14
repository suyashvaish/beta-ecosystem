"""
Elderly-care endpoints.

Covers medication/appointment reminders, emergency SOS, fall-detection
event ingestion, wellness check-ins, and caregiver management. These are
designed to be called either directly by the Flutter app, by Beta's own
voice-command handling, or (for fall detection) by hardware/wearable
integrations in the future.

SECURITY: this module never accepts caregiver FCM device tokens from the
client. Tokens are resolved server-side from registered caregivers - a
client-supplied token list would let any user push arbitrary alerts to
any device (push-injection relay).
"""

from datetime import datetime

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field, StringConstraints
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user
from app.database import get_db
from app.models.caregiver import CaregiverAccessLevel
from app.models.user import User
from app.tools.elderly_care_service import ElderlyCareService
from app.repositories.caregiver_repository import CaregiverRepository

router = APIRouter(prefix="/elderly-care", tags=["elderly-care"])


def get_elderly_care_service(db: AsyncSession = Depends(get_db)) -> ElderlyCareService:
    return ElderlyCareService(db)


class MedicationReminderRequest(BaseModel):
    medication_name: str = Field(..., min_length=1, max_length=200)
    dosage: str = Field(..., min_length=1, max_length=100)
    scheduled_for: datetime


class AppointmentReminderRequest(BaseModel):
    description: str = Field(..., min_length=1, max_length=500)
    scheduled_for: datetime


class SosRequest(BaseModel):
    message: str = Field(..., min_length=1, max_length=500)


class FallDetectionEventRequest(BaseModel):
    sensor_payload: dict = Field(..., description="Raw sensor readings; stored as-is")
    caregiver_tokens: list[str] = Field(
        default_factory=list,
        max_length=20,
        description="DEPRECATED - ignored. Caregiver tokens are resolved server-side.",
    )


class WellnessCheckInRequest(BaseModel):
    mood: str = Field(..., min_length=1, max_length=50)
    notes: str = Field(default="", max_length=2000)


class CaregiverRequest(BaseModel):
    caregiver_name: str = Field(..., min_length=1, max_length=200)
    caregiver_email: str | None = Field(default=None, max_length=320)
    caregiver_phone: str | None = Field(default=None, max_length=30)
    access_level: CaregiverAccessLevel = CaregiverAccessLevel.view_only


async def _registered_caregiver_tokens(
    db: AsyncSession, user_id: User
) -> list[str]:
    """Resolve caregiver FCM tokens server-side. Client never supplies them."""
    repo = CaregiverRepository(db)
    caregivers = await repo.list_for_cared_for_user(user_id.id)
    tokens: list[str] = []
    for caregiver in caregivers:
        token = getattr(caregiver, "fcm_device_token", None)
        if token:
            tokens.append(token)
    return tokens


@router.post("/medication-reminders")
async def create_medication_reminder(
    payload: MedicationReminderRequest,
    current_user: User = Depends(get_current_user),
    service: ElderlyCareService = Depends(get_elderly_care_service),
):
    return await service.schedule_medication_reminder(
        user_id=current_user.id,
        medication_name=payload.medication_name,
        dosage=payload.dosage,
        scheduled_for=payload.scheduled_for,
    )


@router.post("/appointment-reminders")
async def create_appointment_reminder(
    payload: AppointmentReminderRequest,
    current_user: User = Depends(get_current_user),
    service: ElderlyCareService = Depends(get_elderly_care_service),
):
    return await service.schedule_appointment_reminder(
        user_id=current_user.id,
        appointment_description=payload.description,
        scheduled_for=payload.scheduled_for,
    )


@router.post("/sos")
async def trigger_sos(
    payload: SosRequest,
    current_user: User = Depends(get_current_user),
    service: ElderlyCareService = Depends(get_elderly_care_service),
    db: AsyncSession = Depends(get_db),
):
    caregiver_tokens = await _registered_caregiver_tokens(db, current_user)
    return await service.trigger_emergency_sos(
        user_id=current_user.id, message=payload.message, caregiver_tokens=caregiver_tokens
    )


@router.post("/fall-detection-events")
async def report_fall_detection_event(
    payload: FallDetectionEventRequest,
    current_user: User = Depends(get_current_user),
    service: ElderlyCareService = Depends(get_elderly_care_service),
    db: AsyncSession = Depends(get_db),
):
    """
    Placeholder ingestion endpoint for wearable/sensor fall-detection
    hardware. Persists the event and immediately raises an SOS to the
    registered caregivers (tokens resolved server-side).
    """
    caregiver_tokens = await _registered_caregiver_tokens(db, current_user)
    return await service.record_fall_detection_event(
        user_id=current_user.id,
        sensor_payload=payload.sensor_payload,
        caregiver_tokens=caregiver_tokens,
    )


@router.post("/wellness-check-ins")
async def create_wellness_check_in(
    payload: WellnessCheckInRequest,
    current_user: User = Depends(get_current_user),
    service: ElderlyCareService = Depends(get_elderly_care_service),
):
    return await service.record_wellness_check_in(
        user_id=current_user.id, mood=payload.mood, notes=payload.notes
    )


@router.post("/caregivers")
async def add_caregiver(
    payload: CaregiverRequest,
    current_user: User = Depends(get_current_user),
    service: ElderlyCareService = Depends(get_elderly_care_service),
):
    return await service.add_caregiver(
        cared_for_user_id=current_user.id,
        caregiver_name=payload.caregiver_name,
        caregiver_email=payload.caregiver_email,
        caregiver_phone=payload.caregiver_phone,
        access_level=payload.access_level,
    )