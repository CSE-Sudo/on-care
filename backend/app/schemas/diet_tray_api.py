"""분석용 식판 응답 스키마. (#2150)"""
from __future__ import annotations

from pydantic import BaseModel, Field

from app.schemas.points_api import CouponOut


class DietTrayOut(BaseModel):
    """GET /me/diet-tray — 식판 카드가 그릴 진행 상황과 상태.

    `status`: `progress`(조건을 채우는 중이거나 담당 트레이너 없음)·`claimable`(지금
    받을 수 있음)·`issued`(받은 수령 쿠폰을 아직 헬스장에서 쓰지 않음)·`received`
    (식판을 받음 — 1인 1회라 더 받지 않는다).

    `photo_days` 는 `window_from`~`window_to`(KST, 오늘 포함 `window_days`일) 안에서
    식단 사진을 남긴 날 수, `required_days` 는 받는 데 필요한 날 수다. `coupon` 은
    `issued`·`received` 일 때의 식판 수령 쿠폰이고, 그 밖에는 null 이다.
    """

    status: str
    photo_days: int
    required_days: int
    window_days: int
    window_from: str
    window_to: str
    has_trainer: bool
    coupon: CouponOut | None = None


class DietTrayClaimRequest(BaseModel):
    """POST /me/diet-tray/claim 입력. `client_request_id` 는 받기 시도 단위 멱등키다."""

    client_request_id: str | None = Field(default=None, min_length=1, max_length=64)
