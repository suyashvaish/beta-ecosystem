"""beta connect contact sharing (Ecosystem 2.0 Feature B)

Revision ID: d4e6f8a1b3c5
Revises: c3d5e7f9b1a2
Create Date: 2026-11-17

Creates contact_share_sessions for voice-first contact exchange
between two Beta users via one-time expiring pairing codes with dual
consent. Additive only; fully reversible.
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "d4e6f8a1b3c5"
down_revision = "c3d5e7f9b1a2"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "contact_share_sessions",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "initiator_user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("intended_name", sa.String(255), nullable=False),
        sa.Column("pairing_code", sa.String(8), nullable=False),
        sa.Column("code_expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column(
            "status",
            sa.Enum(
                "initiated", "pending_accept", "completed",
                "declined", "expired", "cancelled",
                name="sharestatus",
            ),
            nullable=False,
            server_default="initiated",
        ),
        sa.Column("responder_user_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("initiator_approved_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("responder_approved_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("initiator_name", sa.String(255), nullable=True),
        sa.Column("initiator_phone", sa.String(32), nullable=True),
        sa.Column("initiator_email", sa.String(320), nullable=True),
        sa.Column("responder_name", sa.String(255), nullable=True),
        sa.Column("responder_phone", sa.String(32), nullable=True),
        sa.Column("responder_email", sa.String(320), nullable=True),
        sa.Column("failed_attempts", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index(
        "ix_contact_share_sessions_initiator_user_id",
        "contact_share_sessions", ["initiator_user_id"],
    )
    op.create_index(
        "ix_contact_share_sessions_pairing_code",
        "contact_share_sessions", ["pairing_code"], unique=True,
    )
    op.create_index(
        "ix_contact_share_sessions_status",
        "contact_share_sessions", ["status"],
    )
    op.create_index(
        "ix_contact_share_status_created",
        "contact_share_sessions", ["status", "created_at"],
    )
    op.create_foreign_key(
        "fk_contact_share_responder",
        "contact_share_sessions", "users",
        ["responder_user_id"], ["id"], ondelete="CASCADE",
    )


def downgrade() -> None:
    op.drop_constraint("fk_contact_share_responder", "contact_share_sessions", type_="foreignkey")
    op.drop_index("ix_contact_share_status_created", table_name="contact_share_sessions")
    op.drop_index("ix_contact_share_sessions_status", table_name="contact_share_sessions")
    op.drop_index("ix_contact_share_sessions_pairing_code", table_name="contact_share_sessions")
    op.drop_index(
        "ix_contact_share_sessions_initiator_user_id", table_name="contact_share_sessions"
    )
    op.drop_table("contact_share_sessions")
    sa.Enum(name="sharestatus").drop(op.get_bind(), checkfirst=True)