"""
Factory for obtaining the active AI provider.

This is the single place that decides which concrete `AIProvider` is used.
Providers are selected via the AI_PROVIDER setting:
  - "openai": OpenAI Responses API (existing behaviour preserved).
  - "local":  any self-hosted OpenAI-compatible server (Ollama for dev,
             vLLM / llama.cpp for production), running small open-weight
             models like Qwen 2.5 or Gemma 3 - Beta Intelligence.

Settings validation guarantees the chosen provider has the credentials or
endpoint it needs, so this factory can never construct a broken provider.
"""

from functools import lru_cache

from app.ai.base import AIProvider
from app.config.settings import get_settings
from app.ai.openai_provider import OpenAIProvider
from app.ai.local_provider import LocalOpenAICompatProvider


@lru_cache
def get_ai_provider() -> AIProvider:
    settings = get_settings()
    if settings.AI_PROVIDER == "local":
        return LocalOpenAICompatProvider()
    return OpenAIProvider()