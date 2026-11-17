"""
Tests for emergency keyword detection and events (spec 5.5-5.7).

Critical properties:
  - phrase detection is deterministic (no LLM): English + Hindi phrases,
    normalization ("Madad!!" matches), word-boundary safety for short
    words ("helped" does not trigger "help")
  - dedupe: repeat triggers inside the window return the same event
  - ack: first acknowledgement transitions the event; repeat ack by the
    same user is idempotent
  - resolve/false-alarm paths work
  - history isolation: only the elder or circle members see history
"""

import uuid

import pytest

from app.models.emergency_event import EmergencyEventStatus
from app.models.user import User
from app.services.emergency_service import (
    EmergencyService,
    detect_emergency_phrase,
)


@pytest.fixture
def service(db_session):
    return EmergencyService(db_session)


async def _make_user(db, name, email_suffix=None):
    user = User(
        firebase_uid=f"uid-{uuid.uuid4()}",
        email=f"{name}{email_suffix or ''}@t.co",
        display_name=name,
    )
    db.add(user)
    await db.flush()
    return user


# ------------------------------------------------------------ detection

def test_detect_english_phrases():
    assert detect_emergency_phrase("Help!") == "help"
    assert detect_emergency_phrase("EMERGENCY") == "emergency"


def test_detect_hindi_phrases():
    assert detect_emergency_phrase("Mujhe madad chahiye!!") == "mujhe madad chahiye"
    assert detect_emergency_phrase("  bachao  ") == "bachao"
    assert detect_emergency_phrase("BETA MADAD") == "madad"


def test_word_boundary_safety():
    # Short word "help" must NOT match inside "helped" (false-trigger guard).
    assert detect_emergency_phrase("I helped my neighbour") is None


def test_normal_phrases_do_not_trigger():
    assert detect_emergency_phrase("How are you today?") is None
    assert detect_emergency_phrase("Beta, mujhe paas mein doctor dhoondh do") is None


# ------------------------------------------------------------- events

@pytest.mark.asyncio
async def test_trigger_creates_active_event(service, db_session):
    elder = await _make_user(db_session, "elder")
    event = await service.trigger_event(elder, "bachao", "voice_keyword")
    assert event.status == EmergencyEventStatus.active
    assert event.trigger_phrase == "bachao"


@pytest.mark.asyncio
async def test_dedupe_within_window(service, db_session):
    elder = await _make_user(db_session, "elder")
    first = await service.trigger_event(elder, "madad", "voice_keyword")
    second = await service.trigger_event(elder, "madad", "voice_keyword")
    assert first.id == second.id  # deduped, not a second event


@pytest.mark.asyncio
async def test_non_emergency_phrase_rejected_for_voice_source(service, db_session):
    from app.utils.exceptions import ValidationError

    elder = await _make_user(db_session, "elder")
    with pytest.raises(ValidationError):
        await service.trigger_event(elder, "hello beta", "voice_keyword")


@pytest.mark.asyncio
async def test_manual_sos_bypasses_phrase_check(service, db_session):
    elder = await _make_user(db_session, "elder")
    event = await service.trigger_event(
        elder, "pressed the SOS button", "manual_sos"
    )
    assert event.status == EmergencyEventStatus.active
    assert event.source == "manual_sos"


@pytest.mark.asyncio
async def test_acknowledge_transitions_and_is_idempotent(service, db_session):
    elder = await _make_user(db_session, "elder")
    event = await service.trigger_event(elder, "help", "voice_keyword")

    acked = await service.acknowledge(elder, event.id, note="Calling now")
    assert acked.status == EmergencyEventStatus.acknowledged
    assert acked.acknowledged_at is not None

    # Repeat ack by the same user: no error, no duplicate rows.
    again = await service.acknowledge(elder, event.id)
    assert again.status == EmergencyEventStatus.acknowledged


@pytest.mark.asyncio
async def test_resolve_and_false_alarm(service, db_session):
    elder = await _make_user(db_session, "elder")
    event = await service.trigger_event(elder, "bachao", "voice_keyword")
    resolved = await service.resolve(elder, event.id, false_alarm=True)
    assert resolved.status == EmergencyEventStatus.false_alarm
    assert resolved.resolved_at is not None


@pytest.mark.asyncio
async def test_history_isolation(service, db_session):
    from app.models.caregiver import Caregiver, CircleRole
    from app.utils.exceptions import AuthorizationError

    elder = await _make_user(db_session, "elder")
    child = await _make_user(db_session, "child")
    outsider = await _make_user(db_session, "out")
    db_session.add(Caregiver(
        cared_for_user_id=elder.id,
        caregiver_name="child",
        caregiver_email="child@t.co",
        caregiver_user_id=child.id,
        circle_role=CircleRole.caregiver,
    ))
    await db_session.flush()
    await service.trigger_event(elder, "madad", "voice_keyword")

    # Child (circle member) sees history.
    history = await service.history(child, elder.id)
    assert len(history) == 1
    # Elder sees their own history.
    own = await service.history(elder, elder.id)
    assert len(own) == 1
    # Outsider rejected.
    with pytest.raises(AuthorizationError):
        await service.history(outsider, elder.id)