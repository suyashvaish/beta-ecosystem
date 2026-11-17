"""Aggregates all v1 routers into a single APIRouter."""

from fastapi import APIRouter

from app.api.v1 import (
    ai_routes,
    auth_routes,
    care_circle_routes,
    chat_routes,
    connect_routes,
    elderly_care_routes,
    family_talk_routes,
    memory_routes,
    notification_routes,
    speech_routes,
    user_routes,
)

api_router = APIRouter()
api_router.include_router(auth_routes.router)
api_router.include_router(user_routes.router)
api_router.include_router(chat_routes.router)
api_router.include_router(ai_routes.router)
api_router.include_router(care_circle_routes.router)
api_router.include_router(family_talk_routes.router)
api_router.include_router(connect_routes.router)
api_router.include_router(memory_routes.router)
api_router.include_router(notification_routes.router)
api_router.include_router(speech_routes.router)
api_router.include_router(elderly_care_routes.router)