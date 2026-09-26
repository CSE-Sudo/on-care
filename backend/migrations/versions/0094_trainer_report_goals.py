"""트레이너가 리포트 ② 에서 고른 다음 주 목표. (#2232)

`week_start` 는 목표가 **적용되는 주**다. 다음 주 리포트의 `③ 지난 주 목표
달성` 이 자기 주의 목표를 그대로 꺼내 달성 여부를 판정한다 — 회수되지 않는
목표는 공수표라, 고르는 화면만 있고 이 표가 없으면 기능이 반쪽이다.

Revision ID: 0094_trainer_report_goals
Revises: 0093_member_weekly_feedback
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0094_trainer_report_goals"
down_revision: str | Sequence[str] | None = "0093_member_weekly_feedback"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "trainer_report_goals",
        sa.Column("id", sa.String(length=64), primary_key=True),
        sa.Column(
            "trainer_id",
            sa.String(length=64),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
        sa.Column(
            "member_id",
            sa.String(length=64),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
        sa.Column("week_start", sa.String(length=10), nullable=False, index=True),
        sa.Column("goals_json", sa.Text(), nullable=False, server_default="[]"),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        # 한 회원의 한 주에 목표 묶음은 하나다. 담당이 바뀌어도 그 주의 목표는
        # 회원의 것이라, 트레이너까지 키에 넣으면 인수인계한 주에 목록이 둘로
        # 갈라진다.
        sa.UniqueConstraint(
            "member_id", "week_start", name="uq_trainer_report_goals_member_week"
        ),
    )


def downgrade() -> None:
    op.drop_table("trainer_report_goals")
