"""건강 목표 마지막 변경자·시각과 알림이 가리키는 회원. (#1832)

건강 목표(`health_profiles.conditions` 의 목표 칩)는 회원(온보딩·MY)과 담당
트레이너(트레이너 웹 회원 신체·목표 창)가 같은 칸을 함께 고친다. 서로 승인을 받게
하지 않고 바로 적용하는 대신, 누가 언제 바꿨는지 남기고 상대에게 알린다. 지금은
그 기록이 없어 한쪽이 바꾼 목표를 다른 쪽이 모르고 지나간다.

- `focus_changed_by` — `member` | `trainer`
- `focus_changed_by_id` — 바꾼 사람 id. 탈퇴해도 기록 문구(역할·시각)는 남도록
  외래키를 걸지 않는다(`health_profiles.user_id` 와 같은 표를 두 번 가리키면 ORM
  관계가 모호해지는 문제도 피한다).
- `focus_changed_at` — 바꾼 시각
- `notifications.subject_id` — 알림이 가리키는 대상 회원 id. 트레이너가 `회원
  건강 목표 변경` 알림을 누르면 그 회원 상세로 가야 하는데, 지금 알림 행에는 갈
  곳을 정할 값이 `category` 뿐이다. 비어 있어도 되는 열이라 기존 알림은 그대로다.

Revision ID: 0068_health_goal_change
Revises: 0067_points_ledger
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0068_health_goal_change"
down_revision: str | Sequence[str] | None = "0067_points_ledger"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "health_profiles",
        sa.Column("focus_changed_by", sa.String(10), nullable=True),
    )
    op.add_column(
        "health_profiles",
        sa.Column("focus_changed_by_id", sa.String(64), nullable=True),
    )
    op.add_column(
        "health_profiles",
        sa.Column("focus_changed_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "notifications",
        sa.Column("subject_id", sa.String(64), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("notifications", "subject_id")
    op.drop_column("health_profiles", "focus_changed_at")
    op.drop_column("health_profiles", "focus_changed_by_id")
    op.drop_column("health_profiles", "focus_changed_by")
