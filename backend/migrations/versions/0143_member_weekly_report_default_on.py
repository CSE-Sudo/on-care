"""회원 트레이너 주간 리포트 알림 기본값을 켬으로. (#3025)

트레이너가 보낸 주간 리포트 알림이 기본 꺼짐이라, 설정을 바꾼 적 없는 회원의
알림함에 리포트가 아무 흔적 없이 도착했다. 이 `false` 는 리포트 알림이 없던 시기
앱의 하드코딩 값(#200)을 서버로 옮길 때(#489) 따라온 값으로, 제품상 이유가 없다.

- 컬럼 기본값을 `true` 로 바꾼다. 행이 없는 회원은 서비스 기본값(`DEFAULTS`)을
  따르므로 코드 변경만으로 켜진다.
- **이미 있는 행의 `weekly_report=false` 를 한 번 `true` 로 바꾼다.** 회원이 다른
  스위치 하나만 바꿔도 `update_settings` 가 나머지 칸을 기본값으로 채운 행을
  만들었기 때문에, 저장된 `false` 대부분은 회원이 고른 값이 아니다. 둘을 구별할
  기록이 없어 일괄로 켜고, 스스로 끈 회원은 스위치로 다시 끌 수 있다.

downgrade 는 컬럼 기본값만 되돌린다. 누가 바뀌었는지 구별할 수 없어 값은 되돌리지
않는다.

Revision ID: 0143_member_weekly_report_on
Revises: 0142_email_verification
Create Date: 2026-10-03
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0143_member_weekly_report_on"
down_revision: str | Sequence[str] | None = "0142_email_verification"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.alter_column(
        "member_notification_settings",
        "weekly_report",
        existing_type=sa.Boolean(),
        existing_nullable=False,
        server_default=sa.true(),
    )
    op.execute(
        sa.text(
            "UPDATE member_notification_settings "
            "SET weekly_report = TRUE WHERE weekly_report = FALSE"
        )
    )


def downgrade() -> None:
    op.alter_column(
        "member_notification_settings",
        "weekly_report",
        existing_type=sa.Boolean(),
        existing_nullable=False,
        server_default=sa.false(),
    )
