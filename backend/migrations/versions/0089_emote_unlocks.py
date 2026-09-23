"""채팅 이모티콘을 하나씩 사서 7일 동안 쓴다. (#2153)

24시간 동안 모든 이모티콘을 쓰던 이용권(`emote_passes`, #2020) 대신, 이모티콘 하나를
사면 산 때부터 7일 동안 그 이모티콘을 보낸다. 기존 표는 지난 원장과 짝이 맞게 남기고,
바뀌기 전에 산 이용권은 남은 시간 동안 그대로 쓴다.

Revision ID: 0089_emote_unlocks
Revises: 0088_daily_routine_completion
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0089_emote_unlocks"
down_revision: str | Sequence[str] | None = "0088_daily_routine_completion"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "emote_unlocks",
        sa.Column("id", sa.String(length=64), primary_key=True),
        sa.Column(
            "user_id",
            sa.String(length=64),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
        sa.Column("emote_id", sa.String(length=40), nullable=False),
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
            "user_id", "client_request_id", name="uq_emote_unlock_client_request"
        ),
    )
    op.create_index(
        "ix_emote_unlocks_user_emote", "emote_unlocks", ["user_id", "emote_id"]
    )


def downgrade() -> None:
    op.drop_index("ix_emote_unlocks_user_emote", table_name="emote_unlocks")
    op.drop_table("emote_unlocks")
