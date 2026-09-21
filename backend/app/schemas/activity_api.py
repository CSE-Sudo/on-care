"""기록 그래프 응답 스키마 — 날짜별 기록과 그래프 색. (#2075, #2076)

포인트 교환 응답(`ExchangeOut.graph_color`)과 기록 그래프 조회가 함께 읽으므로,
`points_api` 를 import 하지 않는 별도 모듈에 둔다(`streak_shield_api` 와 같다).
"""
from __future__ import annotations

from pydantic import BaseModel


class ActivityDayOut(BaseModel):
    """기록 그래프의 칸 하나 — 하루의 기록 상태.

    `date` 는 KST 날짜(YYYY-MM-DD)다. 식단은 끼니 하나라도 있으면 `has_diet` 이고
    (적립 규칙과 같은 눈금이다, #1786), 운동은 1분이라도 기록했으면
    `has_exercise` 다. `protected` 는 보호권으로 이어 붙인 날(#1788)로, 그날 실제
    기록은 없다 — 두 `has_*` 는 false 이고 연속에만 든다.
    """

    date: str
    has_diet: bool = False
    has_exercise: bool = False
    protected: bool = False


class GraphColorOut(BaseModel):
    """그래프 색 — 지금 색과 연 색. (#2076)

    `current` 는 지금 기록 그래프를 그리는 색이고, 기본 색은 `blue` 다. `unlocked` 는
    고를 수 있는 색 전부로, 포인트를 내지 않는 기본 색이 늘 첫 칸에 든다.
    `palette` 는 서버가 파는 색 전부(기본 색 포함)이고 `cost` 는 한 색의 값이다 —
    앱이 가격·목록을 따로 들고 있으면 규칙을 바꿀 때 화면만 옛 값으로 남는다.
    """

    current: str
    unlocked: list[str]
    palette: list[str]
    cost: int


class ActivityCalendarOut(BaseModel):
    """GET /me/activity-calendar — 날짜별 기록·기록 연속·그래프 색.

    `days` 는 `from_date`…`to_date` 를 하루도 빠짐없이 채운 오름차순 배열이다 —
    기록이 없는 날도 빈 칸으로 온다. 오늘 이후 날짜는 싣지 않는다.
    `record_streak_days` 는 식단이든 운동이든 남긴 날(보호한 날 포함)이 이어진
    길이로, 운동 탭의 `연속 N일`(운동만, 이번 주 안)과는 다른 값이다.
    `protectable_from`·`protectable_to` 는 지금 보호권을 쓸 수 있는 날의 구간
    (양끝 포함)으로, `GET /me/streak-shields` 와 같은 값이다. 그 구간 안에서 `days[]`
    가 비어 있고(`has_*` 둘 다 false) 아직 보호하지 않은 칸이 누를 수 있는 칸이다.
    """

    from_date: str
    to_date: str
    days: list[ActivityDayOut]
    record_streak_days: int
    shields_held: int = 0
    protectable_from: str | None = None
    protectable_to: str | None = None
    color: GraphColorOut


class GraphColorRequest(BaseModel):
    """PUT /me/graph-color 입력 — 고른 색. 기본 색으로 되돌리려면 `blue` 다."""

    color: str
