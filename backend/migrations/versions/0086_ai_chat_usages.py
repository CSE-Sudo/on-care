"""AI 챗봇이 답한 대화 — 하루 무료 횟수와 포인트 구매. (#2145)

LLM 이 실제로 답한 대화마다 한 줄을 남긴다. 하루 한도는 `(user_id, kst_date)` 로
세고, 포인트로 산 대화는 `paid`·`cost`·`balance_after` 를 들고 있다. 같은 메시지의
재전송은 `(user_id, client_request_id)` 유일로 한 번만 센다.

Revision ID: 0086_ai_chat_usages
Revises: 0085_weekly_report_purchases
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0086_ai_chat_usages"
down_revision: str | Sequence[str] | None = "0085_weekly_report_purchases"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "ai_chat_usages",
        sa.Column("id", sa.String(length=64), primary_key=True),
        sa.Column(
            "user_id",
            sa.String(length=64),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
        sa.Column("kst_date", sa.String(length=10), nullable=False),
        sa.Column("paid", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("cost", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("balance_after", sa.Integer(), nullable=True),
        sa.Column("message_id", sa.String(length=64), nullable=True),
        sa.Column("client_request_id", sa.String(length=64), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.UniqueConstraint(
            "user_id", "client_request_id", name="uq_ai_chat_usage_client_request"
        ),
    )
    op.create_index(
        "ix_ai_chat_usages_user_date", "ai_chat_usages", ["user_id", "kst_date"]
    )


def downgrade() -> None:
    op.drop_index("ix_ai_chat_usages_user_date", table_name="ai_chat_usages")
    op.drop_table("ai_chat_usages")
