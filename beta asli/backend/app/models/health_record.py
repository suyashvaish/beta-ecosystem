"""
Health record model.

Placeholder storage for elderly-care health data (vitals, medication logs,
fall-detection events, wellness check-in results). Kept generic via a JSON
`data` field so specific record shapes can evolve without migrations for
every new field; `record_type` lets us filter/query by kind.
"""

import enum
import uuid

from sqlalchemy import JSON, Enum, ForeignKey, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.base import Base, TimestampMixin


class HealthRecordType(str, enum.Enum):
    medication_log = "medication_log"
    vitals = "vitals"
    fall_detection_event = "fall_detection_event"
    wellness_check_in = "wellness_check_in"
    appointment = "appointment"
    note = "note"


class HealthRecord(Base, TimestampMixin):
    __tablename__ = "health_records"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    record_type: Mapped[HealthRecordType] = mapped_column(
        Enum(HealthRecordType), nullable=False
    )
    data: Mapped[dict] = mapped_column(JSON, nullable=False, default=dict)
    notes: Mapped[str] = mapped_column(Text, default="")

    user: Mapped["User"] = relationship(back_populates="health_records")
