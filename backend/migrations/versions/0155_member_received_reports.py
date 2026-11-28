"""회원 쪽 리포트 수신 기록 표 추가 (#3348)

회원이 리포트를 "받았다"는 근거가 대화 메시지(`chat_messages.report_week_start`)
뿐이었다. 그 행은 보낸 트레이너에게도 달려 있어(`trainer_id` CASCADE) 트레이너가
탈퇴하면 대화와 함께 사라지고, 회원이 받은 주가 닫혔다. 받은 리포트 목록도 대화를
읽어 만들어, 담당이 끊기면 통째로 비었다.

회원에게만 달린 수신 기록을 따로 둔다. `id` 는 그 전송의 메시지 id 와 같고(대화가
지워져도 남아야 해 FK 는 걸지 않는다), `trainer_id` 는 SET NULL 이다.

이미 나간 리포트는 지금 남아 있는 대화 메시지에서 옮겨 적는다. 보낸 트레이너가
이미 탈퇴해 대화가 사라진 전송은 되살릴 근거가 없다.

Revision ID: 0155_member_received_reports
Revises: 0154_report_snapshots
Create Date: 2026-10-13
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0155_member_received_reports"
down_revision: str | Sequence[str] | None = "0154_report_snapshots"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "member_received_reports",
        sa.Column("id", sa.String(length=64), primary_key=True),
        sa.Column(
            "member_id",
            sa.String(length=64),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "trainer_id",
            sa.String(length=64),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("week_start", sa.String(length=10), nullable=False),
        sa.Column("body", sa.Text(), nullable=False, server_default=""),
        sa.Column("report_snapshot_json", sa.Text(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )
    op.create_index(
        "ix_member_received_reports_member_id",
        "member_received_reports",
        ["member_id"],
    )
    op.create_index(
        "ix_member_received_reports_member_week",
        "member_received_reports",
        ["member_id", "week_start"],
    )
    op.execute(
        """
        INSERT INTO member_received_reports
            (id, member_id, trainer_id, week_start, body,
             report_snapshot_json, created_at)
        SELECT id, member_id, trainer_id, report_week_start, body,
               report_snapshot_json, created_at
        FROM chat_messages
        WHERE sender = 'trainer' AND report_week_start IS NOT NULL
        """
    )


def downgrade() -> None:
    op.drop_index(
        "ix_member_received_reports_member_week",
        table_name="member_received_reports",
    )
    op.drop_index(
        "ix_member_received_reports_member_id",
        table_name="member_received_reports",
    )
    op.drop_table("member_received_reports")
