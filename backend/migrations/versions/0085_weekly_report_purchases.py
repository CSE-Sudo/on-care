"""포인트로 받은 주간 리포트 — 어느 주를 샀는지. (#2022)

담당 트레이너가 없는 회원이 포인트로 한 주의 리포트를 받는다. 리포트 내용은
저장하지 않고(앱이 회원 기록으로 세운다) 산 주만 남긴다. 같은 주는 한 번만 산다.

Revision ID: 0084_weekly_report_purchases
Revises: 0083_profile_pets
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0084_weekly_report_purchases"
down_revision: str | Sequence[str] | None = "0083_profile_pets"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "weekly_report_purchases",
        sa.Column("id", sa.String(length=64), primary_key=True),
        sa.Column(
            "user_id",
            sa.String(length=64),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
        sa.Column("week_start", sa.String(length=10), nullable=False),
        sa.Column("cost", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("client_request_id", sa.String(length=64), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.UniqueConstraint(
            "user_id", "week_start", name="uq_weekly_report_purchase_week"
        ),
        sa.UniqueConstraint(
            "user_id",
            "client_request_id",
            name="uq_weekly_report_purchase_client_request",
        ),
    )


def downgrade() -> None:
    op.drop_table("weekly_report_purchases")
