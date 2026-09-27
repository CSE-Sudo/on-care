"""알림 문장 틀 코드와 인자. (#2302)

알림은 만든 순간의 한국어 문장(`title`·`body`)만 저장해, 영어 화면에서도 한국어로
보였다. 문장 틀 코드(`template`)와 인자(`template_args`)를 함께 남겨 읽는 쪽이 자기
언어로 다시 조립하게 한다.

둘 다 비워 둘 수 있다 — 이미 쌓인 알림에는 틀이 없고, 그 알림은 저장된 문장을 그대로
보여 준다. 백필하지 않는 이유는 옛 문장에서 인자를 거꾸로 뽑아낼 규칙이 없어서다.

Revision ID: 0096_notification_templates
Revises: 0095_notification_target_date
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0096_notification_templates"
down_revision: str | Sequence[str] | None = "0095_notification_target_date"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "notifications",
        sa.Column("template", sa.String(length=40), nullable=True),
    )
    op.add_column(
        "notifications",
        sa.Column("template_args", sa.JSON(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("notifications", "template_args")
    op.drop_column("notifications", "template")
