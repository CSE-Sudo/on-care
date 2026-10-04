"""운동 기록에 저장 요청 멱등키와 순서 칸 추가. (#3095)

회원 앱은 운동 여러 개를 한 요청으로 저장한다. 응답을 잃은 뒤 다시 누르면 같은
기록과 포인트가 한 벌 더 생겼다 — 이 경로에만 멱등키가 없었다.

- `client_request_id`: 저장 요청의 멱등키. 키 없이 저장한 기록은 NULL 이다.
- `client_request_index`: 그 요청 안에서 몇 번째 항목인지(0부터).
- `(user_id, client_request_id, client_request_index)` 유일 제약: 동시에 온
  재시도가 같은 자리를 두 번 넣지 못하게 한다. NULL 은 제약 밖이다.

기존 행은 둘 다 NULL 이라 이 마이그레이션만으로 바뀌는 동작은 없다.

Revision ID: 0146_exercise_client_request
Revises: 0143_member_weekly_report_on
Create Date: 2026-10-04
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0146_exercise_client_request"
down_revision: str | Sequence[str] | None = "0143_member_weekly_report_on"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "exercise_sessions",
        sa.Column("client_request_id", sa.String(length=64), nullable=True),
    )
    op.add_column(
        "exercise_sessions",
        sa.Column("client_request_index", sa.Integer(), nullable=True),
    )
    op.create_unique_constraint(
        "uq_exercise_sessions_client_request",
        "exercise_sessions",
        ["user_id", "client_request_id", "client_request_index"],
    )


def downgrade() -> None:
    op.drop_constraint(
        "uq_exercise_sessions_client_request",
        "exercise_sessions",
        type_="unique",
    )
    op.drop_column("exercise_sessions", "client_request_index")
    op.drop_column("exercise_sessions", "client_request_id")
