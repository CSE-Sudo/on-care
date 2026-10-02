"""기간 토글(`오늘 / 이번 주 / 전체`)이 덮는 구간. (#1017, #1025)

경계를 **서버가 정한다.** 회원 앱·트레이너웹이 각자 계산하면 같은 회원의
`이번 주` 가 화면마다 다른 날부터 시작하고, 그러면 상담에서 둘이 서로 다른
숫자를 들고 앉게 된다.

식단이 먼저 쓰기 시작했지만(#1017) 규칙 자체는 식단의 것이 아니다 — 운동
조언(#1025)도 같은 구간을 봐야 해서 여기로 옮겨 두 서비스가 한 정의를
가리키게 했다.
"""
from __future__ import annotations

from datetime import date as date_type
from datetime import timedelta

from app.core import clock
from app.core.week import monday_of

#: 기간 이름. 화면의 기간 토글과 같은 말이다.
PERIOD_TODAY = "today"
PERIOD_WEEK = "week"
PERIOD_ALL = "all"

#: `전체` 가 거슬러 올라가는 날 수. 두 앱의 `전체` 그래프와 같은 12주다 (#1018).
ALL_PERIOD_DAYS = 84


def period_bounds(period: str, today: date_type | None = None) -> tuple[str, str]:
    """기간 이름 → [시작, 끝] (양끝 포함, `YYYY-MM-DD`)."""
    day = today or clock.today()
    if period == PERIOD_TODAY:
        return day.isoformat(), day.isoformat()
    if period == PERIOD_WEEK:
        monday = monday_of(day)
        return monday.isoformat(), day.isoformat()
    return (day - timedelta(days=ALL_PERIOD_DAYS - 1)).isoformat(), day.isoformat()
