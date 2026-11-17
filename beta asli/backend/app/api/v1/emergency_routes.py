"""
Emergency routes (spec 5.5-5.7).

  POST /emergency/detect     - deterministic phrase check (app pre-filter;
                               server re-validation, no LLM involved)
  POST /emergency/events     - trigger an emergency event (voice keyword,
                               manual SOS, fall detection)
  POST /emergency/acknowledge - family member acknowledges
  POST /emergency/resolve    - resolve or mark false alarm
  GET  /emergency/history/{elder_user_id} - circle-scoped history

Emergency flow NEVER depends on the LLM or AI provider availability.
"""

import uuid
from typing import Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user
from app.database import get_db
from app.models.user import User
from app.services.emergency_service import EmergencyService

router = APIRouter(prefix="/emergency", tags=["emergency"])


def get_service(db: AsyncSession = Depends(get_db)) -> EmergencyService:
    return EmergencyService(db)


class DetectRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=2000)


class TriggerEventRequest(BaseModel):
    trigger_phrase: str = Field(..., min_length=1, max_length=255)
    source: str = Field(default="voice_keyword", pattern="^(voice_keyword|manual_sos|fall_detection)$")
    latitude: Optional[float] = Field(default=None, ge=-90, le=90)
    longitude: Optional[float] = Field(default=None, ge=-180, le=180)


class AcknowledgeRequest(BaseModel):
    event_id: uuid.UUID
    note: Optional[str] = Field(default=None, max_length=2000)


class ResolveRequest(BaseModel):
    event_id: uuid.UUID
    false_alarm: bool = False


@router.post("/detect")
async def detect_emergency(
    payload: DetectRequest,
    user: User = Depends(get_current_user),
    service: EmergencyService = Depends(get_service),
):
    """Deterministic phrase check. Returns the matched phrase or null."""
    matched = service.is_emergency_phrase(payload.text)
    return {"matched": matched, "is_emergency": matched is not None}


@router.post("/events")
async def trigger_emergency_event(
    payload: TriggerEventRequest,
    user: User = Depends(get_current_user),
    service: EmergencyService = Depends(get_service),
):
    event = await service.trigger_event(
        elder_user=user,
        trigger_phrase=payload.trigger_phrase,
        source=payload.source,
        latitude=payload.latitude,
        longitude=payload.longitude,
    )
    return service._event_out(event)


@router.post("/acknowledge")
async def acknowledge_emergency(
    payload: AcknowledgeRequest,
    user: User = Depends(get_current_user),
    service: EmergencyService = Depends(get_service),
):
    event = await service.acknowledge(user, payload.event_id, payload.note)
    return service._event_out(event)


@router.post("/resolve")
async def resolve_emergency(
    payload: ResolveRequest,
    user: User = Depends(get_current_user),
    service: EmergencyService = Depends(get_service),
):
    event = await service.resolve(user, payload.event_id, payload.false_alarm)
    return service._event_out(event)


@router.get("/history/{elder_user_id}")
async def emergency_history(
    elder_user_id: uuid.UUID,
    user: User = Depends(get_current_user),
    service: EmergencyService = Depends(get_service),
):
    return await service.history(user, elder_user_id)