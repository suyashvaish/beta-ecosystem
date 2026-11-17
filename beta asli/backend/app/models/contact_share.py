"""
Beta Connect contact-share session model (Feature B).

Two elderly Beta users exchange contact info via a natural voice flow,
secured by a server-generated pairing code:

  1. User A asks Beta to share contacts with "Ramesh ji".
  2. Backend creates a session with a ONE-TIME, expiring pairing code
     (spoken aloud by Beta A; entered/recognized by Beta B).
  3. User B's app submits the code -> session moves to `pending_accept`.
  4. BOTH users explicitly approve -> `completed`, contact payload
     becomes readable by both parties.
  5. Either side can decline/cancel at any time.

Security properties (spec 4.3/4.4):
  - Codes are random 32-bit values, single-use, expire after 5 min.
  - A code binds to the initiator; a session identifies BOTH recipients
    before any personal data moves.
  - Replay: a used/expired code is rejected forever (status transitions
    are one-way).
  - Audit: every state change is persisted with timestamps; contact
    payloads are stored per-share, never logged.

Contact payloads contain ONLY the fields each user chose to share
(name, phone, email). No addresses, notes, or arbitrary contact data.
"""

import enum
import uuid
from datetime import datetime

from sqlalchemy import DateTime, Enum, ForeignKey, Index, Integer, String
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.base import Base, TimestampMixin

CODE_EXPIRY_MINUTES = 5


class ShareStatus(str, enum.Enum):
    initiated = "initiated"      # A asked; code generated, not yet spoken/consumed
    pending_accept = "pending_accept"  # B submitted the code
    completed = "completed"      # both approved; payloads released
    declined = "declined"
    expired = "expired"
    cancelled = "cancelled"


class ContactShareSession(Base, TimestampMixin):
    __tablename__ = "contact_share_sessions"
    __table_args__ = (
        Index("ix_contact_share_status_created", "status", "created_at"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )

    # Initiator (user A) and intended recipient's display hint (user B
    # has NOT yet been identified - that happens when they submit the code).
    initiator_user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    intended_name: Mapped[str] = mapped_column(String(255))

    # One-time pairing code. Plain text is acceptable here because the
    # code is public-by-design (spoken aloud) and single-use with 5-min
    # expiry; the secret is its short lifetime, not its secrecy.
    pairing_code: Mapped[str] = mapped_column(String(8), unique=True, index=True)
    code_expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))

    status: Mapped[str] = mapped_column(
        Enum(ShareStatus), default=ShareStatus.initiated, index=True
    )

    # Responder (user B), set when they submit the code.
    responder_user_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=True
    )

    # Dual consent timestamps.
    initiator_approved_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    responder_approved_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    # Contact payloads - only released (readable via API) when status
    # is completed. Fields each party chose to share.
    initiator_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    initiator_phone: Mapped[str | None] = mapped_column(String(32), nullable=True)
    initiator_email: Mapped[str | None] = mapped_column(String(320), nullable=True)
    responder_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    responder_phone: Mapped[str | None] = mapped_column(String(32), nullable=True)
    responder_email: Mapped[str | None] = mapped_column(String(320), nullable=True)

    # Retry guard: how many times the wrong code was submitted against
    # this session (session-level brute-force visibility; codes are
    # random enough that server-wide guessing is infeasible).
    failed_attempts: Mapped[int] = mapped_column(Integer, default=0)

    initiator: Mapped["User"] = relationship(foreign_keys=[initiator_user_id])
    responder: Mapped["User"] = relationship(foreign_keys=[responder_user_id])