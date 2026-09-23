"""PT 일정에 붙는 개인운동 — 일정 연결·전송 종류·한마디. (#2223)

프로그램 만들기에서 PT 프로그램과 함께 정한 개인운동은 그 PT 일정에 붙어 있다가
PT 를 완료할 때 회원에게 간다(#2224). 지금까지 `trainer_routines` 와
`trainer_schedule` 사이에는 아무 연결이 없어, 어떤 개인운동이 어느 PT 의 것인지
알 방법이 없었다.

세 칸을 연다.

- `schedule_id` — 붙어 있는 PT 일정. 개인운동만 보낸 경우는 붙일 일정이 없어
  비어 있다. 일정이 지워져도 개인운동은 남기고 연결만 끊는다(`SET NULL`) —
  이미 회원에게 간 운동이 일정과 함께 사라지면 안 된다.
- `delivery_kind` — 이 전송이 어떤 종류였나(`pt_with_routine` /
  `routine_only` / `cancelled_routine_only`). 이력에서 종류를 구분해 보여
  준다(#2225). 이 칸이 생기기 전 배정과 AI 제안 후보는 비어 있다.
- `trainer_message` — 전송에 붙인 회원에게 한마디. 선택 입력이라 보통 빈
  문자열이다. `reason` 과 달리 운동 하나가 아니라 전송 전체에 붙는 말이라
  칸을 나눈다.

`status` 에는 새 값 `scheduled`(일정에 붙었고 아직 전송 전)가 생긴다. 컬럼이
`String(20)` 에 제약 없는 자유 문자열이라 스키마 변경은 없다.

Revision ID: 0090_routine_schedule_link
Revises: 0089_emote_unlocks
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0090_routine_schedule_link"
down_revision: str | Sequence[str] | None = "0089_emote_unlocks"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "trainer_routines",
        sa.Column("schedule_id", sa.String(length=64), nullable=True),
    )
    op.create_index(
        "ix_trainer_routines_schedule_id", "trainer_routines", ["schedule_id"]
    )
    op.create_foreign_key(
        "fk_trainer_routines_schedule_id",
        "trainer_routines",
        "trainer_schedule",
        ["schedule_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.add_column(
        "trainer_routines",
        sa.Column("delivery_kind", sa.String(length=32), nullable=True),
    )
    op.add_column(
        "trainer_routines",
        sa.Column(
            "trainer_message",
            sa.String(length=200),
            nullable=False,
            server_default="",
        ),
    )


def downgrade() -> None:
    op.drop_column("trainer_routines", "trainer_message")
    op.drop_column("trainer_routines", "delivery_kind")
    op.drop_constraint(
        "fk_trainer_routines_schedule_id", "trainer_routines", type_="foreignkey"
    )
    op.drop_index("ix_trainer_routines_schedule_id", table_name="trainer_routines")
    op.drop_column("trainer_routines", "schedule_id")
