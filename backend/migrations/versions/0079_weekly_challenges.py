"""주간 운동 챌린지 참가 기록. (#1789)

포인트를 걸고 한 주(KST 월~일) 운동 목표를 채우면 더 돌려받는 챌린지다.

- `weekly_challenges` — 회원이 참가한 주 하나당 한 줄. 참가는 한 주에 한 번이라
  `(user_id, week_start)` 유니크다. 목표(`goal`)는 참가할 때의 주간 운동 횟수 목표로
  고정하고, 건 포인트(`stake`)·보상(`reward`)도 참가 시점 값을 남긴다.
- 상태는 active(진행 중)|succeeded|failed. 스케줄러가 없어 주가 끝난 뒤 회원이
  챌린지·사용처·포인트·알림을 읽을 때 판정한다. 판정 때 센 운동한 날 수를
  `final_days` 에 남긴다 — 판정 뒤 지난 주 기록이 바뀌어도 결과 화면은 그대로다.
- 포인트 움직임은 `points_ledger` 에 남는다 — 참가 `spend`(`challenge_stake`), 성공
  `earn`(`challenge_reward`). 내역 표의 종류·부호 제약은 그대로라 바꿀 것이 없다.

되돌리면 표만 지운다. 내역의 챌린지 행은 잔액과 맞춰 두려고 남긴다.

Revision ID: 0079_weekly_challenges
Revises: 0078_streak_shields
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0079_weekly_challenges"
down_revision: str | Sequence[str] | None = "0078_streak_shields"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "weekly_challenges",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column(
            "user_id",
            sa.String(64),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("week_start", sa.String(10), nullable=False),
        sa.Column("goal", sa.Integer(), nullable=False),
        sa.Column("stake", sa.Integer(), nullable=False),
        sa.Column("reward", sa.Integer(), nullable=False),
        sa.Column(
            "status", sa.String(12), nullable=False, server_default="active"
        ),
        sa.Column("final_days", sa.Integer(), nullable=True),
        sa.Column("client_request_id", sa.String(64), nullable=True),
        sa.Column("joined_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("settled_at", sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint(
            "status IN ('active', 'succeeded', 'failed')",
            name="ck_weekly_challenges_status",
        ),
        sa.CheckConstraint(
            "goal BETWEEN 1 AND 7", name="ck_weekly_challenges_goal"
        ),
        sa.CheckConstraint("stake > 0", name="ck_weekly_challenges_stake"),
        sa.CheckConstraint("reward > 0", name="ck_weekly_challenges_reward"),
        sa.UniqueConstraint(
            "user_id", "week_start", name="uq_weekly_challenges_user_week"
        ),
        sa.UniqueConstraint(
            "user_id",
            "client_request_id",
            name="uq_weekly_challenges_client_request",
        ),
    )
    op.create_index(
        "ix_weekly_challenges_user_id", "weekly_challenges", ["user_id"]
    )
    op.create_index(
        "ix_weekly_challenges_user_status",
        "weekly_challenges",
        ["user_id", "status"],
    )


def downgrade() -> None:
    op.drop_index("ix_weekly_challenges_user_status", table_name="weekly_challenges")
    op.drop_index("ix_weekly_challenges_user_id", table_name="weekly_challenges")
    op.drop_table("weekly_challenges")
