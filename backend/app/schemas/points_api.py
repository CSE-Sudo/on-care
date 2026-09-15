"""활동 포인트 응답 스키마. (#1786, 사용처·쿠폰 #1787)"""
from __future__ import annotations

from datetime import datetime
from typing import TYPE_CHECKING

from pydantic import BaseModel, Field

from app.schemas.streak_shield_api import StreakShieldOut

if TYPE_CHECKING:
    from app.services.points_service import PointsResult


class ShopItemOut(BaseModel):
    """사용처 화면의 교환 항목 하나와 지금 교환할 수 있는지.

    `blocked_reason`: 교환 버튼을 막는 이유 — `no_trainer`(담당 트레이너 없음)·
    `active_coupon`(사용하지 않은 같은 쿠폰 보유)·`shield_limit`(쓰지 않은 연속 기록
    보호권을 최대로 보유, #1788)·`insufficient_points`(잔액 부족).
    교환할 수 있으면 null. `shortfall` 은 모자란 포인트로, 모자라지 않으면 0 이다.
    """

    id: str
    title: str
    benefit: str
    description: str
    cost: int
    valid_days: int
    #: 누가 사용 처리하나 — trainer|member.
    redeemer: str
    requires_trainer: bool
    available: bool
    blocked_reason: str | None = None
    shortfall: int = 0


class PointsShopOut(BaseModel):
    """GET /me/points/shop — 잔액과 교환 항목."""

    balance: int
    has_trainer: bool
    items: list[ShopItemOut]


class ExchangeRequest(BaseModel):
    """POST /me/points/exchange 입력.

    `client_request_id` 는 교환 시도 단위 멱등키다. 같은 값으로 다시 보내면 새로
    쓰지 않고 처음 발급한 쿠폰을 돌려준다.
    """

    item: str = Field(min_length=1, max_length=40)
    client_request_id: str | None = Field(default=None, min_length=1, max_length=64)


class CouponOut(BaseModel):
    """회원이 보는 쿠폰 한 장.

    `status`: issued(사용 가능)|used|expired|cancelled. 기한이 지난 쿠폰은 서버가
    아직 만료로 내리지 않았어도 expired 로 싣는다.
    `expires_on` 은 쓸 수 있는 마지막 날(KST), `days_left` 는 그날까지 남은 날
    (당일 0, 사용 가능이 아니면 0).
    `trainer_name`·`gym_name` 은 교환할 때의 담당 트레이너·헬스장(PT 재등록만).
    """

    id: str
    item: str
    title: str
    benefit: str
    cost: int
    status: str
    redeemer: str
    trainer_name: str = ""
    gym_name: str = ""
    issued_at: datetime
    issued_on: str
    expires_at: datetime
    expires_on: str
    days_left: int
    used_at: datetime | None = None
    cancelled_at: datetime | None = None


class ExchangeOut(BaseModel):
    """POST /me/points/exchange 응답 — 발급한 쿠폰, 쓴 포인트, 그 뒤의 잔액.

    연속 기록 보호권(#1788)은 쿠폰이 아니라 `coupon` 이 null 이고 `shield` 에 받은
    보호권이 온다. 두 칸 중 교환한 항목의 것 하나만 있다.
    """

    coupon: CouponOut | None = None
    shield: StreakShieldOut | None = None
    spent: int
    balance: int


class PointsOut(BaseModel):
    """이번 저장으로 받은 포인트와 그 뒤의 잔액.

    식단 기록·운동 직접 추가·배정 루틴 완료의 **생성 응답**에만 붙는다.
    `awarded` 는 그날 한도를 넘었으면 0 이다 — 앱은 0 이면 적립 표시 없이 저장
    알림만 띄운다.
    """

    awarded: int
    balance: int

    @classmethod
    def of(cls, result: PointsResult) -> PointsOut:
        return cls(awarded=result.awarded, balance=result.balance)
