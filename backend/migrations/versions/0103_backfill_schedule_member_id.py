"""스케줄로 만든 일정의 비어 있던 회원 id 를 이름으로 채운다. (#2586)

트레이너 웹 새 일정 창은 담당 회원을 골라도 회원 id 를 보내지 않아, 스케줄에서
만든 PT·상담 일정은 `member_id` 가 비고 이름(`client_name`)만 남았다. 그래서 회원
앱 `/me/coach/sessions`·회원별 일정 조회·대시보드 이탈 위험이 이 일정을 못 찾았다.
이제 웹이 id 를 보내므로, 이미 쌓인 행도 이름으로 잇는다.

같은 트레이너의 담당 회원(해제·휴면 포함) 가운데 이름이 **정확히 한 명**과 맞을
때만 잇는다. 동명이인이 있거나 맞는 회원이 없으면(이름만 있는 가망 고객) 그대로
둔다 — 잘못 이으면 남의 일정과 PT 글이 다른 회원 앱에 실린다.

downgrade 는 되돌리지 않는다 — 채운 행과 원래 id 가 있던 행을 가를 수 없다.

Revision ID: 0103_backfill_schedule_member_id
Revises: 0102_clear_reservation_note
Create Date: 2026-09-30
"""
from __future__ import annotations

from collections.abc import Sequence

from alembic import op

revision: str = "0103_backfill_schedule_member_id"
down_revision: str | Sequence[str] | None = "0102_clear_reservation_note"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute(
        "UPDATE trainer_schedule AS s SET member_id = m.member_id "
        "FROM ("
        "SELECT tc.trainer_id, u.name, MIN(tc.member_id) AS member_id "
        "FROM trainer_clients AS tc JOIN users AS u ON u.id = tc.member_id "
        "WHERE u.name <> '' "
        "GROUP BY tc.trainer_id, u.name "
        "HAVING COUNT(DISTINCT tc.member_id) = 1"
        ") AS m "
        "WHERE s.member_id IS NULL "
        "AND s.trainer_id = m.trainer_id "
        "AND s.client_name = m.name"
    )


def downgrade() -> None:
    pass
