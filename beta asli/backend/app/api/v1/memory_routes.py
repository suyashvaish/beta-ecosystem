"""
Memory endpoints.

Mostly useful for debugging, admin tooling, and letting a caregiver/user
inspect or correct what Beta "remembers". Regular chat turns manage
memory automatically via `MemoryService`; these endpoints are a manual
escape hatch on top of the same service.
"""

import uuid as uuid_module
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query

from app.ai.base import AIProvider
from app.ai.factory import get_ai_provider
from app.auth.dependencies import get_current_user
from app.database import get_db
from app.memory.memory_service import MemoryService
from app.models.user import User
from app.repositories.memory_repository import MemoryRepository
from app.schemas.memory import MemoryCreateRequest, MemoryResponse

router = APIRouter(prefix="/memories", tags=["memory"])


@router.post("", response_model=MemoryResponse)
async def create_memory(
    payload: MemoryCreateRequest,
    current_user: User = Depends(get_current_user),
    db=Depends(get_db),
    ai_provider: AIProvider = Depends(get_ai_provider),
):
    memory_service = MemoryService(db, ai_provider)
    return await memory_service.store_memory(
        user_id=current_user.id,
        content=payload.content,
        memory_type=payload.memory_type,
        importance=payload.importance,
    )


@router.get("", response_model=list[MemoryResponse])
async def list_memories(
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
    current_user: User = Depends(get_current_user),
    db=Depends(get_db),
):
    repo = MemoryRepository(db)
    return await repo.list_for_user(current_user.id, limit=limit, offset=offset)


@router.delete("/{memory_id}", status_code=204)
async def delete_memory(
    memory_id: str,
    current_user: User = Depends(get_current_user),
    db=Depends(get_db),
):
    # Validate the id shape up front instead of a raw UUID() call that
    # would surface an unhandled 500 for malformed input.
    try:
        parsed_id = uuid_module.UUID(memory_id)
    except (ValueError, AttributeError, TypeError):
        raise HTTPException(status_code=404, detail="Memory not found")

    repo = MemoryRepository(db)
    memories = await repo.list_for_user(current_user.id)
    target = next((m for m in memories if m.id == parsed_id), None)
    if target is None:
        # 404 rather than a silent no-op 204: a caller must not be able
        # to probe which memory ids exist via a 204/404 difference...
        raise HTTPException(status_code=404, detail="Memory not found")
    await repo.delete(target)