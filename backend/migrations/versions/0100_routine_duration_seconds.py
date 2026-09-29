"""개인운동(배정 루틴)의 운동 시간을 초로도 남긴다. (#2221)

트레이너 웹이 운동 시간을 시·분·초 세 칸으로 적는다. 프로그램 운동은 JSON 안에
초를 싣지만, 개인운동은 `trainer_routines.minutes` 컬럼이라 초를 담을 칸이
따로 필요하다. 비어 있으면 예전처럼 `minutes` × 60 으로 읽는다.

Revision ID: 0100_routine_duration_seconds
Revises: 0099_diet_trainer_picks
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0100_routine_duration_seconds"
down_revision: str | Sequence[str] | None = "0099_diet_trainer_picks"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "trainer_routines",
        sa.Column("duration_seconds", sa.Integer(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("trainer_routines", "duration_seconds")
