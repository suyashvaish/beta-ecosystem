"""
Speech provider abstractions.

Beta is a voice assistant, but transcription/synthesis provider choice
(OpenAI Whisper, Google Speech, Azure, ElevenLabs, etc.) is a decision the
Flutter client team may make later or need to change. These interfaces let
the backend expose stable `/speech/*` endpoints today while the concrete
provider is filled in later — call sites never need to change.
"""

from abc import ABC, abstractmethod


class SpeechToTextProvider(ABC):
    @abstractmethod
    async def transcribe(self, audio_bytes: bytes, mime_type: str) -> str:
        """Transcribe raw audio bytes to text."""
        raise NotImplementedError


class TextToSpeechProvider(ABC):
    @abstractmethod
    async def synthesize(self, text: str, voice_id: str | None = None) -> bytes:
        """Synthesize speech audio (bytes) for the given text."""
        raise NotImplementedError


class NotImplementedSTTProvider(SpeechToTextProvider):
    """
    Placeholder STT provider.

    Wired up now so `/api/v1/speech/transcribe` has a real, working code
    path end-to-end. Replace with a concrete provider (e.g. Whisper API)
    by implementing `SpeechToTextProvider` and updating `speech/factory.py`.
    """

    async def transcribe(self, audio_bytes: bytes, mime_type: str) -> str:
        raise NotImplementedError(
            "Speech-to-text is not yet configured. Implement SpeechToTextProvider "
            "and register it in app/speech/factory.py."
        )


class NotImplementedTTSProvider(TextToSpeechProvider):
    """Placeholder TTS provider — see NotImplementedSTTProvider docstring."""

    async def synthesize(self, text: str, voice_id: str | None = None) -> bytes:
        raise NotImplementedError(
            "Text-to-speech is not yet configured. Implement TextToSpeechProvider "
            "and register it in app/speech/factory.py."
        )
