"""회원 메모의 운동 기록 출처 `exercise_memo` 와 기록 연결 칸. (#2332)

운동 탭 기록 카드(PT 세션·개인 운동·회원 직접 기록)에서 트레이너만 보는 메모를
남기는 경로가 생긴다. 메모 창이 어느 기록에서 남긴 메모인지(`PT 세션 · 9/23`)를
보여 주도록 기록의 갈래·id·날짜·이름을 메모에 함께 저장한다.

- `source` 체크 제약에 `exercise_memo` 를 더한다
- `ref_kind`·`ref_name` 은 빈 문자열 기본값, `ref_id`·`ref_date` 는 NULL 허용
  — 기존 메모는 그대로 읽힌다

예전 개인 운동 피드백(`exercise_sessions.trainer_feedback`)은 회원이 이미 받아 본
트레이너 피드백이라 메모로 옮기지 않는다(#2517).

downgrade 는 운동 기록 메모를 지운 뒤 컬럼·제약을 되돌린다 — 되돌린 제약이
그 행을 받지 못한다.

Revision ID: 0106_trainer_memo_exercise_ref
Revises: 0105_schedule_consultation_link
Create Date: 2026-09-30
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0106_trainer_memo_exercise_ref"
down_revision: str | Sequence[str] | None = "0105_schedule_consultation_link"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_TABLE = "trainer_client_memos"
_CHECK = "ck_trainer_client_memo_source"


def upgrade() -> None:
    op.add_column(
        _TABLE,
        sa.Column("ref_kind", sa.String(length=16), nullable=False, server_default=""),
    )
    op.add_column(_TABLE, sa.Column("ref_id", sa.String(length=64), nullable=True))
    op.add_column(_TABLE, sa.Column("ref_date", sa.String(length=10), nullable=True))
    op.add_column(
        _TABLE,
        sa.Column("ref_name", sa.String(length=100), nullable=False, server_default=""),
    )
    op.drop_constraint(_CHECK, _TABLE, type_="check")
    op.create_check_constraint(
        _CHECK, _TABLE, "source IN ('trainer', 'chat_insight', 'exercise_memo')"
    )


def downgrade() -> None:
    op.execute(sa.text(f"DELETE FROM {_TABLE} WHERE source = 'exercise_memo'"))
    op.drop_constraint(_CHECK, _TABLE, type_="check")
    op.create_check_constraint(_CHECK, _TABLE, "source IN ('trainer', 'chat_insight')")
    op.drop_column(_TABLE, "ref_name")
    op.drop_column(_TABLE, "ref_date")
    op.drop_column(_TABLE, "ref_id")
    op.drop_column(_TABLE, "ref_kind")
