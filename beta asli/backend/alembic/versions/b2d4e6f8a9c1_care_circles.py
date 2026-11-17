"""care circles and multi-caregiver membership (Ecosystem 2.0)

Revision ID: b2d4e6f8a9c1
Revises: a1c4f8e2b7d9
Create Date: 2026-11-17

Creates care_circles and care_invitations, extends caregivers with
care_circle_id + circle_role, and BACKFILLS existing caregiver rows
into per-elder circles (legacy rows become viewers). Existing data is
never deleted; the migration is reversible (drop added columns/tables).
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "b2d4e6f8a9c1"
down_revision = "a1c4f8e2b7d9"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # ---- care_circles -------------------------------------------------
    op.create_table(
        "care_circles",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "elder_user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
            unique=True,
        ),
        sa.Column("name", sa.String(255), nullable=False, server_default="Family"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_care_circles_elder", "care_circles", ["elder_user_id"])

    # ---- care_invitations ---------------------------------------------
    op.create_table(
        "care_invitations",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "circle_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("care_circles.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "invited_by_user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("invite_code", sa.String(64), nullable=False, unique=True),
        sa.Column("invited_email", sa.String(320), nullable=True),
        sa.Column("proposed_role", sa.Enum("primary_guardian", "caregiver", "viewer", name="circlerole"), nullable=False, server_default="viewer"),
        sa.Column("status", sa.String(32), nullable=False, server_default="pending"),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_care_invitations_circle_id", "care_invitations", ["circle_id"])
    op.create_index("ix_care_invitations_invite_code", "care_invitations", ["invite_code"])
    op.create_index("ix_care_invitations_status", "care_invitations", ["status"])

    # ---- caregivers: circle membership --------------------------------
    op.add_column(
        "caregivers",
        sa.Column(
            "care_circle_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("care_circles.id", ondelete="SET NULL"),
            nullable=True,
        ),
    )
    op.add_column(
        "caregivers",
        sa.Column(
            "circle_role",
            sa.Enum("primary_guardian", "caregiver", "viewer", name="circlerole"),
            nullable=True,
        ),
    )
    op.create_index("ix_caregivers_care_circle_id", "caregivers", ["care_circle_id"])

    # ---- backfill existing rows (data-preserving) ----------------------
    # One circle per elder; link every existing caregiver row; legacy rows
    # default to viewer. Nothing is deleted or rewritten destructively.
    op.execute(
        """
        INSERT INTO care_circles (id, elder_user_id, name, created_at, updated_at)
        SELECT
            gen_random_uuid(),
            u.id,
            'Family',
            now(),
            now()
        FROM users u
        WHERE EXISTS (SELECT 1 FROM caregivers c WHERE c.cared_for_user_id = u.id)
        ON CONFLICT (elder_user_id) DO NOTHING;
        """
    )
    op.execute(
        """
        UPDATE caregivers c
        SET care_circle_id = cc.id,
            circle_role = CASE WHEN c.circle_role IS NULL THEN 'viewer' ELSE c.circle_role END
        FROM care_circles cc
        WHERE cc.elder_user_id = c.cared_for_user_id
          AND c.care_circle_id IS NULL;
        """
    )


def downgrade() -> None:
    op.drop_index("ix_caregivers_care_circle_id", table_name="caregivers")
    op.drop_column("caregivers", "circle_role")
    op.drop_column("caregivers", "care_circle_id")
    op.drop_index("ix_care_invitations_status", table_name="care_invitations")
    op.drop_index("ix_care_invitations_invite_code", table_name="care_invitations")
    op.drop_index("ix_care_invitations_circle_id", table_name="care_invitations")
    op.drop_table("care_invitations")
    op.drop_index("ix_care_circles_elder", table_name="care_circles")
    op.drop_table("care_circles")
    sa.Enum(name="circlerole").drop(op.get_bind(), checkfirst=True)