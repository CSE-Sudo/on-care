"""가입 동의 기록 표 `user_consents` 추가. (#2819)

두 앱의 가입 흐름에 동의 절차가 없어, 어느 계정이 어느 문서 버전에 언제 동의했는지
남는 곳이 없었다. 항목(약관·개인정보·건강정보·만 14세·마케팅)마다 한 행을 둔다.

기존 계정에는 행을 만들지 않는다 — 건강정보는 명시 동의가 필요해 일괄로 채울 수
없다. 행이 없는 계정은 `GET /users/me` 가 `consent_required: true` 로 알리고, 앱이
다음 로그인 때 동의 화면을 띄운다.

Revision ID: 0136_user_consents
Revises: 0138_schema_model_alignment
Create Date: 2026-10-01
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0136_user_consents"
down_revision: str | Sequence[str] | None = "0138_schema_model_alignment"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "user_consents",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "user_id",
            sa.String(length=64),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("kind", sa.String(length=20), nullable=False),
        sa.Column("version", sa.String(length=20), nullable=False),
        sa.Column("agreed_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.UniqueConstraint(
            "user_id", "kind", "version", name="uq_user_consents_user_kind_version"
        ),
    )
    op.create_index("ix_user_consents_user_id", "user_consents", ["user_id"])


def downgrade() -> None:
    op.drop_index("ix_user_consents_user_id", table_name="user_consents")
    op.drop_table("user_consents")
