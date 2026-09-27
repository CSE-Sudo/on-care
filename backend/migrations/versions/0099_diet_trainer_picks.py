"""트레이너가 AI 후보 가운데 골라 회원에게 추천한 메뉴. (#2378)

회원당 한 건. 회원 앱 홈 `추천 식단` 첫 장의 `트레이너 추천` 이 이 행이다.

Revision ID: 0099_diet_trainer_picks
Revises: 0098_drop_health_profile_goals
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0099_diet_trainer_picks"
down_revision: str | Sequence[str] | None = "0098_drop_health_profile_goals"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "diet_trainer_picks",
        sa.Column("id", sa.String(length=64), primary_key=True),
        sa.Column(
            "member_id",
            sa.String(length=64),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
            unique=True,
        ),
        sa.Column(
            "trainer_id",
            sa.String(length=64),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
        sa.Column("slot", sa.String(length=20), nullable=False),
        sa.Column("name", sa.String(length=80), nullable=False),
        sa.Column("tag", sa.String(length=20), nullable=False),
        sa.Column("keyword", sa.String(length=40), nullable=False, server_default=""),
        sa.Column("confirmed_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("resolved_at", sa.DateTime(timezone=True), nullable=True),
    )


def downgrade() -> None:
    op.drop_table("diet_trainer_picks")
