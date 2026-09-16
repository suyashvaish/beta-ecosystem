"""
Chat endpoints.

`POST /chat` is the primary endpoint described in the spec (simple
request/reply). `POST /chat/stream` offers the same capability as an SSE
stream for lower perceived latency on the Flutter client. `GET /chat/conversations`
and `GET /chat/conversations/{id}` support viewing history.
"""

import json
import uuid

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from sqlalchemy.ext.asyncio import AsyncSession

from app.ai.base import AIProvider
from app.ai.factory import get_ai_provider
from app.auth.dependencies import get_current_user
from app.database import get_db
from app.models.user import User
from app.repositories.conversation_repository import ConversationRepository
from app.schemas.chat import ChatRequest, ChatResponse, ConversationResponse
from app.services.chat_service import ChatService
from app.utils.logging import get_logger

logger = get_logger(__name__)
router = APIRouter(prefix="/chat", tags=["chat"])


def get_chat_service(
    db: AsyncSession = Depends(get_db),
    ai_provider: AIProvider = Depends(get_ai_provider),
) -> ChatService:
    return ChatService(db, ai_provider)


@router.post("", response_model=ChatResponse)
async def chat(
    payload: ChatRequest,
    current_user: User = Depends(get_current_user),
    chat_service: ChatService = Depends(get_chat_service),
):
    conversation_id, assistant_message = await chat_service.send_message(
        user_id=current_user.id,
        message=payload.message,
        conversation_id=payload.conversation_id,
    )
    return ChatResponse(
        reply=assistant_message.content,
        conversation_id=conversation_id,
        message_id=assistant_message.id,
    )


@router.post("/stream")
async def chat_stream(
    payload: ChatRequest,
    current_user: User = Depends(get_current_user),
    chat_service: ChatService = Depends(get_chat_service),
):
    """
    Server-Sent-Events stream of the assistant's reply, chunk by chunk.

    Event sequence:
      1. `event: conversation` — fired once, immediately, with
         `{"conversation_id": "..."}` so the client can attach follow-up
         turns to the same conversation even when starting a brand-new one.
      2. unnamed `data:` events — each `{"text": "..."}`, one per chunk.
      3. `event: done` — stream complete.
      4. `event: error` — only on failure, with `{"detail": "..."}`.
    """

    conversation_id, prompt = await chat_service.begin_turn(
        user_id=current_user.id,
        message=payload.message,
        conversation_id=payload.conversation_id,
    )

    async def event_generator():
        yield (
            "event: conversation\n"
            f"data: {json.dumps({'conversation_id': str(conversation_id)})}\n\n"
        )
        try:
            async for chunk in chat_service.stream_reply_and_persist(
                conversation_id, current_user.id, prompt
            ):
                yield f"data: {json.dumps({'text': chunk})}\n\n"
        except Exception as exc:  # pragma: no cover - defensive; keeps stream well-formed
            # Never forward raw exception text to the client - it can contain
            # internal details (DB errors, provider messages, stack info).
            # Log the real error server-side and send a safe message instead.
            logger.error(
                "Chat stream failed mid-response",
                extra={
                    "extra_fields": {
                        "conversation_id": str(conversation_id),
                        "error": str(exc),
                    }
                },
            )
            safe_message = "Beta couldn't finish that response. Please try again."
            yield f"event: error\ndata: {json.dumps({'detail': safe_message})}\n\n"
            return
        yield "event: done\ndata: {}\n\n"

    return StreamingResponse(event_generator(), media_type="text/event-stream")


@router.get("/conversations", response_model=list[ConversationResponse])
async def list_conversations(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    repo = ConversationRepository(db)
    return await repo.list_for_user(current_user.id)


@router.get("/conversations/{conversation_id}", response_model=ConversationResponse)
async def get_conversation(
    conversation_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    repo = ConversationRepository(db)
    conversation = await repo.get_by_id(conversation_id, current_user.id)
    if conversation is None:
        raise HTTPException(status_code=404, detail="Conversation not found")
    return conversation
