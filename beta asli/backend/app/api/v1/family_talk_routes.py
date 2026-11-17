"""
Family Talk routes (Feature C).

Two-way messaging between an elder (Beta Asli) and their circle
(Beta Care). All authorization is server-side via FamilyTalkService.

Endpoints (proposal 8, adapted to existing conventions):
  GET  /family/conversations/{elder_user_id}/messages   - history
  POST /family/messages                                  - send text
  POST /family/voice-messages                             - send voice
  POST /family/messages/read                             - mark read
"""

import uuid
from typing import Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user
from app.database import get_db
from app.models.user import User
from app.services.family_talk_service import FamilyTalkService

router = APIRouter(prefix="/family", tags=["family-talk"])


def get_service(db: AsyncSession = Depends(get_db)) -> FamilyTalkService:
    return FamilyTalkService(db)


class SendTextRequest(BaseModel):
    elder_user_id: uuid.UUID
    text: str = Field(..., min_length=1, max_length=4000)
    recipient_user_id: Optional[uuid.UUID] = None


class SendVoiceRequest(BaseModel):
    elder_user_id: uuid.UUID
    audio_url: str = Field(..., max_length=1024)
    duration_seconds: int = Field(..., gt=0, le=120)
    transcript: Optional[str] = Field(default=None, max_length=4000)
    recipient_user_id: Optional[uuid.UUID] = None


class MarkReadRequest(BaseModel):
    elder_user_id: uuid.UUID
    message_id: uuid.UUID


def _message_out(m, sender: User):
    return {
        "id": str(m.id),
        "sender_user_id": str(m.sender_user_id),
        "sender_name": (sender.display_name if sender else None) or "Family member",
        "message_type": m.message_type.value,
        "body": m.body,
        "audio_url": m.audio_url,
        "duration_seconds": m.duration_seconds,
        "transcript": m.transcript,
        "status": m.status.value,
        "read": m.read_at is not None,
        "created_at": m.created_at.isoformat(),
    }


@router.get("/conversations/{elder_user_id}/messages")
async def conversation_history(
    elder_user_id: uuid.UUID,
    before_message_id: Optional[uuid.UUID] = None,
    limit: int = 50,
    user: User = Depends(get_current_user),
    service: FamilyTalkService = Depends(get_service),
):
    messages = await service.history(user, elder_user_id, before_message_id, limit)
    # Resolve sender names in one pass for the UI.
    out = []
    for m in messages:
        sender = await service.db.get(User, m.sender_user_id)
        out.append(_message_out(m, sender))
    return out


@router.post("/messages")
async def send_text_message(
    payload: SendTextRequest,
    user: User = Depends(get_current_user),
    service: FamilyTalkService = Depends(get_service),
):
    message = await service.send_text(
        sender_user=user,
        elder_user_id=payload.elder_user_id,
        text=payload.text,
        recipient_user_id=payload.recipient_user_id,
    )
    return _message_out(message, user)


@router.post("/voice-messages")
async def send_voice_message(
    payload: SendVoiceRequest,
    user: User = Depends(get_current_user),
    service: FamilyTalkService = Depends(get_service),
    db: AsyncSession = Depends(get_db),
):
    message = await service.send_voice(
        sender_user=user,
        elder_user_id=payload.elder_user_id,
        audio_url=payload.audio_url,
        duration_seconds=payload.duration_seconds,
        transcript=payload.transcript,
        recipient_user_id=payload.recipient_user_id,
    )
    return _message_out(message, user)


@router.post("/messages/read")
async def mark_message_read(
    payload: MarkReadRequest,
    user: User = Depends(get_current_user),
    service: FamilyTalkService = Depends(get_service),
):
    message = await service.mark_read(user, payload.elder_user_id, payload.message_id)
    sender = await service.db.get(User, message.sender_user_id)
    return _message_out(message, sender)