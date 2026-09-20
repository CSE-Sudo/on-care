"""채팅 이모티콘 — 24시간 이용권과 메시지의 이모티콘 id. (#2020)

이용권은 한 번 사면 24시간 동안 모든 이모티콘을 쓴다. 남은 시간은 `expires_at`
하나로 계산하고, 만료는 스케줄러 없이 조회할 때 비교한다(쿠폰과 같은 방식).

`chat_messages.emote_id` 는 이모티콘 메시지의 그림을 고르는 값이다. 본문은 그대로
남겨 이모티콘을 그리지 못하는 자리(알림·로스터의 마지막 메시지)가 읽는다.

Revision ID: 0080_chat_emotes
Revises: 0079_weekly_challenges
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0080_chat_emotes"
down_revision: str | Sequence[str] | None = "0079_weekly_challenges"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "emote_passes",
        sa.Column("id", sa.String(length=64), primary_key=True),
        sa.Column(
            "user_id",
            sa.String(length=64),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
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
            "user_id", "client_request_id", name="uq_emote_pass_client_request"
        ),
    )
    op.add_column(
        "chat_messages", sa.Column("emote_id", sa.String(length=40), nullable=True)
    )


def downgrade() -> None:
    op.drop_column("chat_messages", "emote_id")
    op.drop_table("emote_passes")
