"""참조표 시드 데이터의 지문. (#2100)

`food_nutrients` 는 표가 비었을 때만 시드해서, 시드 데이터(큐레이션 값·공공 표준
집계본)를 고쳐도 이미 떠 있는 DB 에는 닿지 않았다. #2096 은 그 차이를 데이터
마이그레이션(0075)으로 메웠지만, 공공 표준 집계를 다시 만들면 1천 행 넘게 바뀌고
앞으로도 고칠 때마다 마이그레이션을 새로 써야 한다.

그래서 시드 데이터로 만든 지문을 이 표에 적어 두고, 앱이 기동할 때 다르면 그
참조표를 새 시드로 통째로 바꾼다(`init_db._seed_food_nutrients`). 참조표는 읽기
전용이고 다른 표가 참조하지 않아 통째로 바꿔도 회원 기록에 영향이 없다.

이 표가 비어 있는 채로 처음 기동하면(이 마이그레이션 직후) 지문이 없으므로 한 번
다시 시드한다 — 이미 떠 있는 DB 가 새 값을 받는 경로다.

Revision ID: 0076_reference_data_versions
Revises: 0075_food_nutrient_macros
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0076_reference_data_versions"
down_revision: str | Sequence[str] | None = "0075_food_nutrient_macros"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "reference_data_versions",
        sa.Column("name", sa.String(50), primary_key=True),
        sa.Column("fingerprint", sa.String(64), nullable=False),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
    )


def downgrade() -> None:
    op.drop_table("reference_data_versions")
