"""담당 링크의 데이터 공유 동의 철회 시각. (#1631)

담당을 끊어도 `trainer_clients.data_consent_at` 이 그대로 남아, 나중에 같은
트레이너와 다시 연결되면 새 동의 없이 옛 동의가 되살아났다. 철회했다는 사실도
어디에도 남지 않았다.

담당 해제를 동의 철회로 보고 `data_consent_revoked_at` 을 둔다. 해제할 때
`data_consent_at` 을 비우고 이 칸에 시각을 적는다.

이미 해제된 링크(`active = false`)도 같은 상태로 맞춘다 — 그대로 두면 이
기능 이전에 끊긴 링크만 옛 동의가 되살아난다. 실제 해제 시각은 남아 있지 않으므로
마이그레이션 시각을 적는다.

downgrade 는 컬럼만 지운다. 비운 동의 시각은 되돌릴 수 없다 — 철회된 동의를
되살리는 것이 이 변경이 막으려던 일이기도 하다.

Revision ID: 0097_data_consent_revocation
Revises: 0096_notification_templates
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0097_data_consent_revocation"
down_revision: str | Sequence[str] | None = "0096_notification_templates"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "trainer_clients",
        sa.Column(
            "data_consent_revoked_at", sa.DateTime(timezone=True), nullable=True
        ),
    )
    op.execute(
        sa.text(
            "UPDATE trainer_clients "
            "SET data_consent_at = NULL, data_consent_revoked_at = now() "
            "WHERE active = false"
        )
    )


def downgrade() -> None:
    op.drop_column("trainer_clients", "data_consent_revoked_at")
