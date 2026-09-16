"""
Elderly-care endpoints.

Covers medication/appointment reminders, emergency SOS, fall-detection
event ingestion, wellness check-ins, and caregiver management. These are
designed to be called either directly by the Flutter app, by Beta's own
voice-command handling, or (for fall detection) by hardware/wearable
integrations in the future.
"""

import uuid
from datetime import datetime

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user
from app.database import get_db
from app.models.caregiver import CaregiverAccessLevel
from app.models.user import User
from app.tools.elderly_care_service import ElderlyCareService

router = APIRouter(prefix="/elderly-care", tags=["elderly-care"])


def get_elderly_care_service(db: AsyncSession = Depends(get_db)) -> ElderlyCareService:
    return ElderlyCareService(db)


@router.post("/medication-reminders")
async def create_medication_reminder(
    medication_name: str,
    dosage: str,
    scheduled_for: datetime,
    device_token: str | None = None,
    current_user: User = Depends(get_current_user),
    service: ElderlyCareService = Depends(get_elderly_care_service),
):
    return await service.schedule_medication_reminder(
        user_id=current_user.id,
        medication_name=medication_name,
        dosage=dosage,
        scheduled_for=scheduled_for,
        device_token=device_token,
    )


@router.post("/appointment-reminders")
async def create_appointment_reminder(
    description: str,
    scheduled_for: datetime,
    device_token: str | None = None,
    current_user: User = Depends(get_current_user),
    service: ElderlyCareService = Depends(get_elderly_care_service),
):
    return await service.schedule_appointment_reminder(
        user_id=current_user.id,
        appointment_description=description,
        scheduled_for=scheduled_for,
        device_token=device_token,
    )


@router.post("/sos")
async def trigger_sos(
    message: str,
    caregiver_tokens: list[str],
    current_user: User = Depends(get_current_user),
    service: ElderlyCareService = Depends(get_elderly_care_service),
):
    return await service.trigger_emergency_sos(
        user_id=current_user.id, message=message, caregiver_tokens=caregiver_tokens
    )


@router.post("/fall-detection-events")
async def report_fall_detection_event(
    sensor_payload: dict,
    caregiver_tokens: list[str],
    current_user: User = Depends(get_current_user),
    service: ElderlyCareService = Depends(get_elderly_care_service),
):
    """
    Placeholder ingestion endpoint for wearable/sensor fall-detection
    hardware. Persists the event and immediately raises an SOS.
    """
    return await service.record_fall_detection_event(
        user_id=current_user.id,
        sensor_payload=sensor_payload,
        caregiver_tokens=caregiver_tokens,
    )


@router.post("/wellness-check-ins")
async def create_wellness_check_in(
    mood: str,
    notes: str = "",
    current_user: User = Depends(get_current_user),
    service: ElderlyCareService = Depends(get_elderly_care_service),
):
    return await service.record_wellness_check_in(
        user_id=current_user.id, mood=mood, notes=notes
    )


@router.post("/caregivers")
async def add_caregiver(
    caregiver_name: str,
    caregiver_email: str | None = None,
    caregiver_phone: str | None = None,
    access_level: CaregiverAccessLevel = CaregiverAccessLevel.view_only,
    current_user: User = Depends(get_current_user),
    service: ElderlyCareService = Depends(get_elderly_care_service),
):
    return await service.add_caregiver(
        cared_for_user_id=current_user.id,
        caregiver_name=caregiver_name,
        caregiver_email=caregiver_email,
        caregiver_phone=caregiver_phone,
        access_level=access_level,
    )
