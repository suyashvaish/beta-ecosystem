"""add caregiver fcm_device_token

Revision ID: a1c4f8e2b7d9
Revises: 15ff2a5349ec
Create Date: 2026-11-14

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a1c4f8e2b7d9'
down_revision: Union[str, None] = '15ff2a5349ec'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Server-owned FCM push token per caregiver row; used to fan out
    # emergency alerts without ever accepting client-supplied tokens.
    op.add_column(
        'caregivers',
        sa.Column('fcm_device_token', sa.String(length=4096), nullable=True),
    )


def downgrade() -> None:
    op.drop_column('caregivers', 'fcm_device_token')