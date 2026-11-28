"""포인트로 받은 주간 리포트 응답. (#2022)"""
from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel


class WeeklyReportInsightOut(BaseModel):
    """살 때 그 주에 있던 감지 한 건. (#3349)

    `GET /ai-coach/insights` 의 한 줄에서 문장(`text`)과 메시지 id 를 뺀 것이다 —
    리포트는 종류별 횟수만 적는다.
    """

    kind: str
    body_part: str | None = None
    created_at: datetime


class WeeklyReportPurchaseOut(BaseModel):
    """산 주 하나. 리포트는 앱이 세우되 재료는 살 때의 값이다(#3349)."""

    #: 그 주 월요일 `YYYY-MM-DD`(KST).
    week_start: str
    purchased_at: datetime
    #: 살 때 그 주에 있던 감지 기록(오래된 것 먼저). 빈 목록은 "감지가 없었다",
    #: null 은 "남겨 둔 것이 없다" 다(#3349 전에 산 주) — 앱이 `GET
    #: /ai-coach/insights` 로 되돌아가되, 그 창(30일) 밖의 주는 칸을 비운다.
    insights: list[WeeklyReportInsightOut] | None = None


class WeeklyReportListOut(BaseModel):
    """GET /me/weekly-reports — 산 주(최근 주 먼저)와 지금 살 수 있는 주."""

    reports: list[WeeklyReportPurchaseOut]
    #: 지금 교환하면 받는 주(지난주 월요일). 사용처 카드가 기간을 적는다.
    next_week_start: str
    cost: int
