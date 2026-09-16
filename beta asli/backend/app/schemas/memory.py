"""Schemas for memory endpoints."""

import uuid
from datetime import datetime

from pydantic import BaseModel, Field

from app.models.memory import MemoryType


class MemoryCreateRequest(BaseModel):
    memory_type: MemoryType
    content: str = Field(..., min_length=1, max_length=4000)
    importance: int = Field(default=1, ge=1, le=5)


class MemoryResponse(BaseModel):
    id: uuid.UUID
    memory_type: MemoryType
    content: str
    importance: int
    created_at: datetime

    model_config = {"from_attributes": True}
