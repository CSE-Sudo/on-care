"""사용자 토큰 세대 칸 `users.token_version` 추가. (#2766)

트레이너가 비밀번호를 바꿔도 다른 기기에 이미 나간 토큰은 그대로 살아 있었다.
refresh 폐기 표(`revoked_refresh_tokens`)는 `jti` 한 장씩만 끊어 다른 기기의 토큰을
모른다. 토큰마다 발급 당시 세대를 싣고 검증 때 이 칸과 비교해, 비밀번호 변경이
세대를 올리면 그 전 토큰이 한꺼번에 무효가 되게 한다. 기존 행은 0세대이고 세대
클레임이 없는 기존 토큰도 0세대로 보므로, 이 마이그레이션만으로 끊기는 세션은 없다.

Revision ID: 0110_user_token_version
Revises: 0109_notification_action_target
Create Date: 2026-10-01
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0110_user_token_version"
down_revision: str | Sequence[str] | None = "0109_notification_action_target"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column(
            "token_version",
            sa.Integer(),
            nullable=False,
            server_default="0",
        ),
    )


def downgrade() -> None:
    op.drop_column("users", "token_version")
