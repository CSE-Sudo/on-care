"""활동 포인트 응답 스키마. (#1786, 사용처·쿠폰 #1787)"""
from __future__ import annotations

from datetime import datetime
from typing import TYPE_CHECKING

from pydantic import BaseModel, Field

from app.schemas.activity_api import GraphColorOut
from app.schemas.profile_pet_api import ProfilePetOut
from app.schemas.streak_shield_api import StreakShieldOut

if TYPE_CHECKING:
    from app.services.points_service import PointsResult


class ShopItemOut(BaseModel):
    """사용처 화면의 교환 항목 하나와 지금 교환할 수 있는지.

    `blocked_reason`: 교환 버튼을 막는 이유 — `no_trainer`(담당 트레이너 없음)·
    `no_gym`(연결한 헬스장 없음)·`active_coupon`(사용하지 않은 같은 쿠폰 보유)·
    `shield_limit`(쓰지 않은 연속 기록 보호권을 최대로 보유, #1788)·
    `active_pass`(이용 중인 이모티콘 이용권, #2020)·`active_pet`(달고 있는 프로필 펫,
    #2021)·`week_owned`(지난주 리포트를 이미 받음, #2022)·`monthly_limit`(이번 달에 이미 교환)·`insufficient_points`(잔액 부족) 순으로
    하나만. 교환할 수 있으면 null. `shortfall` 은 모자란 포인트로, 모자라지 않으면
    0 이다.

    기간제 항목을 이미 쓰고 있으면(프로필 펫 이모지, #2021) `active_option` 에 고른
    갈래, `active_until` 에 끝나는 시각, `remaining_seconds` 에 남은 초가 온다 — 카드가
    남은 기간을 보여 준다. 쓰고 있지 않으면 null·null·0 이다.
    """

    id: str
    title: str
    benefit: str
    description: str
    cost: int
    valid_days: int
    requires_trainer: bool
    requires_gym: bool
    available: bool
    blocked_reason: str | None = None
    shortfall: int = 0
    active_option: str | None = None
    active_until: datetime | None = None
    remaining_seconds: int = 0


class PointsShopOut(BaseModel):
    """GET /me/points/shop — 잔액과 교환 항목."""

    balance: int
    has_trainer: bool
    has_gym: bool
    items: list[ShopItemOut]


class ExchangeRequest(BaseModel):
    """POST /me/points/exchange 입력.

    `client_request_id` 는 교환 시도 단위 멱등키다. 같은 값으로 다시 보내면 새로
    쓰지 않고 처음 발급한 쿠폰을 돌려준다.

    `option` 은 항목이 여러 갈래일 때 고른 갈래다 — 그래프 색 바꾸기(#2076)에서 어느
    색을 열지 싣는다. 갈래가 없는 항목은 주지 않는다.
    """

    item: str = Field(min_length=1, max_length=40)
    option: str | None = Field(default=None, min_length=1, max_length=40)
    client_request_id: str | None = Field(default=None, min_length=1, max_length=64)


class CouponOut(BaseModel):
    """회원이 보는 쿠폰 한 장.

    `status`: issued(사용 가능)|used|expired|cancelled. 기한이 지난 쿠폰은 서버가
    아직 만료로 내리지 않았어도 expired 로 싣는다.
    `expires_on` 은 쓸 수 있는 마지막 날(KST), `days_left` 는 그날까지 남은 날
    (당일 0, 사용 가능이 아니면 0).
    `trainer_name` 은 교환할 때의 담당 트레이너(PT 재등록만), `gym_name` 은 교환할
    때의 헬스장(PT 재등록·개인 락커)이다.
    `no_expiry` 가 참이면 기한이 없는 쿠폰(분석용 식판, #2150)이다 — `expires_on` 은
    뜻이 없고 `days_left` 는 0 이다.
    """

    id: str
    item: str
    title: str
    benefit: str
    cost: int
    status: str
    trainer_name: str = ""
    gym_name: str = ""
    issued_at: datetime
    issued_on: str
    expires_at: datetime
    expires_on: str
    days_left: int
    no_expiry: bool = False
    used_at: datetime | None = None
    cancelled_at: datetime | None = None


class ExchangeOut(BaseModel):
    """POST /me/points/exchange 응답 — 발급한 쿠폰, 쓴 포인트, 그 뒤의 잔액.

    연속 기록 보호권(#1788)은 쿠폰이 아니라 `coupon` 이 null 이고 `shield` 에 받은
    보호권이, 그래프 색 바꾸기(#2076)는 `graph_color` 에 연 뒤의 색 상태가 온다.
    프로필 펫(#2021)·주간 리포트(#2022)도 제 칸에 온다. 교환한 항목의 것 하나만 있다.
    """

    coupon: CouponOut | None = None
    shield: StreakShieldOut | None = None
    graph_color: GraphColorOut | None = None
    #: 프로필 펫 이모지(#2021)를 교환했으면 단 펫과 남은 기간.
    profile_pet: ProfilePetOut | None = None
    #: 주간 리포트(#2022)를 교환했으면 받은 주의 월요일 `YYYY-MM-DD`.
    weekly_report_week: str | None = None
    spent: int
    balance: int


class PointsHistoryItemOut(BaseModel):
    """포인트 내역 한 줄. (#2146)

    `kind`: earn(적립)·spend(사용)·revoke(회수 — 기록을 지워 적립을 되돌림)·
    refund(반환 — 쿠폰 취소 등으로 사용을 되돌림). `delta` 는 잔액 변화량이다(적립·
    반환은 양수, 사용·회수는 0 이하). `reason` 은 사유 코드 — diet_entry ·
    exercise_manual · routine_complete · coupon_<항목> · streak_shield · graph_color ·
    emote_pass_24h · profile_pet · weekly_report · challenge_stake ·
    challenge_reward · ai_chat. `count` 는 묶은 줄 수로, AI 코치 대화(`ai_chat`)만
    하루치를 한 줄로 묶어 1 보다 크다.
    """

    id: str
    kind: str
    reason: str
    delta: int
    count: int = 1
    kst_date: str
    created_at: datetime


class PointsHistoryOut(BaseModel):
    """GET /me/points/history — 최근 며칠치 내역(최신순)과 지금 잔액.

    `next_before` 가 있으면 그 값을 `before` 로 넘겨 그 앞 날짜들을 이어 받는다.
    """

    balance: int
    items: list[PointsHistoryItemOut]
    next_before: str | None = None


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
