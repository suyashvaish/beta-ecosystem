"""
Care circle model (Feature D: multiple caregivers for one elder).

A care circle groups the family around ONE elderly user. Members are the
existing `Caregiver` rows (extended, not duplicated) - `Caregiver` gains
`care_circle_id` so legacy rows can be backfilled into a circle. Roles
live on the member (Caregiver) row:

  primary_guardian - manage members, invite, revoke, care settings
  caregiver        - care data + medication + alerts + Family Talk
  viewer           - limited view + Family Talk per permissions

`CareCircle.role_for(elder_user_id)` resolves the elder themself as
primary guardian of their own circle.
"""

import enum
import uuid

from sqlalchemy import Enum, ForeignKey, Index, String, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.base import Base, TimestampMixin


class CircleRole(str, enum.Enum):
    primary_guardian = "primary_guardian"
    caregiver = "caregiver"
    viewer = "viewer"


class CareCircle(Base, TimestampMixin):
    __tablename__ = "care_circles"
    __table_args__ = (
        Index("ix_care_circles_elder", "elder_user_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    elder_user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), unique=True
    )
    name: Mapped[str] = mapped_column(String(255), default="Family")

    elder_user: Mapped["User"] = relationship(foreign_keys=[elder_user_id])
    members: Mapped[list["Caregiver"]] = relationship(
        back_populates="care_circle", foreign_keys="Caregiver.care_circle_id"
    )


class CareInvitation(Base, TimestampMixin):
    __tablename__ = "care_invitations"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    circle_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("care_circles.id", ondelete="CASCADE"), index=True
    )
    # Authenticated user who created the invitation.
    invited_by_user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE")
    )
    invite_code: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    invited_email: Mapped[str | None] = mapped_column(String(320), nullable=True)
    proposed_role: Mapped[str] = mapped_column(
        Enum(CircleRole), default=CircleRole.viewer
    )
    status: Mapped[str] = mapped_column(
        String(32), default="pending", index=True
    )  # pending | accepted | revoked | expired
    expires_at: Mapped[uuid.UUID] = mapped_column(
        String(64), nullable=True
    )  # ISO timestamp string; kept as text for simplicity