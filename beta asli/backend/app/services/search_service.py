"""
Search services for Beta Intelligence.

Three provider-independent services, each returning plain dictionaries the
AI tool layer (or the Flutter apps) can render directly:

  - MapsSearchService: nearby places / place details via Google Maps
    Platform (Places API). Falls back honestly when the key is missing
    or the API fails - Beta never invents results.
  - WebSearchService: general web search through a provider chain:
    Tavily (free tier, LLM-oriented clean results) -> SerpApi (paid JSON
    API, ToS-compliant) -> DuckDuckGo (keyless library fallback).
    The first provider that is configured and responds wins; a provider
    failure falls through to the next instead of failing the whole tool.
  - ProductSearchService: product discovery through Google Maps
    "shopping-ish" local retailer search where available; the tool
    returns merchant, address, and rating information rather than
    fabricating prices.

All external calls are hard-timeout-bounded; secrets come only from
settings (env); failures surface as SearchUnavailable with a plain
message so the assistant can say so naturally in voice.
"""

import asyncio
from typing import Any, Dict, List, Optional

import httpx

from app.config.settings import get_settings
from app.utils.exceptions import AIServiceError
from app.utils.logging import get_logger

settings = get_settings()
logger = get_logger(__name__)

_MAPS_NEARBY_BASE = "https://maps.googleapis.com/maps/api/place/nearbysearch/json"
_MAPS_TEXT_BASE = "https://maps.googleapis.com/maps/api/place/textsearch/json"
_MAPS_DETAILS_BASE = "https://maps.googleapis.com/maps/api/place/details/json"
_SERPAPI_BASE = "https://serpapi.com/search.json"
_TAVILY_BASE = "https://api.tavily.com/search"


class SearchUnavailable(AIServiceError):
    """Raised when a search provider is not configured or unreachable."""


class MapsSearchService:
    """Google Maps Platform (Places API) search."""

    def _check_configured(self) -> None:
        if not settings.GOOGLE_MAPS_API_KEY:
            raise SearchUnavailable(
                "Location search is not configured on this server yet."
            )

    def _rank(self, results: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        # Google already returns results ordered by prominence/relevance
        # for nearby search; keep that order (spec 3.2 step 5).
        return results

    async def search_nearby(
        self,
        latitude: float,
        longitude: float,
        query: str,
        radius_meters: int = 3000,
        limit: int = 5,
    ) -> List[Dict[str, Any]]:
        """Nearby keyword search around a location (e.g. medical shops)."""
        self._check_configured()
        params = {
            "key": settings.GOOGLE_MAPS_API_KEY,
            "location": f"{latitude},{longitude}",
            "radius": min(max(radius_meters, 100), 50000),
            "keyword": query,
        }
        try:
            async with httpx.AsyncClient(
                timeout=settings.WEB_SEARCH_TIMEOUT_SECONDS
            ) as client:
                resp = await client.get(_MAPS_NEARBY_BASE, params=params)
                resp.raise_for_status()
                data = resp.json()
        except httpx.HTTPError as exc:
            logger.warning(
                "Maps nearby search failed",
                extra={"extra_fields": {"error": str(exc)}},
            )
            raise SearchUnavailable("Location search is not responding right now.") from exc
        if data.get("status") not in ("OK", "ZERO_RESULTS"):
            raise SearchUnavailable("Location search returned an error.")
        return self._to_places(data.get("results", [])[:limit])

    async def search_text(
        self, query: str, latitude: Optional[float] = None,
        longitude: Optional[float] = None, limit: int = 5,
    ) -> List[Dict[str, Any]]:
        """Text search (e.g. 'walking stick' retailers near the user)."""
        self._check_configured()
        params = {"key": settings.GOOGLE_MAPS_API_KEY, "query": query}
        if latitude is not None and longitude is not None:
            params["location"] = f"{latitude},{longitude}"
            params["radius"] = 5000
        try:
            async with httpx.AsyncClient(
                timeout=settings.WEB_SEARCH_TIMEOUT_SECONDS
            ) as client:
                resp = await client.get(_MAPS_TEXT_BASE, params=params)
                resp.raise_for_status()
                data = resp.json()
        except httpx.HTTPError as exc:
            logger.warning(
                "Maps text search failed",
                extra={"extra_fields": {"error": str(exc)}},
            )
            raise SearchUnavailable("Location search is not responding right now.") from exc
        if data.get("status") not in ("OK", "ZERO_RESULTS"):
            raise SearchUnavailable("Location search returned an error.")
        return self._to_places(data.get("results", [])[:limit])

    async def place_details(self, place_id: str) -> Dict[str, Any]:
        """Full details (address, phone, hours) for one place."""
        self._check_configured()
        params = {
            "key": settings.GOOGLE_MAPS_API_KEY,
            "placeid": place_id,
            "fields": "name,formatted_address,formatted_phone_number,"
                      "opening_hours,website,rating,url",
        }
        try:
            async with httpx.AsyncClient(
                timeout=settings.WEB_SEARCH_TIMEOUT_SECONDS
            ) as client:
                resp = await client.get(_MAPS_DETAILS_BASE, params=params)
                resp.raise_for_status()
                data = resp.json()
        except httpx.HTTPError as exc:
            raise SearchUnavailable("Location search is not responding right now.") from exc
        if data.get("status") != "OK":
            raise SearchUnavailable("Could not find that place.")
        return data.get("result", {})

    @staticmethod
    def _to_places(raw_results: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        places = []
        for r in raw_results:
            geometry = r.get("geometry", {}).get("location", {})
            places.append({
                "name": r.get("name"),
                "address": r.get("vicinity") or r.get("formatted_address"),
                "latitude": geometry.get("lat"),
                "longitude": geometry.get("lng"),
                "rating": r.get("rating"),
                "types": r.get("types", []),
                "place_id": r.get("place_id"),
            })
        return places


class WebSearchService:
    """
    General web search through a provider chain.

    Order (configurable via WEB_SEARCH_PROVIDERS):
      1. Tavily - free tier (1,000 searches/month), returns clean
         LLM-ready text, best default for an AI assistant.
      2. SerpApi - existing paid JSON provider, kept for deployments
         that already have a key.
      3. DuckDuckGo - keyless library fallback, no credentials needed.

    A provider that is not configured (missing key) is skipped; a
    provider that errors is logged and the chain falls through to the
    next. Only when every provider fails does the tool raise
    SearchUnavailable - Beta then says so honestly instead of inventing
    results.
    """

    def _provider_chain(self) -> List[str]:
        chain = [
            p.strip().lower()
            for p in settings.WEB_SEARCH_PROVIDERS.split(",")
            if p.strip()
        ]
        return chain or ["duckduckgo"]

    async def _search_tavily(self, query: str, limit: int) -> List[Dict[str, Any]]:
        if not settings.TAVILY_API_KEY:
            raise SearchUnavailable("tavily not configured")
        payload = {
            "api_key": settings.TAVILY_API_KEY,
            "query": query,
            "max_results": min(limit, 10),
            "include_answer": False,
        }
        try:
            async with httpx.AsyncClient(
                timeout=settings.WEB_SEARCH_TIMEOUT_SECONDS
            ) as client:
                resp = await client.post(_TAVILY_BASE, json=payload)
                resp.raise_for_status()
                data = resp.json()
        except (httpx.HTTPError, ValueError) as exc:
            raise SearchUnavailable("tavily error") from exc
        results = []
        for item in data.get("results", [])[:limit]:
            results.append({
                "title": item.get("title"),
                "link": item.get("url"),
                "snippet": item.get("content"),
            })
        if not results:
            raise SearchUnavailable("tavily returned no results")
        return results

    async def _search_serpapi(self, query: str, limit: int) -> List[Dict[str, Any]]:
        if not settings.SERPAPI_KEY:
            raise SearchUnavailable("serpapi not configured")
        params = {"api_key": settings.SERPAPI_KEY, "q": query, "num": max(limit, 10)}
        try:
            async with httpx.AsyncClient(
                timeout=settings.WEB_SEARCH_TIMEOUT_SECONDS
            ) as client:
                resp = await client.get(_SERPAPI_BASE, params=params)
                resp.raise_for_status()
                data = resp.json()
        except (httpx.HTTPError, ValueError) as exc:
            raise SearchUnavailable("serpapi error") from exc
        results = []
        for item in data.get("organic_results", [])[:limit]:
            results.append({
                "title": item.get("title"),
                "link": item.get("link"),
                "snippet": item.get("snippet"),
            })
        if not results:
            raise SearchUnavailable("serpapi returned no results")
        return results

    async def _search_duckduckgo(self, query: str, limit: int) -> List[Dict[str, Any]]:
        # Keyless fallback. duckduckgo-search is a synchronous library,
        # so it runs in a worker thread to keep the event loop free.
        def _ddg() -> List[Dict[str, Any]]:
            from duckduckgo_search import DDGS

            with DDGS() as ddgs:
                raw = ddgs.text(query, max_results=limit)
                return [
                    {
                        "title": r.get("title"),
                        "link": r.get("href"),
                        "snippet": r.get("body"),
                    }
                    for r in raw
                ]

        try:
            results = await asyncio.to_thread(_ddg)
        except Exception as exc:  # noqa: BLE001
            raise SearchUnavailable("duckduckgo error") from exc
        if not results:
            raise SearchUnavailable("duckduckgo returned no results")
        return results

    async def search(self, query: str, limit: int = 5) -> List[Dict[str, Any]]:
        failures: List[str] = []

        for provider in self._provider_chain():
            try:
                if provider == "tavily":
                    return await self._search_tavily(query, limit)
                if provider == "serpapi":
                    return await self._search_serpapi(query, limit)
                if provider == "duckduckgo":
                    return await self._search_duckduckgo(query, limit)
                logger.warning(
                    "Unknown web search provider in chain",
                    extra={"extra_fields": {"provider": provider}},
                )
            except SearchUnavailable as exc:
                failures.append(f"{provider}: {exc}")
                logger.info(
                    "Web search provider failed; trying next",
                    extra={"extra_fields": {"provider": provider, "error": str(exc)}},
                )

        raise SearchUnavailable(
            "Web search is not responding right now. Please try again."
        )


class ProductSearchService:
    """
    Product discovery.

    Today this resolves nearby retailers selling the item via Maps text
    search (merchant, address, rating) - honest, verifiable information
    with no fabricated prices. When a dedicated shopping API credential
    is configured later, add it here; the tool interface stays the same.
    """

    def __init__(self) -> None:
        self._maps = MapsSearchService()

    async def search_products(
        self, query: str, latitude: Optional[float] = None,
        longitude: Optional[float] = None, limit: int = 5,
    ) -> List[Dict[str, Any]]:
        results = await self._maps.search_text(
            f"buy {query}", latitude=latitude, longitude=longitude, limit=limit
        )
        for r in results:
            r["item"] = query
        return results


def get_maps_search_service() -> MapsSearchService:
    return MapsSearchService()


def get_web_search_service() -> WebSearchService:
    return WebSearchService()


def get_product_search_service() -> ProductSearchService:
    return ProductSearchService()