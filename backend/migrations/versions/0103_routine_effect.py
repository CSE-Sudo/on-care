"""추천 개인운동에 회원에게 보일 효과 한 줄을 둔다. (#2570)

회원 앱 추천 개인운동 카드의 이름 아래 줄이다. 지금까지는 `reason` 한 칸이
AI 추천 사유(트레이너 판단 재료)·운동 이름 나열·트레이너 입력을 겸해, 회원이
읽을 효과를 더 얹으면 뜻이 섞였다. 트레이너가 비워 보내면 서버가 운동 유형 ×
회원 건강 목표 문구표로 채운다. 이 칸이 생기기 전의 배정은 비어 있고, 그때
회원 앱은 예전처럼 `reason` 으로 떨어진다.

Revision ID: 0103_routine_effect
Revises: 0102_clear_reservation_note
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0103_routine_effect"
down_revision: str | Sequence[str] | None = "0102_clear_reservation_note"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "trainer_routines",
        sa.Column(
            "effect", sa.String(length=40), nullable=False, server_default=""
        ),
    )


def downgrade() -> None:
    op.drop_column("trainer_routines", "effect")
