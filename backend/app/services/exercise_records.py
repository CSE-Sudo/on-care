"""직접 기록한 운동의 개인 기록 태그. (#2971)

운동 기록 상세의 운동 줄에 붙는 태그 하나를 정한다 — 평가가 아니라 사실만
알린다. "더 늘려 보세요" 같은 판단은 트레이너 리포트의 몫이다.

- ``max_weight``: 같은 근력 운동을 전에 든 어떤 중량보다 무겁다.
- ``longest``: 같은 운동(근력 외)을 전에 한 어떤 시간보다 길다.
- ``first``: 이 이름으로 처음 적은 운동이다.

한 기록에는 하나만 붙는다. 우선순위는 위 순서다 — 처음 적은 운동은 비교할
지난 기록이 없으니 최고·최장이 될 수 없고, 근력은 중량으로, 나머지는 시간으로만
견준다.

같은 운동은 이름의 공백을 지우고 소문자로 맞춰 묶는다 — `벤치 프레스` 와
`벤치프레스` 는 같은 운동이다. 종목표 대표 이름으로 묶는 일은 AI 해석이 들어가
따로 다룬다(#2971 범위 밖).

회원이 직접 적은 기록(`source == member`)만 본다. PT·배정 루틴 기록은 회원이
적은 값이 아니고, 상세 화면도 직접 기록만 보여 준다.
"""
from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass
from datetime import date, datetime

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.models import ExerciseSession
from app.services import exercise_activity, exercise_types

MAX_WEIGHT = "max_weight"
LONGEST = "longest"
FIRST = "first"

_MEMBER = "member"


def exercise_key(name: str | None) -> str:
    """같은 운동으로 묶는 열쇠 — 공백을 모두 지우고 소문자로 맞춘다."""
    return "".join((name or "").split()).lower()


def _seconds_of(row) -> int:
    """걸린 시간(초). 초를 모르는 옛 기록은 분에서 환산한다."""
    seconds = getattr(row, "duration_seconds", None)
    if seconds:
        return int(seconds)
    return int(row.minutes or 0) * 60


@dataclass(frozen=True)
class _Entry:
    id: str
    key: str
    strength: bool
    weight: float | None
    seconds: int
    #: 어느 기록이 먼저인가. 같은 날이면 먼저 저장한 기록이 먼저다.
    order: tuple[date, datetime]


def _entry(row) -> _Entry | None:
    key = exercise_key(row.name)
    when = exercise_activity.activity_date_of(row)
    # 이름이 없던 옛 기록·날짜를 알 수 없는 기록은 견줄 수 없다.
    if not key or when is None:
        return None
    created = row.created_at or datetime.min
    return _Entry(
        id=row.id,
        key=key,
        strength=exercise_types.normalize(row.type) == "strength",
        weight=row.weight,
        seconds=_seconds_of(row),
        order=(when, created.replace(tzinfo=None)),
    )


def tag_of(entry: _Entry, earlier: Sequence[_Entry]) -> str | None:
    """[earlier](같은 운동의 더 이른 기록)와 견준 [entry] 의 태그."""
    if not earlier:
        return FIRST
    if entry.strength:
        if entry.weight is None:
            return None
        before = [e.weight for e in earlier if e.strength and e.weight is not None]
        if before and entry.weight > max(before):
            return MAX_WEIGHT
        return None
    before_seconds = [e.seconds for e in earlier if not e.strength]
    if before_seconds and entry.seconds > max(before_seconds):
        return LONGEST
    return None


def personal_records(
    db: Session, user_id: str, rows: Sequence
) -> dict[str, str]:
    """[rows] 중 직접 기록한 운동마다 붙일 태그. 태그가 없는 기록은 빠진다.

    회원의 직접 기록 전체를 한 번 읽어 이름별로 견준다. 회원 한 명의 운동 기록은
    많아야 수천 건이라 조회할 때 계산해도 충분하다.
    """
    targets = [r for r in rows if getattr(r, "source", _MEMBER) == _MEMBER]
    if not targets:
        return {}
    history = db.scalars(
        select(ExerciseSession)
        .where(ExerciseSession.user_id == user_id)
        .where(ExerciseSession.source == _MEMBER)
    ).all()
    by_key: dict[str, list[_Entry]] = {}
    for row in history:
        entry = _entry(row)
        if entry is not None:
            by_key.setdefault(entry.key, []).append(entry)

    tags: dict[str, str] = {}
    for row in targets:
        entry = _entry(row)
        if entry is None:
            continue
        earlier = [
            e for e in by_key.get(entry.key, ())
            if e.id != entry.id and e.order < entry.order
        ]
        tag = tag_of(entry, earlier)
        if tag is not None:
            tags[entry.id] = tag
    return tags
