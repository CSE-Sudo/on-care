"""
기록 그래프 라우터 — 날짜별 기록 조회와 그래프 색 고르기. (#2075, #2076)

  GET /me/activity-calendar?from=&to=  -> { from_date, to_date, days[],
                                            record_streak_days, shields_held,
                                            protectable_from, protectable_to, color }
  GET /me/records/span                 -> { diet_first_date, exercise_first_date }
  PUT /me/graph-color                  -> { current, unlocked, palette, cost }

색을 **여는** 것은 다른 사용처 항목과 같은 `POST /me/points/exchange`
(`item: graph_color`, `option: <색>`)다. 여기 PUT 은 이미 연 색 사이를 오가는
것이라 포인트가 들지 않는다.

날짜는 모두 KST 다. `from`·`to` 는 YYYY-MM-DD 이고, 주지 않으면 오늘로 끝나는
8주다 — 앱 기록 그래프가 그리는 구간과 같다.

읽기는 CurrentUser(데모 폴백 허용), 쓰기는 RequireMember 다 — 포인트 사용처와
같은 규약이다.
"""
from __future__ import annotations

from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.api.deps import CurrentUser, RequireMember
from app.db.session import get_db
from app.schemas.diet_api import RecordSpanResponse
from app.schemas.activity_api import (
    ActivityCalendarOut,
    GraphColorOut,
    GraphColorRequest,
)
from app.services import (
    activity_calendar_service,
    diet_service,
    exercise_service,
    graph_color_service,
)

router = APIRouter(tags=["points"])


@router.get("/me/activity-calendar", response_model=ActivityCalendarOut)
def my_activity_calendar(
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
    from_date: Annotated[date | None, Query(alias="from")] = None,
    to_date: Annotated[date | None, Query(alias="to")] = None,
) -> ActivityCalendarOut:
    """날짜별 기록(식단·운동·보호)과 기록 연속, 지금 그래프 색."""
    return activity_calendar_service.calendar(
        db, current_user.id, start=from_date, end=to_date
    )


@router.get("/me/records/span", response_model=RecordSpanResponse)
def my_record_span(
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> RecordSpanResponse:
    """식단·운동을 처음 남긴 날. `전체` 그래프의 시작점이다(#2079, #2236).

    식단 기간 조회(`GET /diet/days`)는 `from` 을 생략하면 알아서 첫 기록일부터
    주지만, 운동은 주 단위(`?week_start=`)라 어느 주부터 부를지를 화면이 알아야
    한다. 기록이 없으면 null 이고, 그때 `전체` 는 오늘 하루만 그린다.
    """
    return RecordSpanResponse(
        diet_first_date=diet_service.first_entry_date(db, current_user.id),
        exercise_first_date=exercise_service.first_session_date(db, current_user.id),
    )


@router.put("/me/graph-color", response_model=GraphColorOut)
def set_my_graph_color(
    payload: GraphColorRequest,
    member: RequireMember,
    db: Annotated[Session, Depends(get_db)],
) -> GraphColorOut:
    """그래프 색을 바꾼다. 포인트는 들지 않는다.

    없는 색은 404, 아직 열지 않은 색은 409 다. 기본 색(`blue`)은 늘 고를 수 있다.
    """
    try:
        return graph_color_service.select_color(db, member.id, payload.color)
    except graph_color_service.UnknownColor as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except graph_color_service.ColorLocked as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
