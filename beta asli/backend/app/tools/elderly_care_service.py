"""
Elderly-care orchestration service.

Wraps the notification and health-record repositories/services into
higher-level, domain-specific operations. Hardware-integration points
(fall detection sensors, wearable vitals) are placeholders — they define
the method signature and persistence behavior now, so hardware can be
wired in later without changing calling code or the database schema.
"""

import uuid
from datetime import datetime
from typing import Optional, Sequence

from sqlalchemy.ext.asyncio import AsyncSession

from app.models.caregiver import Caregiver, CaregiverAccessLevel
from app.models.health_record import HealthRecord, HealthRecordType
from app.models.notification import NotificationType
from app.repositories.notification_repository import NotificationRepository
from app.services.notification_service import NotificationService
from app.utils.logging import get_logger

logger = get_logger(__name__)


class ElderlyCareService:
    def __init__(self, db: AsyncSession):
        self.db = db
        self.notification_service = NotificationService(db)
        self.notification_repo = NotificationRepository(db)

    async def schedule_medication_reminder(
        self,
        user_id: uuid.UUID,
        medication_name: str,
        dosage: str,
        scheduled_for: datetime,
        device_token: Optional[str] = None,
    ):
        return await self.notification_service.create_notification(
            user_id=user_id,
            notification_type=NotificationType.medication_reminder,
            title="Medication Reminder",
            body=f"Time to take {medication_name} ({dosage}).",
            scheduled_for=scheduled_for,
            device_token=device_token,
        )

    async def schedule_appointment_reminder(
        self,
        user_id: uuid.UUID,
        appointment_description: str,
        scheduled_for: datetime,
        device_token: Optional[str] = None,
    ):
        return await self.notification_service.create_notification(
            user_id=user_id,
            notification_type=NotificationType.appointment_reminder,
            title="Upcoming Appointment",
            body=appointment_description,
            scheduled_for=scheduled_for,
            device_token=device_token,
        )

    async def trigger_emergency_sos(
        self, user_id: uuid.UUID, message: str, caregiver_tokens: Sequence[str]
    ):
        """Triggered by a voice command, panic button, or fall-detection event."""
        logger.warning(
            "Emergency SOS triggered", extra={"extra_fields": {"user_id": str(user_id)}}
        )
        return await self.notification_service.send_emergency_alert(
            user_id=user_id, message=message, caregiver_tokens=caregiver_tokens
        )

    async def record_fall_detection_event(
        self, user_id: uuid.UUID, sensor_payload: dict, caregiver_tokens: Sequence[str]
    ) -> HealthRecord:
        """
        Placeholder ingestion point for a fall-detection hardware event.

        Real hardware integration (wearable SDK, sensor fusion) would call
        this method with `sensor_payload` containing whatever the device
        reports (impact force, orientation change, etc.). For now we persist
        the raw payload and immediately raise an SOS.
        """
        record = HealthRecord(
            user_id=user_id,
            record_type=HealthRecordType.fall_detection_event,
            data=sensor_payload,
            notes="Auto-detected fall event",
        )
        self.db.add(record)
        await self.db.flush()
        await self.db.refresh(record)

        await self.trigger_emergency_sos(
            user_id=user_id,
            message="A possible fall has been detected. Please check in immediately.",
            caregiver_tokens=caregiver_tokens,
        )
        return record

    async def record_wellness_check_in(
        self, user_id: uuid.UUID, mood: str, notes: str = ""
    ) -> HealthRecord:
        record = HealthRecord(
            user_id=user_id,
            record_type=HealthRecordType.wellness_check_in,
            data={"mood": mood},
            notes=notes,
        )
        self.db.add(record)
        await self.db.flush()
        await self.db.refresh(record)
        return record

    async def add_caregiver(
        self,
        cared_for_user_id: uuid.UUID,
        caregiver_name: str,
        caregiver_email: Optional[str] = None,
        caregiver_phone: Optional[str] = None,
        access_level: CaregiverAccessLevel = CaregiverAccessLevel.view_only,
    ) -> Caregiver:
        caregiver = Caregiver(
            cared_for_user_id=cared_for_user_id,
            caregiver_name=caregiver_name,
            caregiver_email=caregiver_email,
            caregiver_phone=caregiver_phone,
            access_level=access_level,
        )
        self.db.add(caregiver)
        await self.db.flush()
        await self.db.refresh(caregiver)
        return caregiver
