"""기록 그래프 색. (#2076)

포인트 사용처에서 150P 로 여는 그래프 색 표를 만든다. 기본 색(회원앱 파랑)은
누구나 쓰므로 행이 없고, 행이 있는 색만 포인트로 연 색이다. 그중 `selected` 인
행 하나가 지금 기록 그래프을 그리는 색이다.

- 같은 색을 두 번 사지 않는다(`uq_graph_colors_color`).
- 한 회원이 고른 색은 하나뿐이다(partial unique index) — 기본 색으로 되돌리면
  고른 행이 없는 상태다.

교환에 쓴 포인트는 기존 `points_ledger` 에 `spend` 로 남으므로 내역 표는 바꾸지
않는다.

Revision ID: 0080_graph_colors
Revises: 0079_weekly_challenges
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0080_graph_colors"
down_revision: str | Sequence[str] | None = "0079_weekly_challenges"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "graph_colors",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column(
            "user_id",
            sa.String(64),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("color", sa.String(16), nullable=False),
        sa.Column("cost", sa.Integer(), nullable=False),
        sa.Column("client_request_id", sa.String(64), nullable=True),
        sa.Column("acquired_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column(
            "selected", sa.Boolean(), nullable=False, server_default=sa.text("false")
        ),
        sa.CheckConstraint("cost > 0", name="ck_graph_colors_cost"),
        sa.UniqueConstraint("user_id", "color", name="uq_graph_colors_color"),
        sa.UniqueConstraint(
            "user_id", "client_request_id", name="uq_graph_colors_client_request"
        ),
    )
    op.create_index("ix_graph_colors_user_id", "graph_colors", ["user_id"])
    op.create_index(
        "uq_graph_colors_selected",
        "graph_colors",
        ["user_id"],
        unique=True,
        postgresql_where=sa.text("selected"),
    )


def downgrade() -> None:
    op.drop_index("uq_graph_colors_selected", table_name="graph_colors")
    op.drop_index("ix_graph_colors_user_id", table_name="graph_colors")
    op.drop_table("graph_colors")
