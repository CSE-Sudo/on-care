"""식단 사진 분석 사용량 — 하루 상한을 DB 에서 센다. (#2827)

`POST /diet/analyze` 가 외부 비전 모델을 부르기 직전에 한 줄을 남긴다. 하루 상한은
`(user_id, kst_date)` 로 센다. 인메모리가 아니라 DB 라서 재기동·여러 인스턴스에서도
값이 같다.

Revision ID: 0135_diet_analysis_usages
Revises: 0133_password_reset_tokens
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0135_diet_analysis_usages"
down_revision: str | Sequence[str] | None = "0133_password_reset_tokens"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "diet_analysis_usages",
        sa.Column("id", sa.String(length=64), primary_key=True),
        sa.Column(
            "user_id",
            sa.String(length=64),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
        sa.Column("kst_date", sa.String(length=10), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )
    op.create_index(
        "ix_diet_analysis_usages_user_date",
        "diet_analysis_usages",
        ["user_id", "kst_date"],
    )


def downgrade() -> None:
    op.drop_index("ix_diet_analysis_usages_user_date", table_name="diet_analysis_usages")
    op.drop_table("diet_analysis_usages")
