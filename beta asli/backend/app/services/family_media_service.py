"""
Family Talk media storage (Feature C companion).

Voice notes for the walkie-talkie flow need somewhere for the audio
bytes to live. MVP: the backend's local disk under FAMILY_MEDIA_DIR,
partitioned per elder so one family's media never mixes with
another's. No new table or migration is needed - the URL itself
encodes the location:

    family-media://{elder_user_id}/{audio_id}

Playback ALWAYS re-authorizes circle membership before reading the
file, so the stored URL is never a bearer credential: only circle
members can fetch the bytes, via the authenticated endpoint.
Production deployments swap this module for S3/GCS behind the same
function signatures (save_voice_note / load_voice_note).
"""

import uuid
from pathlib import Path
from urllib.parse import urlparse

from app.config.settings import get_settings
from app.utils.exceptions import AuthorizationError, ValidationError

# A 120s AAC voice note is ~1 MB; 10 MB is a generous safety ceiling.
MAX_VOICE_NOTE_BYTES = 10 * 1024 * 1024
AUDIO_EXTENSION = ".m4a"


def media_root() -> Path:
    root = Path(get_settings().FAMILY_MEDIA_DIR).resolve()
    root.mkdir(parents=True, exist_ok=True)
    return root


def parse_media_url(audio_url: str) -> tuple[uuid.UUID, uuid.UUID]:
    """Validates a family-media:// URL and returns (elder_id, audio_id).

    Raises ValidationError on anything malformed - this is the guard
    that makes path traversal impossible: both URL components must be
    real UUIDs before they ever touch the filesystem.
    """
    parsed = urlparse(str(audio_url))
    if parsed.scheme != "family-media":
        raise ValidationError("Unsupported audio URL scheme.")
    try:
        elder_id = uuid.UUID(parsed.netloc)
        audio_id = uuid.UUID(parsed.path.lstrip("/"))
    except ValueError:
        raise ValidationError("Malformed voice note URL.")
    return elder_id, audio_id


def save_voice_note(elder_user_id: uuid.UUID, data: bytes) -> tuple[str, uuid.UUID]:
    """Persists voice-note bytes for this elder's family; returns the
    opaque family-media:// URL and the audio id."""
    if not data:
        raise ValidationError("Audio file is empty.")
    if len(data) > MAX_VOICE_NOTE_BYTES:
        raise ValidationError(
            f"Voice note exceeds the {MAX_VOICE_NOTE_BYTES // (1024 * 1024)} MB limit."
        )
    audio_id = uuid.uuid4()
    directory = media_root() / str(elder_user_id)
    directory.mkdir(parents=True, exist_ok=True)
    (directory / f"{audio_id}{AUDIO_EXTENSION}").write_bytes(data)
    return f"family-media://{elder_user_id}/{audio_id}", audio_id


def load_voice_note(elder_user_id: uuid.UUID, audio_id: uuid.UUID) -> bytes:
    """Reads a stored voice note. The ROUTE authorizes circle membership
    before calling this; the function itself stays storage-only."""
    directory = (media_root() / str(elder_user_id)).resolve()
    path = (directory / f"{audio_id}{AUDIO_EXTENSION}").resolve()
    # Belt-and-braces: UUID components already make traversal
    # impossible, but never serve anything that resolved outside this
    # elder's directory.
    if not str(path).startswith(str(directory)):
        raise AuthorizationError("Voice note not found.")
    if not path.is_file():
        raise AuthorizationError("Voice note not found.")
    return path.read_bytes()