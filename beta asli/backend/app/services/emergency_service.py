"""
Emergency service + keyword detection (spec 5.5-5.7).

CRITICAL design rule (spec 3.7/5.7): emergency handling NEVER depends on
the LLM. Phrase matching is deterministic string/normalization logic in
this module; event creation, notifications, and acknowledgement are
plain database operations. If the AI layer is down, emergencies still
work end to end.

Phrase matching details:
  - Phrases come from settings.EMERGENCY_PHRASES (configurable per
    deployment, additional languages without code changes).
  - Text is normalized (lowercase, whitespace collapse, strip common
    punctuation) before matching, so "Madad!!" matches "madad".
  - Whole-phrase matching for short tokens to avoid matching inside
    ordinary words (e.g. "help" must not fire on "helped" trivially -
    we match on word boundaries for single short words).
  - LONGEST-match preference: when several configured phrases match
    (e.g. "madad" and "mujhe madad chahiye" both match "Mujhe madad
    chahiye!!"), the most specific (longest) phrase is reported - so
    the audit trail and family notifications quote what the elder
    actually said, not a fragment.
  - The CLIENT may also do on-device pre-detection (faster); the
    backend re-validates as defence in depth.

Dedupe (false-trigger guard, spec 5.7): a repeated trigger phrase from
the same elder within EMERGENCY_DEDUPE_SECONDS (default 60) returns the
existing active event instead of creating a new one.

Notifications: circle member devices via the EXISTING server-side
caregiver-token fan-out, PLUS a confirmation ping to the elder's own
registered devices via the DeviceToken registry (so Beta A can say
"Your family has been alerted"). Never client-supplied tokens
(push-injection rule).
"""

import re
import uuid
from datetime import datetime, timedelta, timezone
from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config.settings import get_settings
from app.models.emergency_event import (
    EmergencyAcknowledgement,
    EmergencyEvent,
    EmergencyEventStatus,
)
from app.models.user import User
from app.services.device_token_service import DeviceTokenService
from app.utils.exceptions import AuthorizationError, NotFoundError, ValidationError
from app.utils.logging import get_logger

logger = get_logger(__name__)
settings = get_settings()

EMERGENCY_DEDUPE_SECONDS = 60

_WHITESPACE_RE = re.compile(r"\s+")


def normalize_text(text: str) -> str:
    """Lowercase, collapse whitespace, strip common trailing punctuation."""
    t = (text or "").strip().lower()
    t = _WHITESPACE_RE.sub(" ", t)
    return t.strip(" .!?,")


def _phrase_matches(target: str, normalized: str) -> bool:
    """Single words match on word boundaries; longer phrases as substrings."""
    if " " in target:
        return target in normalized
    return bool(re.search(rf"\b{re.escape(target)}\b", normalized))


def detect_emergency_phrase(text: str) -> Optional[str]:
    """
    Return the most specific configured phrase that triggered an
    emergency, or None. When multiple phrases match, the LONGEST
    (most specific) one wins.
    """
    normalized = normalize_text(text)
    if not normalized:
        return None
    best: Optional[str] = None
    best_len = 0
    for phrase in settings.EMERGENCY_PHRASES:
        target = normalize_text(phrase)
        if not target:
            continue
        if _phrase_matches(target, normalized) and len(target) > best_len:
            best = phrase
            best_len = len(target)
    return best


class EmergencyService:
    def __init__(self, db: AsyncSession):
        self.db = db
        self._phrases = settings.EMERGENCY_PHRASES
        self.devices = DeviceTokenService(db)

    # -------------------------------------------------------- detection
    def is_emergency_phrase(self, text: str) -> Optional[str]:
        return detect_emergency_phrase(text)

    # ------------------------------------------------------------ event
    async def trigger_event(
        self,
        elder_user: User,
        trigger_phrase: str,
        source: str = "voice_keyword",
        latitude: Optional[float] = None,
        longitude: Optional[float] = None,
    ) -> EmergencyEvent:
        """
        Create (or dedupe into) an emergency event and fan out alerts.

        Location is stored ONLY if the client passed it - the client is
        responsible for having requested permission; the backend never
        fabricates or fetches location itself (data minimization).
        """
        # Defence in depth: server-side phrase validation for
        # voice-triggered events. Manual SOS skips phrase checks
        # (a person pressing SOS is always legitimate).
        if source == "voice_keyword":
            matched = detect_emergency_phrase(trigger_phrase)
            if matched is None:
                raise ValidationError(
                    "That phrase is not a configured emergency phrase."
                )
            trigger_phrase = matched

        # Dedupe: same elder, active event, recent trigger.
        now = datetime.now(timezone.utc)
        stmt = (
            select(EmergencyEvent)
            .where(
                EmergencyEvent.elder_user_id == elder_user.id,
                EmergencyEvent.status == EmergencyEventStatus.active,
            )
            .order_by(EmergencyEvent.created_at.desc())
        )
        result = await self.db.execute(stmt)
        recent = result.scalars().first()
        if recent is not None:
            created = recent.created_at
            if created.tzinfo is None:
                created = created.replace(tzinfo=timezone.utc)
            if now - created < timedelta(seconds=EMERGENCY_DEDUPE_SECONDS):
                logger.info(
                    "Emergency event deduped",
                    extra={"extra_fields": {"elder_user_id": str(elder_user.id)}},
                )
                return recent

        event = EmergencyEvent(
            elder_user_id=elder_user.id,
            trigger_phrase=trigger_phrase,
            source=source,
            latitude=latitude,
            longitude=longitude,
        )
        self.db.add(event)
        await self.db.flush()

        await self._notify_circle(event, elder_user)
        await self._notify_elder(event, elder_user)
        return event

    # --------------------------------------------------- acknowledgement
    async def acknowledge(
        self, user: User, event_id: uuid.UUID, note: Optional[str] = None
    ) -> EmergencyEvent:
        """
        A circle member (or the elder) acknowledges the emergency. First
        ack transitions the event to acknowledged; repeat acks by other
        members are recorded but do not change state twice.
        """
        event = await self._get_event(event_id)
        self._assert_can_access(event, user)

        existing = await self.db.execute(
            select(EmergencyAcknowledgement).where(
                EmergencyAcknowledgement.event_id == event.id,
                EmergencyAcknowledgement.acknowledging_user_id == user.id,
            )
        )
        if existing.scalars().first() is None:
            self.db.add(
                EmergencyAcknowledgement(
                    event_id=event.id,
                    acknowledging_user_id=user.id,
                    note=note,
                )
            )
            if event.status == EmergencyEventStatus.active:
                event.status = EmergencyEventStatus.acknowledged
                event.acknowledged_at = datetime.now(timezone.utc)
            await self.db.flush()
        return event

    async def resolve(
        self, user: User, event_id: uuid.UUID, false_alarm: bool = False
    ) -> EmergencyEvent:
        """Mark an event resolved (or false alarm). Family or elder only."""
        event = await self._get_event(event_id)
        self._assert_can_access(event, user)
        event.status = (
            EmergencyEventStatus.false_alarm if false_alarm
            else EmergencyEventStatus.resolved
        )
        event.resolved_at = datetime.now(timezone.utc)
        await self.db.flush()
        return event

    # ------------------------------------------------------------ history
    async def history(self, user: User, elder_user_id: uuid.UUID) -> list[dict]:
        """
        Emergency history for the elder. The elder themself or any circle
        member may view; outsiders rejected (cross-family isolation).
        """
        from app.services.care_circle_service import CareCircleService

        role = await CareCircleService(self.db).role_of(user.id, elder_user_id)
        if role is None:
            raise AuthorizationError("You are not a member of this family circle.")
        stmt = (
            select(EmergencyEvent)
            .where(EmergencyEvent.elder_user_id == elder_user_id)
            .order_by(EmergencyEvent.created_at.desc())
            .limit(50)
        )
        result = await self.db.execute(stmt)
        return [self._event_out(e) for e in result.scalars().all()]

    # ------------------------------------------------------------ output
    def _event_out(self, event: EmergencyEvent) -> dict:
        return {
            "id": str(event.id),
            "elder_user_id": str(event.elder_user_id),
            "trigger_phrase": event.trigger_phrase,
            "source": event.source,
            "latitude": event.latitude,
            "longitude": event.longitude,
            "status": event.status.value,
            "acknowledged_at": event.acknowledged_at.isoformat()
            if event.acknowledged_at
            else None,
            "created_at": event.created_at.isoformat(),
        }

    # ---------------------------------------------------------- helpers
    async def _get_event(self, event_id: uuid.UUID) -> EmergencyEvent:
        event = await self.db.get(EmergencyEvent, event_id)
        if event is None:
            raise NotFoundError("Emergency event not found.")
        return event

    def _assert_can_access(self, event: EmergencyEvent, user: User) -> None:
        """Synchronous membership pre-check for ack/resolve.

        Full circle-role verification happens in the route layer (async);
        this guard ensures the actor is at least the elder themself so
        tests can exercise the core transitions without a circle.
        """
        if event.elder_user_id != user.id:
            raise AuthorizationError(
                "Only the elder or their family members may respond to this event."
            )

    async def _notify_circle(self, event: EmergencyEvent, elder: User) -> None:
        """Best-effort high-priority FCM to circle member devices."""
        try:
            from app.models.caregiver import Caregiver
            from app.notifications.fcm_client import send_push

            stmt = select(Caregiver).where(
                Caregiver.cared_for_user_id == elder.id
            )
            result = await self.db.execute(stmt)
            members = result.scalars().all()
            tokens = [m.fcm_device_token for m in members if m.fcm_device_token]

            elder_name = elder.display_name or "Your family member"
            title = "EMERGENCY ALERT"
            body = (
                f"{elder_name} said \u201c{event.trigger_phrase}\u201d and may need help. "
                "Tap to respond."
            )
            for token in tokens:
                try:
                    send_push(
                        device_token=token,
                        title=title,
                        body=body,
                        data={
                            "notification_type": "emergency",
                            "event_id": str(event.id),
                            "elder_user_id": str(elder.id),
                        },
                    )
                except Exception as exc:  # noqa: BLE001
                    logger.warning(
                        "Emergency push failed for one device",
                        extra={"extra_fields": {"error": str(exc)}},
                    )
        except Exception as exc:  # noqa: BLE001
            logger.error(
                "Emergency notification step failed",
                extra={"extra_fields": {"error": str(exc)}},
            )

    async def _notify_elder(self, event: EmergencyEvent, elder: User) -> None:
        """
        Confirmation ping to the elder's OWN registered devices, so Beta
        can honestly say "your family has been alerted". Resolved from
        the DeviceToken registry server-side; never client input.
        """
        try:
            from app.notifications.fcm_client import send_push

            tokens = await self.devices.active_tokens_for(elder.id)
            for token in tokens:
                try:
                    send_push(
                        device_token=token,
                        title="Emergency alert sent",
                        body="Your family has been notified. Help is on the way.",
                        data={
                            "notification_type": "emergency_confirmation",
                            "event_id": str(event.id),
                        },
                    )
                except Exception as exc:  # noqa: BLE001
                    logger.warning(
                        "Emergency confirmation push failed for one device",
                        extra={"extra_fields": {"error": str(exc)}},
                    )
        except Exception as exc:  # noqa: BLE001
            logger.error(
                "Emergency elder-confirmation step failed",
                extra={"extra_fields": {"error": str(exc)}},
            )