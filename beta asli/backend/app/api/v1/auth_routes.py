"""
Authentication endpoints.

Firebase handles the actual credential verification (email/password, OAuth,
phone) on the client. This backend's job is to verify the resulting ID
token, provision/find the local user record, and manage logout (token
revocation). There is no local password storage anywhere in this service.
"""

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user
from app.auth.firebase import revoke_refresh_tokens, verify_id_token
from app.database import get_db
from app.models.user import User
from app.repositories.user_repository import UserRepository
from app.schemas.auth import (
    LogoutResponse,
    SignInResponse,
    TokenVerifyRequest,
    TokenVerifyResponse,
)
from app.schemas.user import UserProfileResponse

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/sign-in", response_model=SignInResponse)
async def sign_in(payload: TokenVerifyRequest, db: AsyncSession = Depends(get_db)):
    """
    Verify a freshly-obtained Firebase ID token and provision the local
    user record if this is their first sign-in.
    """
    decoded = verify_id_token(payload.id_token)
    firebase_uid = decoded["uid"]
    email = decoded.get("email")

    repo = UserRepository(db)
    user = await repo.get_by_firebase_uid(firebase_uid)
    is_new_user = user is None
    if user is None:
        user = await repo.create(firebase_uid=firebase_uid, email=email)

    return SignInResponse(
        user_id=str(user.id), firebase_uid=firebase_uid, is_new_user=is_new_user
    )


@router.post("/verify", response_model=TokenVerifyResponse)
async def verify_token(payload: TokenVerifyRequest, db: AsyncSession = Depends(get_db)):
    """Verify a token's validity without necessarily creating a session."""
    decoded = verify_id_token(payload.id_token)
    repo = UserRepository(db)
    existing = await repo.get_by_firebase_uid(decoded["uid"])
    return TokenVerifyResponse(
        valid=True,
        firebase_uid=decoded["uid"],
        email=decoded.get("email"),
        is_new_user=existing is None,
    )


@router.get("/profile", response_model=UserProfileResponse)
async def get_profile(current_user: User = Depends(get_current_user)):
    return current_user


@router.post("/logout", response_model=LogoutResponse)
async def logout(current_user: User = Depends(get_current_user)):
    """Revoke all refresh tokens, forcing re-authentication on all devices."""
    revoke_refresh_tokens(current_user.firebase_uid)
    return LogoutResponse(success=True)
