"""알림별 목적지 칸 `notifications.action_target` 추가. (#2690)

회원 알림의 목적지는 갈래별 표(`api/v1/notifications.py` 의 `_ACTION_BY_CATEGORY`)로만
정해져, 같은 리마인더인 나트륨 경고와 운동 목표 알림이 모두 홈으로 갔다. 회원 앱
데모는 알림마다 목적지가 달라(식단·운동) 실서버가 데모를 따르도록 알림 한 건에
목적지를 둘 수 있게 한다. 비어 있으면 지금처럼 갈래별 표를 쓴다.

Revision ID: 0109_notification_action_target
Revises: 0108_drop_member_note
Create Date: 2026-10-01
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0109_notification_action_target"
down_revision: str | Sequence[str] | None = "0108_drop_member_note"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "notifications",
        sa.Column("action_target", sa.String(length=20), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("notifications", "action_target")
