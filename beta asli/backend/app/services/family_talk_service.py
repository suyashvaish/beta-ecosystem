"""
Family Talk service (Feature C).

Two-way elder <-> circle communication. Authorization model:
  - The elder themself can always send/read in their own conversation.
  - Circle members need ANY role (viewer+) to read and send - Family
    Talk is the basic family connectivity feature; per-role send
    restrictions can be added later without schema changes.
  - Outsiders (no membership) get AuthorizationError - enforced
    SERVER-SIDE here, never by hiding UI (spec 11).

Message flow mirrors the existing NotificationService pattern:
persist first (source of truth), then best-effort FCM push to the
OTHER participants' registered devices. Delivery failures never lose
the message - recipients fetch history on next app open (offline
recovery).

Audio: only metadata is stored here. The audio bytes go to storage via
the speech/upload routes (existing pattern); audio_url must be an
authenticated https storage URL. This service never accepts raw audio.
"""

import uuid
from datetime import datetime, timezone
from typing import Optional, Sequence

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.care_circle import CircleRole  # noqa: F401 (re-export convenience)
from app.models.family_message import (
    FamilyConversation,
    FamilyMessageType,
    FamilyTalkMessage,
)
from app.models.user import User
from app.services.care_circle_service import CareCircleService
from app.utils.exceptions import AuthorizationError, ValidationError
from app.utils.logging import get_logger

logger = get_logger(__name__)

MAX_TEXT_LENGTH = 4000
MAX_VOICE_DURATION_SECONDS = 120


class FamilyTalkService:
    def __init__(self, db: AsyncSession):
        self.db = db
        self.circles = CareCircleService(db)

    # ---------------------------------------------------- conversation
    async def get_or_create_conversation(self, elder_user_id: uuid.UUID) -> FamilyConversation:
        stmt = select(FamilyConversation).where(
            FamilyConversation.elder_user_id == elder_user_id
        )
        result = await self.db.execute(stmt)
        conversation = result.scalars().first()
        if conversation is not None:
            return conversation
        conversation = FamilyConversation(elder_user_id=elder_user_id)
        self.db.add(conversation)
        await self.db.flush()
        return conversation

    async def _authorize(
        self, actor_user_id: uuid.UUID, elder_user_id: uuid.UUID
    ) -> None:
        """Any circle role (or the elder) may use Family Talk."""
        role = await self.circles.role_of(actor_user_id, elder_user_id)
        if role is None:
            raise AuthorizationError("You are not a member of this family circle.")

    # --------------------------------------------------------- send
    async def send_text(
        self,
        sender_user: User,
        elder_user_id: uuid.UUID,
        text: str,
        recipient_user_id: Optional[uuid.UUID] = None,
    ) -> FamilyTalkMessage:
        await self._authorize(sender_user.id, elder_user_id)
        text = (text or "").strip()
        if not text:
            raise ValidationError("Message cannot be empty.")
        if len(text) > MAX_TEXT_LENGTH:
            raise ValidationError(f"Message too long (max {MAX_TEXT_LENGTH} characters).")

        conversation = await self.get_or_create_conversation(elder_user_id)
        message = FamilyTalkMessage(
            conversation_id=conversation.id,
            sender_user_id=sender_user.id,
            recipient_user_id=recipient_user_id,
            message_type=FamilyMessageType.text,
            body=text,
        )
        self.db.add(message)
        await self.db.flush()

        await self._notify_circle(message, elder_user_id, sender_user)
        return message

    async def send_voice(
        self,
        sender_user: User,
        elder_user_id: uuid.UUID,
        audio_url: str,
        duration_seconds: int,
        transcript: Optional[str] = None,
        recipient_user_id: Optional[uuid.UUID] = None,
    ) -> FamilyTalkMessage:
        await self._authorize(sender_user.id, elder_user_id)
        if not audio_url or not str(audio_url).startswith("https://"):
            raise ValidationError("A secure audio URL is required.")
        duration = int(duration_seconds)
        if duration <= 0 or duration > MAX_VOICE_DURATION_SECONDS:
            raise ValidationError(
                f"Voice message duration must be 1-{MAX_VOICE_DURATION_SECONDS} seconds."
            )

        conversation = await self.get_or_create_conversation(elder_user_id)
        message = FamilyTalkMessage(
            conversation_id=conversation.id,
            sender_user_id=sender_user.id,
            recipient_user_id=recipient_user_id,
            message_type=FamilyMessageType.voice,
            audio_url=str(audio_url),
            duration_seconds=duration,
            transcript=transcript,
        )
        self.db.add(message)
        await self.db.flush()

        await self._notify_circle(message, elder_user_id, sender_user)
        return message

    # --------------------------------------------------------- history
    async def history(
        self,
        actor_user: User,
        elder_user_id: uuid.UUID,
        before_message_id: Optional[uuid.UUID] = None,
        limit: int = 50,
    ) -> Sequence[FamilyTalkMessage]:
        await self._authorize(actor_user.id, elder_user_id)
        conversation = await self.get_or_create_conversation(elder_user_id)
        stmt = (
            select(FamilyTalkMessage)
            .where(FamilyTalkMessage.conversation_id == conversation.id)
            .order_by(FamilyTalkMessage.created_at.desc())
            .limit(min(max(limit, 1), 100))
        )
        if before_message_id is not None:
            ref = await self.db.get(FamilyTalkMessage, before_message_id)
            if ref is not None:
                stmt = stmt.where(FamilyTalkMessage.created_at < ref.created_at)
        result = await self.db.execute(stmt)
        messages = result.scalars().all()
        return list(reversed(messages))  # oldest -> newest for the UI

    # ------------------------------------------------------ read state
    async def mark_read(
        self, actor_user: User, elder_user_id: uuid.UUID, message_id: uuid.UUID
    ) -> FamilyTalkMessage:
        await self._authorize(actor_user.id, elder_user_id)
        message = await self.db.get(FamilyTalkMessage, message_id)
        if message is None:
            raise AuthorizationError("Message not found.")
        conversation = await self.db.get(FamilyConversation, message.conversation_id)
        if conversation is None or conversation.elder_user_id != elder_user_id:
            raise AuthorizationError("Message not found.")
        if message.read_at is None:
            message.read_at = datetime.now(timezone.utc)
            await self.db.flush()
        return message

    # --------------------------------------------------------- push
    async def _notify_circle(
        self,
        message: FamilyTalkMessage,
        elder_user_id: uuid.UUID,
        sender: User,
    ) -> None:
        """
        Best-effort FCM push to the other participants. NEVER sends to the
        sender themself. Tokens are resolved server-side from registered
        Caregiver rows (and the elder's own registered device) - never
        accepted from the client (push-injection rule).
        """
        try:
            from app.models.caregiver import Caregiver
            from app.notifications.fcm_client import send_push

            # 1) Circle members' devices.
            stmt = select(Caregiver).where(Caregiver.cared_for_user_id == elder_user_id)
            result = await self.db.execute(stmt)
            members = result.scalars().all()
            tokens = [
                m.fcm_device_token
                for m in members
                if m.fcm_device_token and m.caregiver_user_id != sender.id
            ]

            # 2) The elder themself (when a child sends to them).
            if sender.id != elder_user_id:
                elder_token = await self._elder_device_token(elder_user_id)
                if elder_token:
                    tokens.append(elder_token)

            if not tokens:
                return

            sender_name = sender.display_name or "Your family"
            if message.message_type == FamilyMessageType.voice:
                title = f"Voice message from {sender_name}"
                body = f"Tap to listen ({message.duration_seconds}s)."
                kind = "family_voice_message"
            else:
                title = f"Message from {sender_name}"
                body = message.body[:120] if message.body else ""
                kind = "family_text_message"
            for token in tokens:
                try:
                    send_push(
                        device_token=token,
                        title=title,
                        body=body,
                        data={
                            "notification_type": kind,
                            "elder_user_id": str(elder_user_id),
                            "message_id": str(message.id),
                        },
                    )
                except Exception as exc:  # noqa: BLE001
                    logger.warning(
                        "Family Talk push failed for one device",
                        extra={"extra_fields": {"error": str(exc)}},
                    )
        except Exception as exc:  # noqa: BLE001
            # Push is best-effort; message delivery itself already persisted.
            logger.warning(
                "Family Talk push step failed",
                extra={"extra_fields": {"error": str(exc)}},
            )

    async def _elder_device_token(self, elder_user_id: uuid.UUID) -> Optional[str]:
        """
        The elder's own device token, if registered.

        MVP: resolved from a token registry attached to the elder's
        profile (future `device_tokens` table); None today. Kept in one
        place so a real registry table later is a localized change.
        """
        elder = await self.db.get(User, elder_user_id)
        if elder is None:
            return None
        return getattr(elder, "fcm_device_token", None)