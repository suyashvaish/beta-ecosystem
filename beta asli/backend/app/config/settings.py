"""
Application settings.

All configuration is loaded from environment variables (via a `.env` file in
local development, or real environment variables in production/Docker).
Values are validated and type-cast automatically; missing required values
fail fast at startup instead of at first use (12-factor app style).

Beta Ecosystem 2.0: the AI layer is provider-independent. OPENAI_API_KEY
is now OPTIONAL. The backend starts with a self-hosted (Ollama / vLLM /
llama.cpp) OpenAI-compatible provider when configured via AI_PROVIDER.
"""

from functools import lru_cache
from typing import List, Literal

from pydantic import Field, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

# Default emergency phrases (spec 5.5). English + Hindi; deployments can
# extend/override via the EMERGENCY_PHRASES env var (comma-separated).
_DEFAULT_EMERGENCY_PHRASES = [
    "help",
    "emergency",
    "madad",
    "mujhe madad chahiye",
    "bachao",
]


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
    ALLOWED_ORIGINS: List[str] = []
    RATE_LIMIT_PER_MINUTE: int = 60

    @field_validator("ALLOWED_ORIGINS", mode="before")
    @classmethod
    def split_origins(cls, v):
        if isinstance(v, str):
            return [origin.strip() for origin in v.split(",") if origin.strip()]
        return v

    @field_validator("EMERGENCY_PHRASES", mode="before")
    @classmethod
    def split_phrases(cls, v):
        if isinstance(v, str):
            return [p.strip() for p in v.split(",") if p.strip()]
        return v

    @model_validator(mode="after")
    def validate_security(self) -> "Settings":
        # 1) Never run with wildcard CORS.
        if "*" in self.ALLOWED_ORIGINS:
            raise ValueError(
                "ALLOWED_ORIGINS must not contain '*'. List explicit origins "
                "(e.g. http://localhost:3000) or set ENVIRONMENT=local."
            )
        if not self.ALLOWED_ORIGINS and self.ENVIRONMENT == "local":
            self.ALLOWED_ORIGINS = ["http://localhost:3000", "http://localhost:8080"]
        # 2) DEBUG must never be true outside local development.
        if self.ENVIRONMENT in ("staging", "production"):
            self.DEBUG = False
        # 3) AI provider consistency: the chosen provider must have its
        #    credentials/endpoint configured, or the app fails fast with a
        #    clear message instead of an obscure first-request error.
        if self.AI_PROVIDER == "openai" and not self.OPENAI_API_KEY:
            raise ValueError(
                "AI_PROVIDER=openai requires OPENAI_API_KEY. Alternatively "
                "set AI_PROVIDER=local with LOCAL_AI_BASE_URL (Ollama / "
                "vLLM / llama.cpp OpenAI-compatible server)."
            )
        if self.AI_PROVIDER == "local" and not self.LOCAL_AI_BASE_URL:
            raise ValueError(
                "AI_PROVIDER=local requires LOCAL_AI_BASE_URL, e.g. "
                "http://ollama:11434/v1 (Ollama) or your vLLM endpoint."
            )
        # 4) Emergency phrases must never be empty (elder safety).
        if not self.EMERGENCY_PHRASES:
            raise ValueError("EMERGENCY_PHRASES must contain at least one phrase.")
        return self

    @property
    def ALLOWED_METHODS(self) -> List[str]:
        return ["GET", "POST", "PATCH", "DELETE", "OPTIONS"]

    @property
    def ALLOWED_HEADERS(self) -> List[str]:
        return ["Authorization", "Content-Type"]

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

    # ---- AI provider (Beta Intelligence) --------------------------------------
    # "openai" keeps the existing Responses-API path. "local" uses any
    # OpenAI-compatible self-hosted server (Ollama / vLLM / llama.cpp),
    # letting Beta run on open-weight models like Qwen 2.5 or Gemma 3.
    AI_PROVIDER: Literal["openai", "local"] = "openai"
    OPENAI_API_KEY: str = Field(
        default="",
        description="OpenAI API key. Only required when AI_PROVIDER=openai.",
    )
    OPENAI_MODEL: str = "gpt-4.1"
    OPENAI_EMBEDDING_MODEL: str = "text-embedding-3-small"
    LOCAL_AI_BASE_URL: str = Field(
        default="",
        description="OpenAI-compatible base URL of the self-hosted model "
        "server, e.g. http://ollama:11434/v1 (dev) or a vLLM endpoint (prod).",
    )
    LOCAL_AI_API_KEY: str = Field(
        default="",
        description="Optional bearer token for the self-hosted model server "
        "(llama.cpp/vLLM can require one; Ollama ignores it).",
    )
    LOCAL_CHAT_MODEL: str = Field(
        default="qwen2.5:7b-instruct",
        description="Chat model on the local server. Recommended: "
        "qwen2.5:7b-instruct (Apache-2.0, strong Hindi/English, tools).",
    )
    LOCAL_EMBEDDING_MODEL: str = Field(
        default="nomic-embed-text",
        description="Embedding model on the local server (e.g. Ollama's "
        "nomic-embed-text, 768 dims). Must match EMBEDDING_DIMENSIONS.",
    )
    AI_SYSTEM_PROMPT: str = (
        "You are Beta, a warm, patient, and reliable AI assistant for elderly "
        "people. You help the user with daily tasks, reminders, and "
        "conversation. You understand English, Hindi, and Hinglish. Keep "
        "responses concise, clear, and simple - short sentences, no jargon."
    )
    AI_MAX_RETRIES: int = 3
    AI_REQUEST_TIMEOUT_SECONDS: int = 30
    # Tool-calling guardrails (Beta Intelligence).
    AI_MAX_TOOL_ROUNDS: int = 4
    AI_TOOL_CALL_TIMEOUT_SECONDS: int = 10
    AI_MAX_TOOLS_PER_TURN: int = 8

    # ---- Emergency (spec 5.5) ------------------------------------------------
    EMERGENCY_PHRASES: List[str] = Field(
        default_factory=lambda: list(_DEFAULT_EMERGENCY_PHRASES),
        description="Configurable emergency phrases, comma-separated in env. "
        "Default: help, emergency, madad, mujhe madad chahiye, bachao.",
    )

    # ---- Speech (STT/TTS) ------------------------------------------------
    OPENAI_STT_MODEL: str = "whisper-1"
    OPENAI_TTS_MODEL: str = "tts-1"
    OPENAI_TTS_DEFAULT_VOICE: str = "alloy"
    MAX_AUDIO_UPLOAD_BYTES: int = 25 * 1024 * 1024  # 25 MB
    MAX_TTS_TEXT_LENGTH: int = 4000  # characters

    # ---- Memory / Vector store ------------------------------------------------
    VECTOR_DIMENSIONS: int = 1536
    EMBEDDING_DIMENSIONS: int = 1536
    MEMORY_TOP_K: int = 5
    SHORT_TERM_MEMORY_TURNS: int = 10

    # ---- Search providers (Beta Intelligence) -----------------------------
    # Credentials are optional: a missing provider means that tool is
    # unavailable and Beta says so honestly instead of inventing results.
    # Web search tries providers in this order: Tavily -> SerpApi ->
    # DuckDuckGo (keyless). WEB_SEARCH_PROVIDERS overrides the order or
    # restricts which are used, comma-separated (e.g. "duckduckgo" only).
    GOOGLE_MAPS_API_KEY: str = ""
    SERPAPI_KEY: str = ""
    TAVILY_API_KEY: str = ""
    WEB_SEARCH_TIMEOUT_SECONDS: int = 10
    WEB_SEARCH_PROVIDERS: str = "tavily,serpapi,duckduckgo"

    # ---- Notifications ---------------------------------------------------------
    FCM_CREDENTIALS_PATH: str = "firebase-credentials.json"

    # ---- Logging -----------------------------------------------------------
    LOG_LEVEL: str = "INFO"
    LOG_JSON: bool = True


@lru_cache
def get_settings() -> Settings:
    """Cached settings accessor so we parse env vars only once."""
    return Settings()