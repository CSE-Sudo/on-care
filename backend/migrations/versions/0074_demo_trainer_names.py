"""데모 트레이너 15명의 이름을 실제 이름으로 옮긴다. (#2062)

데모 트레이너 이름이 `김트레이너`·`박트레이너` 처럼 성에 직함을 붙인 자리표시자라
사람 이름이 아니라 직함처럼 읽혔다. 트레이너 줄이 이름과 직함을 한 줄에 두면서
(#2038) `김트레이너 퍼스널 트레이너` 로 `트레이너` 가 두 번 읽혔고, 실제 알림도
`{이름} 트레이너님이` 로 만들어져 `김트레이너 트레이너님이 …` 가 됐다.

시드는 새 이름으로 행을 만든다. 그런데 시드는 **행이 없을 때만** 넣으므로, 이미
떠 있는 DB 에서는 옛 이름이 그대로 남는다. 트레이너 이름을 저장하는 곳은
`users.name` 하나뿐이고 목록·카드·새 알림은 모두 이 값을 읽으므로, 이 한 칸을
고치면 된다.

**트레이너가 직접 고친 이름은 덮어쓰지 않는다.** id 가 맞고 이름이 아직 자리표시자
그대로일 때만 바꾼다. 누가 이미 `김코치` 로 바꿨다면 그대로 둔다. 되돌릴 때도 같은
조건으로 새 이름일 때만 옛 이름으로 돌린다.

이미 저장된 알림 본문 속 이름은 이 마이그레이션이 고치지 않는다. 알림은 완성된
글자로 저장돼 있어, 보여 줄 때의 이름을 쓰게 바꾸는 일은 #2065 가 다룬다.

행이 없는 DB(새로 만든 DB)에서는 아무 일도 하지 않는다 — 시드가 새 이름으로
만든다.

Revision ID: 0074_demo_trainer_names
Revises: 0073_consultation_slot
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0074_demo_trainer_names"
down_revision: str | Sequence[str] | None = "0073_consultation_slot"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

#: (트레이너 id, 옛 자리표시자, 실제 이름). 시드와 같은 값이어야 한다 —
#: `app/db/seed_trainer.py` 의 `TRAINER_NAME`, `app/db/seed_gyms.py` 의 `_TRAINERS`.
_RENAMES: tuple[tuple[str, str, str], ...] = (
    ("trainer-demo", "김트레이너", "김태오"),
    ("trainer-park", "박트레이너", "박소율"),
    ("trainer-choi", "최트레이너", "최건우"),
    ("trainer-kang", "강트레이너", "강다인"),
    ("trainer-yoon", "윤트레이너", "윤재희"),
    ("trainer-lee", "이트레이너", "이도경"),
    ("trainer-cho", "조트레이너", "조민혁"),
    ("trainer-demo-jung", "정트레이너", "정수빈"),
    ("trainer-demo-ha", "하트레이너", "하윤슬"),
    ("trainer-demo-han", "한트레이너", "한서준"),
    ("trainer-demo-oh", "오트레이너", "오태린"),
    ("trainer-demo-seo", "서트레이너", "서지안"),
    ("trainer-demo-nam", "남트레이너", "남도윤"),
    ("trainer-demo-moon", "문트레이너", "문하람"),
    ("trainer-demo-bae", "배트레이너", "배시우"),
)

_RENAME = sa.text(
    "UPDATE users SET name = :to_name WHERE id = :id AND name = :from_name"
)


def upgrade() -> None:
    conn = op.get_bind()
    for trainer_id, placeholder, real in _RENAMES:
        conn.execute(
            _RENAME, {"id": trainer_id, "from_name": placeholder, "to_name": real}
        )


def downgrade() -> None:
    conn = op.get_bind()
    for trainer_id, placeholder, real in _RENAMES:
        conn.execute(
            _RENAME, {"id": trainer_id, "from_name": real, "to_name": placeholder}
        )
