"""Schemas for user profile endpoints."""

import uuid
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict, EmailStr


class UserProfileResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    firebase_uid: str
    email: Optional[EmailStr] = None
    display_name: Optional[str] = None
    phone_number: Optional[str] = None
    is_active: bool
    is_elderly_profile: bool
    created_at: datetime


class UserProfileUpdateRequest(BaseModel):
    display_name: Optional[str] = None
    phone_number: Optional[str] = None
    is_elderly_profile: Optional[bool] = None
