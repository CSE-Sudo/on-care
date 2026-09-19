"""하루의 **기록** — 식단 한 끼든 운동 한 건이든 남겼으면 기록한 날. (#1788)

연속 기록 보호권이 지키는 것은 이 기록 연속이다. 운동 탭의 `N일 연속 운동`
(`exercise_service._longest_streak`)과는 **다른 값**이다 — 그쪽은 운동만 세고,
보호한 날도 넣지 않는다. 한 화면에서 두 숫자가 다를 수 있고, 그래도 맞다.

한 끼 기준인 이유는 적립 규칙과 같은 눈금을 쓰기 위해서다: 적립(#1786)도
`diet_entry` 한 건당 포인트를 주고 하루 3번까지 받는다 — 한 끼도 기록으로
인정하고 세 끼를 채우면 더 주는 구조다. 연속만 "세 끼 전부" 로 올리면 같은
화면에서 기록의 뜻이 둘이 된다.
"""
from __future__ import annotations

from datetime import date, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.models import DietEntry, ExerciseSession
from app.services import exercise_activity


def has_record(db: Session, member_id: str, day: date) -> bool:
    """[day] 에 식단 또는 운동 기록이 있는가."""
    return has_exercise(db, member_id, day) or has_diet(db, member_id, day)


def has_exercise(db: Session, member_id: str, day: date) -> bool:
    """그날 운동 기록이 있는가. 주간 집계와 같은 (주 시작, 요일) 로 찾는다."""
    monday = day - timedelta(days=day.weekday())
    return (
        db.scalar(
            select(ExerciseSession.id)
            .where(
                ExerciseSession.user_id == member_id,
                ExerciseSession.week_start == monday.isoformat(),
                ExerciseSession.day_label
                == exercise_activity.WEEKDAY_LABELS[day.weekday()],
                ExerciseSession.minutes > 0,
            )
            .limit(1)
        )
        is not None
    )


def has_diet(db: Session, member_id: str, day: date) -> bool:
    """그날 식단 기록이 한 건이라도 있는가. 끼니 종류는 보지 않는다."""
    return (
        db.scalar(
            select(DietEntry.id)
            .where(
                DietEntry.user_id == member_id,
                DietEntry.date == day.isoformat(),
            )
            .limit(1)
        )
        is not None
    )


def record_streak_days(
    db: Session,
    member_id: str,
    *,
    today: date,
    protected: set[str] | None = None,
    limit: int = 365,
) -> int:
    """오늘부터 거슬러 올라가며 이어진 기록 일수.

    오늘은 아직 기록하지 않았을 수 있으므로, 오늘이 비어 있으면 어제부터 센다 —
    그러지 않으면 자정이 지나는 순간 어제까지 쌓은 연속이 0 으로 보인다.
    [protected] 는 보호권으로 이어 붙인 날(YYYY-MM-DD)로, 기록한 날처럼 센다.
    [limit] 은 조회를 묶는 상한이다.
    """
    protected = protected or set()

    def recorded(day: date) -> bool:
        return day.isoformat() in protected or has_record(db, member_id, day)

    start = today if recorded(today) else today - timedelta(days=1)
    count = 0
    cursor = start
    while count < limit and recorded(cursor):
        count += 1
        cursor -= timedelta(days=1)
    return count
