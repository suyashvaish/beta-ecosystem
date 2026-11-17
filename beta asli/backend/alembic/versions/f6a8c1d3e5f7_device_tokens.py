"""device token registry (Ecosystem 2.0 push infrastructure)

Revision ID: f6a8c1d3e5f7
Revises: e5f7a9c1b3d4
Create Date: 2026-11-17

Creates device_tokens - per-user FCM device registry powering
Family Talk elder push and emergency confirmations. Additive only;
fully reversible.
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "f6a8c1d3e5f7"
down_revision = "e5f7a9c1b3d4"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "device_tokens",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("device_token", sa.String(512), nullable=False),
        sa.Column("platform", sa.String(16), nullable=False, server_default="android"),
        sa.Column("active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("last_seen_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_device_tokens_user_id", "device_tokens", ["user_id"])
    op.create_index("ix_device_tokens_device_token", "device_tokens", ["device_token"])
    op.create_index("ix_device_tokens_active", "device_tokens", ["active"])
    op.create_unique_constraint(
        "uq_device_tokens_token", "device_tokens", ["device_token"]
    )


def downgrade() -> None:
    op.drop_constraint("uq_device_tokens_token", "device_tokens", type_="unique")
    op.drop_index("ix_device_tokens_active", table_name="device_tokens")
    op.drop_index("ix_device_tokens_device_token", table_name="device_tokens")
    op.drop_index("ix_device_tokens_user_id", table_name="device_tokens")
    op.drop_table("device_tokens")