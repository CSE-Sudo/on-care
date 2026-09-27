"""자유 서술 회원 목표(`health_profiles.goals`) 삭제. (#2358)

회원 목표는 건강 목표 칩(`conditions`, 최대 2개)으로만 고른다. 자유 서술 칸은 회원
앱 MY 에도, 트레이너 웹 신체·목표 창(#2330)에도 더 이상 없어 아무도 고칠 수 없는
값이 됐고, AI 프롬프트는 칩을 읽도록 바뀌었다. 남겨 두면 옛 글이 목표처럼 읽힐
여지만 남는다.

되돌리면 빈 칸으로 다시 생긴다 — 지운 글은 돌아오지 않는다.

Revision ID: 0097_drop_health_profile_goals
Revises: 0096_notification_templates
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0097_drop_health_profile_goals"
down_revision: str | Sequence[str] | None = "0096_notification_templates"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.drop_column("health_profiles", "goals")


def downgrade() -> None:
    op.add_column(
        "health_profiles",
        sa.Column("goals", sa.Text(), nullable=False, server_default=""),
    )
