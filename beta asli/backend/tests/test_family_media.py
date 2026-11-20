"""
Tests for Family Talk voice-note media (Feature C companion).

Covers the walkie-talkie storage path:
  - media URLs minted by the service are the only accepted form
  - path traversal via malformed URLs is impossible (strict UUIDs)
  - bytes round-trip through save/load
  - oversized and empty uploads are rejected
  - loading a missing file raises (never guesses paths)
  - FamilyTalkService accepts family-media:// URLs (walkie-talkie flow)
"""

import uuid

import pytest

from app.services.family_media_service import (
    load_voice_note,
    parse_media_url,
    save_voice_note,
)
from app.utils.exceptions import AuthorizationError, ValidationError


@pytest.fixture
def media_dir(tmp_path, monkeypatch):
    """Point FAMILY_MEDIA_DIR at a temp dir so tests never touch real
    storage; clear the settings cache so the override is picked up."""
    from app.config.settings import get_settings

    monkeypatch.setenv("FAMILY_MEDIA_DIR", str(tmp_path / "media"))
    get_settings.cache_clear()
    yield tmp_path
    get_settings.cache_clear()


def test_save_and_load_roundtrip(media_dir):
    elder_id = uuid.uuid4()
    audio_url, audio_id = save_voice_note(elder_id, b"fake-audio-bytes")

    assert audio_url == f"family-media://{elder_id}/{audio_id}"
    assert load_voice_note(elder_id, audio_id) == b"fake-audio-bytes"


def test_parse_media_url_validates_scheme(media_dir):
    with pytest.raises(ValidationError):
        parse_media_url("https://storage.example.com/a.m4a")


def test_parse_media_url_rejects_non_uuid_components(media_dir):
    with pytest.raises(ValidationError):
        parse_media_url("family-media://not-a-uuid/also-not-a-uuid")
    with pytest.raises(ValidationError):
        parse_media_url("family-media://../../etc/passwd")


def test_oversized_upload_rejected(media_dir):
    from app.services.family_media_service import MAX_VOICE_NOTE_BYTES

    with pytest.raises(ValidationError):
        save_voice_note(uuid.uuid4(), b"x" * (MAX_VOICE_NOTE_BYTES + 1))


def test_empty_upload_rejected(media_dir):
    with pytest.raises(ValidationError):
        save_voice_note(uuid.uuid4(), b"")


def test_missing_file_raises_authorization(media_dir):
    with pytest.raises(AuthorizationError):
        load_voice_note(uuid.uuid4(), uuid.uuid4())


@pytest.mark.asyncio
async def test_send_voice_accepts_family_media_scheme(db_session, media_dir):
    """Upload -> family-media:// URL -> send_voice, end to end."""
    from app.models.caregiver import Caregiver, CircleRole
    from app.models.family_message import FamilyMessageType
    from app.models.user import User
    from app.services.family_talk_service import FamilyTalkService

    elder = User(firebase_uid=f"uid-{uuid.uuid4()}", email="elder@t.co")
    child = User(firebase_uid=f"uid-{uuid.uuid4()}", email="child@t.co")
    db_session.add_all([elder, child])
    await db_session.flush()
    db_session.add(
        Caregiver(
            cared_for_user_id=elder.id,
            caregiver_name="child",
            caregiver_email="child@t.co",
            caregiver_user_id=child.id,
            circle_role=CircleRole.viewer,
        )
    )
    await db_session.flush()

    service = FamilyTalkService(db_session)
    audio_url, audio_id = save_voice_note(elder.id, b"note-bytes")

    message = await service.send_voice(
        sender_user=child,
        elder_user_id=elder.id,
        audio_url=audio_url,
        duration_seconds=12,
    )
    assert message.message_type == FamilyMessageType.voice
    assert message.duration_seconds == 12
    assert message.audio_url == audio_url
    assert load_voice_note(elder.id, audio_id) == b"note-bytes"