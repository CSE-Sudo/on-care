"""감사 로그에 대상 회원·자원 칸 추가. (#2830)

트레이너의 회원 건강정보 열람, 데이터 공유 동의 발급·철회, 탈퇴는 감사 기록이
없었다. 누가(`user_id`) **누구의**(`target_user_id`) **무엇을**(`resource`) 봤는지
남기려면 대상과 자원 칸이 필요하다. 대상 회원별 이력 조회와 보존 기간 정리를 위해
`(target_user_id, created_at)`·`created_at` 인덱스를 둔다. 기존 행은 대상이 비고
자원이 빈 문자열이다 — 이 마이그레이션만으로 바뀌는 동작은 없다.

Revision ID: 0125_audit_log_target
Revises: 0110_user_token_version
Create Date: 2026-10-01
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0125_audit_log_target"
down_revision: str | Sequence[str] | None = "0110_user_token_version"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "audit_logs",
        sa.Column("target_user_id", sa.String(length=64), nullable=True),
    )
    op.add_column(
        "audit_logs",
        sa.Column(
            "resource", sa.String(length=30), nullable=False, server_default=""
        ),
    )
    op.create_index(
        "ix_audit_logs_target_created",
        "audit_logs",
        ["target_user_id", "created_at"],
    )
    op.create_index("ix_audit_logs_created_at", "audit_logs", ["created_at"])


def downgrade() -> None:
    op.drop_index("ix_audit_logs_created_at", table_name="audit_logs")
    op.drop_index("ix_audit_logs_target_created", table_name="audit_logs")
    op.drop_column("audit_logs", "resource")
    op.drop_column("audit_logs", "target_user_id")
