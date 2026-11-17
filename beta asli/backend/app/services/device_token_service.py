"""
Device token service (push infrastructure, Ecosystem 2.0).

Single source of truth for "which devices belong to this user". Other
services (Family Talk, Emergency, notifications) resolve push targets
through `active_tokens_for(user_id)` - never from client input.

Rules:
  - Register is idempotent on the token: re-registering an existing
    token refreshes `last_seen_at` instead of duplicating (FCM tokens
    rotate rarely; duplicates would double-push).
  - A token can only be registered by the user who OWNS the Firebase
    session that produced it - the route layer enforces this via
    get_current_user.
  - Re-registering a token that belonged to a DIFFERENT user transfers
    it: FCM rotates tokens and a device may change accounts. The old
    owner loses the row (correct - the device no longer belongs to
    them) and this is logged for audit.
  - Revoke (logout / FCM says invalid): soft-delete via `active=False`
    + `revoked_at`. Rows are kept for audit; delivery skips them.
"""

import uuid
from datetime import datetime, timezone
from typing import List

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.device_token import DeviceToken
from app.utils.logging import get_logger

logger = get_logger(__name__)

MAX_TOKENS_PER_USER = 5


class DeviceTokenService:
    def __init__(self, db: AsyncSession):
        self.db = db

    # -------------------------------------------------------- registration
    async def register(
        self, user_id: uuid.UUID, token: str, platform: str = "android"
    ) -> DeviceToken:
        token = (token or "").strip()
        if not token or len(token) > 512:
            raise ValueError("A valid device token is required.")

        # Existing row for this token?
        stmt = select(DeviceToken).where(DeviceToken.device_token == token)
        result = await self.db.execute(stmt)
        existing = result.scalars().first()

        now = datetime.now(timezone.utc)
        if existing is not None:
            if existing.user_id != user_id:
                logger.info(
                    "Device token ownership transferred (device changed account)",
                    extra={
                        "extra_fields": {
                            "old_user_id": str(existing.user_id),
                            "new_user_id": str(user_id),
                        }
                    },
                )
                existing.user_id = user_id
            existing.active = True
            existing.revoked_at = None
            existing.last_seen_at = now
            if platform in ("android", "ios"):
                existing.platform = platform
            await self.db.flush()
            return existing

        # Cap active devices per user (housekeeping: oldest revoked first).
        await self._cap_user_tokens(user_id)

        device = DeviceToken(
            user_id=user_id,
            device_token=token,
            platform=platform if platform in ("android", "ios") else "android",
            last_seen_at=now,
        )
        self.db.add(device)
        await self.db.flush()
        return device

    # ------------------------------------------------------------- resolve
    async def active_tokens_for(self, user_id: uuid.UUID) -> List[str]:
        """All active FCM tokens for a user (multiple devices possible)."""
        stmt = select(DeviceToken).where(
            DeviceToken.user_id == user_id,
            DeviceToken.active.is_(True),
        )
        result = await self.db.execute(stmt)
        return [d.device_token for d in result.scalars().all()]

    # -------------------------------------------------------------- revoke
    async def revoke(self, user_id: uuid.UUID, token: str) -> bool:
        stmt = select(DeviceToken).where(
            DeviceToken.device_token == token,
            DeviceToken.user_id == user_id,
        )
        result = await self.db.execute(stmt)
        device = result.scalars().first()
        if device is None:
            return False
        device.active = False
        device.revoked_at = datetime.now(timezone.utc)
        await self.db.flush()
        return True

    async def revoke_all_for_user(self, user_id: uuid.UUID) -> int:
        """Logout-everywhere: revoke all of the user's active devices."""
        stmt = select(DeviceToken).where(
            DeviceToken.user_id == user_id,
            DeviceToken.active.is_(True),
        )
        result = await self.db.execute(stmt)
        devices = result.scalars().all()
        now = datetime.now(timezone.utc)
        for d in devices:
            d.active = False
            d.revoked_at = now
        await self.db.flush()
        return len(devices)

    # ------------------------------------------------------------ internals
    async def _cap_user_tokens(self, user_id: uuid.UUID) -> None:
        stmt = select(DeviceToken).where(
            DeviceToken.user_id == user_id
        ).order_by(DeviceToken.last_seen_at.desc())
        result = await self.db.execute(stmt)
        devices = result.scalars().all()
        excess = len(devices) + 1 - MAX_TOKENS_PER_USER
        if excess > 0:
            # Revoke the least-recently-seen extras.
            for d in devices[-excess:]:
                d.active = False
                d.revoked_at = datetime.now(timezone.utc)
            await self.db.flush()