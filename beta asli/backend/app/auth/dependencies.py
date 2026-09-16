"""
FastAPI dependencies for authentication.

`get_current_user` verifies the bearer token via Firebase, then finds or
lazily creates the corresponding local `User` row (first-login provisioning).
Downstream routes simply depend on `get_current_user` to get a fully
resolved, authenticated `User` ORM object.
"""

from fastapi import Depends, Header
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.firebase import verify_id_token
from app.database import get_db
from app.models.user import User
from app.repositories.user_repository import UserRepository
from app.utils.exceptions import AuthenticationError


async def get_bearer_token(authorization: str | None = Header(default=None)) -> str:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise AuthenticationError("Missing or malformed Authorization header")
    return authorization.split(" ", 1)[1].strip()


async def get_current_user(
    token: str = Depends(get_bearer_token),
    db: AsyncSession = Depends(get_db),
) -> User:
    decoded = verify_id_token(token)
    firebase_uid = decoded["uid"]
    email = decoded.get("email")

    repo = UserRepository(db)
    user = await repo.get_by_firebase_uid(firebase_uid)
    if user is None:
        user = await repo.create(firebase_uid=firebase_uid, email=email)

    if not user.is_active:
        raise AuthenticationError("This account has been deactivated")

    return user
