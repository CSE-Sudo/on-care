"""개인 운동 회원 피드백 칸 `exercise_sessions.member_note` 삭제. (#2624)

회원이 배정 개인운동을 완료할 때 `피드백(선택)` 칸에 남기던 글이다. 입력과 표시는
#1825 에서 없앴고 그 뒤로 값을 쓰거나 읽는 곳이 없다 — 회원의 불편은 채팅 감지로
모은다. 트레이너 쪽 칸(`trainer_feedback`)을 지운 #2517 과 같은 방식으로 저장된
값도 함께 지운다.

downgrade 는 빈 칸만 되돌린다 — 지운 글은 돌아오지 않는다.

Revision ID: 0108_drop_member_note
Revises: 0107_drop_routine_feedback
Create Date: 2026-09-30
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0108_drop_member_note"
down_revision: str | Sequence[str] | None = "0107_drop_routine_feedback"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.drop_column("exercise_sessions", "member_note")


def downgrade() -> None:
    op.add_column(
        "exercise_sessions",
        sa.Column("member_note", sa.Text(), nullable=False, server_default=""),
    )
