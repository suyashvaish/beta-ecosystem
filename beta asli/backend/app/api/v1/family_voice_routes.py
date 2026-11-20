"""Family Talk voice-note upload and playback routes (Feature C)."""
import uuid

from fastapi import APIRouter, Depends, UploadFile
from fastapi.responses import Response
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user
from app.database import get_db
from app.models.user import User
from app.services.family_media_service import AUDIO_EXTENSION, load_voice_note, save_voice_note
from app.services.family_talk_service import FamilyTalkService
from app.utils.exceptions import AuthorizationError, ValidationError

router = APIRouter(prefix="/family", tags=["family-talk"])


def get_service(db: AsyncSession = Depends(get_db)) -> FamilyTalkService:
    return FamilyTalkService(db)


async def _require_membership(user: User, elder_user_id: uuid.UUID, service: FamilyTalkService) -> None:
    """Caller must be the elder or a member of the elder's circle."""
    role = await service.circles.role_of(user.id, elder_user_id)
    if role is None:
        raise AuthorizationError("You are not a member of this family circle.")


@router.post("/voice-notes/upload")
async def upload_voice_note(
    audio: UploadFile,
    elder_user_id: uuid.UUID,
    duration_seconds: int,
    user: User = Depends(get_current_user),
    service: FamilyTalkService = Depends(get_service),
):
    """Stores one voice note; returns the URL to attach to a message."""
    await _require_membership(user, elder_user_id, service)
    if duration_seconds <= 0 or duration_seconds > 120:
        raise ValidationError("Voice note duration must be 1-120 seconds.")
    data = await audio.read()
    audio_url, _audio_id = save_voice_note(elder_user_id, data)
    return {"audio_url": audio_url}


@router.get("/voice-notes/{elder_user_id}/{audio_id}/audio")
async def get_voice_note_audio(
    elder_user_id: uuid.UUID,
    audio_id: uuid.UUID,
    user: User = Depends(get_current_user),
    service: FamilyTalkService = Depends(get_service),
):
    """Streams one stored voice note - circle members only."""
    await _require_membership(user, elder_user_id, service)
    data = load_voice_note(elder_user_id, audio_id)
    return Response(content=data, media_type="audio/mp4", headers={"Content-Disposition": f'inline; filename="voice{AUDIO_EXTENSION}"'})