"""추천 개인운동을 매일 새로 체크하는 목록으로. (#2161)

- `exercise_sessions.assigned_routine_id` 의 유일 제약을 `(배정, 그날)` 로 바꾼다.
  같은 배정을 날마다 한 번씩 완료할 수 있어야 한다.
- `trainer_routines` 에 목록에 걸린 기간(`active_from`, `ended_on`)을 둔다. 철회는
  행을 지우지 않고 `ended_on` 을 찍는다 — 지난 날짜에 걸려 있던 목록을 되살린다.

기존 행 채우기:
- `active_from` = 승인한 날(AI 제안) 또는 만든 날, KST.
- 담당 없는 회원의 하루치 AI 추천(`client_request_id = 'auto-YYYY-MM-DD'`)은 그날
  하루만 걸려 있던 것이므로 `ended_on` = 다음 날.

Revision ID: 0088_daily_routine_completion
Revises: 0087_points_coupons_zero_cost
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0088_daily_routine_completion"
down_revision: str | Sequence[str] | None = "0087_points_coupons_zero_cost"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.drop_index(
        "ix_exercise_sessions_assigned_routine_id", table_name="exercise_sessions"
    )
    op.create_index(
        "ix_exercise_sessions_assigned_routine_id",
        "exercise_sessions", ["assigned_routine_id"], unique=False,
    )
    op.create_unique_constraint(
        "uq_exercise_sessions_routine_day",
        "exercise_sessions",
        ["assigned_routine_id", "week_start", "day_label"],
    )

    op.add_column(
        "trainer_routines",
        sa.Column("active_from", sa.String(length=10), nullable=True),
    )
    op.add_column(
        "trainer_routines",
        sa.Column("ended_on", sa.String(length=10), nullable=True),
    )
    op.execute(
        """
        UPDATE trainer_routines
           SET active_from = to_char(
                   COALESCE(reviewed_at, created_at, now()) AT TIME ZONE 'Asia/Seoul',
                   'YYYY-MM-DD'
               )
        """
    )
    op.execute(
        """
        UPDATE trainer_routines
           SET active_from = substr(client_request_id, 6, 10),
               ended_on = to_char(
                   to_date(substr(client_request_id, 6, 10), 'YYYY-MM-DD')
                   + 1,
                   'YYYY-MM-DD'
               )
         WHERE trainer_id IS NULL
           AND client_request_id ~ '^auto-[0-9]{4}-[0-9]{2}-[0-9]{2}$'
        """
    )
    op.alter_column("trainer_routines", "active_from", nullable=False)
    op.create_check_constraint(
        "ck_trainer_routines_active_window",
        "trainer_routines",
        "ended_on IS NULL OR ended_on >= active_from",
    )


def downgrade() -> None:
    op.drop_constraint(
        "ck_trainer_routines_active_window", "trainer_routines", type_="check"
    )
    # 내려온 배정은 예전 모델에 자리가 없다 — 그때처럼 행째 지운다.
    op.execute("DELETE FROM trainer_routines WHERE ended_on IS NOT NULL "
               "AND trainer_id IS NOT NULL")
    op.drop_column("trainer_routines", "ended_on")
    op.drop_column("trainer_routines", "active_from")

    op.drop_constraint(
        "uq_exercise_sessions_routine_day", "exercise_sessions", type_="unique"
    )
    # 하루 한 번 완료가 쌓인 배정은 예전의 "배정당 한 번" 으로 돌아갈 수 없다.
    # 가장 이른 완료만 배정에 묶어 두고, 나머지는 운동 기록으로만 남긴다.
    op.execute(
        """
        UPDATE exercise_sessions s
           SET assigned_routine_id = NULL
         WHERE s.assigned_routine_id IS NOT NULL
           AND EXISTS (
               SELECT 1 FROM exercise_sessions o
                WHERE o.assigned_routine_id = s.assigned_routine_id
                  AND (COALESCE(o.completed_at, o.created_at), o.id)
                    < (COALESCE(s.completed_at, s.created_at), s.id)
           )
        """
    )
    op.drop_index(
        "ix_exercise_sessions_assigned_routine_id", table_name="exercise_sessions"
    )
    op.create_index(
        "ix_exercise_sessions_assigned_routine_id",
        "exercise_sessions", ["assigned_routine_id"], unique=True,
    )
