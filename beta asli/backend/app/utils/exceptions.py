"""Application-wide custom exceptions.

Using our own exception hierarchy (instead of raising HTTPException deep
inside services) keeps business logic decoupled from FastAPI/HTTP concerns.
A single exception handler in `main.py` maps these to HTTP responses.
"""


class AppError(Exception):
    """Base class for all application-raised errors."""

    status_code: int = 500
    default_message: str = "An unexpected error occurred"

    def __init__(self, message: str | None = None):
        super().__init__(message or self.default_message)
        self.message = message or self.default_message


class AuthenticationError(AppError):
    status_code = 401
    default_message = "Authentication failed"


class AuthorizationError(AppError):
    status_code = 403
    default_message = "You do not have permission to perform this action"


class NotFoundError(AppError):
    status_code = 404
    default_message = "Resource not found"


class ValidationError(AppError):
    status_code = 422
    default_message = "Invalid request data"


class RateLimitError(AppError):
    status_code = 429
    default_message = "Too many requests, please try again later"


class AIServiceError(AppError):
    status_code = 502
    default_message = "AI service is currently unavailable"
