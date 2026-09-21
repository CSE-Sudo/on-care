"""MY 프로필 펫 이모지 응답. (#2021)"""
from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel


class ProfilePetOut(BaseModel):
    """달고 있는 펫. 없거나 기간이 끝났으면 응답의 `pet` 이 null 이다."""

    #: dog|cat.
    kind: str
    expires_at: datetime
    #: 남은 초. 앱은 이 값으로 `5일 남음` 을 적는다 — 기기 시계가 틀어져도 남은
    #: 기간이 어긋나지 않는다.
    remaining_seconds: int


class ProfilePetStateOut(BaseModel):
    """GET /me/profile-pet — 달고 있는 펫과 값·기간·고를 수 있는 펫."""

    pet: ProfilePetOut | None = None
    cost: int
    days: int
    kinds: list[str]
