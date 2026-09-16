"""Tests for repository-layer database operations."""

import pytest

from app.models.notification import NotificationType
from app.repositories.conversation_repository import ConversationRepository
from app.repositories.notification_repository import NotificationRepository
from app.models.message import MessageRole


@pytest.mark.asyncio
async def test_conversation_repository_add_and_fetch_messages(db_session, test_user):
    repo = ConversationRepository(db_session)
    conversation = await repo.create(user_id=test_user.id, title="Test Chat")

    await repo.add_message(conversation.id, MessageRole.user, "Hi")
    await repo.add_message(conversation.id, MessageRole.assistant, "Hello!")

    recent = await repo.get_recent_messages(conversation.id, limit=10)
    assert len(recent) == 2
    assert recent[0].content == "Hi"
    assert recent[1].content == "Hello!"


@pytest.mark.asyncio
async def test_conversation_repository_list_for_user(db_session, test_user):
    repo = ConversationRepository(db_session)
    await repo.create(user_id=test_user.id, title="Chat 1")
    await repo.create(user_id=test_user.id, title="Chat 2")

    conversations = await repo.list_for_user(test_user.id)
    assert len(conversations) == 2


@pytest.mark.asyncio
async def test_notification_repository_create_and_list(db_session, test_user):
    repo = NotificationRepository(db_session)
    await repo.create(
        user_id=test_user.id,
        notification_type=NotificationType.reminder,
        title="Take a walk",
        body="It's a nice day outside.",
    )

    notifications = await repo.list_for_user(test_user.id)
    assert len(notifications) == 1
    assert notifications[0].title == "Take a walk"
