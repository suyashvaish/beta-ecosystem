"""
Search services for Beta Intelligence.

Three provider-independent services, each returning plain dictionaries the
AI tool layer (or the Flutter apps) can render directly:

  - MapsSearchService: nearby places / place details via Google Maps
    Platform (Places API). Falls back honestly when the key is missing
    or the API fails - Beta never invents results.
  - WebSearchService: general web search via SerpApi's JSON API
    (ToS-compliant; no scraping of Google result pages).
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
    """General web search via SerpApi (ToS-compliant JSON API)."""

    def _check_configured(self) -> None:
        if not settings.SERPAPI_KEY:
            raise SearchUnavailable("Web search is not configured on this server yet.")

    async def search(self, query: str, limit: int = 5) -> List[Dict[str, Any]]:
        self._check_configured()
        params = {"api_key": settings.SERPAPI_KEY, "q": query, "num": max(limit, 10)}
        try:
            async with httpx.AsyncClient(
                timeout=settings.WEB_SEARCH_TIMEOUT_SECONDS
            ) as client:
                resp = await client.get(_SERPAPI_BASE, params=params)
                resp.raise_for_status()
                data = resp.json()
        except httpx.HTTPError as exc:
            logger.warning(
                "Web search failed",
                extra={"extra_fields": {"error": str(exc)}},
            )
            raise SearchUnavailable("Web search is not responding right now.") from exc
        results = []
        for item in data.get("organic_results", [])[:limit]:
            results.append({
                "title": item.get("title"),
                "link": item.get("link"),
                "snippet": item.get("snippet"),
            })
        return results


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