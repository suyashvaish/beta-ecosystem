"""
Application settings.

All configuration is loaded from environment variables (via a `.env` file in
local development, or real environment variables in production/Docker).
We use pydantic-settings so that:
  - values are validated and type-cast automatically
  - missing required values fail fast at startup instead of at first use
  - nothing is hardcoded in the codebase (12-factor app style)
"""

from functools import lru_cache
from typing import List, Literal

from pydantic import AnyUrl, Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    # ---- General ---------------------------------------------------------
    APP_NAME: str = "Beta AI Assistant Backend"
    ENVIRONMENT: Literal["local", "staging", "production"] = "local"
    DEBUG: bool = False
    API_V1_PREFIX: str = "/api/v1"

    # ---- Security ----------------------------------------------------------
    SECRET_KEY: str = Field(..., description="Used for signing internal tokens")
    ALLOWED_ORIGINS: List[str] = ["*"]
    RATE_LIMIT_PER_MINUTE: int = 60

    @field_validator("ALLOWED_ORIGINS", mode="before")
    @classmethod
    def split_origins(cls, v):
        if isinstance(v, str):
            return [origin.strip() for origin in v.split(",") if origin.strip()]
        return v

    # ---- Database ------------------------------------------------------------
    DATABASE_URL: str = Field(
        ...,
        description="Async SQLAlchemy URL, e.g. postgresql+asyncpg://user:pass@host/db",
    )
    DATABASE_ECHO: bool = False
    DB_POOL_SIZE: int = 10
    DB_MAX_OVERFLOW: int = 20

    # ---- Firebase ------------------------------------------------------------
    FIREBASE_CREDENTIALS_PATH: str = "firebase-credentials.json"
    FIREBASE_PROJECT_ID: str = "beta-ai-bbc28"

    # ---- OpenAI / AI ---------------------------------------------------------
    OPENAI_API_KEY: str = Field(..., description="OpenAI API key")
    OPENAI_MODEL: str = "gpt-4.1"
    OPENAI_EMBEDDING_MODEL: str = "text-embedding-3-small"
    AI_SYSTEM_PROMPT: str = (
        "You are Beta, a warm, patient, and reliable AI assistant. "
        "You help the user with daily tasks, reminders, and conversation. "
        "Keep responses concise and clear."
    )
    AI_MAX_RETRIES: int = 3
    AI_REQUEST_TIMEOUT_SECONDS: int = 30

    # ---- Speech (STT/TTS) ------------------------------------------------
    # Same OpenAI account/key as the AI stage above (OPENAI_API_KEY) -
    # Whisper for transcription, the TTS API for synthesis.
    OPENAI_STT_MODEL: str = "whisper-1"
    OPENAI_TTS_MODEL: str = "tts-1"
    OPENAI_TTS_DEFAULT_VOICE: str = "alloy"

    # ---- Memory / Vector store ------------------------------------------------
    VECTOR_DIMENSIONS: int = 1536
    MEMORY_TOP_K: int = 5
    SHORT_TERM_MEMORY_TURNS: int = 10

    # ---- Notifications ---------------------------------------------------------
    FCM_CREDENTIALS_PATH: str = "firebase-credentials.json"

    # ---- Logging -----------------------------------------------------------
    LOG_LEVEL: str = "INFO"
    LOG_JSON: bool = True


@lru_cache
def get_settings() -> Settings:
    """Cached settings accessor so we parse env vars only once."""
    return Settings()
