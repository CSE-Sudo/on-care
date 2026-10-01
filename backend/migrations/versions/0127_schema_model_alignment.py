"""모델과 어긋난 칸의 NOT NULL 보정. (#2838)

CI 가 테스트 기동 때 `create_all()` 로 스키마를 한 번 더 만들어, 모델과 마이그레이션의
차이가 드러나지 않았다. `alembic check` 를 CI 에 넣으면서 드러난 차이를 여기서 맞춘다.

- 모델이 NOT NULL 로 선언한 생성·수정 시각 칸 여섯 개가 마이그레이션에서는 NULL 을
  허용했다. 모두 `server_default=now()` 라 정상 경로로 들어온 행은 값이 있다. 혹시 남은
  NULL 은 지금 시각으로 채운 뒤 제약을 건다 — 행을 지우지 않는다.
- `coach_documents` 의 (user_id, source_ref) 인덱스는 0030 이 만든 것이 맞다. 모델에
  선언이 빠져 있던 쪽을 모델에서 고쳤으므로 여기서는 손대지 않는다.

Revision ID: 0127_schema_model_alignment
Revises: 0110_user_token_version
Create Date: 2026-10-01
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0127_schema_model_alignment"
down_revision: str | Sequence[str] | None = "0110_user_token_version"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

#: (테이블, 칸) — 모델은 NOT NULL, 마이그레이션은 NULL 허용이던 시각 칸.
_TIMESTAMP_COLUMNS: tuple[tuple[str, str], ...] = (
    ("chat_messages", "created_at"),
    ("routine_history", "created_at"),
    ("trainer_clients", "created_at"),
    ("trainer_profiles", "updated_at"),
    ("trainer_routines", "created_at"),
    ("trainer_schedule", "created_at"),
)


def upgrade() -> None:
    for table, column in _TIMESTAMP_COLUMNS:
        op.execute(
            sa.text(f"UPDATE {table} SET {column} = now() WHERE {column} IS NULL")
        )
        op.alter_column(
            table,
            column,
            existing_type=sa.DateTime(timezone=True),
            nullable=False,
            existing_server_default=sa.text("now()"),
        )


def downgrade() -> None:
    for table, column in reversed(_TIMESTAMP_COLUMNS):
        op.alter_column(
            table,
            column,
            existing_type=sa.DateTime(timezone=True),
            nullable=True,
            existing_server_default=sa.text("now()"),
        )
