"""
Memory model.

Represents a single unit of long-term / semantic memory about a user:
a fact, preference, important event, or conversation summary, along with
its vector embedding for similarity search. Using pgvector lets us do
`ORDER BY embedding <-> query_embedding LIMIT k` directly in Postgres,
avoiding a separate vector database while keeping the design swappable
(the repository layer hides this so a different vector store could be
plugged in later).
"""

import enum
import uuid
from typing import List, Optional

from pgvector.sqlalchemy import Vector
from sqlalchemy import Enum, ForeignKey, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.config.settings import get_settings
from app.database.base import Base, TimestampMixin

settings = get_settings()


class MemoryType(str, enum.Enum):
    fact = "fact"
    preference = "preference"
    event = "event"
    conversation_summary = "conversation_summary"


class Memory(Base, TimestampMixin):
    __tablename__ = "memories"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    memory_type: Mapped[MemoryType] = mapped_column(Enum(MemoryType), nullable=False)
    content: Mapped[str] = mapped_column(Text, nullable=False)
    embedding: Mapped[Optional[List[float]]] = mapped_column(
        Vector(settings.VECTOR_DIMENSIONS), nullable=True
    )
    importance: Mapped[int] = mapped_column(default=1)  # 1 (low) - 5 (critical)

    user: Mapped["User"] = relationship(back_populates="memories")
