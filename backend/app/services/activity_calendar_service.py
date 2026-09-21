"""기록 그래프 — 날짜별 기록과 기록 연속. (#2075)

깃허브 그래프처럼 하루에 칸 하나를 칠한다. 어느 날 기록이 끊겼는지 한눈에 보이게
하는 것이 목적이라, 칸의 진하기는 **그날 무엇을 남겼는가** 세 단계다:

1. 아무 기록도 없음 — 빈 칸
2. 식단·운동 중 하나만 — 중간
3. 둘 다 — 가장 진함

보호권(#1788)으로 이어 붙인 날은 실제 기록이 아니므로 `has_diet`·`has_exercise`
둘 다 false 이고 `protected` 만 true 다 — 앱이 그 칸에 방패를 얹어 구분한다.

`record_streak_days` 는 보호권이 지키는 **기록 연속**과 같은 값이다
(`record_activity.record_streak_days`). 운동 탭의 `연속 N일`(운동만, 이번 주 안)과
다른 숫자이고, 이 이슈는 운동 탭을 바꾸지 않는다.

날짜는 모두 KST 다(`clock.today`). 오늘 이후 날짜는 싣지 않는다 — 아직 오지 않은
날을 빈 칸으로 그리면 끊긴 날처럼 보인다.
"""
from __future__ import annotations

from datetime import date, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core import clock
from app.models.models import StreakShield
from app.schemas.activity_api import ActivityCalendarOut, ActivityDayOut
from app.services import graph_color_service, record_activity, streak_shield_service

#: 한 번에 돌려주는 날 수의 상한이자 기본 구간. 53주 × 7일 — 앱이 그리는 격자가
#: 깃허브 잔디와 같은 53칸이다.
MAX_DAYS = 371


def calendar(
    db: Session,
    member_id: str,
    *,
    start: date | None = None,
    end: date | None = None,
) -> ActivityCalendarOut:
    """[start]…[end] 의 날짜별 기록·기록 연속·그래프 색. 아무것도 쓰지 않는다.

    기본 구간은 **오늘로 끝나는 [MAX_DAYS]일**이다 — 앱이 깃허브 잔디처럼 최근
    1년을 그리므로 구간을 주지 않은 호출도 같은 눈금으로 답한다. [end] 가 오늘보다
    뒤면 오늘로 당기고,
    [start] 가 [end] 보다 뒤면 하루짜리 구간으로 본다. 구간이 [MAX_DAYS] 보다
    길면 뒤에서부터 그만큼만 싣는다 — 한 번의 요청이 몇 년치를 읽지 않게 한다.
    """
    today = clock.today()
    last = min(end or today, today)
    first = start or last - timedelta(days=MAX_DAYS - 1)
    if first > last:
        first = last
    if (last - first).days + 1 > MAX_DAYS:
        first = last - timedelta(days=MAX_DAYS - 1)

    diet = record_activity.diet_days(db, member_id, first, last)
    exercise = record_activity.exercise_days(db, member_id, first, last)
    protected_all = _protected_days(db, member_id)
    days: list[ActivityDayOut] = []
    cursor = first
    while cursor <= last:
        key = cursor.isoformat()
        days.append(
            ActivityDayOut(
                date=key,
                has_diet=key in diet,
                has_exercise=key in exercise,
                protected=key in protected_all,
            )
        )
        cursor += timedelta(days=1)

    shields = streak_shield_service.status(db, member_id)
    return ActivityCalendarOut(
        from_date=first.isoformat(),
        to_date=last.isoformat(),
        days=days,
        # 연속은 구간 밖까지 거슬러 세는 값이다 — 보호권 화면이 주는 것과 같은
        # 숫자를 써서, 한 화면의 두 자리에 다른 연속이 보이지 않게 한다.
        record_streak_days=shields.record_streak_days,
        shields_held=shields.held,
        protectable_from=shields.protectable_from,
        protectable_to=shields.protectable_to,
        color=graph_color_service.status(db, member_id),
    )


def _protected_days(db: Session, member_id: str) -> set[str]:
    """보호권으로 이어 붙인 날 전부(YYYY-MM-DD)."""
    return {
        row
        for row in db.scalars(
            select(StreakShield.protected_on).where(
                StreakShield.user_id == member_id,
                StreakShield.status == streak_shield_service.USED,
            )
        ).all()
        if row
    }
