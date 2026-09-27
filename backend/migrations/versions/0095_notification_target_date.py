"""트레이너 알림이 가리키는 날짜. (#2292)

예약·상담 알림을 눌러도 오늘 주 스케줄로만 가, 트레이너가 알림 본문의 날짜를
보고 달력을 다시 넘겨야 했다. 알림을 만들 때 그 날짜(`YYYY-MM-DD`)를 함께
남겨 스케줄을 그 날짜로 연다. 날짜가 없는 옛 알림은 비워 두고, 앱이 전처럼
오늘 스케줄로 보낸다.

Revision ID: 0095_notification_target_date
Revises: 0094_trainer_report_goals
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0095_notification_target_date"
down_revision: str | Sequence[str] | None = "0094_trainer_report_goals"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "notifications",
        sa.Column("target_date", sa.String(length=10), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("notifications", "target_date")
