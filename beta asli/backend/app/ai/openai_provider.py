"""
OpenAI implementation of the AIProvider interface.

Uses the OpenAI Python SDK's async client. Retries with exponential
backoff are applied to transient errors (rate limits, timeouts, 5xx)
via `tenacity`. Any error that survives retries is wrapped into our own
`AIServiceError` so callers never need to know about OpenAI-specific
exception types.
"""

from typing import AsyncIterator, List

from openai import AsyncOpenAI, APIError, APITimeoutError, RateLimitError as OpenAIRateLimitError
from tenacity import (
    retry,
    retry_if_exception_type,
    stop_after_attempt,
    wait_exponential,
)

from app.ai.base import AIProvider, ChatMessage
from app.config.settings import get_settings
from app.utils.exceptions import AIServiceError
from app.utils.logging import get_logger

settings = get_settings()
logger = get_logger(__name__)

_RETRYABLE_EXCEPTIONS = (APITimeoutError, OpenAIRateLimitError, APIError)


class OpenAIProvider(AIProvider):
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
    async def generate_reply(self, messages: List[ChatMessage]) -> str:
        try:
            response = await self._client.responses.create(
                model=settings.OPENAI_MODEL,
                input=[{"role": m["role"], "content": m["content"]} for m in messages],
            )
            return response.output_text
        except _RETRYABLE_EXCEPTIONS:
            raise
        except Exception as exc:  # noqa: BLE001
            logger.error("OpenAI generate_reply failed", extra={"extra_fields": {"error": str(exc)}})
            raise AIServiceError("Failed to generate a response from the AI service") from exc

    async def stream_reply(self, messages: List[ChatMessage]) -> AsyncIterator[str]:
        try:
            async with self._client.responses.stream(
                model=settings.OPENAI_MODEL,
                input=[{"role": m["role"], "content": m["content"]} for m in messages],
            ) as stream:
                async for event in stream:
                    if event.type == "response.output_text.delta":
                        yield event.delta
        except _RETRYABLE_EXCEPTIONS as exc:
            logger.warning("OpenAI stream_reply transient error", extra={"extra_fields": {"error": str(exc)}})
            raise AIServiceError("AI service is temporarily unavailable, please retry") from exc
        except Exception as exc:  # noqa: BLE001
            logger.error("OpenAI stream_reply failed", extra={"extra_fields": {"error": str(exc)}})
            raise AIServiceError("Failed to stream a response from the AI service") from exc

    @retry(
        reraise=True,
        stop=stop_after_attempt(settings.AI_MAX_RETRIES),
        wait=wait_exponential(multiplier=1, min=1, max=10),
        retry=retry_if_exception_type(_RETRYABLE_EXCEPTIONS),
    )
    async def embed(self, text: str) -> List[float]:
        try:
            response = await self._client.embeddings.create(
                model=settings.OPENAI_EMBEDDING_MODEL,
                input=text,
            )
            return response.data[0].embedding
        except _RETRYABLE_EXCEPTIONS:
            raise
        except Exception as exc:  # noqa: BLE001
            logger.error("OpenAI embed failed", extra={"extra_fields": {"error": str(exc)}})
            raise AIServiceError("Failed to generate embedding") from exc
