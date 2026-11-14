"""
Voice endpoints: speech-to-text and text-to-speech.

Input hard limits (MAX_AUDIO_UPLOAD_BYTES / MAX_TTS_TEXT_LENGTH) protect
server memory and OpenAI spend from oversized requests.
"""

from fastapi import APIRouter, Depends, UploadFile
from fastapi.responses import Response

from app.auth.dependencies import get_current_user
from app.config.settings import get_settings
from app.models.user import User
from app.speech.base import SpeechToTextProvider, TextToSpeechProvider
from app.speech.factory import get_stt_provider, get_tts_provider
from app.utils.exceptions import AppError

router = APIRouter(prefix="/speech", tags=["speech"])
settings = get_settings()


@router.post("/transcribe")
async def transcribe(
    audio: UploadFile,
    current_user: User = Depends(get_current_user),
    stt: SpeechToTextProvider = Depends(get_stt_provider),
):
    audio_bytes = await audio.read()

    if len(audio_bytes) > settings.MAX_AUDIO_UPLOAD_BYTES:
        raise AppError(
            f"Audio upload exceeds the {settings.MAX_AUDIO_UPLOAD_BYTES // (1024 * 1024)} MB limit"
        )

    if not audio_bytes:
        raise AppError("Audio file is empty")

    text = await stt.transcribe(audio_bytes, audio.content_type or "audio/wav")
    return {"text": text}


@router.post("/synthesize")
async def synthesize(
    text: str,
    voice_id: str | None = None,
    current_user: User = Depends(get_current_user),
    tts: TextToSpeechProvider = Depends(get_tts_provider),
):
    if not text or not text.strip():
        raise AppError("Text is required")

    if len(text) > settings.MAX_TTS_TEXT_LENGTH:
        raise AppError(f"Text exceeds the {settings.MAX_TTS_TEXT_LENGTH} character limit")

    audio_bytes = await tts.synthesize(text, voice_id)
    return Response(content=audio_bytes, media_type="audio/mpeg")