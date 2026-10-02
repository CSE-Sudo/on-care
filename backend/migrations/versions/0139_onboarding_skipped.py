"""첫 설정 건너뛰기 칸 `health_profiles.onboarding_skipped` 추가. (#2855)

첫 설정 화면의 `건너뛰기` 는 어디에도 남지 않아, 건너뛴 회원이 로그인·세션
복구 때마다 같은 폼으로 다시 끌려갔다. 건너뛴 사실을 계정에 남겨 기기를 바꿔도
다시 묻지 않게 한다. 기존 행은 거짓이라 지금 판단(`onboarded`)은 그대로다.

Revision ID: 0139_onboarding_skipped
Revises: 0131_health_notes_changed
Create Date: 2026-10-01
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0139_onboarding_skipped"
down_revision: str | Sequence[str] | None = "0131_health_notes_changed"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "health_profiles",
        sa.Column(
            "onboarding_skipped",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("false"),
        ),
    )


def downgrade() -> None:
    op.drop_column("health_profiles", "onboarding_skipped")
