"""상담 요청이 트레이너의 빈 자리를 잡는다. (#1873)

회원이 희망 시각을 적어 보내던 방식을 버리고, 트레이너가 열어 둔 `1:1 PT` 자리를
고르게 한다. 고른 자리는 신청하는 순간 잠기고, 수락하면 그대로 첫 일정이 된다.

`preferred_date`·`preferred_time_slot` 은 **남긴다.** 자리 선택 이전에 접수된 요청이
그 두 칸에만 시각을 들고 있어, 지우면 그 요청들의 조회가 깨진다. 새 요청은 고른
자리의 시각을 같은 칸에 옮겨 적는다.

자리 없이 접수된 `pending` 요청은 새 흐름으로 처리할 방법이 없다 — 트레이너가
수락해도 잡을 자리가 없다. 여기서 `expired` 로 정리하고, 회원에게는 앱이 그 상태를
"만료" 로 보여 준다. `accepted`·`rejected`·`cancelled` 인 지난 요청은 건드리지 않는다.

Revision ID: 0073_consultation_slot
Revises: 0072_deletion_reason
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0073_consultation_slot"
down_revision: str | Sequence[str] | None = "0072_deletion_reason"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "consultation_requests",
        sa.Column("slot_id", sa.String(length=64), nullable=True),
    )
    op.create_index(
        "ix_consultation_requests_slot_id", "consultation_requests", ["slot_id"]
    )
    op.create_foreign_key(
        "fk_consultation_requests_slot_id",
        "consultation_requests",
        "trainer_reservation_slots",
        ["slot_id"],
        ["id"],
        ondelete="SET NULL",
    )
    # 이행기 정리 — 자리 없이 접수돼 처리할 수 없게 된 대기 요청을 닫고, 기다리던
    # 회원에게 알린다. 방금 더한 칼럼이라 모든 `pending` 이 대상이다. 0 건이면 두 문
    # 모두 아무 일도 하지 않는다.
    #
    # 알림을 먼저 넣는다 — 상태를 바꾼 뒤에는 어느 요청이 이번에 만료됐는지
    # 가려낼 수 없다.
    op.execute(
        sa.text(
            "INSERT INTO notifications (id, user_id, title, body, category, read) "
            "SELECT "
            "  'noti-mig72-' || substr(md5(random()::text || c.id), 1, 12), "
            "  c.member_id, "
            "  '상담 신청이 만료되었어요', "
            "  '트레이너의 예약 가능한 시간에서 다시 신청해 주세요.', "
            "  'consultation_result', "
            "  false "
            "FROM consultation_requests c "
            "WHERE c.status = 'pending' AND c.slot_id IS NULL"
        )
    )
    op.execute(
        sa.text(
            "UPDATE consultation_requests "
            "SET status = 'expired', updated_at = now() "
            "WHERE status = 'pending' AND slot_id IS NULL"
        )
    )


def downgrade() -> None:
    # 만료로 바꾼 요청은 되돌리지 않는다 — 어느 것이 이 마이그레이션 때문이었는지
    # 구분할 근거가 남아 있지 않고, 되돌려도 잡을 자리가 없다.
    op.drop_constraint(
        "fk_consultation_requests_slot_id", "consultation_requests", type_="foreignkey"
    )
    op.drop_index("ix_consultation_requests_slot_id", table_name="consultation_requests")
    op.drop_column("consultation_requests", "slot_id")
