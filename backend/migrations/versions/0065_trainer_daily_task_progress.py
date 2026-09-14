"""트레이너 대시보드 `오늘 할 일` 진행 상태를 계정 단위로 저장. (#1633)

체크(완료 표시)와 삭제(오늘 목록에서 제외)가 기기 로컬(SharedPreferences)에만
있어, 센터 PC 에서 체크한 항목이 태블릿에서는 그대로 남아 있었다. 알림 수신
설정(`0019_trainer_noti_settings`)이 계정 단위로 간 것과 같은 이유다.

`trainer_profiles` 컬럼이 아니라 별도 테이블인 까닭은 `할 일 진행률` 그래프가
날짜별 이력(최대 9주)을 읽기 때문이다 — 오늘 하루치만 담는 컬럼으로는 그래프가
계속 기기에 남는다.

(trainer_id, date) 하나당 한 행. 보관 기간은 서비스가 쓸 때 정리한다.

Revision ID: 0065_trainer_daily_task_progress
Revises: 0064_exercise_catalog
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0065_trainer_daily_task_progress"
down_revision: str | Sequence[str] | None = "0064_exercise_catalog"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "trainer_daily_task_progress",
        sa.Column(
            "trainer_id",
            sa.String(64),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column("date", sa.String(10), primary_key=True),
        sa.Column("total", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("completed_today", sa.Integer(), nullable=False, server_default="0"),
        sa.Column(
            "completed_carried_over", sa.Integer(), nullable=False, server_default="0"
        ),
        sa.Column("pending_keys_json", sa.Text(), nullable=False, server_default="[]"),
        sa.Column(
            "dismissed_keys_json", sa.Text(), nullable=False, server_default="[]"
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )


def downgrade() -> None:
    op.drop_table("trainer_daily_task_progress")
