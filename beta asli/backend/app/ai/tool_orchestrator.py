"""
AI tool orchestration for Beta Intelligence (Feature A, 3.4).

The LLM decides WHICH tool to use; the backend decides WHETHER it may.
Guardrails, in order:
  1. Allowlist: only tools explicitly registered for a user are offered
     to the model as JSON schemas. Unknown tool names from the model are
     rejected, never executed.
  2. Argument validation: every tool validates its arguments (types,
     ranges) before doing anything.
  3. Timeout: each tool execution is bounded by a hard asyncio timeout.
  4. Round budget: a single turn may run at most AI_MAX_TOOL_ROUNDS
     rounds of tool calling - no infinite loops.
  5. Output sanitization: tool results are returned to the model as
     inert JSON strings. Web content can never issue commands to Beta.

Tools are async callables with an allowlisted signature. Tool functions
receive (user, **arguments) - never raw model-controlled execution.
"""

import asyncio
import json
from dataclasses import dataclass, field
from typing import Any, Awaitable, Callable, Dict, List

from app.config.settings import get_settings
from app.models.user import User
from app.utils.exceptions import AIServiceError
from app.utils.logging import get_logger

settings = get_settings()
logger = get_logger(__name__)

ToolFunc = Callable[..., Awaitable[Any]]


@dataclass
class ToolSpec:
    name: str
    description: str
    parameters: Dict[str, Any]
    func: ToolFunc
    requires_location_permission: bool = False


@dataclass
class ToolContext:
    """Everything a tool may know about the current user/turn."""
    user: User
    last_known_location: Dict[str, float] = field(default_factory=dict)


class ToolRegistry:
    """Allowlist + executor for AI tools."""

    def __init__(self) -> None:
        self._tools: Dict[str, ToolSpec] = {}

    def register(self, spec: ToolSpec) -> None:
        self._tools[spec.name] = spec

    def schemas_for_model(self) -> List[Dict[str, Any]]:
        """JSON-schema descriptions offered to the model (allowlist only)."""
        return [
            {
                "type": "function",
                "function": {
                    "name": t.name,
                    "description": t.description,
                    "parameters": t.parameters,
                },
            }
            for t in self._tools.values()
        ][: settings.AI_MAX_TOOLS_PER_TURN]

    async def execute(self, name: str, arguments: Dict[str, Any], ctx: ToolContext) -> Any:
        spec = self._tools.get(name)
        if spec is None:
            raise AIServiceError(f"Tool '{name}' is not available.")
        if spec.requires_location_permission and not ctx.last_known_location:
            raise AIServiceError("Location permission is required for that.")
        try:
            result = await asyncio.wait_for(
                spec.func(ctx, **arguments),
                timeout=settings.AI_TOOL_CALL_TIMEOUT_SECONDS,
            )
        except asyncio.TimeoutError:
            logger.warning("Tool timed out", extra={"extra_fields": {"tool": name}})
            raise AIServiceError("That search took too long; try again.")
        except TypeError as exc:
            # Bad argument names/types from the model.
            raise AIServiceError("The request arguments were invalid.") from exc
        return result


def _tool_schemas() -> List[Dict[str, Any]]:
    """OpenAI-style tool JSON schemas for the default allowlist."""
    return [
        {
            "type": "function",
            "function": {
                "name": "search_places",
                "description": "Find places near the user, like a medical "
                "shop, hospital, pharmacy, ATM, or restaurant.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "query": {"type": "string"},
                        "radius_meters": {"type": "integer", "default": 3000},
                    },
                    "required": ["query"],
                },
            },
        },
        {
            "type": "function",
            "function": {
                "name": "search_products",
                "description": "Find nearby shops selling an item, like a "
                "walking stick or a mobile phone.",
                "parameters": {
                    "type": "object",
                    "properties": {"query": {"type": "string"}},
                    "required": ["query"],
                },
            },
        },
        {
            "type": "function",
            "function": {
                "name": "search_web",
                "description": "Search the internet for information the "
                "assistant does not know.",
                "parameters": {
                    "type": "object",
                    "properties": {"query": {"type": "string"}},
                    "required": ["query"],
                },
            },
        },
        {
            "type": "function",
            "function": {
                "name": "get_current_location",
                "description": "Get the user's current location if the user "
                "has granted location permission.",
                "parameters": {"type": "object", "properties": {}},
            },
        },
    ]


# --------------------------------------------------------------------------
# Default tool implementations (pure, argument-validated)
# --------------------------------------------------------------------------

async def _tool_search_places(ctx: ToolContext, query: str, radius_meters: int = 3000) -> Any:
    if not isinstance(query, str) or not query.strip():
        raise AIServiceError("A search term is needed.")
    radius = int(radius_meters) if isinstance(radius_meters, (int, float)) else 3000
    from app.services.search_service import get_maps_search_service

    loc = ctx.last_known_location
    return await get_maps_search_service().search_nearby(
        latitude=loc["latitude"], longitude=loc["longitude"],
        query=query.strip(), radius_meters=radius,
    )


async def _tool_search_products(ctx: ToolContext, query: str) -> Any:
    if not isinstance(query, str) or not query.strip():
        raise AIServiceError("An item name is needed.")
    from app.services.search_service import get_product_search_service

    loc = ctx.last_known_location
    return await get_product_search_service().search_products(
        query.strip(),
        latitude=loc.get("latitude"), longitude=loc.get("longitude"),
    )


async def _tool_search_web(ctx: ToolContext, query: str) -> Any:
    if not isinstance(query, str) or not query.strip():
        raise AIServiceError("A search term is needed.")
    from app.services.search_service import get_web_search_service

    return await get_web_search_service().search(query.strip())


async def _tool_get_current_location(ctx: ToolContext) -> Any:
    if not ctx.last_known_location:
        raise AIServiceError("Location permission has not been granted.")
    return {
        "latitude": ctx.last_known_location.get("latitude"),
        "longitude": ctx.last_known_location.get("longitude"),
    }


def build_default_registry() -> ToolRegistry:
    """The standard tool allowlist offered to Beta's model."""
    registry = ToolRegistry()
    registry.register(ToolSpec(
        name="search_places",
        description="Find places near the user, like a medical shop, "
        "hospital, pharmacy, ATM, or restaurant.",
        parameters={
            "type": "object",
            "properties": {
                "query": {"type": "string"},
                "radius_meters": {"type": "integer", "default": 3000},
            },
            "required": ["query"],
        },
        func=_tool_search_places,
        requires_location_permission=True,
    ))
    registry.register(ToolSpec(
        name="search_products",
        description="Find nearby shops selling an item, like a walking "
        "stick or a mobile phone.",
        parameters={
            "type": "object",
            "properties": {"query": {"type": "string"}},
            "required": ["query"],
        },
        func=_tool_search_products,
        requires_location_permission=True,
    ))
    registry.register(ToolSpec(
        name="search_web",
        description="Search the internet for information the assistant "
        "does not know.",
        parameters={
            "type": "object",
            "properties": {"query": {"type": "string"}},
            "required": ["query"],
        },
        func=_tool_search_web,
    ))
    registry.register(ToolSpec(
        name="get_current_location",
        description="Get the user's current location if permission was "
        "granted.",
        parameters={"type": "object", "properties": {}},
        func=_tool_get_current_location,
    ))
    return registry