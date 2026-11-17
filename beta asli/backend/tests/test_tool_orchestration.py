"""
Tests for Beta Intelligence tool orchestration (Feature A).

Focus: the guardrails, not the live model:
  - unknown tool names are rejected, never executed
  - argument validation rejects bad types
  - timeouts surface as honest errors from the registry itself
  - tool results are inert JSON for the model
  - schemas_for_model exposes only the allowlist
"""

import asyncio

import pytest

from app.ai.tool_orchestrator import (
    ToolContext,
    ToolRegistry,
    ToolSpec,
    build_default_registry,
)
from app.utils.exceptions import AIServiceError


class _FakeUser:
    id = "test-user"


@pytest.mark.asyncio
async def test_unknown_tool_rejected():
    registry = ToolRegistry()
    with pytest.raises(AIServiceError):
        await registry.execute("rm_rf", {}, ToolContext(user=_FakeUser()))


@pytest.mark.asyncio
async def test_bad_arguments_rejected():
    registry = ToolRegistry()

    async def echo(ctx, text):
        return text

    registry.register(ToolSpec(
        name="echo",
        description="echo",
        parameters={"type": "object", "properties": {"text": {"type": "string"}}},
        func=echo,
    ))
    # Non-string argument: registry must reject before the tool runs.
    with pytest.raises(AIServiceError):
        await registry.execute("echo", {"text": 12345}, ToolContext(user=_FakeUser()))


@pytest.mark.asyncio
async def test_timeout_surfaces_error():
    """
    The registry's own asyncio.wait_for(AI_TOOL_CALL_TIMEOUT_SECONDS=10)
    must cancel a stuck tool and raise AIServiceError (not TimeoutError).
    The tool sleeps 60s so only the registry guardrail can fire.
    """
    registry = ToolRegistry()

    async def slow(ctx):
        await asyncio.sleep(60)

    registry.register(ToolSpec(
        name="slow", description="slow",
        parameters={"type": "object", "properties": {}}, func=slow,
    ))
    ctx = ToolContext(user=_FakeUser())
    with pytest.raises(AIServiceError):
        await registry.execute("slow", {}, ctx)


@pytest.mark.asyncio
async def test_allowlist_only_in_schemas():
    registry = build_default_registry()
    schemas = registry.schemas_for_model()
    names = {s["function"]["name"] for s in schemas}
    assert "search_places" in names
    assert "search_web" in names
    assert "get_current_location" in names
    # Guardrail: no arbitrary tools leak to the model.
    assert len(names) <= 8


@pytest.mark.asyncio
async def test_location_required_for_places_search():
    registry = build_default_registry()
    ctx = ToolContext(user=_FakeUser(), last_known_location={})
    with pytest.raises(AIServiceError):
        await registry.execute("search_places", {"query": "doctor"}, ctx)


@pytest.mark.asyncio
async def test_registry_allows_only_registered():
    registry = build_default_registry()
    # "search_places" is registered; tools that were never registered
    # must not be executable even if the model names them.
    with pytest.raises(AIServiceError):
        await registry.execute("send_family_message", {}, ToolContext(user=_FakeUser()))