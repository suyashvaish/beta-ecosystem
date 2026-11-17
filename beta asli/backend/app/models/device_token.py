"""
Device token model (Ecosystem 2.0, push infrastructure).

A registry of FCM device tokens per user. This closes the documented
placeholder where Family Talk / Emergency could not notify the ELDER's
own device (only caregiver rows carried tokens before).

Design:
  - One user may own multiple devices (phone + tablet); each token row
    is one device.
  - Tokens are unique globally: FCM delivers to a device, not a user,
    and a stale duplicate row would cause double-pushes.
  - `last_seen_at` updated on each app launch/refresh so stale tokens
    can be pruned or reported honestly by the app.
  - `active` flag for soft revocation (logout) - the row is kept for
    audit, delivery just skips it.
  - The app registers tokens over HTTPS with the authenticated user's
    session; tokens are NEVER accepted as push targets from third
    parties (push-injection rule).

Notification fan-out resolves tokens server-side from THIS table plus
Caregiver rows - the single source of truth for "where to push".
"""

import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, String, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.base import Base, TimestampMixin


class DeviceToken(Base, TimestampMixin):
    __tablename__ = "device_tokens"
    __table_args__ = (
        UniqueConstraint("device_token", name="uq_device_tokens_token"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    # The FCM token for this device (long opaque string).
    device_token: Mapped[str] = mapped_column(String(512), nullable=False, index=True)
    # Client-declared platform hint (android | ios) - used only for
    # payload tuning; not trusted for security decisions.
    platform: Mapped[str] = mapped_column(String(16), default="android")

    active: Mapped[bool] = mapped_column(Boolean, default=True, index=True)
    # Rotated/invalidated by FCM feedback or user logout.
    revoked_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    last_seen_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )

    user: Mapped["User"] = relationship()