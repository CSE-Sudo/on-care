"""최근 4주 기록으로 만든 끼니별 추천 메뉴 리스트. (#2250)

식단 탭 `오늘` AI 맞춤 조언이 다음 식사 메뉴를 이 리스트에서 고른다. AI 에게
한 번 받아 4주 동안 보관한다.

Revision ID: 0090_diet_menu_plans
Revises: 0089_emote_unlocks
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0090_diet_menu_plans"
down_revision: str | Sequence[str] | None = "0089_emote_unlocks"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "diet_menu_plans",
        sa.Column("id", sa.String(length=64), primary_key=True),
        sa.Column(
            "user_id",
            sa.String(length=64),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
        sa.Column("lang", sa.String(length=5), nullable=False, server_default="ko"),
        sa.Column("source", sa.String(length=10), nullable=False),
        sa.Column("items_json", sa.Text(), nullable=False, server_default="[]"),
        sa.Column("basis_days", sa.Integer(), nullable=False, server_default="0"),
        sa.Column(
            "goal_fingerprint", sa.String(length=64), nullable=False, server_default=""
        ),
        sa.Column("created_on", sa.String(length=10), nullable=False),
        sa.Column("expires_on", sa.String(length=10), nullable=False),
        sa.Column("retry_after", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )


def downgrade() -> None:
    op.drop_table("diet_menu_plans")
