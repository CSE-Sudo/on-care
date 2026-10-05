"""시도 제한 기록을 DB 에서 센다 — 분당 한도·로그인 잠금 공유 저장소. (#3143)

분당 한도·로그인 실패 잠금·가입 한도가 프로세스 메모리에 있어 운영 백엔드가 태스크
1개·워커 1개로 묶여 있었고, 재배포·재시작 때마다 잠금이 풀렸다. 시도 한 번을 한 행으로
남기고 모든 태스크가 이 표를 본다(`app/core/rate_limit.py` 의 `DatabaseRateLimiter`).

새 표만 만든다 — 어떤 저장소를 쓸지는 설정(`RATE_LIMIT_STORE`)이 정한다.

Revision ID: 0150_rate_limit_hits
Revises: 0149_pt_program_off_daily_list
Create Date: 2026-10-05
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0150_rate_limit_hits"
down_revision: str | Sequence[str] | None = "0149_pt_program_off_daily_list"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "rate_limit_hits",
        sa.Column("id", sa.BigInteger(), primary_key=True, autoincrement=True),
        sa.Column("key", sa.Text(), nullable=False),
        sa.Column("hit_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
    )
    # 한도 판정: 한 키의 창 안 행 수와 가장 오래된 기록.
    op.create_index(
        "ix_rate_limit_hits_key_hit_at",
        "rate_limit_hits",
        ["key", "hit_at"],
        unique=False,
    )
    # 만료 행 정리.
    op.create_index(
        "ix_rate_limit_hits_expires_at",
        "rate_limit_hits",
        ["expires_at"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("ix_rate_limit_hits_expires_at", table_name="rate_limit_hits")
    op.drop_index("ix_rate_limit_hits_key_hit_at", table_name="rate_limit_hits")
    op.drop_table("rate_limit_hits")
