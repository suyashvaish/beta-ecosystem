"""Voice endpoints: speech-to-text and text-to-speech."""

from fastapi import APIRouter, Depends, UploadFile
from fastapi.responses import Response

from app.auth.dependencies import get_current_user
from app.models.user import User
from app.speech.base import SpeechToTextProvider, TextToSpeechProvider
from app.speech.factory import get_stt_provider, get_tts_provider

router = APIRouter(prefix="/speech", tags=["speech"])


@router.post("/transcribe")
async def transcribe(
    audio: UploadFile,
    current_user: User = Depends(get_current_user),
    stt: SpeechToTextProvider = Depends(get_stt_provider),
):
    audio_bytes = await audio.read()
    text = await stt.transcribe(audio_bytes, audio.content_type or "audio/wav")
    return {"text": text}


@router.post("/synthesize")
async def synthesize(
    text: str,
    voice_id: str | None = None,
    current_user: User = Depends(get_current_user),
    tts: TextToSpeechProvider = Depends(get_tts_provider),
):
    audio_bytes = await tts.synthesize(text, voice_id)
    return Response(content=audio_bytes, media_type="audio/mpeg")
