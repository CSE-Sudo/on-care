"""식단 AI 맞춤 조언이 기간마다 기억해 두는 것. (#2251)

오늘은 그날 추천한 메뉴(최근 3일 안에 추천한 메뉴를 뒤로 미룬다), 이번 주·전체는 한 번
만든 조언을 둔다.

Revision ID: 0091_diet_advice_states
Revises: 0090_diet_menu_plans
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0091_diet_advice_states"
down_revision: str | Sequence[str] | None = "0090_diet_menu_plans"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "diet_advice_states",
        sa.Column("id", sa.String(length=64), primary_key=True),
        sa.Column(
            "user_id",
            sa.String(length=64),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
        sa.Column("period", sa.String(length=10), nullable=False),
        sa.Column("key_date", sa.String(length=10), nullable=False),
        sa.Column("lang", sa.String(length=5), nullable=False, server_default="ko"),
        sa.Column("payload_json", sa.Text(), nullable=False, server_default="{}"),
        sa.Column("retry_after", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.UniqueConstraint(
            "user_id", "period", "key_date", "lang", name="uq_diet_advice_state"
        ),
    )


def downgrade() -> None:
    op.drop_table("diet_advice_states")
