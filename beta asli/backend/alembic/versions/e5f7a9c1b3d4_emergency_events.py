"""emergency events and acknowledgements (Ecosystem 2.0 spec 5.5-5.7)

Revision ID: e5f7a9c1b3d4
Revises: d4e6f8a1b3c5
Create Date: 2026-11-17

Creates emergency_events and emergency_acknowledgements. Emergency
detection is deterministic and LLM-independent; events carry
location-if-permitted, status, and per-member acknowledgements.
Additive only; fully reversible.
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "e5f7a9c1b3d4"
down_revision = "d4e6f8a1b3c5"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "emergency_events",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "elder_user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("trigger_phrase", sa.String(255), nullable=False),
        sa.Column("source", sa.String(32), nullable=False, server_default="voice_keyword"),
        sa.Column("latitude", sa.Float(), nullable=True),
        sa.Column("longitude", sa.Float(), nullable=True),
        sa.Column(
            "status",
            sa.Enum("active", "acknowledged", "resolved", "false_alarm", name="emergencystatus"),
            nullable=False,
            server_default="active",
        ),
        sa.Column("acknowledged_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("resolved_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index(
        "ix_emergency_events_elder_user_id", "emergency_events", ["elder_user_id"]
    )
    op.create_index(
        "ix_emergency_events_status", "emergency_events", ["status"]
    )
    op.create_index(
        "ix_emergency_events_elder_status", "emergency_events",
        ["elder_user_id", "status"],
    )
    op.create_index(
        "ix_emergency_events_elder_created", "emergency_events",
        ["elder_user_id", "created_at"],
    )

    op.create_table(
        "emergency_acknowledgements",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "event_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("emergency_events.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "acknowledging_user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("note", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index(
        "ix_emergency_acknowledgements_event_id",
        "emergency_acknowledgements", ["event_id"],
    )
    op.create_index(
        "uq_emergency_ack_event_user",
        "emergency_acknowledgements",
        ["event_id", "acknowledging_user_id"],
        unique=True,
    )


def downgrade() -> None:
    op.drop_index("uq_emergency_ack_event_user", table_name="emergency_acknowledgements")
    op.drop_index(
        "ix_emergency_acknowledgements_event_id", table_name="emergency_acknowledgements"
    )
    op.drop_table("emergency_acknowledgements")
    op.drop_index("ix_emergency_events_elder_created", table_name="emergency_events")
    op.drop_index("ix_emergency_events_elder_status", table_name="emergency_events")
    op.drop_index("ix_emergency_events_status", table_name="emergency_events")
    op.drop_index("ix_emergency_events_elder_user_id", table_name="emergency_events")
    op.drop_table("emergency_events")
    sa.Enum(name="emergencystatus").drop(op.get_bind(), checkfirst=True)