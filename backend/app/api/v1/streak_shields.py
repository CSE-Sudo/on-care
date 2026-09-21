"""
연속 기록 보호권 라우터 — 보유·사용한 날 조회와 사용. (#1788)

  GET  /me/streak-shields       -> { held, max_held, cost, used[], record_streak_days,
                                      protectable_from, protectable_to }
  POST /me/streak-shields/use   -> 같은 모양(사용 뒤)

교환은 다른 사용처 항목과 같은 `POST /me/points/exchange`(`item: streak_shield`)다.
보호권이 지키는 것은 **기록 연속**(식단 한 끼든 운동 한 건이든 남긴 날)이다 —
운동 탭의 `N일 연속 운동` 과는 다른 값이고, 운동 주간 응답에는 보호권이 실리지
않는다. 보호권을 쓰는 화면은 포인트 화면 기록 그래프(#2075)이다.

읽기는 CurrentUser(데모 폴백 허용), 쓰기는 RequireMember 다 — 포인트 사용처와 같은
규약이다.
"""
from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.api.deps import CurrentUser, RequireMember
from app.db.session import get_db
from app.schemas.streak_shield_api import StreakShieldsOut, StreakShieldUseRequest
from app.services import streak_shield_service

router = APIRouter(tags=["points"])


@router.get("/me/streak-shields", response_model=StreakShieldsOut)
def my_streak_shields(
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> StreakShieldsOut:
    """보유 개수·보호한 날(최근 먼저)·기록 연속 일수·보호할 수 있는 날의 구간."""
    return streak_shield_service.status(db, current_user.id)


@router.post("/me/streak-shields/use", response_model=StreakShieldsOut)
def use_streak_shield(
    payload: StreakShieldUseRequest,
    member: RequireMember,
    db: Annotated[Session, Depends(get_db)],
) -> StreakShieldsOut:
    """빈 하루를 연속 기록에 이어 붙이고 보호권 한 장을 쓴다.

    이미 보호한 날이면 보호권을 더 쓰지 않고 같은 응답 200 이다. 보호할 수 있는
    창(어제부터 거슬러 30일, KST) 밖이거나, 그날 기록(식단·운동)이 있거나, 보호권이
    없으면 409 다.
    """
    try:
        return streak_shield_service.use(db, member.id, payload.date)
    except streak_shield_service.ShieldNotUsable as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
