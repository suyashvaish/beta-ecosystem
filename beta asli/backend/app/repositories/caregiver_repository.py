"""
Data access for the Caregiver model.

Exists so emergency alert fan-out can resolve caregiver FCM tokens
server-side; clients must never supply push tokens for other users.
"""

import uuid
from typing import Optional, Sequence

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.caregiver import Caregiver


class CaregiverRepository:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def list_for_cared_for_user(
        self, cared_for_user_id: uuid.UUID
    ) -> Sequence[Caregiver]:
        stmt = (
            select(Caregiver)
            .where(Caregiver.cared_for_user_id == cared_for_user_id)
            .order_by(Caregiver.created_at.desc())
        )
        result = await self.db.execute(stmt)
        return result.scalars().all()

    async def device_tokens_for_cared_for_user(
        self, cared_for_user_id: uuid.UUID
    ) -> list[str]:
        """All non-empty FCM tokens registered for this user's caregivers."""
        caregivers = await self.list_for_cared_for_user(cared_for_user_id)
        return [c.fcm_device_token for c in caregivers if c.fcm_device_token]

    async def get_by_id(self, caregiver_id: uuid.UUID) -> Optional[Caregiver]:
        stmt = select(Caregiver).where(Caregiver.id == caregiver_id)
        result = await self.db.execute(stmt)
        return result.scalars().first()