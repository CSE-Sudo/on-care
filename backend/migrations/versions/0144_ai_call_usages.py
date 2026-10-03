"""하루 AI 호출 수 — 서버 전체·트레이너 계정 상한을 DB 에서 센다. (#3032)

회원 AI 코치·사진 분석 한도는 한 회원만 묶어, 가입자가 늘면 그 합만큼 비용이 열린다.
트레이너 AI(고객 코치·루틴 후보·리포트 요약)는 하루 상한이 아예 없었다. 외부 모델을
부르기 직전에 `(kst_date, bucket)` 한 행을 원자적으로 더한다 — `global` 은 서버 전체,
`trainer:<id>` 는 그 트레이너의 합이다. 인메모리가 아니라 DB 라서 재기동·여러
인스턴스에서도 값이 같다.

새 표만 만든다 — 이 마이그레이션만으로 바뀌는 동작은 없다.

Revision ID: 0144_ai_call_usages
Revises: 0140_program_draft_member
Create Date: 2026-10-03
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0144_ai_call_usages"
down_revision: str | Sequence[str] | None = "0140_program_draft_member"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "ai_call_usages",
        sa.Column("kst_date", sa.String(length=10), primary_key=True),
        sa.Column("bucket", sa.String(length=80), primary_key=True),
        sa.Column(
            "trainer_id",
            sa.String(length=64),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=True,
        ),
        sa.Column("calls", sa.Integer(), nullable=False, server_default="0"),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )
    op.create_index(
        "ix_ai_call_usages_trainer_id",
        "ai_call_usages",
        ["trainer_id"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("ix_ai_call_usages_trainer_id", table_name="ai_call_usages")
    op.drop_table("ai_call_usages")
