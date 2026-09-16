"""
Abstract interface for LLM providers.

Any provider (OpenAI, Anthropic, local model, etc.) implements this
interface. API routes and services depend only on `AIProvider`, never on
a concrete provider class, so the underlying model can be swapped by
changing a single factory function (see `app.ai.factory`).
"""

from abc import ABC, abstractmethod
from typing import AsyncIterator, List, TypedDict


class ChatMessage(TypedDict):
    role: str  # "system" | "user" | "assistant"
    content: str


class AIProvider(ABC):
    @abstractmethod
    async def generate_reply(self, messages: List[ChatMessage]) -> str:
        """Generate a single complete reply for the given message history."""
        raise NotImplementedError

    @abstractmethod
    async def stream_reply(self, messages: List[ChatMessage]) -> AsyncIterator[str]:
        """Yield the reply incrementally as text chunks."""
        raise NotImplementedError
        yield  # pragma: no cover - makes this an async generator for type checkers

    @abstractmethod
    async def embed(self, text: str) -> List[float]:
        """Return a vector embedding for the given text."""
        raise NotImplementedError
