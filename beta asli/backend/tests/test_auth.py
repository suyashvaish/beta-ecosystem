"""Tests for Firebase auth integration and user provisioning."""

from unittest.mock import patch

import pytest

from app.auth.firebase import verify_id_token
from app.repositories.user_repository import UserRepository
from app.utils.exceptions import AuthenticationError


def test_verify_id_token_success():
    with patch("app.auth.firebase.get_firebase_app"), patch(
        "app.auth.firebase.firebase_auth.verify_id_token",
        return_value={"uid": "abc123", "email": "user@example.com"},
    ):
        decoded = verify_id_token("fake-token")
    assert decoded["uid"] == "abc123"


def test_verify_id_token_invalid_raises_authentication_error():
    from firebase_admin import auth as firebase_auth

    with patch("app.auth.firebase.get_firebase_app"), patch(
        "app.auth.firebase.firebase_auth.verify_id_token",
        side_effect=firebase_auth.InvalidIdTokenError("bad token"),
    ):
        with pytest.raises(AuthenticationError):
            verify_id_token("bad-token")


@pytest.mark.asyncio
async def test_user_repository_creates_new_user(db_session):
    repo = UserRepository(db_session)
    user = await repo.get_by_firebase_uid("new-uid")
    assert user is None

    created = await repo.create(firebase_uid="new-uid", email="new@example.com")
    assert created.firebase_uid == "new-uid"

    fetched = await repo.get_by_firebase_uid("new-uid")
    assert fetched is not None
    assert fetched.id == created.id


@pytest.mark.asyncio
async def test_user_repository_update_profile(db_session, test_user):
    repo = UserRepository(db_session)
    updated = await repo.update_profile(test_user, display_name="Grandma Rose")
    assert updated.display_name == "Grandma Rose"
