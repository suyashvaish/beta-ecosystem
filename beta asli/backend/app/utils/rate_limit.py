"""
Simple sliding-window rate limiter middleware.

For a single-process/dev deployment this in-memory limiter is sufficient.
In a multi-instance production deployment, replace the in-memory store
with Redis (the interface below is intentionally minimal so that's a
localized change).

NOTES:
- Behind a reverse proxy / load balancer, `request.client.host` is the
  proxy's IP for every request. Trust `X-Forwarded-For` (first entry)
  when configured, otherwise all users share one bucket and one abuser
  can lock everyone out.
- Stale client buckets are pruned periodically so the store cannot grow
  unbounded (memory-exhaustion vector).
"""

import time
from collections import defaultdict, deque

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse

from app.config.settings import get_settings

settings = get_settings()

# Number of buckets tracked before a cleanup pass prunes idle ones.
_PRUNE_THRESHOLD = 10_000


class RateLimitMiddleware(BaseHTTPMiddleware):
    def __init__(self, app, requests_per_minute: int | None = None):
        super().__init__(app)
        self.limit = requests_per_minute or settings.RATE_LIMIT_PER_MINUTE
        self.window_seconds = 60
        self._hits: dict[str, deque] = defaultdict(deque)

    def _client_key(self, request: Request) -> str:
        forwarded = request.headers.get("x-forwarded-for")
        if forwarded:
            # First entry is the original client; later ones are proxies.
            return forwarded.split(",")[0].strip()
        return request.client.host if request.client else "unknown"

    async def dispatch(self, request: Request, call_next):
        client_key = self._client_key(request)
        now = time.monotonic()
        hits = self._hits[client_key]

        while hits and now - hits[0] > self.window_seconds:
            hits.popleft()

        if len(hits) >= self.limit:
            return JSONResponse(
                status_code=429,
                content={"detail": "Too many requests, please try again later"},
            )

        hits.append(now)

        # Periodic cleanup: drop idle buckets so memory stays bounded.
        if len(self._hits) > _PRUNE_THRESHOLD:
            self._prune(now)

        return await call_next(request)

    def _prune(self, now: float) -> None:
        stale = [
            key
            for key, bucket in self._hits.items()
            if not bucket or now - bucket[-1] > self.window_seconds
        ]
        for key in stale:
            del self._hits[key]