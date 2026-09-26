"""회원이 한 주를 끝내며 남기는 세 문항. (#2232)

트레이너 리포트의 `회원 주간 피드백` 칸이 읽는 값이다. 수치만 보면 같은 한 주가
`게으름` 으로도 `과부하·일정 문제` 로도 읽히는데, 그 둘은 다음 주 처방이 정반대다.
회원 본인에게 묻는 세 문항(컨디션·강도·통증)이 그 갈림길을 정한다.

Revision ID: 0093_member_weekly_feedback
Revises: 0092_routine_schedule_link
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0093_member_weekly_feedback"
down_revision: str | Sequence[str] | None = "0092_routine_schedule_link"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "member_weekly_feedback",
        sa.Column("id", sa.String(length=64), primary_key=True),
        sa.Column(
            "user_id",
            sa.String(length=64),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
        sa.Column("week_start", sa.String(length=10), nullable=False, index=True),
        sa.Column("condition", sa.String(length=12), nullable=False),
        sa.Column("intensity", sa.String(length=12), nullable=False),
        sa.Column(
            "pain_area", sa.String(length=40), nullable=False, server_default=""
        ),
        sa.Column("pain_on", sa.String(length=10), nullable=False, server_default=""),
        sa.Column("note", sa.Text(), nullable=False, server_default=""),
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
        sa.CheckConstraint(
            "condition IN ('great', 'good', 'ok', 'tired', 'bad')",
            name="ck_member_weekly_feedback_condition",
        ),
        sa.CheckConstraint(
            "intensity IN ('too_easy', 'right', 'hard', 'too_hard')",
            name="ck_member_weekly_feedback_intensity",
        ),
        sa.UniqueConstraint(
            "user_id", "week_start", name="uq_member_weekly_feedback_user_week"
        ),
    )


def downgrade() -> None:
    op.drop_table("member_weekly_feedback")
