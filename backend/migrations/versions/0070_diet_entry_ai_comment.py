"""끼니 AI 코멘트 컬럼. (#1932)

끼니 카드 아래 한 줄로 붙는 AI 코멘트가 실서버에서는 늘 비어 있었다. 앱은
`ai_comment` 를 읽고 데모 서버는 내려주는데, 실서버에는 그 컬럼이 없었다.

`POST /diet/analyze` 는 `coach_comment` 를 실제로 만들어 주지만 저장할 자리가
없어 응답 한 번으로 사라졌다 — 방금 찍어 저장한 끼니도 화면을 다시 열면
코멘트가 없었다.

비울 수 있는 값이 아니라 빈 문자열을 기본값으로 둔다. 사진 없이 손으로 적은
끼니와 이 마이그레이션 이전 기록에는 코멘트가 없다.

Revision ID: 0070_diet_entry_ai_comment
Revises: 0069_drop_schedule_events
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0070_diet_entry_ai_comment"
down_revision: str | Sequence[str] | None = "0069_drop_schedule_events"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "diet_entries",
        sa.Column(
            "ai_comment", sa.Text(), nullable=False, server_default=sa.text("''")
        ),
    )


def downgrade() -> None:
    op.drop_column("diet_entries", "ai_comment")
