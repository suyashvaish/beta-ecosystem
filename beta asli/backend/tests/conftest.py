"""
Shared pytest fixtures.

Uses an in-memory SQLite database (via aiosqlite) for fast, dependency-free
unit tests. Note: pgvector-specific features (cosine similarity search)
are Postgres-only and are covered separately by tests that mock the
repository method rather than hitting real SQL, since SQLite has no
vector extension.
"""

from typing import AsyncIterator, List
from unittest.mock import AsyncMock

import pytest
import pytest_asyncio
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.ai.base import AIProvider, ChatMessage
from app.database.base import Base
from app.models.user import User


class FakeAIProvider(AIProvider):
    """Deterministic AI provider stand-in for tests — no network calls."""

    async def generate_reply(self, messages: List[ChatMessage]) -> str:
        last_user_msg = next(
            (m["content"] for m in reversed(messages) if m["role"] == "user"), ""
        )
        return f"Echo: {last_user_msg}"

    async def stream_reply(self, messages: List[ChatMessage]):
        reply = await self.generate_reply(messages)
        for word in reply.split():
            yield word + " "

    async def embed(self, text: str) -> List[float]:
        # Deterministic pseudo-embedding based on text length, for testing only.
        # Matches settings.VECTOR_DIMENSIONS (1536) so pgvector's column type
        # accepts it even though the `memories` table is excluded from the
        # SQLite test schema (see db_session fixture below).
        return [float(len(text) % 10)] * 1536


@pytest_asyncio.fixture
async def db_session() -> AsyncIterator[AsyncSession]:
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    async with session_factory() as session:
        yield session

    await engine.dispose()


@pytest_asyncio.fixture
async def test_user(db_session: AsyncSession) -> User:
    user = User(firebase_uid="test-firebase-uid", email="test@example.com")
    db_session.add(user)
    await db_session.flush()
    await db_session.refresh(user)
    return user


@pytest.fixture
def fake_ai_provider() -> FakeAIProvider:
    return FakeAIProvider()
