"""개인 운동 트레이너 피드백 칸 `exercise_sessions.trainer_feedback` 삭제. (#2517)

트레이너가 배정 개인운동의 수행 기록 한 건마다 남기던 피드백이다. 트레이너 웹의
작성 화면은 #2334 에서, 저장 API 는 #2517 에서 없앴다. 회원 쪽 개인 운동 피드백은
#1825 에서 먼저 없앴다 — 개인운동에 대해 서로 할 말은 채팅으로 한다.

새 값이 생기지 않는데 옛 값은 회원 앱 운동 카드와 AI 개인운동 추천 근거에 계속
쓰였다. 그 읽기를 모두 걷어 내며 저장된 값도 함께 지운다.

downgrade 는 빈 칸만 되돌린다 — 지운 글은 돌아오지 않는다.

Revision ID: 0107_drop_exercise_trainer_feedback
Revises: 0106_trainer_memo_exercise_ref
Create Date: 2026-09-30
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0107_drop_exercise_trainer_feedback"
down_revision: str | Sequence[str] | None = "0106_trainer_memo_exercise_ref"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.drop_column("exercise_sessions", "trainer_feedback")


def downgrade() -> None:
    op.add_column(
        "exercise_sessions",
        sa.Column("trainer_feedback", sa.Text(), nullable=False, server_default=""),
    )
