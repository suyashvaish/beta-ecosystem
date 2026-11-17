"""
Tests for the device token registry and its push wiring.

Critical properties:
  - register is idempotent on the token (no duplicate rows -> no
    double pushes); re-register refreshes last_seen
  - active_tokens_for returns ALL of a user's active devices
  - revoke (single + all) removes devices from delivery without
    deleting rows (audit retained)
  - ownership transfer: when a device changes accounts, the token row
    follows the new owner
  - Family Talk elder push resolves from the registry (placeholder
    closed): a child's message reaches the elder's registered devices
"""

import uuid

import pytest

from app.models.user import User
from app.services.device_token_service import DeviceTokenService


@pytest.fixture
def service(db_session):
    return DeviceTokenService(db_session)


async def _make_user(db, name):
    user = User(
        firebase_uid=f"uid-{uuid.uuid4()}",
        email=f"{name}@t.co",
        display_name=name,
    )
    db.add(user)
    await db.flush()
    return user


def _token(seed: str) -> str:
    # FCM tokens are long opaque strings.
    return f"fcm-{seed}-" + "x" * 40


@pytest.mark.asyncio
async def test_register_is_idempotent(service, db_session):
    elder = await _make_user(db_session, "elder")
    t = _token("phone1")
    d1 = await service.register(elder.id, t, "android")
    d2 = await service.register(elder.id, t, "android")
    assert d1.id == d2.id  # same row refreshed, not duplicated
    tokens = await service.active_tokens_for(elder.id)
    assert tokens == [t]


@pytest.mark.asyncio
async def test_multiple_devices(service, db_session):
    elder = await _make_user(db_session, "elder")
    t1 = _token("phone")
    t2 = _token("tablet")
    await service.register(elder.id, t1, "android")
    await service.register(elder.id, t2, "ios")

    tokens = await service.active_tokens_for(elder.id)
    assert set(tokens) == {t1, t2}


@pytest.mark.asyncio
async def test_revoke_single_and_all(service, db_session):
    elder = await _make_user(db_session, "elder")
    t1 = _token("phone")
    t2 = _token("tablet")
    await service.register(elder.id, t1, "android")
    await service.register(elder.id, t2, "ios")

    assert await service.revoke(elder.id, t1) is True
    assert await service.active_tokens_for(elder.id) == [t2]

    count = await service.revoke_all_for_user(elder.id)
    assert count == 1
    assert await service.active_tokens_for(elder.id) == []


@pytest.mark.asyncio
async def test_revoke_unknown_token_is_false(service, db_session):
    elder = await _make_user(db_session, "elder")
    assert await service.revoke(elder.id, _token("never-registered")) is False


@pytest.mark.asyncio
async def test_ownership_transfer(service, db_session):
    elder = await _make_user(db_session, "elder")
    new_owner = await _make_user(db_session, "newowner")
    t = _token("shared-device")
    await service.register(elder.id, t, "android")

    # Device changes account: token row transfers to the new owner.
    await service.register(new_owner.id, t, "android")
    assert await service.active_tokens_for(elder.id) == []
    assert await service.active_tokens_for(new_owner.id) == [t]


@pytest.mark.asyncio
async def test_family_talk_pushes_elder_devices(service, db_session, monkeypatch):
    """
    The closed placeholder: when a CHILD sends a Family Talk message, the
    elder's registered devices must receive the push. We intercept
    send_push and assert the elder's token is among the targets.
    """
    from app.services.family_talk_service import FamilyTalkService

    elder = await _make_user(db_session, "elder")
    child = await _make_user(db_session, "child")
    from app.models.caregiver import Caregiver, CircleRole

    db_session.add(Caregiver(
        cared_for_user_id=elder.id,
        caregiver_name="child",
        caregiver_email="child@t.co",
        caregiver_user_id=child.id,
        circle_role=CircleRole.caregiver,
    ))
    await db_session.flush()

    elder_token = _token("elder-phone")
    await service.register(elder.id, elder_token, "android")

    pushed = []

    import app.notifications.fcm_client as fcm
    original = fcm.send_push

    def fake_send_push(device_token, title, body, data):
        pushed.append(device_token)

    monkeypatch.setattr(fcm, "send_push", fake_send_push)
    # family_talk_service imports send_push inside the function body,
    # so patching the module attribute is enough.

    talk = FamilyTalkService(db_session)
    await talk.send_text(child, elder.id, "Papa, lunch at 1?")

    assert elder_token in pushed
    monkeypatch.setattr(fcm, "send_push", original)