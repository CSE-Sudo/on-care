"""트레이너 AI 코칭 스레드 삭제. (#3085)

트레이너가 담당 회원에 대해 AI 에게 묻던 `/trainer/clients/{id}/ai-coach`(#588)를
지웠다. 그 문답은 `ai_conversations(user_id=회원, trainer_id=트레이너)` 에 남아 있는데,
API 가 없어지면 다시 읽을 길이 없는 회원 건강 대화라 남길 이유가 없다. 회원 대화
보관 기간(30일) 정리 대상에서도 빠져 있어 지우지 않으면 무기한 남는다.

`trainer_id` 가 있는 스레드만 지운다. 메시지(`ai_messages`)는 FK `ON DELETE CASCADE`
지만 SQLite 등에서 FK 가 꺼져 있어도 남지 않게 먼저 지운다. 회원 본인 대화
(`trainer_id IS NULL`)는 그대로다. `trainer_id` 칼럼은 이번에 지우지 않는다.

되돌릴 수 없다 — downgrade 는 아무것도 하지 않는다.

Revision ID: 0144_drop_trainer_ai_threads
Revises: 0142_email_verification
Create Date: 2026-10-04
"""
from __future__ import annotations

from collections.abc import Sequence

from alembic import op

revision: str = "0144_drop_trainer_ai_threads"
down_revision: str | Sequence[str] | None = "0142_email_verification"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def purge() -> None:
    op.execute(
        "DELETE FROM ai_messages WHERE conversation_id IN "
        "(SELECT id FROM ai_conversations WHERE trainer_id IS NOT NULL)"
    )
    op.execute("DELETE FROM ai_conversations WHERE trainer_id IS NOT NULL")


def upgrade() -> None:
    purge()


def downgrade() -> None:
    # 지운 대화는 되살릴 수 없다.
    pass
