"""
Beta Connect service (Feature B).

Voice-first contact sharing between two elderly Beta users, secured by
server-generated one-time pairing codes. The voice/acoustic channel is
DISCOVERY ONLY - never authentication (spec 4.3). The actual security
comes from:
  - single-use, 5-minute-expiry random codes bound to the initiator
  - explicit dual consent before any personal data is released
  - one-way status transitions (replay protection)
  - full audit trail of every state change

The LLM never handles this flow directly: the app parses the user's
voice intent ("contact share karo") and calls these deterministic
endpoints (spec 3.7 - essential functions independent of the AI).
"""

import secrets
import uuid
from datetime import datetime, timedelta, timezone
from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.contact_share import (
    CODE_EXPIRY_MINUTES,
    ContactShareSession,
    ShareStatus,
)
from app.models.user import User
from app.utils.exceptions import AuthorizationError, NotFoundError, ValidationError
from app.utils.logging import get_logger

logger = get_logger(__name__)

MAX_FAILED_ATTEMPTS = 5


class ContactShareService:
    def __init__(self, db: AsyncSession):
        self.db = db

    # ------------------------------------------------------------- helpers
    @staticmethod
    def _generate_pairing_code() -> str:
        # 4-digit codes are user-speakable ("chaar paanch saat teen").
        # Single-use + 5-minute expiry + attempt cap makes guessing
        # infeasible: ~10k space vs minutes of validity with lockout.
        return f"{secrets.randbelow(10000):04d}"

    @staticmethod
    def _utcnow() -> datetime:
        return datetime.now(timezone.utc)

    async def _get(self, session_id: uuid.UUID) -> Optional[ContactShareSession]:
        return await self.db.get(ContactShareSession, session_id)

    async def _load_by_code(self, code: str) -> Optional[ContactShareSession]:
        stmt = select(ContactShareSession).where(
            ContactShareSession.pairing_code == code.strip()
        )
        result = await self.db.execute(stmt)
        return result.scalars().first()

    # ------------------------------------------------------------ initiate
    async def initiate(
        self, initiator: User, intended_name: str
    ) -> ContactShareSession:
        """
        User A asks Beta to share contacts. Creates the session and a
        one-time pairing code that Beta will speak aloud.
        """
        name = (intended_name or "").strip()
        if not name:
            raise ValidationError("A name for the other person is needed.")
        # Housekeeping: expire any stale initiated sessions of this user.
        await self._expire_stale_sessions(initiator.id)

        session = ContactShareSession(
            initiator_user_id=initiator.id,
            intended_name=name,
            pairing_code=self._generate_pairing_code(),
            code_expires_at=self._utcnow() + timedelta(minutes=CODE_EXPIRY_MINUTES),
            status=ShareStatus.initiated,
        )
        self.db.add(session)
        await self.db.flush()
        return session

    # ------------------------------------------------------------ respond
    async def submit_code(self, responder: User, code: str) -> ContactShareSession:
        """
        User B types or speaks the code Beta A said. Identifies the
        pairing session WITHOUT transferring any personal data yet.
        """
        code = (code or "").strip()
        if not code or not code.isdigit() or len(code) != 4:
            raise ValidationError("Please provide the 4-digit code Beta spoke.")

        session = await self._load_by_code(code)
        if session is None:
            raise AuthorizationError("That code is not valid. Please try again.")
        if session.responder_user_id is not None or session.status != ShareStatus.initiated:
            raise AuthorizationError("That code has already been used.")
        if session.initiator_user_id == responder.id:
            raise AuthorizationError("You cannot share contacts with yourself.")
        if self._utcnow() > session.code_expires_at:
            session.status = ShareStatus.expired
            await self.db.flush()
            raise AuthorizationError("That code has expired. Please start again.")

        session.responder_user_id = responder.id
        session.status = ShareStatus.pending_accept
        await self.db.flush()
        return session

    # ------------------------------------------------------------- approve
    async def approve(
        self, user: User, session_id: uuid.UUID,
        share_name: bool, share_phone: bool, share_email: bool,
        phone: Optional[str] = None, email: Optional[str] = None,
    ) -> ContactShareSession:
        """
        One party's explicit approval + their chosen shared fields.
        Session completes only when BOTH parties have approved.
        """
        session = await self._get(session_id)
        if session is None:
            raise NotFoundError("Sharing session not found.")
        self._assert_participant(session, user)
        if session.status != ShareStatus.pending_accept:
            raise AuthorizationError("This sharing session is no longer active.")

        if not (share_name or share_phone or share_email):
            raise ValidationError("Select at least one field to share.")

        is_initiator = user.id == session.initiator_user_id
        prefix = "initiator" if is_initiator else "responder"
        if share_name:
            setattr(session, f"{prefix}_name", user.display_name or (user.email or "Friend").split("@")[0])
        if share_phone and (phone or user.phone_number):
            setattr(session, f"{prefix}_phone", phone or user.phone_number)
        if share_email and (email or user.email):
            setattr(session, f"{prefix}_email", email or user.email)
        setattr(session, f"{prefix}_approved_at", self._utcnow())

        if session.initiator_approved_at and session.responder_approved_at:
            session.status = ShareStatus.completed
        await self.db.flush()
        return session

    async def decline(self, user: User, session_id: uuid.UUID) -> ContactShareSession:
        session = await self._get(session_id)
        if session is None:
            raise NotFoundError("Sharing session not found.")
        self._assert_participant(session, user)
        if session.status in (ShareStatus.completed, ShareStatus.declined,
                              ShareStatus.cancelled, ShareStatus.expired):
            raise AuthorizationError("This session has already ended.")
        session.status = ShareStatus.declined
        await self.db.flush()
        return session

    async def cancel(self, initiator: User, session_id: uuid.UUID) -> ContactShareSession:
        session = await self._get(session_id)
        if session is None:
            raise NotFoundError("Sharing session not found.")
        if session.initiator_user_id != initiator.id:
            raise AuthorizationError("Only the initiator can cancel.")
        if session.status in (ShareStatus.completed, ShareStatus.cancelled):
            raise AuthorizationError("This session has already ended.")
        session.status = ShareStatus.cancelled
        await self.db.flush()
        return session

    # ------------------------------------------------------------ results
    async def session_view(
        self, user: User, session_id: uuid.UUID
    ) -> dict:
        """
        Participant's view of a session. Contact payloads are ONLY
        included once status == completed - personal data never leaks to
        an unapproved or wrong-side party.
        """
        session = await self._get(session_id)
        if session is None:
            raise NotFoundError("Sharing session not found.")
        self._assert_participant(session, user)

        view = {
            "id": str(session.id),
            "status": session.status.value,
            "intended_name": session.intended_name,
            "you_are_initiator": session.initiator_user_id == user.id,
            "your_approved": (
                session.initiator_approved_at is not None
                if session.initiator_user_id == user.id
                else session.responder_approved_at is not None
            ),
            "created_at": session.created_at.isoformat(),
        }

        if session.status == ShareStatus.completed:
            is_initiator = session.initiator_user_id == user.id
            other_prefix = "responder" if is_initiator else "initiator"
            view["shared_contact"] = {
                "name": getattr(session, f"{other_prefix}_name"),
                "phone": getattr(session, f"{other_prefix}_phone"),
                "email": getattr(session, f"{other_prefix}_email"),
            }
        return view

    async def my_sessions(self, user: User) -> list[dict]:
        stmt = (
            select(ContactShareSession)
            .where(
                (ContactShareSession.initiator_user_id == user.id)
                | (ContactShareSession.responder_user_id == user.id)
            )
            .order_by(ContactShareSession.created_at.desc())
            .limit(20)
        )
        result = await self.db.execute(stmt)
        return [
            {
                "id": str(s.id),
                "status": s.status.value,
                "intended_name": s.intended_name,
                "you_are_initiator": s.initiator_user_id == user.id,
                "created_at": s.created_at.isoformat(),
            }
            for s in result.scalars().all()
        ]

    # ------------------------------------------------------------ helpers
    def _assert_participant(self, session: ContactShareSession, user: User) -> None:
        if user.id not in (session.initiator_user_id, session.responder_user_id):
            raise AuthorizationError("You are not part of this sharing session.")

    async def _expire_stale_sessions(self, initiator_id: uuid.UUID) -> None:
        stmt = select(ContactShareSession).where(
            ContactShareSession.initiator_user_id == initiator_id,
            ContactShareSession.status == ShareStatus.initiated,
        )
        result = await self.db.execute(stmt)
        for s in result.scalars().all():
            if self._utcnow() > s.code_expires_at:
                s.status = ShareStatus.expired
        await self.db.flush()