"""채팅 이모티콘 응답 — 하나씩 사서 7일 동안 쓴다. (#2153)"""
from __future__ import annotations

from pydantic import BaseModel, Field


class EmoteUnlockOut(BaseModel):
    """쓰고 있는 이모티콘 하나."""

    emote_id: str
    expires_at: str
    #: 남은 초. 앱은 이 값으로 `6일 남음` 을 센다 — 기기 시계가 틀어져도
    #: 남은 기간이 어긋나지 않는다.
    remaining_seconds: int


class EmoteStateOut(BaseModel):
    #: 지금 쓸 수 있는 이모티콘. 먼저 끝나는 것이 앞이다.
    unlocked: list[EmoteUnlockOut]
    #: 이모티콘 하나의 값(포인트).
    cost: int
    #: 하나를 사면 쓸 수 있는 날 수.
    days: int
    #: 지금 포인트 잔액 — 고르는 창이 `모자라요` 를 스스로 판단한다.
    balance: int


class EmoteUnlockRequest(BaseModel):
    client_request_id: str | None = Field(default=None, min_length=1, max_length=64)
