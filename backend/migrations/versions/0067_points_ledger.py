"""활동 포인트 내역 — 적립·사용·회수를 한 줄씩. (#1786)

포인트는 `health_profiles.activity_points` 숫자 하나뿐이었고 올리는 코드가 없었다.
적립 규칙(식단 기록·운동 직접 추가·AI 추천 운동 완료)을 실제로 적용하려면 무엇으로
몇 점을 받았는지가 남아야 한다 — 하루 한도를 세고, 같은 기록에 두 번 주지 않고,
기록을 지우면 받은 만큼 되돌리기 위해서다.

잔액은 계속 `activity_points` 가 들고, 이 표는 그 움직임을 남긴다. 둘은 같은
트랜잭션에서 함께 바뀐다. 사용(`spend`)은 아직 쓰는 곳이 없지만 쿠폰 같은 사용처가
붙을 자리로 종류에 넣어 둔다.

같은 기록(source)에 적립·회수는 한 번씩이다 — `(user_id, kind, source_type,
source_id)` 유니크 제약. 출처가 없는 행(사용 등)은 source 가 NULL 이라 제약 밖이다.

Revision ID: 0067_points_ledger
Revises: 0066_trainer_task_completed_keys
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0067_points_ledger"
down_revision: str | Sequence[str] | None = "0066_trainer_task_completed_keys"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "points_ledger",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column(
            "user_id",
            sa.String(64),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("kind", sa.String(10), nullable=False),
        sa.Column("delta", sa.Integer(), nullable=False),
        sa.Column("reason", sa.String(40), nullable=False),
        sa.Column("source_type", sa.String(40), nullable=True),
        sa.Column("source_id", sa.String(64), nullable=True),
        sa.Column("kst_date", sa.String(10), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.CheckConstraint(
            "kind IN ('earn', 'spend', 'revoke')", name="ck_points_ledger_kind"
        ),
        sa.CheckConstraint(
            "(kind = 'earn' AND delta > 0) OR (kind <> 'earn' AND delta <= 0)",
            name="ck_points_ledger_delta_sign",
        ),
        sa.UniqueConstraint(
            "user_id",
            "kind",
            "source_type",
            "source_id",
            name="uq_points_ledger_source",
        ),
    )
    op.create_index("ix_points_ledger_user_id", "points_ledger", ["user_id"])
    op.create_index(
        "ix_points_ledger_user_day",
        "points_ledger",
        ["user_id", "kst_date", "reason"],
    )


def downgrade() -> None:
    op.drop_index("ix_points_ledger_user_day", table_name="points_ledger")
    op.drop_index("ix_points_ledger_user_id", table_name="points_ledger")
    op.drop_table("points_ledger")
