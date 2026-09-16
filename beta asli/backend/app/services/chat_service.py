"""
Chat service.

Coordinates a single chat turn end-to-end:
  1. Resolve or create the conversation.
  2. Persist the user's message.
  3. Retrieve short-term (recent turns) and semantic (relevant memories) context.
  4. Build the final prompt and call the AI provider.
  5. Persist the assistant's reply.
  6. Opportunistically trigger conversation summarization.

Kept independent of FastAPI so it can be reused by the streaming endpoint,
background jobs, or tests without any HTTP concerns leaking in.
"""

import uuid
from typing import AsyncIterator, Optional, Tuple

from sqlalchemy.ext.asyncio import AsyncSession

from app.ai.base import AIProvider, ChatMessage
from app.config.settings import get_settings
from app.memory.memory_service import MemoryService
from app.models.message import Message, MessageRole
from app.repositories.conversation_repository import ConversationRepository
from app.utils.logging import get_logger

settings = get_settings()
logger = get_logger(__name__)


class ChatService:
    def __init__(self, db: AsyncSession, ai_provider: AIProvider):
        self.db = db
        self.ai_provider = ai_provider
        self.conversation_repo = ConversationRepository(db)
        self.memory_service = MemoryService(db, ai_provider)

    async def _prepare_turn(
        self, user_id: uuid.UUID, message: str, conversation_id: Optional[uuid.UUID]
    ) -> Tuple[uuid.UUID, list[ChatMessage]]:
        """Shared setup for both streaming and non-streaming chat turns."""
        if conversation_id is not None:
            conversation = await self.conversation_repo.get_by_id(conversation_id, user_id)
            if conversation is None:
                conversation = await self.conversation_repo.create(user_id=user_id)
        else:
            conversation = await self.conversation_repo.create(user_id=user_id)

        await self.conversation_repo.add_message(
            conversation.id, MessageRole.user, message
        )

        recent_turns = await self.memory_service.get_recent_turns(conversation.id)
        relevant_memories = await self.memory_service.retrieve_relevant_memories(
            user_id, message
        )
        memory_context = self.memory_service.build_context_block(relevant_memories)

        system_prompt = settings.AI_SYSTEM_PROMPT
        if memory_context:
            system_prompt = f"{system_prompt}\n\n{memory_context}"

        prompt: list[ChatMessage] = [{"role": "system", "content": system_prompt}]
        prompt.extend(recent_turns)

        return conversation.id, prompt

    async def send_message(
        self, user_id: uuid.UUID, message: str, conversation_id: Optional[uuid.UUID] = None
    ) -> Tuple[uuid.UUID, Message]:
        """Non-streaming chat turn. Returns (conversation_id, assistant Message)."""
        conv_id, prompt = await self._prepare_turn(user_id, message, conversation_id)

        reply_text = await self.ai_provider.generate_reply(prompt)

        assistant_message = await self.conversation_repo.add_message(
            conv_id, MessageRole.assistant, reply_text
        )

        await self.memory_service.summarize_conversation_if_needed(conv_id, user_id)

        return conv_id, assistant_message

    async def begin_turn(
        self, user_id: uuid.UUID, message: str, conversation_id: Optional[uuid.UUID] = None
    ) -> Tuple[uuid.UUID, list[ChatMessage]]:
        """
        Public entry point for callers (e.g. the streaming route) that need
        the resolved conversation_id *before* the AI reply starts streaming,
        so it can be sent to the client as the very first event.
        """
        return await self._prepare_turn(user_id, message, conversation_id)

    async def stream_reply_and_persist(
        self, conv_id: uuid.UUID, user_id: uuid.UUID, prompt: list[ChatMessage]
    ) -> AsyncIterator[str]:
        """
        Streams the AI reply chunk-by-chunk for an already-prepared turn
        (see `begin_turn`), then persists the full reply and triggers
        summarization once streaming completes.
        """
        full_reply = ""
        async for chunk in self.ai_provider.stream_reply(prompt):
            full_reply += chunk
            yield chunk

        await self.conversation_repo.add_message(conv_id, MessageRole.assistant, full_reply)
        await self.memory_service.summarize_conversation_if_needed(conv_id, user_id)

    async def stream_message(
        self, user_id: uuid.UUID, message: str, conversation_id: Optional[uuid.UUID] = None
    ) -> AsyncIterator[str]:
        """
        Streaming chat turn (text-only chunks, conversation_id not surfaced
        in-band). Kept for backward compatibility / non-HTTP callers; the
        HTTP route uses `begin_turn` + `stream_reply_and_persist` directly
        so it can emit conversation_id as the first SSE event.
        """
        conv_id, prompt = await self._prepare_turn(user_id, message, conversation_id)
        async for chunk in self.stream_reply_and_persist(conv_id, user_id, prompt):
            yield chunk
