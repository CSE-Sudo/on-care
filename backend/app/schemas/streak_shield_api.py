"""연속 기록 보호권 응답 스키마. (#1788)

포인트 사용처 교환 응답(`ExchangeOut.shield`)과 보호권 조회가 함께 읽으므로, 두
스키마 모듈 어느 쪽도 import 하지 않는 별도 모듈에 둔다.
"""
from __future__ import annotations

from datetime import date as date_, datetime

from pydantic import BaseModel


class StreakShieldOut(BaseModel):
    """보호권 한 장. `status`: held(보유)|used(사용).

    `protected_on` 은 보호한 날(KST, YYYY-MM-DD)로, 쓰지 않았으면 null 이다.
    """

    id: str
    cost: int
    status: str
    acquired_at: datetime
    protected_on: str | None = None
    used_at: datetime | None = None


class StreakShieldUseOut(BaseModel):
    """보호한 날 하나 — 내 혜택의 `사용한 날` 목록 항목."""

    date: str
    used_at: datetime


class StreakShieldsOut(BaseModel):
    """GET /me/streak-shields — 보유 개수·보호한 날·기록 연속.

    `record_streak_days` 는 식단 한 끼든 운동 한 건이든 남긴 날이 이어진 길이다
    (보호한 날 포함). 운동 주간 응답의 `streak_days`(운동만)와 다른 값이다.
    `protectable_date` 는 지금 보호할 수 있는 날(어제)이고, 보호권이 없거나 어제
    기록이 있거나 이미 보호했으면 null 이다.
    """

    held: int
    max_held: int
    cost: int
    used: list[StreakShieldUseOut]
    record_streak_days: int = 0
    protectable_date: str | None = None


class StreakShieldUseRequest(BaseModel):
    """POST /me/streak-shields/use 입력.

    보호할 날을 앱이 **명시**한다. 자정 직전에 본 `보호권 쓰기` 를 자정 뒤에 눌러도
    서버가 다른 날(새 어제)을 보호하지 않고, 그 날짜가 더는 어제가 아니라고 거절한다.
    """

    date: date_

