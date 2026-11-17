"""
Caregiver model.

Represents a caregiver's access relationship to an elderly user's account.
A caregiver may or may not have their own User row; `caregiver_user_id`
is nullable to support both cases. In Ecosystem 2.0 this row doubles as
a care-circle MEMBERSHIP: `care_circle_id` links the member into the
elder's circle and `circle_role` gives the role-based access level.

`fcm_device_token` holds the caregiver's FCM push token. The token is
ALWAYS populated/owned server-side; clients never supply tokens for other
users (a client-supplied token list would allow arbitrary push injection).
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


class CircleRole(str, enum.Enum):
    primary_guardian = "primary_guardian"
    caregiver = "caregiver"
    viewer = "viewer"


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
    # ---- Care circle membership (Ecosystem 2.0, Feature D) ----
    care_circle_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("care_circles.id", ondelete="SET NULL"),
        nullable=True, index=True,
    )
    circle_role: Mapped[Optional[CircleRole]] = mapped_column(
        Enum(CircleRole), default=CircleRole.viewer, nullable=True
    )
    # FCM push token for this caregiver's device. Populated when the
    # caregiver registers their device; used to fan out emergency alerts.
    fcm_device_token: Mapped[Optional[str]] = mapped_column(
        String(4096), nullable=True
    )

    cared_for_user: Mapped["User"] = relationship(
        back_populates="caregiver_links", foreign_keys=[cared_for_user_id]
    )
    care_circle: Mapped[Optional["CareCircle"]] = relationship(
        back_populates="members", foreign_keys=[care_circle_id]
    )