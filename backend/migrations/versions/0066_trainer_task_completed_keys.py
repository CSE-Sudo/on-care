"""트레이너 `오늘 할 일` 에 체크한 키를 명시적으로 저장. (#1716)

체크 상태를 `미션 키 - pending_keys - dismissed_keys` 로 추정하면, 마지막 저장
뒤에 새로 생긴 미션(새 상담 요청 등)이 `pending_keys` 에 없다는 이유만으로 완료로
보인다. 체크한 키를 따로 둔다.

기존 행은 NULL 로 남긴다 — 앱은 NULL 인 날을 옛 추정으로 되살린다.

Revision ID: 0066_trainer_task_completed_keys
Revises: 0065_trainer_daily_task_progress
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0066_trainer_task_completed_keys"
down_revision: str | Sequence[str] | None = "0065_trainer_daily_task_progress"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "trainer_daily_task_progress",
        sa.Column("completed_keys_json", sa.Text(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("trainer_daily_task_progress", "completed_keys_json")
