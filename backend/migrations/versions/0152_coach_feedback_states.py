"""코칭 시트 피드백의 회원별 캐시·하루 생성 횟수 표 추가 (#3351)

`GET /ai-coach/feedback` 은 호출 한 번에 모델을 최대 두 번 부르는데 회원별 제한도 캐시도
없었다. 회원 앱이 기록·날짜 변경 때마다 다시 받게 되면 그 횟수만큼 모델 호출이 늘어난다.
회원 한 명에 한 행으로 만든 카드와 그날 생성 횟수를 둔다. 태스크가 여럿이어도 같은 값을
보도록 프로세스 메모리가 아니라 표에 둔다(`app/services/coach_feedback_service.py`).

새 표만 만든다.

Revision ID: 0152_coach_feedback_states
Revises: 0151_trainer_notify_kinds
Create Date: 2026-10-12
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0152_coach_feedback_states"
down_revision: str | Sequence[str] | None = "0151_trainer_notify_kinds"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "coach_feedback_states",
        sa.Column(
            "user_id",
            sa.String(length=64),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column("kst_date", sa.String(length=10), nullable=False),
        sa.Column("generations", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("revision", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("locale", sa.String(length=8), nullable=True),
        sa.Column("payload_json", sa.Text(), nullable=True),
        sa.Column("generated_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )


def downgrade() -> None:
    op.drop_table("coach_feedback_states")
