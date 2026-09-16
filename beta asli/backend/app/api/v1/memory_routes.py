"""
Memory endpoints.

Mostly useful for debugging, admin tooling, and letting a caregiver/user
inspect or correct what Beta "remembers". Regular chat turns manage
memory automatically via `MemoryService`; these endpoints are a manual
escape hatch on top of the same service.
"""

from fastapi import APIRouter, Depends

from app.ai.base import AIProvider
from app.ai.factory import get_ai_provider
from app.auth.dependencies import get_current_user
from app.database import get_db
from app.memory.memory_service import MemoryService
from app.models.user import User
from app.repositories.memory_repository import MemoryRepository
from app.schemas.memory import MemoryCreateRequest, MemoryResponse
from sqlalchemy.ext.asyncio import AsyncSession

router = APIRouter(prefix="/memories", tags=["memory"])


@router.post("", response_model=MemoryResponse)
async def create_memory(
    payload: MemoryCreateRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
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
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    repo = MemoryRepository(db)
    return await repo.list_for_user(current_user.id)


@router.delete("/{memory_id}", status_code=204)
async def delete_memory(
    memory_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    import uuid as _uuid

    repo = MemoryRepository(db)
    memories = await repo.list_for_user(current_user.id)
    target = next((m for m in memories if m.id == _uuid.UUID(memory_id)), None)
    if target:
        await repo.delete(target)
