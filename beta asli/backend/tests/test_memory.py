"""
Tests for the memory system.

`search_similar` relies on pgvector's cosine-distance operator, which
SQLite (used for fast unit tests) doesn't support. We test the memory
repository's non-vector operations against SQLite directly, and test
`MemoryService.retrieve_relevant_memories` by mocking the repository so
the vector-search SQL itself isn't exercised here (that's covered by
integration tests against a real Postgres+pgvector instance).
"""

from unittest.mock import AsyncMock

import pytest

from app.memory.memory_service import MemoryService
from app.models.memory import MemoryType


@pytest.mark.asyncio
async def test_get_recent_turns_returns_chat_messages(db_session, test_user, fake_ai_provider):
    from app.repositories.conversation_repository import ConversationRepository
    from app.models.message import MessageRole

    conv_repo = ConversationRepository(db_session)
    conversation = await conv_repo.create(user_id=test_user.id)
    await conv_repo.add_message(conversation.id, MessageRole.user, "What's the weather?")
    await conv_repo.add_message(conversation.id, MessageRole.assistant, "It's sunny!")

    memory_service = MemoryService(db_session, fake_ai_provider)
    turns = await memory_service.get_recent_turns(conversation.id)

    assert len(turns) == 2
    assert turns[0]["role"] == "user"
    assert turns[0]["content"] == "What's the weather?"


@pytest.mark.asyncio
async def test_retrieve_relevant_memories_uses_embedding_and_search(
    db_session, test_user, fake_ai_provider
):
    memory_service = MemoryService(db_session, fake_ai_provider)
    memory_service.memory_repo.search_similar = AsyncMock(return_value=[])

    result = await memory_service.retrieve_relevant_memories(test_user.id, "some query")

    assert result == []
    memory_service.memory_repo.search_similar.assert_awaited_once()


def test_build_context_block_formats_memories(fake_ai_provider):
    from types import SimpleNamespace

    memory_service = MemoryService(db=None, ai_provider=fake_ai_provider)
    fake_memories = [
        SimpleNamespace(memory_type=MemoryType.fact, content="Likes tea in the morning"),
    ]
    block = memory_service.build_context_block(fake_memories)
    assert "Likes tea in the morning" in block
    assert "fact" in block


def test_build_context_block_empty_returns_empty_string(fake_ai_provider):
    memory_service = MemoryService(db=None, ai_provider=fake_ai_provider)
    assert memory_service.build_context_block([]) == ""
