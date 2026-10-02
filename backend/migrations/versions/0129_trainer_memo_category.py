"""회원 메모의 분류 칸 `category`. (#2622)

직접 쓴 메모는 운동만이 아니라 식단·통증·일정 이야기도 담는다. 메모 창에서
분류(`운동`·`식단`·`통증·부상`·`생활·일정`)를 하나 고를 수 있게 칸을 둔다.

- 빈 문자열 기본값 — 고르지 않은 메모와 채팅 감지 메모는 비어 있다
- 운동 기록 메모(`exercise_memo`, #2332)는 늘 `exercise` 다. 이미 있는 행도 채운다
- 허용값을 체크 제약으로 못 박는다(응답 스키마가 정해진 값만 받는다)

Revision ID: 0129_trainer_memo_category
Revises: 0128_close_stale_invites
Create Date: 2026-10-01
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0129_trainer_memo_category"
down_revision: str | Sequence[str] | None = "0128_close_stale_invites"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_TABLE = "trainer_client_memos"
_CHECK = "ck_trainer_client_memo_category"


def upgrade() -> None:
    op.add_column(
        _TABLE,
        sa.Column("category", sa.String(length=16), nullable=False, server_default=""),
    )
    op.execute(
        sa.text(f"UPDATE {_TABLE} SET category = 'exercise' WHERE source = 'exercise_memo'")
    )
    op.create_check_constraint(
        _CHECK, _TABLE, "category IN ('', 'exercise', 'diet', 'pain', 'life')"
    )


def downgrade() -> None:
    op.drop_constraint(_CHECK, _TABLE, type_="check")
    op.drop_column(_TABLE, "category")
