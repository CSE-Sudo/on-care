"""건강상태·주의사항을 마지막으로 바꾼 사람·시각 `health_profiles.notes_changed_*`. (#2942)

건강상태·주의사항은 회원과 담당 트레이너가 같은 글을 함께 고친다(#2619). 목표 칩의
`focus_changed_*`(#1832)처럼 누가 언제 바꿨는지 남겨 두 앱이 글 아래에 보여 준다.
목표 칩 기록과 따로 두어, 칩 아래 `마지막 변경` 줄이 주의사항만 고친 저장에
움직이지 않게 한다. 예전 행은 비어 있어 줄을 그리지 않는다.

Revision ID: 0131_health_notes_changed
Revises: 0130_chat_routine_delivery
Create Date: 2026-10-02
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0131_health_notes_changed"
down_revision: str | Sequence[str] | None = "0130_chat_routine_delivery"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "health_profiles",
        sa.Column("notes_changed_by", sa.String(length=10), nullable=True),
    )
    op.add_column(
        "health_profiles",
        sa.Column("notes_changed_by_id", sa.String(length=64), nullable=True),
    )
    op.add_column(
        "health_profiles",
        sa.Column("notes_changed_at", sa.DateTime(timezone=True), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("health_profiles", "notes_changed_at")
    op.drop_column("health_profiles", "notes_changed_by_id")
    op.drop_column("health_profiles", "notes_changed_by")
