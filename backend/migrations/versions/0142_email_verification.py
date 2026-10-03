"""가입 이메일 확인 코드 표 `email_verification_codes`·`users.email_verified_at` 추가. (#3038)

회원·트레이너 가입이 입력한 이메일이 가입하는 사람의 것인지 확인하지 않았다. 계정을
만들기 **전에** 그 주소로 보낸 6자리 코드를 확인한다. 계정이 아직 없으므로 코드는
사용자가 아니라 (이메일, 용도)에 묶는다 — `password_reset_tokens` 처럼 `user_id` 에
걸 수 없다.

- `email_verification_codes`: 코드 원문은 저장하지 않고 서버 비밀값으로 만든 HMAC 만
  담는다(6자리는 경우의 수가 적어 소금 없는 해시는 표가 새면 바로 풀린다). 확인
  실패 횟수(`attempts`)가 상한에 닿으면 그 코드는 더 받지 않는다.
- `users.email_verified_at`: 가입 때 코드로 확인한 시각. 기존 계정은 비어 있다(확인한
  적이 없다). 소셜 자동 연결(#1551)·관리자 지정이 "확인된 이메일"을 판단할 근거다.

기존 행은 그대로다 — 이 마이그레이션만으로 바뀌는 동작은 없다.

Revision ID: 0142_email_verification
Revises: 0140_program_draft_member
Create Date: 2026-10-03
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0142_email_verification"
down_revision: str | Sequence[str] | None = "0140_program_draft_member"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "email_verification_codes",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column("email", sa.String(255), nullable=False),
        sa.Column("purpose", sa.String(32), nullable=False),
        sa.Column("code_hash", sa.String(64), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("attempts", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("used_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
    )
    # 확인은 (이메일, 용도)의 가장 최근 코드를 찾는다.
    op.create_index(
        "ix_email_verification_codes_email_purpose",
        "email_verification_codes",
        ["email", "purpose"],
    )
    op.create_index(
        "ix_email_verification_codes_expires_at",
        "email_verification_codes",
        ["expires_at"],
    )
    op.add_column(
        "users",
        sa.Column("email_verified_at", sa.DateTime(timezone=True), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("users", "email_verified_at")
    op.drop_index(
        "ix_email_verification_codes_expires_at", table_name="email_verification_codes"
    )
    op.drop_index(
        "ix_email_verification_codes_email_purpose",
        table_name="email_verification_codes",
    )
    op.drop_table("email_verification_codes")
