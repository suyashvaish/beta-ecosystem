"""Tests for the chat service (conversation + message persistence, AI integration)."""

from unittest.mock import AsyncMock

import pytest

from app.models.message import MessageRole
from app.repositories.conversation_repository import ConversationRepository
from app.services.chat_service import ChatService


def _make_chat_service(db_session, fake_ai_provider) -> ChatService:
    """
    Build a ChatService with semantic-memory search stubbed out.

    pgvector's cosine-distance operator (`<=>`) is Postgres-only, so unit
    tests run against SQLite mock out `search_similar` here; the real
    query is covered by integration tests against Postgres + pgvector.
    """
    service = ChatService(db_session, fake_ai_provider)
    service.memory_service.memory_repo.search_similar = AsyncMock(return_value=[])
    return service


@pytest.mark.asyncio
async def test_send_message_creates_conversation_and_messages(
    db_session, test_user, fake_ai_provider, monkeypatch
):
    service = _make_chat_service(db_session, fake_ai_provider)

    conversation_id, assistant_message = await service.send_message(
        user_id=test_user.id, message="Hello Beta"
    )

    assert conversation_id is not None
    assert assistant_message.role == MessageRole.assistant
    assert "Hello Beta" in assistant_message.content

    repo = ConversationRepository(db_session)
    conversation = await repo.get_by_id(conversation_id, test_user.id)
    assert conversation is not None
    assert len(conversation.messages) == 2  # user turn + assistant turn
    assert conversation.messages[0].role == MessageRole.user
    assert conversation.messages[0].content == "Hello Beta"


@pytest.mark.asyncio
async def test_send_message_continues_existing_conversation(
    db_session, test_user, fake_ai_provider
):
    service = _make_chat_service(db_session, fake_ai_provider)

    conversation_id, _ = await service.send_message(user_id=test_user.id, message="First")
    conversation_id_2, _ = await service.send_message(
        user_id=test_user.id, message="Second", conversation_id=conversation_id
    )

    assert conversation_id == conversation_id_2

    repo = ConversationRepository(db_session)
    conversation = await repo.get_by_id(conversation_id, test_user.id)
    assert len(conversation.messages) == 4


@pytest.mark.asyncio
async def test_stream_message_yields_chunks_and_persists_reply(
    db_session, test_user, fake_ai_provider
):
    service = _make_chat_service(db_session, fake_ai_provider)

    chunks = []
    async for chunk in service.stream_message(user_id=test_user.id, message="Stream this"):
        chunks.append(chunk)

    assert len(chunks) > 0
    full_text = "".join(chunks)
    assert "Stream this" in full_text
