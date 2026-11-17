"""
Tests for Beta Connect (Feature B).

Critical security properties from spec 4.3/4.4:
  - codes are single-use: a second submit is rejected
  - codes expire: an expired code cannot open a session
  - codes are bound: a wrong responder cannot join
  - no personal data is released before BOTH parties approve
  - non-participants cannot view or alter a session
  - either party can decline; the initiator can cancel
  - payload is visible to each side only after completion
"""

import uuid
from datetime import timedelta

import pytest

from app.models.contact_share import ShareStatus
from app.models.user import User
from app.services.contact_share_service import ContactShareService


@pytest.fixture
def service(db_session):
    return ContactShareService(db_session)


async def _make_user(db, name, phone=None, email=None):
    user = User(
        firebase_uid=f"uid-{uuid.uuid4()}",
        email=email or f"{name}@t.co",
        display_name=name,
        phone_number=phone,
    )
    db.add(user)
    await db.flush()
    return user


@pytest.mark.asyncio
async def test_full_happy_path(service, db_session):
    a = await _make_user(db_session, "Suyash", phone="+911111111111")
    b = await _make_user(db_session, "Ramesh", phone="+922222222222")

    session = await service.initiate(a, "Ramesh ji")
    assert session.status == ShareStatus.initiated
    assert len(session.pairing_code) == 4

    session = await service.submit_code(b, session.pairing_code)
    assert session.status == ShareStatus.pending_accept

    # A approves sharing name+phone
    s = await service.approve(a, session.id, True, True, False)
    assert s.status == ShareStatus.pending_accept  # still waiting on B
    # B approves
    s = await service.approve(b, session.id, True, True, False)
    assert s.status == ShareStatus.completed

    # Both sides now see each other's shared fields
    view_a = await service.session_view(a, session.id)
    view_b = await service.session_view(b, session.id)
    assert view_a["shared_contact"]["name"] == "Ramesh"
    assert view_a["shared_contact"]["phone"] == "+922222222222"
    assert view_b["shared_contact"]["name"] == "Suyash"
    assert view_b["shared_contact"]["phone"] == "+911111111111"


@pytest.mark.asyncio
async def test_code_is_single_use(service, db_session):
    from app.utils.exceptions import AuthorizationError

    a = await _make_user(db_session, "a")
    b = await _make_user(db_session, "b")
    c = await _make_user(db_session, "c")
    session = await service.initiate(a, "b")
    await service.submit_code(b, session.pairing_code)

    with pytest.raises(AuthorizationError):
        await service.submit_code(c, session.pairing_code)


@pytest.mark.asyncio
async def test_expired_code_rejected(service, db_session):
    from app.utils.exceptions import AuthorizationError

    a = await _make_user(db_session, "a")
    b = await _make_user(db_session, "b")
    session = await service.initiate(a, "b")
    session.code_expires_at = session.code_expires_at - timedelta(minutes=6)
    await db_session.flush()

    with pytest.raises(AuthorizationError):
        await service.submit_code(b, session.pairing_code)


@pytest.mark.asyncio
async def test_no_data_before_dual_consent(service, db_session):
    a = await _make_user(db_session, "a")
    b = await _make_user(db_session, "b")
    session = await service.initiate(a, "b")
    await service.submit_code(b, session.pairing_code)

    # A approved, B not yet: view must NOT contain shared_contact
    await service.approve(a, session.id, True, True, False)
    view_b = await service.session_view(b, session.id)
    assert "shared_contact" not in view_b


@pytest.mark.asyncio
async def test_outsider_cannot_view_or_alter(service, db_session):
    from app.utils.exceptions import AuthorizationError

    a = await _make_user(db_session, "a")
    b = await _make_user(db_session, "b")
    outsider = await _make_user(db_session, "x")
    session = await service.initiate(a, "b")
    await service.submit_code(b, session.pairing_code)

    with pytest.raises(AuthorizationError):
        await service.session_view(outsider, session.id)
    with pytest.raises(AuthorizationError):
        await service.approve(outsider, session.id, True, False, False)
    with pytest.raises(AuthorizationError):
        await service.cancel(outsider, session.id)


@pytest.mark.asyncio
async def test_decline_and_cancel_paths(service, db_session):
    a = await _make_user(db_session, "a")
    b = await _make_user(db_session, "b")
    session = await service.initiate(a, "b")
    await service.submit_code(b, session.pairing_code)

    declined = await service.decline(b, session.id)
    assert declined.status == ShareStatus.declined

    # New session: initiator cancels before responder submits code
    s2 = await service.initiate(a, "b")
    cancelled = await service.cancel(a, s2.id)
    assert cancelled.status == ShareStatus.cancelled


@pytest.mark.asyncio
async def test_cannot_share_with_self(service, db_session):
    from app.utils.exceptions import AuthorizationError

    a = await _make_user(db_session, "a")
    session = await service.initiate(a, "b")
    with pytest.raises(AuthorizationError):
        await service.submit_code(a, session.pairing_code)