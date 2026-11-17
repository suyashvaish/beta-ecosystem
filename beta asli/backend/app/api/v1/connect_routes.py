"""
Beta Connect routes (Feature B).

Proposal 8 endpoints adapted to the session lifecycle:
  POST /connect/sessions       - initiate (initiator only)
  POST /connect/discover      - responder submits the spoken code
  POST /connect/accept         - approve + choose fields to share
  POST /connect/decline       - either party declines
  POST /connect/cancel        - initiator cancels
  GET  /connect/sessions      - my recent sessions
  GET  /connect/sessions/{id} - participant view (payload only when completed)

The Flutter app parses the voice intent ("Beta, contact share karo")
and calls these deterministic endpoints; the LLM never mediates consent
or data transfer (spec 3.7).
"""

import uuid
from typing import Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user
from app.database import get_db
from app.models.user import User
from app.services.contact_share_service import ContactShareService

router = APIRouter(prefix="/connect", tags=["beta-connect"])


def get_service(db: AsyncSession = Depends(get_db)) -> ContactShareService:
    return ContactShareService(db)


class InitiateRequest(BaseModel):
    intended_name: str = Field(..., min_length=1, max_length=255)


class DiscoverRequest(BaseModel):
    code: str = Field(..., min_length=4, max_length=4, pattern="^[0-9]{4}$")


class AcceptRequest(BaseModel):
    session_id: uuid.UUID
    share_name: bool = True
    share_phone: bool = False
    share_email: bool = False
    phone: Optional[str] = Field(default=None, max_length=32)
    email: Optional[str] = Field(default=None, max_length=320)


class SessionIdRequest(BaseModel):
    session_id: uuid.UUID


@router.post("/sessions")
async def initiate_sharing(
    payload: InitiateRequest,
    user: User = Depends(get_current_user),
    service: ContactShareService = Depends(get_service),
):
    session = await service.initiate(user, payload.intended_name)
    # The code is returned ONCE to the initiator's app so Beta can speak
    # it aloud. It is never shown to the responder through this API.
    return {
        "session_id": str(session.id),
        "pairing_code": session.pairing_code,
        "expires_at": session.code_expires_at.isoformat(),
        "status": session.status.value,
    }


@router.post("/discover")
async def submit_pairing_code(
    payload: DiscoverRequest,
    user: User = Depends(get_current_user),
    service: ContactShareService = Depends(get_service),
):
    session = await service.submit_code(user, payload.code)
    # No personal data yet: only that a session was found.
    return {
        "session_id": str(session.id),
        "status": session.status.value,
    }


@router.post("/accept")
async def accept_sharing(
    payload: AcceptRequest,
    user: User = Depends(get_current_user),
    service: ContactShareService = Depends(get_service),
):
    session = await service.approve(
        user=user,
        session_id=payload.session_id,
        share_name=payload.share_name,
        share_phone=payload.share_phone,
        share_email=payload.share_email,
        phone=payload.phone,
        email=payload.email,
    )
    return await service.session_view(user, session.id)


@router.post("/decline")
async def decline_sharing(
    payload: SessionIdRequest,
    user: User = Depends(get_current_user),
    service: ContactShareService = Depends(get_service),
):
    session = await service.decline(user, payload.session_id)
    return {"status": session.status.value}


@router.post("/cancel")
async def cancel_sharing(
    payload: SessionIdRequest,
    user: User = Depends(get_current_user),
    service: ContactShareService = Depends(get_service),
):
    session = await service.cancel(user, payload.session_id)
    return {"status": session.status.value}


@router.get("/sessions")
async def my_sessions(
    user: User = Depends(get_current_user),
    service: ContactShareService = Depends(get_service),
):
    return await service.my_sessions(user)


@router.get("/sessions/{session_id}")
async def session_details(
    session_id: uuid.UUID,
    user: User = Depends(get_current_user),
    service: ContactShareService = Depends(get_service),
):
    return await service.session_view(user, session_id)