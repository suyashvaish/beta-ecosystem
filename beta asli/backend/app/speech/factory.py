"""Factory for obtaining the active STT/TTS providers."""

from functools import lru_cache

from app.speech.base import SpeechToTextProvider, TextToSpeechProvider
from app.speech.openai_provider import OpenAITTSProvider, OpenAIWhisperSTTProvider


@lru_cache
def get_stt_provider() -> SpeechToTextProvider:
    return OpenAIWhisperSTTProvider()


@lru_cache
def get_tts_provider() -> TextToSpeechProvider:
    return OpenAITTSProvider()
