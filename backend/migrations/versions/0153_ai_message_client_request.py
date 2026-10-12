"""AI 대화 메시지에 전송 멱등키 칸 추가. (#3352)

모델 호출이 실패해 대체 답이 나간 전송은 사용 기록(`ai_chat_usages`)을 남기지 않는다.
응답을 받지 못한 앱이 같은 키로 다시 보내면 재생할 근거가 없어 질문과 답이 한 쌍 더
저장됐다. 앱도 저장된 대화에 키가 없어, 방금 보낸 말과 저장분을 본문과 기기 시각으로
추측해 맞췄다.

- `client_request_id`: 그 줄을 만든 전송의 멱등키. 한 번의 전송이 남긴 질문과 답이
  같은 값을 갖는다. 키 없이 보냈거나 기존 줄은 NULL 이다.
- 재전송을 이 값으로 찾으므로 인덱스를 둔다.

기존 행은 NULL 이라 이 마이그레이션만으로 바뀌는 동작은 없다.

Revision ID: 0153_ai_message_client_request
Revises: 0151_trainer_notify_kinds
Create Date: 2026-10-12
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0153_ai_message_client_request"
down_revision: str | Sequence[str] | None = "0151_trainer_notify_kinds"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "ai_messages",
        sa.Column("client_request_id", sa.String(length=64), nullable=True),
    )
    op.create_index(
        "ix_ai_messages_client_request_id",
        "ai_messages",
        ["client_request_id"],
    )


def downgrade() -> None:
    op.drop_index("ix_ai_messages_client_request_id", table_name="ai_messages")
    op.drop_column("ai_messages", "client_request_id")
