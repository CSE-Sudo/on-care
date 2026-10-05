"""PT 프로그램 줄을 회원의 매일 개인운동 목록에서 내린다. (#3115)

PT 를 마치고 보낸 PT 프로그램 줄은 `ended_on` 이 비어, 트레이너가 철회할 때까지
회원 운동 탭 `추천 개인운동` 에 날마다 걸렸다. 그 줄을 같은 목록으로 읽는 운동
조언·트레이너 웹 `개인운동 미수행` 신호·리포트 개인운동 수도 PT 프로그램을
개인운동으로 세었다. 이제 PT 프로그램은 보낼 때 목록에 걸지 않는다
(`ended_on == active_from`) — 그날 내용은 PT 기록이 남긴다.

이미 걸려 있는 줄은 오늘(KST)부로 내린다. 지난 날짜 화면이 그날 걸려 있던 목록을
되짚을 수 있게 지난 기간은 그대로 둔다(`ended_on` 은 이날부터 없음, #2161).

PT 프로그램 줄은 PT 일정에 붙어(`schedule_id`) 개인운동 전송 종류
(`delivery_kind`)가 비어 있는 줄이다. 일정 없이 올린 옛 배정은 개인운동과 가를
수 없어 건드리지 않는다.

Revision ID: 0149_pt_program_off_daily_list
Revises: 0148_exercise_client_request
Create Date: 2026-10-04
"""
from __future__ import annotations

from collections.abc import Sequence

from alembic import op

revision: str = "0149_pt_program_off_daily_list"
down_revision: str | Sequence[str] | None = "0148_exercise_client_request"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute(
        """
        UPDATE trainer_routines
        SET ended_on = GREATEST(
            active_from,
            to_char((now() AT TIME ZONE 'Asia/Seoul')::date, 'YYYY-MM-DD')
        )
        WHERE status = 'approved'
          AND delivery_kind IS NULL
          AND schedule_id IS NOT NULL
          AND ended_on IS NULL
        """
    )


def downgrade() -> None:
    # 어느 줄이 원래 걸려 있었는지 남기지 않았다 — 되돌릴 수 없는 정리다.
    pass
