"""프로그램 초안에 회원과 작성 상태 칸 추가. (#2873)

트레이너 웹 코칭 화면이 작성 중인 내용을 회원별로 자동 보관하고, 새로 고침 뒤
`이어서 쓰기` 로 되살린다. 기존 초안 표(#708)는 회원 없는 초안을 전제로 해, 어느
회원에게 짜던 것인지와 위저드 단계·후보 같은 편집기 밖의 작성 상태를 담을 칸이
없었다.

- `member_id`: 자동 보관한 회원. 비어 있으면 지금까지의 회원 없는 초안이다.
  회원이 탈퇴하면 함께 지운다. 회원별로 찾으므로 인덱스를 둔다.
- `workspace_json`: 편집기 밖의 작성 상태를 담는 객체. 기존 행은 빈 객체다.

기존 행은 그대로다 — 이 마이그레이션만으로 바뀌는 동작은 없다.

Revision ID: 0140_program_draft_member
Revises: 0136_user_consents
Create Date: 2026-10-02
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0140_program_draft_member"
down_revision: str | Sequence[str] | None = "0136_user_consents"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "trainer_program_drafts",
        sa.Column(
            "member_id",
            sa.String(length=64),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=True,
        ),
    )
    op.add_column(
        "trainer_program_drafts",
        sa.Column(
            "workspace_json", sa.Text(), nullable=False, server_default="{}"
        ),
    )
    op.create_index(
        "ix_trainer_program_drafts_member_id",
        "trainer_program_drafts",
        ["member_id"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(
        "ix_trainer_program_drafts_member_id",
        table_name="trainer_program_drafts",
    )
    op.drop_column("trainer_program_drafts", "workspace_json")
    op.drop_column("trainer_program_drafts", "member_id")
