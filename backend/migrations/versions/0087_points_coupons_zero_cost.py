"""0P 쿠폰 허용 — 달성 보상으로 받는 식판 수령 쿠폰. (#2150)

분석용 식판은 포인트로 사지 않고 식단 사진 기록 조건을 채워 받는다. 쿠폰 목록·
상세·사용 처리를 다른 쿠폰과 함께 쓰려고 `points_coupons` 에 0P 행으로 담는다.

Revision ID: 0087_points_coupons_zero_cost
Revises: 0086_ai_chat_usages
"""
from __future__ import annotations

from collections.abc import Sequence

from alembic import op

revision: str = "0087_points_coupons_zero_cost"
down_revision: str | Sequence[str] | None = "0086_ai_chat_usages"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.drop_constraint("ck_points_coupons_cost", "points_coupons", type_="check")
    op.create_check_constraint(
        "ck_points_coupons_cost", "points_coupons", "cost >= 0"
    )


def downgrade() -> None:
    # 0P 쿠폰(식판)이 남아 있으면 옛 제약을 걸 수 없다 — 먼저 지운다.
    op.execute("DELETE FROM points_coupons WHERE cost = 0")
    op.drop_constraint("ck_points_coupons_cost", "points_coupons", type_="check")
    op.create_check_constraint("ck_points_coupons_cost", "points_coupons", "cost > 0")
