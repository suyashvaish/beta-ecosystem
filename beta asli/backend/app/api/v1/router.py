"""Aggregates all v1 routers into a single APIRouter."""

from fastapi import APIRouter

from app.api.v1 import (
    auth_routes,
    chat_routes,
    elderly_care_routes,
    memory_routes,
    notification_routes,
    speech_routes,
    user_routes,
)

api_router = APIRouter()
api_router.include_router(auth_routes.router)
api_router.include_router(user_routes.router)
api_router.include_router(chat_routes.router)
api_router.include_router(memory_routes.router)
api_router.include_router(notification_routes.router)
api_router.include_router(speech_routes.router)
api_router.include_router(elderly_care_routes.router)
