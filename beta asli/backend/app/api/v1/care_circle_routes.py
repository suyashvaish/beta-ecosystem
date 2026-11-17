"""
Care circle routes (Feature D).

One elderly profile -> multiple children with separate Beta Care
accounts. All authorization is enforced server-side by
CareCircleService.require_role; the Flutter UI merely reflects it.
"""

import uuid
from typing import Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user
from app.database import get_db
from app.models.care_circle import CircleRole
from app.models.caregiver import Caregiver
from app.models.user import User
from app.services.care_circle_service import CareCircleService

router = APIRouter(prefix="/care-circles", tags=["care-circles"])


def get_service(db: AsyncSession = Depends(get_db)) -> CareCircleService:
    return CareCircleService(db)


class CreateInvitationRequest(BaseModel):
    elder_user_id: uuid.UUID
    invited_email: Optional[str] = Field(default=None, max_length=320)
    proposed_role: CircleRole = CircleRole.viewer


class AcceptInvitationRequest(BaseModel):
    invite_code: str = Field(..., min_length=8, max_length=64)
    accepting_name: str = Field(..., min_length=1, max_length=255)


class UpdateRoleRequest(BaseModel):
    elder_user_id: uuid.UUID
    member_caregiver_id: uuid.UUID
    new_role: CircleRole


class RemoveMemberRequest(BaseModel):
    elder_user_id: uuid.UUID
    member_caregiver_id: uuid.UUID


def _member_out(m):
    return {
        "id": str(m.id),
        "name": m.caregiver_name,
        "email": m.caregiver_email,
        "circle_role": m.circle_role.value if m.circle_role else None,
        "has_account": m.caregiver_user_id is not None,
    }


@router.get("/for-elder/{elder_user_id}")
async def circle_for_elder(
    elder_user_id: uuid.UUID,
    user: User = Depends(get_current_user),
    service: CareCircleService = Depends(get_service),
):
    """Circle overview. Any authorized member (or the elder) may view."""
    await service.require_role(user.id, elder_user_id, CircleRole.viewer)
    circle = await service.get_or_create_circle(elder_user_id)
    members = await service.members_of(circle.id)
    your_role = await service.role_of(user.id, elder_user_id)
    return {
        "circle_id": str(circle.id),
        "name": circle.name,
        "members": [_member_out(m) for m in members],
        "your_role": your_role.value if your_role else None,
    }


@router.post("/invitations")
async def create_invitation(
    payload: CreateInvitationRequest,
    user: User = Depends(get_current_user),
    service: CareCircleService = Depends(get_service),
):
    invitation = await service.create_invitation(
        elder_user_id=payload.elder_user_id,
        invited_by_user_id=user.id,
        invited_email=payload.invited_email,
        proposed_role=payload.proposed_role,
    )
    return {
        "invite_code": invitation.invite_code,
        "expires_at": invitation.expires_at,
        "proposed_role": invitation.proposed_role.value,
    }


@router.post("/invitations/accept")
async def accept_invitation(
    payload: AcceptInvitationRequest,
    user: User = Depends(get_current_user),
    service: CareCircleService = Depends(get_service),
):
    member = await service.accept_invitation(
        code=payload.invite_code,
        accepting_user_id=user.id,
        accepting_email=user.email,
        accepting_name=payload.accepting_name,
    )
    return _member_out(member)


@router.post("/invitations/revoke")
async def revoke_invitation(
    payload: AcceptInvitationRequest,
    user: User = Depends(get_current_user),
    service: CareCircleService = Depends(get_service),
):
    await service.revoke_invitation(payload.invite_code, user.id)
    return {"status": "revoked"}


@router.post("/members/role")
async def update_member_role(
    payload: UpdateRoleRequest,
    user: User = Depends(get_current_user),
    service: CareCircleService = Depends(get_service),
):
    member = await service.update_member_role(
        elder_user_id=payload.elder_user_id,
        actor_user_id=user.id,
        member_caregiver_id=payload.member_caregiver_id,
        new_role=payload.new_role,
    )
    return _member_out(member)


@router.post("/members/remove")
async def remove_member(
    payload: RemoveMemberRequest,
    user: User = Depends(get_current_user),
    service: CareCircleService = Depends(get_service),
):
    await service.remove_member(
        elder_user_id=payload.elder_user_id,
        actor_user_id=user.id,
        member_caregiver_id=payload.member_caregiver_id,
    )
    return {"status": "removed"}


@router.get("/my-elders")
async def my_elders(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Elders this user cares for (care-circle switching in Beta Care)."""
    stmt = select(Caregiver).where(Caregiver.caregiver_user_id == user.id)
    result = await db.execute(stmt)
    rows = result.scalars().all()
    return [
        {
            "elder_user_id": str(r.cared_for_user_id),
            "circle_role": r.circle_role.value if r.circle_role else None,
        }
        for r in rows
    ]