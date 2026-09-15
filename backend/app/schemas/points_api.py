"""활동 포인트 응답 스키마. (#1786)"""
from __future__ import annotations

from typing import TYPE_CHECKING

from pydantic import BaseModel

if TYPE_CHECKING:
    from app.services.points_service import PointsResult


class PointsOut(BaseModel):
    """이번 저장으로 받은 포인트와 그 뒤의 잔액.

    식단 기록·운동 직접 추가·배정 루틴 완료의 **생성 응답**에만 붙는다.
    `awarded` 는 그날 한도를 넘었거나 적립 대상이 아니면(트레이너가 직접 배정한
    루틴 등) 0 이다 — 앱은 0 이면 적립 표시 없이 저장 알림만 띄운다.
    """

    awarded: int
    balance: int

    @classmethod
    def of(cls, result: PointsResult) -> PointsOut:
        return cls(awarded=result.awarded, balance=result.balance)
