"""회원 일정 테이블 제거. (#1928)

회원 앱에서 일정(캘린더)을 걷어냈다. 회원이 일정을 여는 화면이 애초에 없었고 —
`MemberTabHeader` 가 캘린더 콜백을 받기만 하고 그리지 않았다 — 그래서 트레이너가
일정을 잡았을 때 보내던 `일정 보기` 알림도 갈 곳이 없는 버튼이었다.

회원 쪽 일정으로 남는 것은 **트레이너와 잡는 PT 일정**뿐이고, 그것은 이 표가 아니라
`trainer_sessions`·`reservations` 가 들고 있다.

`/schedule/events` 엔드포인트와 `dashboard.today_schedule` 도 함께 걷어냈으므로 이 표를
읽고 쓰는 곳이 남아 있지 않다.

Revision ID: 0069_drop_schedule_events
Revises: 0068_health_goal_change
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0069_drop_schedule_events"
down_revision: str | Sequence[str] | None = "0068_health_goal_change"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.drop_table("schedule_events")


def downgrade() -> None:
    op.create_table(
        "schedule_events",
        sa.Column("id", sa.String(length=64), nullable=False),
        sa.Column("user_id", sa.String(length=64), nullable=False),
        sa.Column("date", sa.String(length=10), nullable=False),
        sa.Column("time", sa.String(length=10), nullable=False),
        sa.Column("title", sa.String(length=200), nullable=False),
        sa.Column("category", sa.String(length=20), nullable=False),
        sa.Column("emoji", sa.String(length=10), nullable=False),
        sa.Column("color_hex", sa.String(length=10), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        op.f("ix_schedule_events_user_id"), "schedule_events", ["user_id"]
    )
    op.create_index(op.f("ix_schedule_events_date"), "schedule_events", ["date"])
