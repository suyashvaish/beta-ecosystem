"""
Tests for Family Talk (Feature C).

Covers the critical authorization and integrity properties:
  - only circle members (any role) or the elder can send/read
  - outsiders are rejected (cross-family isolation)
  - elder and child can message each other both ways
  - voice messages require https URLs and sane durations
  - read state transitions once
  - history is ordered oldest -> newest
"""

import uuid

import pytest

from app.models.caregiver import Caregiver, CircleRole
from app.models.family_message import FamilyMessageType
from app.models.user import User
from app.services.family_talk_service import FamilyTalkService


@pytest.fixture
def service(db_session):
    return FamilyTalkService(db_session)


async def _make_user(db, name):
    user = User(firebase_uid=f"uid-{uuid.uuid4()}", email=f"{name}@t.co", display_name=name)
    db.add(user)
    await db.flush()
    return user


async def _make_member(db, elder, name, linked_user, role=CircleRole.viewer):
    member = Caregiver(
        cared_for_user_id=elder.id,
        caregiver_name=name,
        caregiver_email=f"{name}@t.co",
        caregiver_user_id=linked_user.id,
        circle_role=role,
    )
    db.add(member)
    await db.flush()
    return member


@pytest.mark.asyncio
async def test_elder_and_child_message_both_ways(service, db_session):
    elder = await _make_user(db_session, "elder")
    child = await _make_user(db_session, "child")
    await _make_member(db_session, elder, "child", child, CircleRole.caregiver)

    # Child -> elder
    m1 = await service.send_text(child, elder.id, "Hi Papa, how are you?")
    assert m1.sender_user_id == child.id

    # Elder -> children
    m2 = await service.send_text(elder, elder.id, "I am fine beta!")
    assert m2.sender_user_id == elder.id

    history = await service.history(child, elder.id)
    assert [m.body for m in history] == ["Hi Papa, how are you?", "I am fine beta!"]


@pytest.mark.asyncio
async def test_outsider_rejected(service, db_session):
    from app.utils.exceptions import AuthorizationError

    elder = await _make_user(db_session, "elder")
    outsider = await _make_user(db_session, "outsider")
    child = await _make_user(db_session, "child")
    await _make_member(db_session, elder, "child", child)

    with pytest.raises(AuthorizationError):
        await service.send_text(outsider, elder.id, "hello")
    with pytest.raises(AuthorizationError):
        await service.history(outsider, elder.id)


@pytest.mark.asyncio
async def test_viewer_can_read_and_send(service, db_session):
    elder = await _make_user(db_session, "elder")
    viewer = await _make_user(db_session, "viewer")
    await _make_member(db_session, elder, "viewer", viewer, CircleRole.viewer)

    m = await service.send_text(viewer, elder.id, "Hello from viewer")
    history = await service.history(viewer, elder.id)
    assert len(history) == 1
    assert history[0].body == "Hello from viewer"


@pytest.mark.asyncio
async def test_voice_message_validation(service, db_session):
    from app.utils.exceptions import ValidationError

    elder = await _make_user(db_session, "elder")
    child = await _make_user(db_session, "child")
    await _make_member(db_session, elder, "child", child, CircleRole.caregiver)

    # Insecure URL rejected
    with pytest.raises(ValidationError):
        await service.send_voice(child, elder.id, "http://insecure.com/a.m4a", 10)
    # Too long rejected
    with pytest.raises(ValidationError):
        await service.send_voice(
            child, elder.id, "https://storage.example.com/a.m4a", 999
        )
    # Valid voice message passes
    m = await service.send_voice(
        child, elder.id, "https://storage.example.com/a.m4a", 45, transcript="Hello"
    )
    assert m.message_type == FamilyMessageType.voice
    assert m.duration_seconds == 45


@pytest.mark.asyncio
async def test_read_state_transitions_once(service, db_session):
    elder = await _make_user(db_session, "elder")
    child = await _make_user(db_session, "child")
    await _make_member(db_session, elder, "child", child, CircleRole.caregiver)
    m = await service.send_text(child, elder.id, "Read me")

    assert m.read_at is None
    m2 = await service.mark_read(elder, elder.id, m.id)
    assert m2.read_at is not None
    first = m2.read_at
    m3 = await service.mark_read(elder, elder.id, m.id)
    assert m3.read_at == first  # idempotent


@pytest.mark.asyncio
async def test_history_paginates_newest_first(service, db_session):
    elder = await _make_user(db_session, "elder")
    child = await _make_user(db_session, "child")
    await _make_member(db_session, elder, "child", child, CircleRole.caregiver)

    for i in range(5):
        await service.send_text(child, elder.id, f"msg {i}")

    history = await service.history(child, elder.id, limit=3)
    assert len(history) == 3
    # newest three, presented oldest -> newest
    assert [m.body for m in history] == ["msg 2", "msg 3", "msg 4"]