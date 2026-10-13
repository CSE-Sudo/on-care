"""보낸 리포트·구매 리포트의 내용 스냅샷 컬럼 추가 (#3349)

트레이너가 글로 보낸 리포트와 포인트로 받은 리포트는 수치를 저장하지 않고 회원이 열
때마다 다시 계산했다. 보낸 뒤 회원이 그 주 기록이나 건강 목표를 고치면 같은 리포트가
여는 날에 따라 다른 내용이 됐고, 구매 리포트의 감지 기록은 30일 창을 벗어나면
"감지된 것이 없어요" 로 바뀌었다.

보내거나 사는 시점의 값을 JSON 으로 남긴다. 모두 NULL 허용이다 — 이 컬럼이 생기기
전의 리포트는 소급해 채우지 않고, 읽는 쪽이 NULL 이면 지금처럼 다시 계산한다.

Revision ID: 0154_report_snapshots
Revises: 0153_ai_message_client_request
Create Date: 2026-10-12
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0154_report_snapshots"
down_revision: str | Sequence[str] | None = "0153_ai_message_client_request"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "chat_messages",
        sa.Column("report_snapshot_json", sa.Text(), nullable=True),
    )
    op.add_column(
        "weekly_report_purchases",
        sa.Column("report_snapshot_json", sa.Text(), nullable=True),
    )
    op.add_column(
        "weekly_report_purchases",
        sa.Column("insights_json", sa.Text(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("weekly_report_purchases", "insights_json")
    op.drop_column("weekly_report_purchases", "report_snapshot_json")
    op.drop_column("chat_messages", "report_snapshot_json")
