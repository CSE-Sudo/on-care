"""트레이너 가입 초대 코드 제거

초대 코드(0024)는 헬스장이 발급한 코드로 소속을 정해 트레이너를 가입시키려던
장치였지만, 발급 경로가 끝내 없어 운영에서 새 트레이너를 받을 수 없었다(#1627).
소속은 가입 뒤 트레이너가 헬스장을 찾아 직접 고르기로 하고(`PUT /trainer/me/gym`),
코드 테이블을 걷어 낸다.

downgrade 는 빈 테이블만 되살린다 — 지운 코드 행은 돌아오지 않는다.

Revision ID: 0101_drop_trainer_invite_codes
Revises: 0100_routine_duration_seconds
Create Date: 2026-09-29
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0101_drop_trainer_invite_codes"
down_revision: str | Sequence[str] | None = "0100_routine_duration_seconds"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.drop_index(
        "ix_trainer_invite_codes_gym_id", table_name="trainer_invite_codes"
    )
    op.drop_table("trainer_invite_codes")


def downgrade() -> None:
    op.create_table(
        "trainer_invite_codes",
        sa.Column("code", sa.String(length=32), nullable=False),
        sa.Column("gym_id", sa.String(length=64), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("used_by", sa.String(length=64), nullable=True),
        sa.Column("used_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["gym_id"], ["places.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["used_by"], ["users.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("code"),
    )
    op.create_index(
        "ix_trainer_invite_codes_gym_id", "trainer_invite_codes", ["gym_id"]
    )
