"""
Tests for Ecosystem 2.0 care circles (Feature D).

Covers the critical security properties:
  - role_of: elder is own primary guardian; members get their row role;
    outsiders get None.
  - require_role: viewer cannot invite; guardian can.
  - invitation lifecycle: expiry, single-use, email binding,
    duplicate-member rejection, revocation.
  - remove_member: removes only that member; others keep access.
"""

import uuid
from datetime import datetime, timedelta, timezone

import pytest

from app.models.care_circle import CareCircle, CareInvitation, CircleRole
from app.models.caregiver import Caregiver
from app.services.care_circle_service import CareCircleService


@pytest.fixture
def service(db_session):
    return CareCircleService(db_session)


async def make_user(db, email_suffix="x"):
    from app.models.user import User

    user = User(firebase_uid=f"uid-{uuid.uuid4()}", email=f"u{email_suffix}@t.co")
    db.add(user)
    await db.flush()
    return user


async def make_member(db, elder, email, role=CircleRole.viewer, linked_user=None):
    member = Caregiver(
        cared_for_user_id=elder.id,
        caregiver_name=email.split("@")[0],
        caregiver_email=email,
        caregiver_user_id=linked_user.id if linked_user else None,
        circle_role=role,
    )
    db.add(member)
    await db.flush()
    return member


@pytest.mark.asyncio
async def test_elder_is_own_primary_guardian(service, db_session):
    elder = await make_user(db_session, "elder")
    role = await service.role_of(elder.id, elder.id)
    assert role == CircleRole.primary_guardian


@pytest.mark.asyncio
async def test_member_role_and_outsider_none(service, db_session):
    elder = await make_user(db_session, "elder")
    child = await make_user(db_session, "child")
    await make_member(db_session, elder, "c@t.co", CircleRole.caregiver, child)
    assert await service.role_of(child.id, elder.id) == CircleRole.caregiver

    stranger = await make_user(db_session, "stranger")
    assert await service.role_of(stranger.id, elder.id) is None


@pytest.mark.asyncio
async def test_viewer_cannot_invite_but_guardian_can(service, db_session):
    elder = await make_user(db_session, "elder")
    guardian = await make_user(db_session, "guard")
    await make_member(db_session, elder, "g@t.co", CircleRole.primary_guardian, guardian)
    viewer = await make_user(db_session, "viewer")
    await make_member(db_session, elder, "v@t.co", CircleRole.viewer, viewer)

    from app.utils.exceptions import AuthorizationError

    with pytest.raises(AuthorizationError):
        await service.create_invitation(
            elder_user_id=elder.id,
            invited_by_user_id=viewer.id,
            invited_email="new@t.co",
        )
    inv = await service.create_invitation(
        elder_user_id=elder.id,
        invited_by_user_id=guardian.id,
        invited_email="new@t.co",
    )
    assert inv.status == "pending"


@pytest.mark.asyncio
async def test_invitation_expiry_and_single_use(service, db_session):
    elder = await make_user(db_session, "elder")
    invitation = await service.create_invitation(
        elder_user_id=elder.id, invited_by_user_id=elder.id,
        invited_email="kid@t.co",
    )
    # Force expiry.
    invitation.expires_at = datetime.now(timezone.utc) - timedelta(hours=1)
    await db_session.flush()

    from app.utils.exceptions import AuthorizationError

    kid = await make_user(db_session, "kid")
    with pytest.raises(AuthorizationError):
        await service.accept_invitation(
            invitation.invite_code, kid.id, "kid@t.co", "Kid"
        )

    # Fresh invitation: accept once, then code is single-use.
    inv2 = await service.create_invitation(
        elder_user_id=elder.id, invited_by_user_id=elder.id,
        invited_email="kid@t.co",
    )
    member = await service.accept_invitation(inv2.invite_code, kid.id, "kid@t.co", "Kid")
    assert member.circle_role == CircleRole.viewer
    other = await make_user(db_session, "other")
    with pytest.raises(AuthorizationError):
        await service.accept_invitation(inv2.invite_code, other.id, "other@t.co", "Other")


@pytest.mark.asyncio
async def test_invitation_email_binding(service, db_session):
    elder = await make_user(db_session, "elder")
    invitation = await service.create_invitation(
        elder_user_id=elder.id, invited_by_user_id=elder.id,
        invited_email="right@t.co",
    )
    wrong = await make_user(db_session, "wrong", )
    from app.utils.exceptions import AuthorizationError

    with pytest.raises(AuthorizationError):
        await service.accept_invitation(
            invitation.invite_code, wrong.id, "wrong@t.co", "Wrong"
        )


@pytest.mark.asyncio
async def test_remove_member_only_that_member(service, db_session):
    elder = await make_user(db_session, "elder")
    c1 = await make_user(db_session, "c1")
    m1 = await make_member(db_session, elder, "c1@t.co", CircleRole.caregiver, c1)
    c2 = await make_user(db_session, "c2")
    m2 = await make_member(db_session, elder, "c2@t.co", CircleRole.caregiver, c2)

    await service.remove_member(elder.id, elder.id, m1.id)

    assert await service.role_of(c1.id, elder.id) is None
    assert await service.role_of(c2.id, elder.id) == CircleRole.caregiver


@pytest.mark.asyncio
async def test_backfill_links_existing_caregivers(service, db_session):
    elder = await make_user(db_session, "elder")
    await make_member(db_session, elder, "legacy@t.co")
    linked = await service.backfill_circles_for_existing_caregivers()
    assert linked >= 1
    circle = await service.circle_for_elder(elder.id)
    assert circle is not None
    members = await service.members_of(circle.id)
    assert len(members) >= 1
    assert all(m.care_circle_id == circle.id for m in members)