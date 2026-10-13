"""트레이너 알림 종류별 수신 설정 컬럼 추가 (#2420)

서버에서 끌 수 있는 트레이너 알림이 새 메시지(`notify_new_message`) 하나뿐이라, 상담
요청·예약·담당 회원 소식은 설정과 상관없이 항상 알림함에 들어왔다. 트레이너 웹의 알림
탭은 이 세 스위치를 미리 만들어 두고 서버에 칸이 없으면 막아 두었다(#2264).

`0019_trainer_noti_settings` 와 같은 방식으로 `trainer_profiles` 컬럼을 둔다. 기본값은
켬 — 기존 트레이너는 지금처럼 모든 알림을 받는다.

Revision ID: 0151_trainer_notify_kinds
Revises: 0150_rate_limit_hits
Create Date: 2026-10-06
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0151_trainer_notify_kinds"
down_revision: str | Sequence[str] | None = "0150_rate_limit_hits"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_COLUMNS = ("notify_consultation", "notify_reservation", "notify_member_updates")


def upgrade() -> None:
    # server_default 로 기존 행에도 바로 '켬'이 채워진다 — 그 값이 계약상의 기본값이다.
    for name in _COLUMNS:
        op.add_column(
            "trainer_profiles",
            sa.Column(name, sa.Boolean(), nullable=False, server_default=sa.true()),
        )


def downgrade() -> None:
    for name in reversed(_COLUMNS):
        op.drop_column("trainer_profiles", name)
