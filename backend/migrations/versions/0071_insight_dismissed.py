"""AI 코치 감지 기록의 제외 표시. (#1975)

잘못 감지된 줄을 회원이 기록에서 치울 수 있게 한다. 감지는 저장하지 않고 대화에서
매번 계산하므로(`coach/insights.py`) 지울 대상이 따로 없다 — 대신 **그 줄의 감지를
더 보지 않겠다**는 표시를 메시지에 남긴다.

메시지 자체는 지우지 않는다. 회원이 쓴 말은 대화에 그대로 남고, AI 가 맥락으로
읽는 것도 그대로다. 빠지는 것은 감지 기록 한 줄뿐이다.

Revision ID: 0071_insight_dismissed
Revises: 0070_diet_entry_ai_comment
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0071_insight_dismissed"
down_revision: str | Sequence[str] | None = "0070_diet_entry_ai_comment"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "ai_messages",
        sa.Column(
            "insight_dismissed",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("false"),
        ),
    )


def downgrade() -> None:
    op.drop_column("ai_messages", "insight_dismissed")
