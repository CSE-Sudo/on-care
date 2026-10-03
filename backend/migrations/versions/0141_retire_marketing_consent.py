"""마케팅 수신 동의 행에 철회 시각 기록. (#3007)

두 앱 가입·재동의 화면의 [선택] 마케팅 알림 수신 동의를 더는 받지 않는다. 보내는
기능도, 거두는 화면도, 처리방침의 이용 목적도 없이 받기만 했다.

이미 남은 `kind='marketing'` 행은 **지우지 않고** 철회 시각만 채운다 — 언제 동의했고
언제 거둬졌는지가 이력으로 남아야 한다. 이미 철회 시각이 있는 행은 건드리지 않는다.

되돌리면 마케팅 행의 철회 시각을 다시 비운다. 지금까지 마케팅 동의를 거두는 경로가
따로 없었으므로, 비어 있던 행은 이 마이그레이션이 채운 것뿐이다.

Revision ID: 0141_retire_marketing_consent
Revises: 0140_program_draft_member
Create Date: 2026-10-03
"""
from __future__ import annotations

from collections.abc import Sequence

from alembic import op

revision: str = "0141_retire_marketing_consent"
down_revision: str | Sequence[str] | None = "0140_program_draft_member"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute(
        "UPDATE user_consents SET revoked_at = now() "
        "WHERE kind = 'marketing' AND revoked_at IS NULL"
    )


def downgrade() -> None:
    op.execute(
        "UPDATE user_consents SET revoked_at = NULL WHERE kind = 'marketing'"
    )
