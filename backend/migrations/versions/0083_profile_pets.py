"""MY 프로필 펫 이모지 — 포인트로 여는 기간제 꾸밈. (#2021)

강아지나 고양이 하나를 골라 7일 동안 MY 프로필 이름 옆에 단다. 언제까지인지는
`expires_at` 하나가 들고 있고, 만료는 스케줄러 없이 조회할 때 비교한다(이모티콘
이용권과 같은 방식). 지난 행은 지우지 않는다.

Revision ID: 0083_profile_pets
Revises: 0082_isometric_hold_seconds
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0083_profile_pets"
down_revision: str | Sequence[str] | None = "0082_isometric_hold_seconds"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "profile_pets",
        sa.Column("id", sa.String(length=64), primary_key=True),
        sa.Column(
            "user_id",
            sa.String(length=64),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
        sa.Column("kind", sa.String(length=16), nullable=False),
        sa.Column("cost", sa.Integer(), nullable=False, server_default="0"),
        sa.Column(
            "expires_at", sa.DateTime(timezone=True), nullable=False, index=True
        ),
        sa.Column("client_request_id", sa.String(length=64), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.UniqueConstraint(
            "user_id", "client_request_id", name="uq_profile_pet_client_request"
        ),
    )


def downgrade() -> None:
    op.drop_table("profile_pets")
