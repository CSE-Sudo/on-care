"""포인트로 받은 주간 리포트 응답. (#2022)"""
from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel


class WeeklyReportPurchaseOut(BaseModel):
    """산 주 하나. 리포트 내용은 앱이 회원 기록으로 세운다."""

    #: 그 주 월요일 `YYYY-MM-DD`(KST).
    week_start: str
    purchased_at: datetime


class WeeklyReportListOut(BaseModel):
    """GET /me/weekly-reports — 산 주(최근 주 먼저)와 지금 살 수 있는 주."""

    reports: list[WeeklyReportPurchaseOut]
    #: 지금 교환하면 받는 주(지난주 월요일). 사용처 카드가 기간을 적는다.
    next_week_start: str
    cost: int
