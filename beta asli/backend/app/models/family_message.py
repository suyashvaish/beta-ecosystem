"""
Family Talk message model (Feature C).

Two-way communication between an elder (Beta Asli) and their care circle
(Beta Care). This is deliberately SEPARATE from the AI chat
`Message` model: different domain (human-to-human), different lifecycle
(delivery status, read state), different authorization (circle roles).

Message shape:
  - Belongs to the elder's family conversation (one per elder).
  - `sender_user_id` always an authenticated User (elder or member).
  - `recipient_user_id` NULL = message to the whole family,
    or a specific user for direct messages.
  - Text messages carry `body`; voice messages carry audio metadata
    (audio_url, duration, optional transcript). Audio bytes live in
    storage; only the URL is persisted (authenticated access enforced
    at the storage/download layer).
  - `status`: sent | delivered | failed - retried/updated by clients on
    recovery (offline resilience, spec 5.2/6).
  - `read_at` set when the recipient opens the message. For whole-family
    messages this is the FIRST read by any recipient (MVP limitation,
    documented in ECOSYSTEM_2.0_NOTES.md).
"""

import enum
import uuid
from datetime import datetime

from sqlalchemy import DateTime, Enum, ForeignKey, Index, Integer, String, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.base import Base, TimestampMixin


class FamilyMessageType(str, enum.Enum):
    text = "text"
    voice = "voice"


class FamilyMessageStatus(str, enum.Enum):
    sent = "sent"
    delivered = "delivered"
    failed = "failed"


class FamilyTalkMessage(Base, TimestampMixin):
    __tablename__ = "family_messages"
    __table_args__ = (
        Index("ix_family_messages_conversation_created", "conversation_id", "created_at"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    # The elder's family conversation (one row per elder, see service).
    conversation_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("family_conversations.id", ondelete="CASCADE"),
        index=True,
    )
    sender_user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    # NULL = addressed to the whole circle.
    recipient_user_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )

    message_type: Mapped[FamilyMessageType] = mapped_column(
        Enum(FamilyMessageType), default=FamilyMessageType.text
    )
    body: Mapped[str | None] = mapped_column(Text, nullable=True)
    # Voice messages: metadata only; audio bytes live in secure storage.
    audio_url: Mapped[str | None] = mapped_column(String(1024), nullable=True)
    duration_seconds: Mapped[int | None] = mapped_column(Integer, nullable=True)
    transcript: Mapped[str | None] = mapped_column(Text, nullable=True)

    status: Mapped[FamilyMessageStatus] = mapped_column(
        Enum(FamilyMessageStatus), default=FamilyMessageStatus.sent, index=True
    )
    read_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    conversation: Mapped["FamilyConversation"] = relationship(back_populates="messages")


class FamilyConversation(Base, TimestampMixin):
    """One Family Talk conversation per elder (their family circle)."""

    __tablename__ = "family_conversations"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    elder_user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), unique=True
    )
    elder_user: Mapped["User"] = relationship(foreign_keys=[elder_user_id])
    messages: Mapped[list["FamilyTalkMessage"]] = relationship(
        back_populates="conversation",
        cascade="all, delete-orphan",
        order_by="FamilyTalkMessage.created_at",
    )