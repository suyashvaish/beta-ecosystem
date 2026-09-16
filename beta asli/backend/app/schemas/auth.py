"""Schemas for authentication endpoints."""

from pydantic import BaseModel, Field


class TokenVerifyRequest(BaseModel):
    id_token: str = Field(..., description="Firebase ID token from client SDK")


class TokenVerifyResponse(BaseModel):
    valid: bool
    firebase_uid: str
    email: str | None = None
    is_new_user: bool = False


class SignInResponse(BaseModel):
    """
    Returned after a successful sign-in verification.

    Firebase handles credential verification client-side (email/password,
    phone, OAuth, etc.); the client then sends us the resulting ID token,
    which this backend verifies and exchanges for a local session record.
    """

    user_id: str
    firebase_uid: str
    is_new_user: bool


class LogoutResponse(BaseModel):
    success: bool
    message: str = "Logged out successfully"
