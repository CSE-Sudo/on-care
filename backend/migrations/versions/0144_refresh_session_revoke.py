"""refresh 토큰 재사용 감지 때 세션 전체를 끊을 자리. (#3086)

재사용 감지(#966)는 다시 온 토큰 한 장만 거부해, 탈취한 쪽이 먼저 회전해 받은 다음
토큰들은 그대로 살았다. refresh 토큰에 로그인 세션 이름(`sid`)을 싣고, 탈취로 판단한
세션을 여기에 적어 그 세션의 토큰을 모두 거부한다.

- `revoked_sessions`: 끊긴 세션. `expires_at`(세션 절대 수명 끝)이 지나면 정리한다.
- `revoked_refresh_tokens.reason`: 폐기 사유(`rotated`·`logout`·`stale`). 회전된 지
  얼마 안 된 토큰의 재사용(동시 갱신)과 탈취를 가른다. 기존 행은 비어 있다.

기존 토큰·행은 그대로다 — 이 마이그레이션만으로 끊기는 세션은 없다.

Revision ID: 0144_refresh_session_revoke
Revises: 0143_member_weekly_report_on
Create Date: 2026-10-04
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0144_refresh_session_revoke"
down_revision: str | Sequence[str] | None = "0143_member_weekly_report_on"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "revoked_refresh_tokens",
        sa.Column("reason", sa.String(length=16), nullable=True),
    )
    op.create_table(
        "revoked_sessions",
        sa.Column("sid", sa.String(64), primary_key=True),
        sa.Column(
            "user_id",
            sa.String(64),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column(
            "revoked_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
    )
    op.create_index(
        "ix_revoked_sessions_user_id", "revoked_sessions", ["user_id"]
    )
    # 정리(purge)는 만료 시각으로 훑는다.
    op.create_index(
        "ix_revoked_sessions_expires_at", "revoked_sessions", ["expires_at"]
    )


def downgrade() -> None:
    op.drop_index("ix_revoked_sessions_expires_at", table_name="revoked_sessions")
    op.drop_index("ix_revoked_sessions_user_id", table_name="revoked_sessions")
    op.drop_table("revoked_sessions")
    op.drop_column("revoked_refresh_tokens", "reason")
