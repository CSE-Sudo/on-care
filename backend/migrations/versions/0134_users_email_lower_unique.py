"""사용자 이메일 소문자 정규화와 대소문자 무시 유니크 인덱스. (#2816)

가입·로그인은 이메일을 대소문자 그대로 비교하고, 관리자 승격(`ADMIN_EMAILS`)은
대소문자를 무시했다. 그래서 `Admin@…` 처럼 대소문자만 바꾼 주소로 가입하면 다음
기동 때 관리자로 승격될 수 있었다. 이제 앱은 이메일을 소문자로 저장·비교하고,
여기서 기존 행을 소문자로 바꾼 뒤 `lower(email)` 유니크 인덱스로 DB 가 막는다.

**대소문자만 다른 중복이 이미 있으면 멈춘다.** 어느 계정을 남길지는 사람이
정해야 한다 — 자동으로 합치거나 지우면 남의 기록이 섞이거나 사라진다. 실패
메시지에 겹치는 이메일과 계정 id 를 적으므로, 정리한 뒤 다시 올리면 된다.

Revision ID: 0134_users_email_lower_unique
Revises: 0138_schema_model_alignment
Create Date: 2026-10-01
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0134_users_email_lower_unique"
down_revision: str | Sequence[str] | None = "0138_schema_model_alignment"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

INDEX_NAME = "uq_users_email_lower"


class CaseDuplicateEmails(RuntimeError):
    """대소문자만 다른 이메일이 둘 이상의 계정에 있다 — 사람이 정리해야 한다."""


def find_case_duplicates(conn: sa.engine.Connection) -> list[tuple[str, list[str]]]:
    """`lower(email)` 이 같은 계정 묶음. [(소문자 이메일, [계정 id…])]."""
    rows = conn.execute(
        sa.text(
            "SELECT lower(email) AS e, array_agg(id ORDER BY id) AS ids "
            "FROM users GROUP BY lower(email) HAVING count(*) > 1 ORDER BY 1"
        )
    ).all()
    return [(row.e, list(row.ids)) for row in rows]


def describe_duplicates(groups: list[tuple[str, list[str]]]) -> str:
    lines = [f"  {email}: {', '.join(ids)}" for email, ids in groups]
    return (
        "대소문자만 다른 이메일을 쓰는 계정이 있어 마이그레이션을 멈춥니다. "
        "남길 계정을 정해 나머지의 이메일을 바꾸거나 정리한 뒤 다시 실행하세요.\n"
        + "\n".join(lines)
    )


def lowercase_emails(conn: sa.engine.Connection) -> int:
    """대문자가 섞인 이메일을 소문자로 바꾼다. 바꾼 행 수."""
    result = conn.execute(
        sa.text("UPDATE users SET email = lower(email) WHERE email <> lower(email)")
    )
    return result.rowcount or 0


def upgrade() -> None:
    conn = op.get_bind()
    groups = find_case_duplicates(conn)
    if groups:
        raise CaseDuplicateEmails(describe_duplicates(groups))
    lowercase_emails(conn)
    op.execute(
        f"CREATE UNIQUE INDEX IF NOT EXISTS {INDEX_NAME} ON users (lower(email))"
    )


def downgrade() -> None:
    # 소문자로 바꾼 이메일은 되돌릴 원래 표기가 남아 있지 않다. 인덱스만 걷는다.
    op.execute(f"DROP INDEX IF EXISTS {INDEX_NAME}")
