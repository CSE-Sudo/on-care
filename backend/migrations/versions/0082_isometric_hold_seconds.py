"""등척성 홀드의 버티는 시간(초)과 운동 기록의 초. (#1969, #2071)

플랭크·행잉처럼 **버티는** 운동은 한 세트를 몇 회가 아니라 몇 초로 잰다. 그런데
초를 담을 칸이 어디에도 없어, 데모 픽스처는 `플랭크 3세트 · 60초` 처럼 **이름에**
적었고 45초 홀드가 `reps: 3` 으로 적히기도 했다 — 이름에 적힌 글자는 어떤
집계에도 잡히지 않고, `reps: 3` 은 45초를 "3회" 라고 말하는 틀린 데이터다.

네 칸을 연다.

- `exercise_catalog.isometric` — 이 종목이 버티는 운동인가. 폼이 `횟수` 칸을 `초`
  칸으로 바꿔 보일지의 **기본값**이고, 표에 없는 자유 입력 이름이 있으므로
  사용자가 폼에서 바꿀 수 있다. 기존 행은 전부 `false` 이고, 시드에 표시가 있는
  `플랭크` 만 여기서 참으로 올린다.
- `exercise_sessions.hold_seconds` / `trainer_routines.hold_seconds` — 한 세트를
  버티는 시간. `reps` 와 한 자리를 나눠 쓴다: 있으면 횟수가 비고, 없으면 반대다.
- `exercise_sessions.duration_seconds` — 그 운동에 실제로 쓴 시간(초). `minutes`
  는 그대로 두고 서버가 초에서 계산해 채운다. 주간 집계·트레이너웹이 분을 읽기
  때문이다. 이 칸이 비어 있는 옛 기록은 `minutes × 60` 으로 읽는다.

넷 다 nullable 이라 기존 행은 손대지 않는다 — 비어 있는 것이 "적지 않았다" 이고,
0 으로 채우면 0초를 버텼다는 말이 된다.

Revision ID: 0082_isometric_hold_seconds
Revises: 0081_graph_colors
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0082_isometric_hold_seconds"
down_revision: str | Sequence[str] | None = "0081_graph_colors"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "exercise_catalog",
        sa.Column(
            "isometric",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("false"),
        ),
    )
    # 시드가 표시해 둔 종목을 이미 시딩된 DB 에도 반영한다. 시딩은 표가 비어
    # 있을 때만 도는 멱등 경로라, 이 줄이 없으면 운영 DB 의 플랭크는 표시가
    # 없는 채로 남는다. 별칭(`사이드플랭크`)은 같은 행을 가리키므로 함께 붙는다.
    op.execute(
        "UPDATE exercise_catalog SET isometric = true WHERE name_norm = '플랭크'"
    )
    op.add_column(
        "exercise_sessions", sa.Column("hold_seconds", sa.Integer(), nullable=True)
    )
    op.add_column(
        "exercise_sessions",
        sa.Column("duration_seconds", sa.Integer(), nullable=True),
    )
    op.add_column(
        "trainer_routines", sa.Column("hold_seconds", sa.Integer(), nullable=True)
    )


def downgrade() -> None:
    op.drop_column("trainer_routines", "hold_seconds")
    op.drop_column("exercise_sessions", "duration_seconds")
    op.drop_column("exercise_sessions", "hold_seconds")
    op.drop_column("exercise_catalog", "isometric")
