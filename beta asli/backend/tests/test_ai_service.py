"""Tests for the AI provider abstraction and OpenAI implementation error handling."""

from unittest.mock import AsyncMock, patch

import pytest

from app.ai.openai_provider import OpenAIProvider
from app.utils.exceptions import AIServiceError


@pytest.mark.asyncio
async def test_generate_reply_wraps_unexpected_errors_as_ai_service_error():
    with patch("app.ai.openai_provider.AsyncOpenAI") as mock_client_cls:
        mock_client = mock_client_cls.return_value
        mock_client.responses.create = AsyncMock(side_effect=ValueError("boom"))

        provider = OpenAIProvider()
        with pytest.raises(AIServiceError):
            await provider.generate_reply([{"role": "user", "content": "hi"}])


@pytest.mark.asyncio
async def test_generate_reply_returns_output_text_on_success():
    with patch("app.ai.openai_provider.AsyncOpenAI") as mock_client_cls:
        mock_client = mock_client_cls.return_value
        mock_response = AsyncMock()
        mock_response.output_text = "Hello there!"
        mock_client.responses.create = AsyncMock(return_value=mock_response)

        provider = OpenAIProvider()
        reply = await provider.generate_reply([{"role": "user", "content": "hi"}])

        assert reply == "Hello there!"


@pytest.mark.asyncio
async def test_embed_returns_vector_on_success():
    with patch("app.ai.openai_provider.AsyncOpenAI") as mock_client_cls:
        mock_client = mock_client_cls.return_value
        mock_embedding_data = AsyncMock()
        mock_embedding_data.embedding = [0.1, 0.2, 0.3]
        mock_response = AsyncMock()
        mock_response.data = [mock_embedding_data]
        mock_client.embeddings.create = AsyncMock(return_value=mock_response)

        provider = OpenAIProvider()
        vector = await provider.embed("some text")

        assert vector == [0.1, 0.2, 0.3]
