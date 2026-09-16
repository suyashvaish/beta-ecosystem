"""
Caregiver model.

Represents a caregiver's access relationship to an elderly user's account.
A caregiver may or may not have their own User row (they might just be
notified via email/SMS); `caregiver_user_id` is nullable to support both
cases.
"""

import enum
import uuid
from typing import Optional

from sqlalchemy import Enum, ForeignKey, String
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.base import Base, TimestampMixin


class CaregiverAccessLevel(str, enum.Enum):
    view_only = "view_only"
    full_access = "full_access"
    emergency_only = "emergency_only"


class Caregiver(Base, TimestampMixin):
    __tablename__ = "caregivers"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    cared_for_user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    caregiver_user_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    caregiver_name: Mapped[str] = mapped_column(String(255))
    caregiver_email: Mapped[Optional[str]] = mapped_column(String(320), nullable=True)
    caregiver_phone: Mapped[Optional[str]] = mapped_column(String(32), nullable=True)
    access_level: Mapped[CaregiverAccessLevel] = mapped_column(
        Enum(CaregiverAccessLevel), default=CaregiverAccessLevel.view_only
    )

    cared_for_user: Mapped["User"] = relationship(
        back_populates="caregiver_links", foreign_keys=[cared_for_user_id]
    )
