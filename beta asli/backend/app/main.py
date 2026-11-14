"""
Application entrypoint.

Wires together configuration, logging, middleware, exception handling,
and the versioned API router. Run locally with:

    uvicorn app.main:app --reload

or via Docker (see docker-compose.yml).
"""

from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.api.v1.router import api_router
from app.config.settings import get_settings
from app.utils.exceptions import AppError
from app.utils.logging import configure_logging, get_logger
from app.utils.rate_limit import RateLimitMiddleware

settings = get_settings()
configure_logging()
logger = get_logger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info(f"Starting {settings.APP_NAME} in {settings.ENVIRONMENT} mode")
    yield
    logger.info("Shutting down")


app = FastAPI(
    title=settings.APP_NAME,
    version="1.0.0",
    description=(
        "Backend for Beta, an AI voice assistant, designed to grow into a "
        "full elderly-care AI platform."
    ),
    lifespan=lifespan,
    # debug=False always: settings.DEBUG controls logging verbosity, but
    # FastAPI's debug mode embeds raw tracebacks in error responses and
    # re-raises exceptions - never acceptable in production.
    debug=False,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.ALLOWED_ORIGINS,  # explicit origins only, never "*"
    allow_credentials=True,
    allow_methods=settings.ALLOWED_METHODS,
    allow_headers=settings.ALLOWED_HEADERS,
)
app.add_middleware(RateLimitMiddleware)


@app.exception_handler(AppError)
async def app_error_handler(request: Request, exc: AppError) -> JSONResponse:
    """
    Central mapping from our domain exceptions to HTTP responses.

    Keeps services/repositories free of any HTTP-specific code — they just
    raise `AppError` subclasses and this is the only place that translates
    them into responses.
    """
    logger.warning(
        "Handled application error",
        extra={
            "extra_fields": {
                "path": str(request.url),
                "error_type": type(exc).__name__,
                "message": exc.message,
            }
        },
    )
    return JSONResponse(status_code=exc.status_code, content={"detail": exc.message})


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    logger.error(
        "Unhandled exception",
        extra={"extra_fields": {"path": str(request.url), "error": str(exc)}},
    )
    return JSONResponse(status_code=500, content={"detail": "An unexpected error occurred"})


@app.get("/health", tags=["health"])
async def health_check():
    """Liveness/readiness probe used by Docker/Kubernetes and load balancers."""
    # Environment name intentionally omitted - it leaks deployment detail.
    return {"status": "ok"}


app.include_router(api_router, prefix=settings.API_V1_PREFIX)