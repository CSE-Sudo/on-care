"""포인트 쿠폰과 사용 반환 내역. (#1787)

포인트 사용처가 생긴다. 사용처 화면에서 포인트를 헬스장 쿠폰으로 교환하고(PT 재등록
3만원 할인, 개인 락커 1개월 무료), 쿠폰은 직원이 확인한 뒤 회원 휴대폰에서 사용
처리한다.

- `points_coupons` — 교환한 쿠폰 한 장. 상태는 issued|used|expired|cancelled.
  사용 가능한 쿠폰은 종류마다 회원당 한 장뿐이다(partial unique index).
- `points_ledger` 에 반환(`refund`) 종류를 더한다. 담당 트레이너 연결이 끊겨
  PT 재등록 쿠폰이, 헬스장 연결이 끊겨 락커 쿠폰이 취소되면 교환에 쓴 포인트를
  돌려준다. 회수(`revoke`)가 같은
  source 의 적립을 되돌리듯, 반환은 같은 source 의 사용을 되돌린다 — 그래서 부호가
  적립과 같은 양수다.

되돌리면 반환 내역 행을 지운다. 옛 CHECK 제약이 양수 반환을 받아 주지 않기 때문이다
(잔액은 되돌리지 않는다 — 개발 DB 에서만 쓰는 경로다).

Revision ID: 0069_points_coupons
Revises: 0068_health_goal_change
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0069_points_coupons"
down_revision: str | Sequence[str] | None = "0068_health_goal_change"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.drop_constraint("ck_points_ledger_kind", "points_ledger", type_="check")
    op.create_check_constraint(
        "ck_points_ledger_kind",
        "points_ledger",
        "kind IN ('earn', 'spend', 'revoke', 'refund')",
    )
    op.drop_constraint("ck_points_ledger_delta_sign", "points_ledger", type_="check")
    op.create_check_constraint(
        "ck_points_ledger_delta_sign",
        "points_ledger",
        "(kind IN ('earn', 'refund') AND delta > 0) "
        "OR (kind IN ('spend', 'revoke') AND delta <= 0)",
    )

    op.create_table(
        "points_coupons",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column(
            "user_id",
            sa.String(64),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("item", sa.String(40), nullable=False),
        sa.Column("cost", sa.Integer(), nullable=False),
        sa.Column(
            "status", sa.String(12), nullable=False, server_default="issued"
        ),
        sa.Column(
            "trainer_id",
            sa.String(64),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("trainer_name", sa.String(100), nullable=False, server_default=""),
        sa.Column("gym_name", sa.String(200), nullable=False, server_default=""),
        sa.Column("client_request_id", sa.String(64), nullable=True),
        sa.Column("issued_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("used_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("cancelled_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("expiry_reminded_at", sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint(
            "status IN ('issued', 'used', 'expired', 'cancelled')",
            name="ck_points_coupons_status",
        ),
        sa.CheckConstraint("cost > 0", name="ck_points_coupons_cost"),
        sa.UniqueConstraint(
            "user_id", "client_request_id", name="uq_points_coupons_client_request"
        ),
    )
    op.create_index("ix_points_coupons_user_id", "points_coupons", ["user_id"])
    op.create_index(
        "ix_points_coupons_user_status", "points_coupons", ["user_id", "status"]
    )
    op.create_index(
        "uq_points_coupons_active_item",
        "points_coupons",
        ["user_id", "item"],
        unique=True,
        postgresql_where=sa.text("status = 'issued'"),
    )


def downgrade() -> None:
    op.drop_index("uq_points_coupons_active_item", table_name="points_coupons")
    op.drop_index("ix_points_coupons_user_status", table_name="points_coupons")
    op.drop_index("ix_points_coupons_user_id", table_name="points_coupons")
    op.drop_table("points_coupons")

    op.execute("DELETE FROM points_ledger WHERE kind = 'refund'")
    op.drop_constraint("ck_points_ledger_delta_sign", "points_ledger", type_="check")
    op.create_check_constraint(
        "ck_points_ledger_delta_sign",
        "points_ledger",
        "(kind = 'earn' AND delta > 0) OR (kind <> 'earn' AND delta <= 0)",
    )
    op.drop_constraint("ck_points_ledger_kind", "points_ledger", type_="check")
    op.create_check_constraint(
        "ck_points_ledger_kind",
        "points_ledger",
        "kind IN ('earn', 'spend', 'revoke')",
    )
