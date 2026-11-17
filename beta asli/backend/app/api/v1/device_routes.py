"""
Device token routes (push infrastructure).

  POST /devices/register   - register/refresh this user's device token
  POST /devices/revoke      - revoke one token (logout on this device)
  POST /devices/revoke-all  - logout everywhere
  GET  /devices             - my registered devices (id + platform +
                              last seen; tokens themselves are never
                              echoed back to the client)

A user can only manage their OWN devices - enforced by the
authenticated user from the token, not by any client-supplied field.
"""

import uuid

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user
from app.database import get_db
from app.models.user import User
from app.services.device_token_service import DeviceTokenService

router = APIRouter(prefix="/devices", tags=["devices"])


def get_service(db: AsyncSession = Depends(get_db)) -> DeviceTokenService:
    return DeviceTokenService(db)


class RegisterRequest(BaseModel):
    token: str = Field(..., min_length=32, max_length=512)
    platform: str = Field(default="android", pattern="^(android|ios)$")


class RevokeRequest(BaseModel):
    token: str = Field(..., min_length=32, max_length=512)


@router.post("/register")
async def register_device(
    payload: RegisterRequest,
    user: User = Depends(get_current_user),
    service: DeviceTokenService = Depends(get_service),
):
    device = await service.register(user.id, payload.token, payload.platform)
    return {
        "device_id": str(device.id),
        "platform": device.platform,
        "active": device.active,
        "last_seen_at": device.last_seen_at.isoformat(),
    }


@router.post("/revoke")
async def revoke_device(
    payload: RevokeRequest,
    user: User = Depends(get_current_user),
    service: DeviceTokenService = Depends(get_service),
):
    revoked = await service.revoke(user.id, payload.token)
    return {"revoked": revoked}


@router.post("/revoke-all")
async def revoke_all_devices(
    user: User = Depends(get_current_user),
    service: DeviceTokenService = Depends(get_service),
):
    count = await service.revoke_all_for_user(user.id)
    return {"revoked_count": count}


@router.get("")
async def my_devices(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    from sqlalchemy import select

    from app.models.device_token import DeviceToken

    stmt = select(DeviceToken).where(DeviceToken.user_id == user.id)
    result = await db.execute(stmt)
    return [
        {
            "device_id": str(d.id),
            "platform": d.platform,
            "active": d.active,
            "last_seen_at": d.last_seen_at.isoformat(),
        }
        for d in result.scalars().all()
    ]