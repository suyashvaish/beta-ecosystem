"""
Care circle repository and authorization service (Feature D).

Server-side authorization for everything circle-related:
  - get_or_create_circle: idempotent circle per elder.
  - circle_for_elder / circles_for_member: membership queries.
  - role_of: THE single source of truth for what a user may do with an
    elder's data. The elder themself is primary guardian of their own
    circle; members get their row role. No membership, no access.
  - create_invitation / accept_invitation / revoke: secure, expiring,
    single-use invitation lifecycle.
  - remove_member: revokes access without touching other members.

Every route must resolve role server-side through this service - client
UI hiding is never authorization (spec 11).
"""

import secrets
import uuid
from datetime import datetime, timedelta, timezone
from typing import Optional, Sequence

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.care_circle import CareCircle, CareInvitation, CircleRole
from app.models.caregiver import Caregiver
from app.utils.exceptions import AuthorizationError
from app.utils.logging import get_logger

logger = get_logger(__name__)

INVITE_EXPIRY_HOURS = 72


class CareCircleService:
    def __init__(self, db: AsyncSession):
        self.db = db

    # ------------------------------------------------------------ circles
    async def get_or_create_circle(self, elder_user_id: uuid.UUID) -> CareCircle:
        stmt = select(CareCircle).where(CareCircle.elder_user_id == elder_user_id)
        result = await self.db.execute(stmt)
        circle = result.scalars().first()
        if circle is not None:
            return circle
        circle = CareCircle(elder_user_id=elder_user_id)
        self.db.add(circle)
        await self.db.flush()
        return circle

    async def circle_for_elder(self, elder_user_id: uuid.UUID) -> Optional[CareCircle]:
        stmt = select(CareCircle).where(CareCircle.elder_user_id == elder_user_id)
        result = await self.db.execute(stmt)
        return result.scalars().first()

    async def members_of(self, circle_id: uuid.UUID) -> Sequence[Caregiver]:
        stmt = (
            select(Caregiver)
            .where(Caregiver.care_circle_id == circle_id)
            .order_by(Caregiver.created_at.desc())
        )
        result = await self.db.execute(stmt)
        return result.scalars().all()

    # ------------------------------------------------------------- roles
    async def role_of(self, actor_user_id: uuid.UUID, elder_user_id: uuid.UUID) -> Optional[CircleRole]:
        """The one place that decides an actor's power over an elder's data."""
        if actor_user_id == elder_user_id:
            return CircleRole.primary_guardian  # elder owns their circle
        stmt = select(Caregiver).where(
            Caregiver.caregiver_user_id == actor_user_id,
            Caregiver.cared_for_user_id == elder_user_id,
        )
        result = await self.db.execute(stmt)
        member = result.scalars().first()
        if member is None:
            return None
        return member.circle_role

    async def require_role(
        self, actor_user_id: uuid.UUID, elder_user_id: uuid.UUID,
        minimum: CircleRole,
    ) -> CircleRole:
        """Raise AuthorizationError unless actor has at least `minimum`."""
        role = await self.role_of(actor_user_id, elder_user_id)
        order = [CircleRole.viewer, CircleRole.caregiver, CircleRole.primary_guardian]
        if role is None or order.index(role) < order.index(minimum):
            raise AuthorizationError("You do not have access to this family circle.")
        return role

    # -------------------------------------------------------- invitations
    async def create_invitation(
        self,
        elder_user_id: uuid.UUID,
        invited_by_user_id: uuid.UUID,
        invited_email: Optional[str],
        proposed_role: CircleRole = CircleRole.viewer,
        expiry_hours: int = INVITE_EXPIRY_HOURS,
    ) -> CareInvitation:
        # Only primary guardians may invite (elder themself or an existing
        # primary guardian member).
        await self.require_role(invited_by_user_id, elder_user_id, CircleRole.primary_guardian)
        circle = await self.get_or_create_circle(elder_user_id)
        invitation = CareInvitation(
            circle_id=circle.id,
            invited_by_user_id=invited_by_user_id,
            invite_code=secrets.token_urlsafe(24),
            invited_email=invited_email,
            proposed_role=proposed_role,
            status="pending",
            expires_at=datetime.now(timezone.utc) + timedelta(hours=expiry_hours),
        )
        self.db.add(invitation)
        await self.db.flush()
        return invitation

    async def get_invitation_by_code(self, code: str) -> Optional[CareInvitation]:
        stmt = select(CareInvitation).where(CareInvitation.invite_code == code)
        result = await self.db.execute(stmt)
        return result.scalars().first()

    async def accept_invitation(
        self, code: str, accepting_user_id: uuid.UUID,
        accepting_email: Optional[str], accepting_name: str,
    ) -> Caregiver:
        invitation = await self.get_invitation_by_code(code)
        if invitation is None or invitation.status != "pending":
            raise AuthorizationError("This invitation is no longer valid.")
        now = datetime.now(timezone.utc)
        if invitation.expires_at.tzinfo is None:
            expires = invitation.expires_at.replace(tzinfo=timezone.utc)
        else:
            expires = invitation.expires_at
        if now > expires:
            invitation.status = "expired"
            await self.db.flush()
            raise AuthorizationError("This invitation has expired.")
        if (
            invitation.invited_email
            and accepting_email
            and invitation.invited_email.lower() != accepting_email.lower()
        ):
            raise AuthorizationError("This invitation was issued to a different email address.")

        circle = await self.db.get(CareCircle, invitation.circle_id)
        elder_user_id = circle.elder_user_id

        # Duplicate handling: same account already a member -> reject.
        existing = select(Caregiver).where(
            Caregiver.caregiver_user_id == accepting_user_id,
            Caregiver.cared_for_user_id == elder_user_id,
        )
        result = await self.db.execute(existing)
        if result.scalars().first() is not None:
            raise AuthorizationError("You are already a member of this circle.")

        # Reuse the pending duplicate-member Caregiver row if one exists
        # (same email, not yet linked to an account); otherwise create.
        reuse_stmt = select(Caregiver).where(
            Caregiver.cared_for_user_id == elder_user_id,
            Caregiver.caregiver_email == (invitation.invited_email or accepting_email),
            Caregiver.caregiver_user_id.is_(None),
        )
        reuse_result = await self.db.execute(reuse_stmt)
        member_row = reuse_result.scalars().first()
        if member_row is None:
            member_row = Caregiver(cared_for_user_id=elder_user_id, caregiver_name=accepting_name)
            self.db.add(member_row)
        member_row.caregiver_user_id = accepting_user_id
        member_row.caregiver_name = accepting_name
        if accepting_email:
            member_row.caregiver_email = accepting_email
        member_row.care_circle_id = circle.id
        member_row.circle_role = invitation.proposed_role

        invitation.status = "accepted"
        await self.db.flush()
        return member_row

    async def revoke_invitation(self, code: str, revoker_user_id: uuid.UUID) -> None:
        invitation = await self.get_invitation_by_code(code)
        if invitation is None:
            raise AuthorizationError("Invitation not found.")
        circle = await self.db.get(CareCircle, invitation.circle_id)
        await self.require_role(revoker_user_id, circle.elder_user_id, CircleRole.primary_guardian)
        invitation.status = "revoked"
        await self.db.flush()

    # ------------------------------------------------------ membership
    async def update_member_role(
        self, elder_user_id: uuid.UUID, actor_user_id: uuid.UUID,
        member_caregiver_id: uuid.UUID, new_role: CircleRole,
    ) -> Caregiver:
        await self.require_role(actor_user_id, elder_user_id, CircleRole.primary_guardian)
        member = await self.db.get(Caregiver, member_caregiver_id)
        if member is None or member.cared_for_user_id != elder_user_id:
            raise AuthorizationError("Member not found in this circle.")
        member.circle_role = new_role
        await self.db.flush()
        return member

    async def remove_member(
        self, elder_user_id: uuid.UUID, actor_user_id: uuid.UUID,
        member_caregiver_id: uuid.UUID,
    ) -> None:
        """Revoke one member's access; other members unaffected."""
        await self.require_role(actor_user_id, elder_user_id, CircleRole.primary_guardian)
        member = await self.db.get(Caregiver, member_caregiver_id)
        if member is None or member.cared_for_user_id != elder_user_id:
            raise AuthorizationError("Member not found in this circle.")
        await self.db.delete(member)
        await self.db.flush()

    async def backfill_circles_for_existing_caregivers(self) -> int:
        """
        Ecosystem 2.0 migration backfill: give every elder a circle and
        link existing caregiver rows into it (legacy view_only rows
        become circle viewers). Returns number of rows linked.
        Never deletes or rewrites existing data.
        """
        linked = 0
        stmt = select(Caregiver).where(Caregiver.care_circle_id.is_(None))
        result = await self.db.execute(stmt)
        rows = result.scalars().all()
        for row in rows:
            circle = await self.get_or_create_circle(row.cared_for_user_id)
            row.care_circle_id = circle.id
            if row.circle_role is None:
                row.circle_role = CircleRole.viewer
            linked += 1
        await self.db.flush()
        return linked