"""
Data access for the Memory model, including semantic similarity search.

`search_similar` uses pgvector's cosine-distance operator (`<=>`) to find
the top-k memories closest to a query embedding. Because this query is
expressed through SQLAlchemy's `.op()` mechanism, swapping the underlying
vector store later only requires changing this repository, not any
calling code.
"""

import uuid
from typing import List, Optional, Sequence

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.memory import Memory, MemoryType


class MemoryRepository:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def create(
        self,
        user_id: uuid.UUID,
        memory_type: MemoryType,
        content: str,
        embedding: Optional[List[float]] = None,
        importance: int = 1,
    ) -> Memory:
        memory = Memory(
            user_id=user_id,
            memory_type=memory_type,
            content=content,
            embedding=embedding,
            importance=importance,
        )
        self.db.add(memory)
        await self.db.flush()
        await self.db.refresh(memory)
        return memory

    async def list_for_user(
        self, user_id: uuid.UUID, memory_type: Optional[MemoryType] = None
    ) -> Sequence[Memory]:
        stmt = select(Memory).where(Memory.user_id == user_id)
        if memory_type is not None:
            stmt = stmt.where(Memory.memory_type == memory_type)
        stmt = stmt.order_by(Memory.created_at.desc())
        result = await self.db.execute(stmt)
        return result.scalars().all()

    async def search_similar(
        self, user_id: uuid.UUID, query_embedding: List[float], top_k: int
    ) -> Sequence[Memory]:
        """Return the top_k memories most semantically similar to the query."""
        stmt = (
            select(Memory)
            .where(Memory.user_id == user_id, Memory.embedding.is_not(None))
            .order_by(Memory.embedding.cosine_distance(query_embedding))
            .limit(top_k)
        )
        result = await self.db.execute(stmt)
        return result.scalars().all()

    async def delete(self, memory: Memory) -> None:
        await self.db.delete(memory)
        await self.db.flush()
