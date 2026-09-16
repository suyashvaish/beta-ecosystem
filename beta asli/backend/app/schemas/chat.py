"""Schemas for the AI chat endpoints."""

import uuid
from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, Field

from app.models.message import MessageRole


class ChatRequest(BaseModel):
    message: str = Field(..., min_length=1, max_length=8000)
    conversation_id: Optional[uuid.UUID] = Field(
        default=None,
        description="Existing conversation to continue; omit to start a new one",
    )


class ChatResponse(BaseModel):
    reply: str
    conversation_id: uuid.UUID
    message_id: uuid.UUID


class MessageResponse(BaseModel):
    id: uuid.UUID
    role: MessageRole
    content: str
    created_at: datetime

    model_config = {"from_attributes": True}


class ConversationResponse(BaseModel):
    id: uuid.UUID
    title: Optional[str]
    summary: Optional[str]
    is_active: bool
    created_at: datetime
    messages: List[MessageResponse] = []

    model_config = {"from_attributes": True}
