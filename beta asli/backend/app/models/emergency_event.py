"""
Emergency event models (Ecosystem 2.0, spec 5.5-5.7).

Emergency detection is DETERMINISTIC and INDEPENDENT of the LLM:
the app runs an authorized listening mode (wake phrase active or screen
open), matches configured phrases client-side, and calls the emergency
endpoints. The backend does its own phrase validation as defence in
depth, plus:

  - dedupe window: identical phrase from the same elder within
    EMERGENCY_DEDUPE_SECONDS is recorded once (false-trigger guard,
    spec 5.7)
  - acknowledgements: each circle member's ack is tracked; the event
    stays unacknowledged until at least one family member responds
  - audit: every event persists with location-if-permitted, timestamps,
    and phrase that triggered it. Never logged: audio, full context.

Configurable phrases live in settings (EMERGENCY_PHRASES) so additional
languages ship without code changes (spec 5.5).
"""

import enum
import uuid
from datetime import datetime

from sqlalchemy import DateTime, Enum, ForeignKey, Index, String, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.base import Base, TimestampMixin


class EmergencyEventStatus(str, enum.Enum):
    active = "active"          # raised, not yet acknowledged
    acknowledged = "acknowledged"  # a family member has responded
    resolved = "resolved"      # family marked it handled
    false_alarm = "false_alarm"    # cancelled by the elder or family


class EmergencyEvent(Base, TimestampMixin):
    __tablename__ = "emergency_events"
    __table_args__ = (
        Index("ix_emergency_events_elder_status", "elder_user_id", "status"),
        Index("ix_emergency_events_elder_created", "elder_user_id", "created_at"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    elder_user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    # What triggered the event (audited; never audio).
    trigger_phrase: Mapped[str] = mapped_column(String(255))
    source: Mapped[str] = mapped_column(String(32), default="voice_keyword")
    # voice_keyword | manual_sos | fall_detection

    # Location only if the elder granted permission (data minimization).
    latitude: Mapped[float | None] = mapped_column(nullable=True)
    longitude: Mapped[float | None] = mapped_column(nullable=True)

    status: Mapped[str] = mapped_column(
        Enum(EmergencyEventStatus), default=EmergencyEventStatus.active, index=True
    )
    acknowledged_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    resolved_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    elder: Mapped["User"] = relationship(foreign_keys=[elder_user_id])
    acknowledgements: Mapped[list["EmergencyAcknowledgement"]] = relationship(
        back_populates="event", cascade="all, delete-orphan"
    )


class EmergencyAcknowledgement(Base, TimestampMixin):
    __tablename__ = "emergency_acknowledgements"
    __table_args__ = (
        Index("uq_emergency_ack_event_user", "event_id", "acknowledging_user_id",
              unique=True),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    event_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("emergency_events.id", ondelete="CASCADE"),
        index=True,
    )
    acknowledging_user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE")
    )
    note: Mapped[str | None] = mapped_column(Text, nullable=True)

    event: Mapped["EmergencyEvent"] = relationship(back_populates="acknowledgements")