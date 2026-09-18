"""회원 탈퇴 사유. (#2019)

왜 떠나는지 모은 적이 없었다. 탈퇴는 되돌릴 수 없는 동작이라 한 번 더 확인하는
자리이기도 하고, 무엇이 불편했는지는 그 자리에서만 물을 수 있다.

**회원 행과 잇지 않는다.** 회원은 이 표에 쓰는 바로 그 순간 지워지므로 FK 를 걸면
남길 수가 없다. 남기는 것도 사유 코드와 시각뿐이다 — 누가 썼는지는 모으지 않는다.

Revision ID: 0072_deletion_reason
Revises: 0071_insight_dismissed
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0072_deletion_reason"
down_revision: str | Sequence[str] | None = "0071_insight_dismissed"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "account_deletion_reasons",
        sa.Column("id", sa.String(length=64), nullable=False),
        sa.Column("reason", sa.String(length=40), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        op.f("ix_account_deletion_reasons_reason"),
        "account_deletion_reasons",
        ["reason"],
    )


def downgrade() -> None:
    op.drop_index(
        op.f("ix_account_deletion_reasons_reason"),
        table_name="account_deletion_reasons",
    )
    op.drop_table("account_deletion_reasons")
