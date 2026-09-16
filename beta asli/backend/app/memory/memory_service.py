"""
Memory service.

Orchestrates the different kinds of memory Beta uses:

- Short-term memory: the last N raw messages of the active conversation
  (fetched directly from `ConversationRepository`, no embeddings needed).
- Long-term / semantic memory: durable facts, preferences, and important
  events, stored with embeddings in the `memories` table and retrieved by
  vector similarity to the current user message.
- Conversation summaries: periodically generated and stored back onto the
  conversation, so very long conversations don't blow the context window.

`get_context_for_prompt` is the single entry point the chat service calls
before generating a reply — this is also the seam where full RAG (e.g.
retrieval over external documents) can be added later without touching
the chat service.
"""

import uuid
from typing import List, Sequence

from sqlalchemy.ext.asyncio import AsyncSession

from app.ai.base import AIProvider, ChatMessage
from app.models.memory import Memory, MemoryType
from app.repositories.conversation_repository import ConversationRepository
from app.repositories.memory_repository import MemoryRepository
from app.config.settings import get_settings
from app.utils.logging import get_logger

settings = get_settings()
logger = get_logger(__name__)


class MemoryService:
    def __init__(self, db: AsyncSession, ai_provider: AIProvider):
        self.db = db
        self.ai_provider = ai_provider
        self.conversation_repo = ConversationRepository(db)
        self.memory_repo = MemoryRepository(db)

    async def get_recent_turns(self, conversation_id: uuid.UUID) -> List[ChatMessage]:
        """Short-term memory: recent raw turns from this conversation."""
        messages = await self.conversation_repo.get_recent_messages(
            conversation_id, limit=settings.SHORT_TERM_MEMORY_TURNS
        )
        return [{"role": m.role.value, "content": m.content} for m in messages]

    async def retrieve_relevant_memories(
        self, user_id: uuid.UUID, query_text: str
    ) -> Sequence[Memory]:
        """Semantic memory: memories most relevant to the current message."""
        try:
            query_embedding = await self.ai_provider.embed(query_text)
        except Exception:  # noqa: BLE001
            logger.warning("Embedding failed; skipping semantic memory retrieval")
            return []
        return await self.memory_repo.search_similar(
            user_id=user_id,
            query_embedding=query_embedding,
            top_k=settings.MEMORY_TOP_K,
        )

    async def store_memory(
        self,
        user_id: uuid.UUID,
        content: str,
        memory_type: MemoryType = MemoryType.fact,
        importance: int = 1,
    ) -> Memory:
        """Persist a new long-term memory, embedding it for future retrieval."""
        embedding = await self.ai_provider.embed(content)
        return await self.memory_repo.create(
            user_id=user_id,
            memory_type=memory_type,
            content=content,
            embedding=embedding,
            importance=importance,
        )

    async def summarize_conversation_if_needed(
        self, conversation_id: uuid.UUID, user_id: uuid.UUID
    ) -> None:
        """
        Regenerate the conversation summary once it grows long.

        This keeps prompts small for long-running conversations while still
        giving the model awareness of what was discussed earlier.
        """
        messages = await self.conversation_repo.get_recent_messages(
            conversation_id, limit=settings.SHORT_TERM_MEMORY_TURNS * 2
        )
        if len(messages) < settings.SHORT_TERM_MEMORY_TURNS * 2:
            return  # not long enough yet

        transcript = "\n".join(f"{m.role.value}: {m.content}" for m in messages)
        summary_prompt: List[ChatMessage] = [
            {
                "role": "system",
                "content": (
                    "Summarize the following conversation in 3-5 sentences, "
                    "focusing on facts, decisions, and anything the assistant "
                    "should remember going forward."
                ),
            },
            {"role": "user", "content": transcript},
        ]
        summary = await self.ai_provider.generate_reply(summary_prompt)

        conversation = await self.conversation_repo.get_by_id(conversation_id, user_id)
        if conversation:
            await self.conversation_repo.update_summary(conversation, summary)
            await self.store_memory(
                user_id=user_id,
                content=summary,
                memory_type=MemoryType.conversation_summary,
                importance=2,
            )

    def build_context_block(self, memories: Sequence[Memory]) -> str:
        """Render retrieved memories into a system-prompt-friendly text block."""
        if not memories:
            return ""
        lines = [f"- ({m.memory_type.value}) {m.content}" for m in memories]
        return "Relevant things you know about this user:\n" + "\n".join(lines)
