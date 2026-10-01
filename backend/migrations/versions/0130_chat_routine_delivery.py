"""루틴 전송 안내 칸 `chat_messages.routine_delivery_json` 추가. (#2672)

트레이너가 회원에게 운동을 보내면(개인운동만·PT 프로그램·취소 뒤 개인운동·단건
배정·AI 제안 승인) 알림만 가고 채팅에는 남지 않았다. 주간 리포트처럼 채팅
가운데에 전송 안내 카드를 남기려고, 그 메시지가 어떤 전송인지(종류·운동 이름)를
JSON 으로 담는다. 일반 대화는 비어 있어 예전 행과 조회 흐름은 그대로다.

Revision ID: 0130_chat_routine_delivery
Revises: 0129_trainer_memo_category
Create Date: 2026-10-01
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0130_chat_routine_delivery"
down_revision: str | Sequence[str] | None = "0129_trainer_memo_category"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "chat_messages",
        sa.Column("routine_delivery_json", sa.Text(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("chat_messages", "routine_delivery_json")
