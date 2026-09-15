"""포인트 체험 예약 — 체험 슬롯 종류와 체험 기록. (#1790)

트레이너 예약 시간에는 비는 칸이 생긴다. 트레이너가 켜 둔 빈 시간에만, 담당
트레이너가 없는 회원이 500P 로 20분 자세 점검 체험을 예약한다.

- `trainer_reservation_slots.session_type` 에 `체험` 을 더한다. 체험은 1:1 PT·상담과
  같은 층위의 **약속 종류**다 — 회원 예약이 만드는 일정이 이 종류를 그대로 물려받아
  트레이너 스케줄에서도 체험으로 보인다. 별도 불리언을 두면 "상담 + 체험" 같은
  뜻 없는 조합이 생긴다.
- `points_trials` — 체험 예약 한 건의 포인트 기록. 예약 행(`trainer_reservations`)은
  회원이 취소하면 지워지므로, 쓴 포인트의 결말(반환·소멸)과 "트레이너별 1회" 판정을
  거기에 둘 수 없다. 상태는 booked|completed|no_show|refunded|forfeited.
  반환된 체험은 1회에 세지 않는다(partial unique index).

되돌리면 체험 슬롯을 1:1 PT 로 바꾸고 표를 지운다. 포인트 내역(`points_ledger`)의
사용·반환 행은 옛 제약에서도 유효하므로 그대로 둔다.

Revision ID: 0069_points_trials
Revises: 0068_points_coupons
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0069_points_trials"
down_revision: str | Sequence[str] | None = "0068_points_coupons"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.drop_constraint(
        "ck_reservation_slot_session_type",
        "trainer_reservation_slots",
        type_="check",
    )
    op.create_check_constraint(
        "ck_reservation_slot_session_type",
        "trainer_reservation_slots",
        "session_type IN ('1:1 PT', '상담', '체험')",
    )

    op.create_table(
        "points_trials",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column(
            "member_id",
            sa.String(64),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "trainer_id",
            sa.String(64),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("slot_id", sa.String(64), nullable=False),
        sa.Column("reservation_id", sa.String(64), nullable=True),
        sa.Column("schedule_id", sa.String(64), nullable=True),
        sa.Column("cost", sa.Integer(), nullable=False),
        sa.Column("status", sa.String(12), nullable=False, server_default="booked"),
        sa.Column("starts_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("settled_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("settled_by", sa.String(16), nullable=False, server_default=""),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=True,
        ),
        sa.CheckConstraint(
            "status IN ('booked', 'completed', 'no_show', 'refunded', 'forfeited')",
            name="ck_points_trials_status",
        ),
        sa.CheckConstraint("cost > 0", name="ck_points_trials_cost"),
        sa.CheckConstraint(
            "settled_by IN ('', 'member', 'trainer')",
            name="ck_points_trials_settled_by",
        ),
    )
    op.create_index("ix_points_trials_member_id", "points_trials", ["member_id"])
    op.create_index("ix_points_trials_trainer_id", "points_trials", ["trainer_id"])
    op.create_index(
        "ix_points_trials_reservation_id", "points_trials", ["reservation_id"]
    )
    op.create_index("ix_points_trials_schedule_id", "points_trials", ["schedule_id"])
    op.create_index(
        "uq_points_trials_member_trainer",
        "points_trials",
        ["member_id", "trainer_id"],
        unique=True,
        postgresql_where=sa.text("status <> 'refunded'"),
    )


def downgrade() -> None:
    op.drop_index("uq_points_trials_member_trainer", table_name="points_trials")
    op.drop_index("ix_points_trials_schedule_id", table_name="points_trials")
    op.drop_index("ix_points_trials_reservation_id", table_name="points_trials")
    op.drop_index("ix_points_trials_trainer_id", table_name="points_trials")
    op.drop_index("ix_points_trials_member_id", table_name="points_trials")
    op.drop_table("points_trials")

    op.execute(
        "UPDATE trainer_reservation_slots SET session_type = '1:1 PT' "
        "WHERE session_type = '체험'"
    )
    op.drop_constraint(
        "ck_reservation_slot_session_type",
        "trainer_reservation_slots",
        type_="check",
    )
    op.create_check_constraint(
        "ck_reservation_slot_session_type",
        "trainer_reservation_slots",
        "session_type IN ('1:1 PT', '상담')",
    )
