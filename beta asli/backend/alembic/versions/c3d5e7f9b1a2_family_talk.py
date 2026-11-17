"""family talk (Ecosystem 2.0 Feature C)

Revision ID: c3d5e7f9b1a2
Revises: b2d4e6f8a9c1
Create Date: 2026-11-17

Creates family_conversations and family_messages for two-way
elder <-> circle communication (text + voice metadata). No existing
tables are modified; fully reversible.
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "c3d5e7f9b1a2"
down_revision = "b2d4e6f8a9c1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "family_conversations",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "elder_user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
            unique=True,
        ),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )

    op.create_table(
        "family_messages",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "conversation_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("family_conversations.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "sender_user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "recipient_user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column(
            "message_type",
            sa.Enum("text", "voice", name="familymsgtype"),
            nullable=False,
            server_default="text",
        ),
        sa.Column("body", sa.Text(), nullable=True),
        sa.Column("audio_url", sa.String(1024), nullable=True),
        sa.Column("duration_seconds", sa.Integer(), nullable=True),
        sa.Column("transcript", sa.Text(), nullable=True),
        sa.Column(
            "status",
            sa.Enum("sent", "delivered", "failed", name="familymsgstatus"),
            nullable=False,
            server_default="sent",
        ),
        sa.Column("read_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index(
        "ix_family_messages_conversation_id", "family_messages", ["conversation_id"]
    )
    op.create_index(
        "ix_family_messages_conversation_created",
        "family_messages",
        ["conversation_id", "created_at"],
    )
    op.create_index("ix_family_messages_sender_user_id", "family_messages", ["sender_user_id"])
    op.create_index("ix_family_messages_status", "family_messages", ["status"])


def downgrade() -> None:
    op.drop_index("ix_family_messages_status", table_name="family_messages")
    op.drop_index("ix_family_messages_sender_user_id", table_name="family_messages")
    op.drop_index(
        "ix_family_messages_conversation_created", table_name="family_messages"
    )
    op.drop_index("ix_family_messages_conversation_id", table_name="family_messages")
    op.drop_table("family_messages")
    op.drop_table("family_conversations")
    sa.Enum(name="familymsgstatus").drop(op.get_bind(), checkfirst=True)
    sa.Enum(name="familymsgtype").drop(op.get_bind(), checkfirst=True)