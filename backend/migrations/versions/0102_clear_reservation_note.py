"""회원 앱 예약 일정의 '회원 앱 예약' 표식 정리. (#2575)

회원 앱 예약은 트레이너 일정을 만들면서 `note` 에 '회원 앱 예약' 을 넣었다. 그런데
PT 일정의 `note` 는 트레이너 피드백이라(#2515), 피드백 없이 완료하면 이 문구가 회원
앱 완료 PT 카드·이탈 위험·AI 개인 운동 추천에 피드백으로 잡혔다. 이제 예약은 `note`
를 비워 두므로, 이미 쌓인 행에서도 표식을 걷어 낸다.

예약에 연결된 일정(`trainer_reservations.schedule_id`)만 건드린다 — 트레이너가 직접
같은 문구를 적은 일정까지 지우지 않는다.

downgrade 는 되돌리지 않는다 — 표식이던 행과 원래 비어 있던 행을 가를 수 없다.

Revision ID: 0102_clear_reservation_note
Revises: 0101_drop_trainer_invite_codes
Create Date: 2026-09-30
"""
from __future__ import annotations

from collections.abc import Sequence

from alembic import op

revision: str = "0102_clear_reservation_note"
down_revision: str | Sequence[str] | None = "0101_drop_trainer_invite_codes"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute(
        "UPDATE trainer_schedule SET note = '' "
        "WHERE note = '회원 앱 예약' "
        "AND id IN (SELECT schedule_id FROM trainer_reservations "
        "WHERE schedule_id IS NOT NULL)"
    )


def downgrade() -> None:
    pass
