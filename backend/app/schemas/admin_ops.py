"""운영자의 신고·계정 관리와 회원의 트레이너 신고. (#3008)"""
from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field, model_validator

from app.schemas.text_limits import TEXT_LINE_MAX

ReportReason = Literal["impersonation", "inappropriate_message", "other"]
ReportStatus = Literal["open", "resolved", "dismissed"]


class TrainerReportCreate(BaseModel):
    """회원 앱의 신고 시트. 기타 사유는 설명이 있어야 한다."""

    reason: ReportReason
    memo: str = Field(default="", max_length=TEXT_LINE_MAX)

    @model_validator(mode="after")
    def _other_needs_memo(self) -> "TrainerReportCreate":
        self.memo = self.memo.strip()
        if self.reason == "other" and not self.memo:
            raise ValueError("기타 사유는 내용을 적어 주세요.")
        return self


class TrainerReportOut(BaseModel):
    """신고를 받은 결과. 회원 앱은 접수 안내만 띄운다."""

    id: str
    status: ReportStatus
    created_at: datetime


class AdminTrainerReportOut(BaseModel):
    """운영 화면의 신고 한 건. 신고한 회원은 싣지 않는다 — 처리에는 대상과 사유면
    충분하고, 운영 화면이 회원 신원을 모으지 않게 한다."""

    id: str
    trainer_id: str
    trainer_name: str
    trainer_email: str
    #: 대상 트레이너 계정이 살아 있는가 — 신고 카드에서 바로 정지·해제를 고른다.
    trainer_is_active: bool
    reason: ReportReason
    memo: str
    status: ReportStatus
    created_at: datetime
    resolved_at: datetime | None = None


class AdminReportCloseIn(BaseModel):
    """신고 처리 결과. `resolved` 는 조치함, `dismissed` 는 조치 없이 넘김."""

    outcome: Literal["resolved", "dismissed"]


class AdminTrainerOut(BaseModel):
    """운영 화면의 트레이너 한 명 — 검색·정지·해제에 쓴다."""

    trainer_id: str
    name: str
    email: str
    gym_name: str
    gym_address: str
    is_active: bool
    created_at: datetime | None
    #: 처리 전 신고 수.
    open_reports: int = 0


class AdminUserStatusOut(BaseModel):
    """계정 정지·해제 결과. (#3009)"""

    user_id: str
    role: str
    is_active: bool
    #: 이번 정지로 해제한 담당 회원 수. 해제·회원 계정은 0.
    released_clients: int = 0
