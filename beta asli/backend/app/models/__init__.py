"""
ORM models package.

All model modules are imported here so that Alembic's `--autogenerate`
can discover every table via `Base.metadata`.
"""

from app.models.user import User
from app.models.conversation import Conversation
from app.models.message import Message
from app.models.family_message import (
    FamilyConversation,
    FamilyMessageType,
    FamilyTalkMessage,
)
from app.models.memory import Memory
from app.models.user_preference import UserPreference
from app.models.notification import Notification
from app.models.caregiver import Caregiver
from app.models.health_record import HealthRecord
from app.models.emergency_contact import EmergencyContact
from app.models.care_circle import CareCircle, CareInvitation, CircleRole
from app.models.contact_share import ContactShareSession, ShareStatus
from app.models.emergency_event import (
    EmergencyAcknowledgement,
    EmergencyEvent,
    EmergencyEventStatus,
)
from app.models.device_token import DeviceToken

__all__ = [
    "User",
    "Conversation",
    "Message",
    "FamilyConversation",
    "FamilyMessageType",
    "FamilyTalkMessage",
    "Memory",
    "UserPreference",
    "Notification",
    "Caregiver",
    "HealthRecord",
    "EmergencyContact",
    "CareCircle",
    "CareInvitation",
    "CircleRole",
    "ContactShareSession",
    "ShareStatus",
    "EmergencyAcknowledgement",
    "EmergencyEvent",
    "EmergencyEventStatus",
    "DeviceToken",
]