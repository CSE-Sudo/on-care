"""연속 기록 보호권. (#1788)

포인트 사용처에서 300P 로 교환하는 보호권 표를 만든다. 회원이 운동을 못 한 어제를
연속 기록에 이어 붙이면 그 날짜를 남긴다.

- `streak_shields` — 보호권 한 장. 상태는 held|used. 쓴 보호권만 보호한 날
  (`protected_on`, KST)과 사용 시각을 가진다.
- 회원·날짜마다 쓴 보호권은 한 장뿐이다(partial unique index) — 하루에 보호는 한 번.

교환에 쓴 포인트는 기존 `points_ledger` 에 `spend` 로 남으므로 내역 표는 바꾸지
않는다. 되돌리면 표를 지운다(내역·잔액은 되돌리지 않는다 — 개발 DB 에서만 쓰는
경로다).

Revision ID: 0069_streak_shields
Revises: 0068_points_coupons
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0069_streak_shields"
down_revision: str | Sequence[str] | None = "0068_points_coupons"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "streak_shields",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column(
            "user_id",
            sa.String(64),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("cost", sa.Integer(), nullable=False),
        sa.Column("status", sa.String(8), nullable=False, server_default="held"),
        sa.Column("client_request_id", sa.String(64), nullable=True),
        sa.Column("acquired_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("protected_on", sa.String(10), nullable=True),
        sa.Column("used_at", sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint(
            "status IN ('held', 'used')", name="ck_streak_shields_status"
        ),
        sa.CheckConstraint(
            "(status = 'held' AND protected_on IS NULL AND used_at IS NULL) "
            "OR (status = 'used' AND protected_on IS NOT NULL AND used_at IS NOT NULL)",
            name="ck_streak_shields_use",
        ),
        sa.CheckConstraint("cost > 0", name="ck_streak_shields_cost"),
        sa.UniqueConstraint(
            "user_id", "client_request_id", name="uq_streak_shields_client_request"
        ),
    )
    op.create_index("ix_streak_shields_user_id", "streak_shields", ["user_id"])
    op.create_index(
        "ix_streak_shields_user_status", "streak_shields", ["user_id", "status"]
    )
    op.create_index(
        "uq_streak_shields_protected_on",
        "streak_shields",
        ["user_id", "protected_on"],
        unique=True,
        postgresql_where=sa.text("protected_on IS NOT NULL"),
    )


def downgrade() -> None:
    op.drop_index("uq_streak_shields_protected_on", table_name="streak_shields")
    op.drop_index("ix_streak_shields_user_status", table_name="streak_shields")
    op.drop_index("ix_streak_shields_user_id", table_name="streak_shields")
    op.drop_table("streak_shields")
