"""
Async database engine and session management.

We use SQLAlchemy 2.x's async engine with asyncpg as the driver. A single
engine is created per process; sessions are created per-request via the
`get_db` FastAPI dependency, ensuring each request gets an isolated
transaction scope that is committed/rolled back and closed automatically.
"""

from contextlib import asynccontextmanager
from typing import AsyncGenerator

from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from app.config.settings import get_settings

settings = get_settings()

def _build_engine() -> AsyncEngine:
    # SQLite (used in local/unit tests) doesn't support pool sizing options;
    # only pass them for real server-based databases like Postgres.
    engine_kwargs = {"echo": settings.DATABASE_ECHO, "pool_pre_ping": True}
    if not settings.DATABASE_URL.startswith("sqlite"):
        engine_kwargs["pool_size"] = settings.DB_POOL_SIZE
        engine_kwargs["max_overflow"] = settings.DB_MAX_OVERFLOW
    return create_async_engine(settings.DATABASE_URL, **engine_kwargs)


engine: AsyncEngine = _build_engine()

AsyncSessionLocal = async_sessionmaker(
    bind=engine,
    autoflush=False,
    autocommit=False,
    expire_on_commit=False,
)


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    """FastAPI dependency that yields a database session per request."""
    async with AsyncSessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()


@asynccontextmanager
async def session_scope() -> AsyncGenerator[AsyncSession, None]:
    """Context manager for use outside of request scope (e.g. background jobs)."""
    async with AsyncSessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()
