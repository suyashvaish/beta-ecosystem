"""Data access for the User model."""

import uuid
from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import User


class UserRepository:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def get_by_id(self, user_id: uuid.UUID) -> Optional[User]:
        result = await self.db.execute(select(User).where(User.id == user_id))
        return result.scalar_one_or_none()

    async def get_by_firebase_uid(self, firebase_uid: str) -> Optional[User]:
        result = await self.db.execute(
            select(User).where(User.firebase_uid == firebase_uid)
        )
        return result.scalar_one_or_none()

    async def create(
        self, firebase_uid: str, email: str | None = None, display_name: str | None = None
    ) -> User:
        user = User(firebase_uid=firebase_uid, email=email, display_name=display_name)
        self.db.add(user)
        await self.db.flush()
        await self.db.refresh(user)
        return user

    async def update_profile(
        self, user: User, display_name: str | None = None,
        phone_number: str | None = None, is_elderly_profile: bool | None = None,
    ) -> User:
        if display_name is not None:
            user.display_name = display_name
        if phone_number is not None:
            user.phone_number = phone_number
        if is_elderly_profile is not None:
            user.is_elderly_profile = is_elderly_profile
        await self.db.flush()
        await self.db.refresh(user)
        return user

    async def deactivate(self, user: User) -> None:
        user.is_active = False
        await self.db.flush()
