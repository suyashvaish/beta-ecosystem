"""
OpenAI implementation of the speech provider interfaces.

Mirrors `app/ai/openai_provider.py`'s shape exactly (same AsyncOpenAI
client pattern, same tenacity retry policy on transient errors, same
`AIServiceError`-style wrapping) so this fits the existing backend
conventions rather than introducing a new one.

- `OpenAIWhisperSTTProvider.transcribe()` calls the Whisper transcription
  endpoint. Signature matches `SpeechToTextProvider.transcribe` exactly,
  so `speech_routes.py` needed no changes.
- `OpenAITTSProvider.synthesize()` calls the OpenAI TTS endpoint and
  returns audio bytes (mp3). Signature matches `TextToSpeechProvider.synthesize`
  exactly.

Both reuse the same `OPENAI_API_KEY` already configured for the AI stage —
no new credentials, no new SDK (`openai` is already a dependency).
"""

import io

from openai import AsyncOpenAI, APIError, APITimeoutError, RateLimitError as OpenAIRateLimitError
from tenacity import (
    retry,
    retry_if_exception_type,
    stop_after_attempt,
    wait_exponential,
)

from app.config.settings import get_settings
from app.speech.base import SpeechToTextProvider, TextToSpeechProvider
from app.utils.exceptions import AIServiceError
from app.utils.logging import get_logger

settings = get_settings()
logger = get_logger(__name__)

_RETRYABLE_EXCEPTIONS = (APITimeoutError, OpenAIRateLimitError, APIError)


class OpenAIWhisperSTTProvider(SpeechToTextProvider):
    def __init__(self) -> None:
        self._client = AsyncOpenAI(
            api_key=settings.OPENAI_API_KEY,
            timeout=settings.AI_REQUEST_TIMEOUT_SECONDS,
        )

    @retry(
        reraise=True,
        stop=stop_after_attempt(settings.AI_MAX_RETRIES),
        wait=wait_exponential(multiplier=1, min=1, max=10),
        retry=retry_if_exception_type(_RETRYABLE_EXCEPTIONS),
    )
    async def transcribe(self, audio_bytes: bytes, mime_type: str) -> str:
        if not audio_bytes:
            raise AIServiceError("No audio was received to transcribe")

        ext = (mime_type.split("/")[-1] or "wav").split(";")[0]
        audio_file = io.BytesIO(audio_bytes)
        audio_file.name = f"utterance.{ext}"  # SDK infers format from filename

        try:
            response = await self._client.audio.transcriptions.create(
                model=settings.OPENAI_STT_MODEL,
                file=audio_file,
            )
            return response.text.strip()
        except _RETRYABLE_EXCEPTIONS:
            raise
        except Exception as exc:  # noqa: BLE001
            logger.error("OpenAI transcribe failed", extra={"extra_fields": {"error": str(exc)}})
            raise AIServiceError("Failed to transcribe audio") from exc


class OpenAITTSProvider(TextToSpeechProvider):
    def __init__(self) -> None:
        self._client = AsyncOpenAI(
            api_key=settings.OPENAI_API_KEY,
            timeout=settings.AI_REQUEST_TIMEOUT_SECONDS,
        )

    @retry(
        reraise=True,
        stop=stop_after_attempt(settings.AI_MAX_RETRIES),
        wait=wait_exponential(multiplier=1, min=1, max=10),
        retry=retry_if_exception_type(_RETRYABLE_EXCEPTIONS),
    )
    async def synthesize(self, text: str, voice_id: str | None = None) -> bytes:
        if not text.strip():
            raise AIServiceError("No text was provided to synthesize")

        try:
            response = await self._client.audio.speech.create(
                model=settings.OPENAI_TTS_MODEL,
                voice=voice_id or settings.OPENAI_TTS_DEFAULT_VOICE,
                input=text,
            )
            return response.content
        except _RETRYABLE_EXCEPTIONS:
            raise
        except Exception as exc:  # noqa: BLE001
            logger.error("OpenAI synthesize failed", extra={"extra_fields": {"error": str(exc)}})
            raise AIServiceError("Failed to synthesize speech") from exc
