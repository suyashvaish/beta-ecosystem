"""
Structured logging configuration.

Uses Python's standard logging module with a JSON formatter so logs are
easy to ingest into log aggregators (CloudWatch, Datadog, ELK, etc.) in
production, while staying human-readable in local development.
"""

import json
import logging
import sys
from datetime import datetime, timezone
from typing import Any, Dict

from app.config.settings import get_settings

settings = get_settings()


class JSONFormatter(logging.Formatter):
    """Formats log records as single-line JSON objects."""

    def format(self, record: logging.LogRecord) -> str:
        payload: Dict[str, Any] = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)

        # Never log secrets even if accidentally passed via `extra`
        REDACT_KEYS = {"password", "token", "api_key", "secret"}
        for key, value in getattr(record, "extra_fields", {}).items():
            if any(redacted in key.lower() for redacted in REDACT_KEYS):
                payload[key] = "***redacted***"
            else:
                payload[key] = value

        return json.dumps(payload, default=str)


def configure_logging() -> None:
    """Configure root logger once at application startup."""
    root_logger = logging.getLogger()
    root_logger.setLevel(settings.LOG_LEVEL)

    # Remove any pre-existing handlers (e.g. from uvicorn defaults)
    root_logger.handlers.clear()

    handler = logging.StreamHandler(sys.stdout)
    if settings.LOG_JSON:
        handler.setFormatter(JSONFormatter())
    else:
        handler.setFormatter(
            logging.Formatter(
                "%(asctime)s | %(levelname)s | %(name)s | %(message)s"
            )
        )
    root_logger.addHandler(handler)

    # Quiet down noisy third-party loggers
    logging.getLogger("uvicorn.access").setLevel(logging.WARNING)
    logging.getLogger("httpx").setLevel(logging.WARNING)


def get_logger(name: str) -> logging.Logger:
    return logging.getLogger(name)
