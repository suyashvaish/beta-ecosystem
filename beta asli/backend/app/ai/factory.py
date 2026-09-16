"""
Factory for obtaining the active AI provider.

This is the single place that decides which concrete `AIProvider` is used.
To integrate a different LLM provider in the future, add a new branch here
(and a new class implementing `AIProvider`) — no other code changes.
"""

from functools import lru_cache

from app.ai.base import AIProvider
from app.ai.openai_provider import OpenAIProvider


@lru_cache
def get_ai_provider() -> AIProvider:
    # Only OpenAI is implemented today; this indirection is what makes
    # swapping providers later a one-line change.
    return OpenAIProvider()
