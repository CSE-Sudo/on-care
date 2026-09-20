"""채팅 이모티콘 이용권 응답. (#2020)"""
from __future__ import annotations

from pydantic import BaseModel, Field


class EmotePassOut(BaseModel):
    """이용 중인 이용권. 없으면 응답의 `pass` 가 null 이다."""

    expires_at: str
    #: 남은 초. 앱은 이 값으로 `3시간 12분 남음` 을 센다 — 기기 시계가 틀어져도
    #: 남은 시간이 어긋나지 않는다.
    remaining_seconds: int


class EmoteStateOut(BaseModel):
    pass_: EmotePassOut | None = Field(default=None, alias="pass")
    cost: int
    hours: int
    #: 지금 포인트 잔액 — 고르는 창이 `모자라요` 를 스스로 판단한다.
    balance: int

    model_config = {"populate_by_name": True}


class EmotePassBuyRequest(BaseModel):
    client_request_id: str | None = Field(default=None, min_length=1, max_length=64)
