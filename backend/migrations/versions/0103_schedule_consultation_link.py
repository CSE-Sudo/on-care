"""상담 일정에 상담 요청을 잇는 `trainer_schedule.consultation_id`. (#2584)

상담 수락이 담당 연결을 만들지 않게 되면서, 아직 연결 전인 회원의 상담 일정도
트레이너 스케줄에 보여야 한다. 스케줄 조회는 회원이 붙은 일정을 활성 담당일 때만
보여 주므로(#2281), "상담 요청으로 생긴 일정" 임을 가를 값이 필요하다. 일정 카드가
`상담 요청 내용`(운동 목표·문의 글)을 읽는 길이기도 하다.

이미 수락으로 만들어진 일정도 맞춘다. 수락은 일정을 자리 종류(`1:1 PT`)로 만들고
회원 문의 글을 `note` 에 넣었다 — `note` 는 트레이너 피드백·상담 메모 자리라 회원
글이 거기 있으면 안 된다.

- 수락된 요청과 트레이너·회원·날짜·시각이 같은 일정에 `consultation_id` 를 잇는다
  (트레이너가 옮긴 일정은 잇지 않는다 — 무엇이 그 상담인지 가를 수 없다)
- 이어진 일정의 `note` 가 회원 문의 글과 똑같을 때만 비운다(트레이너가 고쳐 쓴 글은 남긴다)
- 이어진 일정 중 완료되지 않은 것만 종류를 `상담` 으로 바꾼다. 완료된 `1:1 PT` 는
  이미 회원 운동 기록이 파생돼 있어, 종류만 바꾸면 기록과 일정이 어긋난다

일정·담당 연결은 지우지 않는다. downgrade 는 컬럼만 되돌린다 — 바꾼 종류·메모는
원래 값을 가를 수 없어 되돌리지 않는다.

Revision ID: 0103_schedule_consultation_link
Revises: 0102_clear_reservation_note
Create Date: 2026-09-30
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0103_schedule_consultation_link"
down_revision: str | Sequence[str] | None = "0102_clear_reservation_note"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "trainer_schedule",
        sa.Column("consultation_id", sa.String(length=64), nullable=True),
    )
    op.create_index(
        "ix_trainer_schedule_consultation_id",
        "trainer_schedule",
        ["consultation_id"],
    )
    op.create_foreign_key(
        "fk_trainer_schedule_consultation_id",
        "trainer_schedule",
        "consultation_requests",
        ["consultation_id"],
        ["id"],
        ondelete="SET NULL",
    )
    backfill()


def backfill() -> None:
    """예전 수락이 만든 일정을 상담 요청에 잇고 종류·메모를 맞춘다."""
    # 한 요청에 맞는 일정이 둘 이상이면(같은 시각에 두 번 잡힌 경우) 가장 작은 id
    # 하나만 잇는다 — 둘 다 이으면 한 상담이 스케줄에 두 번 보인다.
    op.execute(
        "UPDATE trainer_schedule AS s SET consultation_id = c.id "
        "FROM consultation_requests AS c "
        "WHERE c.status = 'accepted' "
        "AND s.consultation_id IS NULL "
        "AND s.trainer_id = c.trainer_id "
        "AND s.member_id = c.member_id "
        "AND s.date = c.preferred_date "
        "AND s.time = c.preferred_time_slot "
        "AND s.id = ("
        "SELECT MIN(s2.id) FROM trainer_schedule AS s2 "
        "WHERE s2.trainer_id = c.trainer_id "
        "AND s2.member_id = c.member_id "
        "AND s2.date = c.preferred_date "
        "AND s2.time = c.preferred_time_slot)"
    )
    op.execute(
        "UPDATE trainer_schedule AS s SET note = '' "
        "FROM consultation_requests AS c "
        "WHERE s.consultation_id = c.id "
        "AND c.message IS NOT NULL AND c.message <> '' "
        "AND s.note = c.message"
    )
    op.execute(
        "UPDATE trainer_schedule SET type = '상담' "
        "WHERE consultation_id IS NOT NULL "
        "AND type <> '상담' "
        "AND status <> '완료'"
    )


def downgrade() -> None:
    op.drop_constraint(
        "fk_trainer_schedule_consultation_id",
        "trainer_schedule",
        type_="foreignkey",
    )
    op.drop_index(
        "ix_trainer_schedule_consultation_id", table_name="trainer_schedule"
    )
    op.drop_column("trainer_schedule", "consultation_id")
