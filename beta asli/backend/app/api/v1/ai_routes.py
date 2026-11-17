"""
AI routes for Beta Intelligence (Feature A).

  POST /chat       - tool-aware chat turn (search/place/product results
                     are returned alongside the assistant reply so the
                     Flutter app can render result cards).
  GET  /status     - which AI provider is active and which tools are
                     available (lets the app show honest capability state
                     instead of guessing).
"""

import uuid
from typing import Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.ai.factory import get_ai_provider
from app.auth.dependencies import get_current_user
from app.database import get_db
from app.models.user import User
from app.services.tool_chat_service import ToolAwareChatService
from app.utils.rate_limit import rate_limiter
from app.utils.exceptions import AIServiceError
from app.utils.logging import get_logger

logger = get_logger(__name__)

router = APIRouter(prefix="/ai", tags=["ai"])


class ToolChatRequest(BaseModel):
    message: str = Field(..., min_length=1, max_length=2000)
    conversation_id: Optional[uuid.UUID] = None
    latitude: Optional[float] = Field(default=None, ge=-90, le=90)
    longitude: Optional[float] = Field(default=None, ge=-180, le=180)


class ToolChatResponse(BaseModel):
    conversation_id: uuid.UUID
    reply: str
    tool_results: list = []


@router.post("/chat", response_model=ToolChatResponse)
async def ai_chat(
    body: ToolChatRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    rate_limiter.check(f"ai_chat:{user.id}")
    location = None
    if body.latitude is not None and body.longitude is not None:
        location = {"latitude": body.latitude, "longitude": body.longitude}

    service = ToolAwareChatService(db, get_ai_provider())
    conv_id, assistant_msg, tool_results = await service.send_message_with_tools(
        user_id=user.id,
        message=body.message,
        conversation_id=body.conversation_id,
        last_known_location=location,
    )
    return ToolChatResponse(
        conversation_id=conv_id,
        reply=assistant_msg.content,
        tool_results=tool_results,
    )


@router.get("/status")
async def ai_status(user: User = Depends(get_current_user)):
    provider = get_ai_provider()
    provider_name = type(provider).__name__
    # Honest capability report: search tools work only when their
    # provider credentials are configured.
    from app.config.settings import get_settings
    s = get_settings()
    return {
        "provider": provider_name,
        "tools": {
            "search_places": bool(s.GOOGLE_MAPS_API_KEY),
            "search_products": bool(s.GOOGLE_MAPS_API_KEY),
            "search_web": bool(s.SERPAPI_KEY),
            "location": True,
        },
    }