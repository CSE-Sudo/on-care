"""트레이너 운영자 승인 응답. (#2825)"""
from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field

VerificationStatus = Literal["pending", "approved", "rejected"]


class TrainerVerificationOut(BaseModel):
    """`GET /trainer/me` 의 `verification`. 트레이너 웹이 안내 배너를 고른다."""

    status: VerificationStatus
    #: 승인·반려 시각. 대기 중이거나 백필된 기존 트레이너는 비어 있다.
    decided_at: datetime | None = None
    #: 반려 사유. 승인·대기면 빈 문자열.
    note: str = ""


class AdminTrainerVerificationOut(BaseModel):
    """운영자가 승인 여부를 정할 때 보는 트레이너 한 명."""

    trainer_id: str
    name: str
    email: str
    specialty: str
    career_years: int
    certifications: list[str]
    gym_id: str | None
    gym_name: str
    gym_address: str
    #: 소속이 헬스장(`places.category='fitness'`)인가 — 승인돼도 아니면 노출되지 않는다.
    gym_is_fitness: bool
    status: VerificationStatus
    decided_at: datetime | None
    decided_by: str | None
    note: str
    created_at: datetime | None
    #: 계정이 살아 있는가. 운영자가 정지하면 false(#3009) — 운영 화면이 정지·해제
    #: 버튼을 고른다.
    is_active: bool = True


class AdminUserStatusOut(BaseModel):
    """계정 정지·해제 결과. (#3009)"""

    user_id: str
    role: str
    is_active: bool
    #: 이번 정지로 해제한 담당 회원 수. 해제·회원 계정은 0.
    released_clients: int = 0


class TrainerRejectIn(BaseModel):
    """반려 사유. 트레이너 웹에 그대로 보인다."""

    reason: str = Field(default="", max_length=300)
