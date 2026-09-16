"""User model.

Users are authenticated via Firebase; `firebase_uid` is the link between
our local User row and the Firebase-managed identity. We keep a local copy
of basic profile info so we can join against it cheaply in SQL without
calling out to Firebase on every request.
"""

import uuid
from typing import List, Optional

from sqlalchemy import Boolean, String
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.base import Base, TimestampMixin


class User(Base, TimestampMixin):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    firebase_uid: Mapped[str] = mapped_column(String(128), unique=True, index=True)
    email: Mapped[Optional[str]] = mapped_column(String(320), unique=True, index=True, nullable=True)
    display_name: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    phone_number: Mapped[Optional[str]] = mapped_column(String(32), nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    is_elderly_profile: Mapped[bool] = mapped_column(Boolean, default=False)

    conversations: Mapped[List["Conversation"]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )
    memories: Mapped[List["Memory"]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )
    preferences: Mapped[Optional["UserPreference"]] = relationship(
        back_populates="user", cascade="all, delete-orphan", uselist=False
    )
    notifications: Mapped[List["Notification"]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )
    caregiver_links: Mapped[List["Caregiver"]] = relationship(
        back_populates="cared_for_user",
        cascade="all, delete-orphan",
        foreign_keys="Caregiver.cared_for_user_id",
    )
    health_records: Mapped[List["HealthRecord"]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )
    emergency_contacts: Mapped[List["EmergencyContact"]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )
