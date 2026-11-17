"""
Self-hosted OpenAI-compatible provider for Beta Intelligence.

Works with ANY server exposing the OpenAI /chat/completions and
/embeddings endpoints:
  - Ollama           (local development): http://localhost:11434/v1
  - vLLM             (GPU production):    vLLM OpenAI server
  - llama.cpp server (lightweight prod):   llama-server --endpoint /v1

This lets Beta run on small open-weight instruct models (Qwen 2.5,
Gemma 3, etc.) with no OpenAI dependency. Tool calling is implemented
via the standard "tools" + "tool_calls" JSON schema, which these servers
support for tool-capable models.

Retries with exponential backoff are applied to transient errors via
tenacity, mirroring OpenAIProvider's behaviour, so callers never need to
know which server type is behind the interface.
"""

import json
from typing import Any, AsyncIterator, Dict, List

import httpx
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


class LocalOpenAICompatProvider(AIProvider):
    """AIProvider backed by a self-hosted OpenAI-compatible server."""

    def __init__(self) -> None:
        # Empty api_key: Ollama ignores it; vLLM/llama.cpp accept the
        # optional LOCAL_AI_API_KEY when configured.
        self._client = AsyncOpenAI(
            api_key=settings.LOCAL_AI_API_KEY or "not-set",
            base_url=settings.LOCAL_AI_BASE_URL,
            timeout=settings.AI_REQUEST_TIMEOUT_SECONDS,
        )

    # ------------------------------------------------------------------ chat
    @retry(
        reraise=True,
        stop=stop_after_attempt(settings.AI_MAX_RETRIES),
        wait=wait_exponential(multiplier=1, min=1, max=10),
        retry=retry_if_exception_type(_RETRYABLE_EXCEPTIONS),
    )
    async def generate_reply(self, messages: List[ChatMessage]) -> str:
        try:
            response = await self._client.chat.completions.create(
                model=settings.LOCAL_CHAT_MODEL,
                messages=[{"role": m["role"], "content": m["content"]} for m in messages],
            )
            content = response.choices[0].message.content
            if not content:
                raise AIServiceError("The local model returned an empty response")
            return content
        except _RETRYABLE_EXCEPTIONS:
            raise
        except AIServiceError:
            raise
        except Exception as exc:  # noqa: BLE001
            logger.error(
                "Local provider generate_reply failed",
                extra={"extra_fields": {"error": str(exc)}},
            )
            raise AIServiceError("Failed to generate a response from the AI service") from exc

    async def stream_reply(self, messages: List[ChatMessage]) -> AsyncIterator[str]:
        try:
            stream = await self._client.chat.completions.create(
                model=settings.LOCAL_CHAT_MODEL,
                messages=[{"role": m["role"], "content": m["content"]} for m in messages],
                stream=True,
            )
            async for chunk in stream:
                if chunk.choices and chunk.choices[0].delta.content:
                    yield chunk.choices[0].delta.content
        except _RETRYABLE_EXCEPTIONS as exc:
            logger.warning(
                "Local provider stream transient error",
                extra={"extra_fields": {"error": str(exc)}},
            )
            raise AIServiceError("AI service is temporarily unavailable, please retry") from exc
        except Exception as exc:  # noqa: BLE001
            logger.error(
                "Local provider stream_reply failed",
                extra={"extra_fields": {"error": str(exc)}},
            )
            raise AIServiceError("Failed to stream a response from the AI service") from exc

    # ------------------------------------------------------------- embeddings
    @retry(
        reraise=True,
        stop=stop_after_attempt(settings.AI_MAX_RETRIES),
        wait=wait_exponential(multiplier=1, min=1, max=10),
        retry=retry_if_exception_type(_RETRYABLE_EXCEPTIONS),
    )
    async def embed(self, text: str) -> List[float]:
        try:
            response = await self._client.embeddings.create(
                model=settings.LOCAL_EMBEDDING_MODEL,
                input=text,
            )
            return response.data[0].embedding
        except _RETRYABLE_EXCEPTIONS:
            raise
        except Exception as exc:  # noqa: BLE001
            logger.error(
                "Local provider embed failed",
                extra={"extra_fields": {"error": str(exc)}},
            )
            raise AIServiceError("Failed to generate embedding") from exc

    # ------------------------------------------------------------ tool calling
    async def generate_with_tools(
        self,
        messages: List[ChatMessage],
        tools: List[Dict[str, Any]],
    ) -> Any:
        """
        One round of model-driven tool selection.

        Returns the raw chat-completion message so the orchestrator can
        inspect .tool_calls (name + JSON arguments) or .content. The
        orchestrator executes tools with its own guards (allowlist,
        argument validation, timeout, round budget) - never here.
        """
        try:
            response = await self._client.chat.completions.create(
                model=settings.LOCAL_CHAT_MODEL,
                messages=[{"role": m["role"], "content": m["content"]} for m in messages],
                tools=tools,
                tool_choice="auto",
            )
            return response.choices[0].message
        except _RETRYABLE_EXCEPTIONS:
            raise
        except Exception as exc:  # noqa: BLE001
            logger.error(
                "Local provider tool round failed",
                extra={"extra_fields": {"error": str(exc)}},
            )
            raise AIServiceError("Failed to run a tool-calling round") from exc


def normalize_tool_call(raw: Any) -> Dict[str, Any]:
    """Best-effort conversion of a provider tool_call into {name, arguments}.

    Handles both structured tool_call objects and the plain-string JSON
    some small models emit; returns {"name": ..., "arguments": dict}.
    Raises AIServiceError on unparseable output.
    """
    try:
        name = getattr(raw, "name", None) or raw.get("name")
        args = getattr(raw, "arguments", None)
        if args is None:
            args = raw.get("arguments", {})
        if isinstance(args, str):
            args = json.loads(args) if args.strip() else {}
        if not name or not isinstance(args, dict):
            raise ValueError("missing name or non-dict arguments")
        return {"name": str(name), "arguments": args}
    except Exception as exc:
        raise AIServiceError("Model produced an invalid tool call") from exc