"""회원이 열 수 있는 주간 리포트 — 받았거나 산 주만. (#3366)

주간 리포트는 트레이너가 보내 주거나(#1600) 회원이 포인트로 사야(#2022) 보는
것이다. 예전에는 `GET /me/coach/weekly-report` 가 이를 확인하지 않아, 잠금이 앱
화면에만 걸려 있었다 — 경로를 직접 부르면 사지 않은 주도 읽혔다.

- **받은 주**: 트레이너가 리포트를 보내며 대화에 남긴 안내(`ChatMessage.
  report_week_start`)가 근거다. 트레이너 화면의 전송 기록(#2288)과 같은 값이다.
  **보낸 트레이너가 지금의 담당인지는 묻지 않는다** — 담당이 바뀌거나 끊긴 뒤에도
  이미 받은 리포트는 회원의 것이다(#3347). 대화는 보낸 트레이너가 탈퇴하면 함께
  사라지므로, 회원 쪽에 남는 수신 기록(`MemberReceivedReport`, #3348)도 함께 본다.
- **산 주**: `WeeklyReportPurchase` 한 행(`weekly_report_purchase_service.owns`).
- 결과지는 그 주와 함께 직전 넉 주를 읽어 `4주 평균 대비` 를 그린다. 열 수 있는
  주를 그리는 데 필요한 직전 주는 **비교에 쓰는 수치만**([comparison_only]) 준다 —
  통째로 주면 한 주를 사서 다섯 주를 읽는 길이 된다.
"""
from __future__ import annotations

from datetime import date, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.models import ChatMessage
from app.schemas.trainer_api import WeeklyReportOut
from app.services import received_reports, weekly_report_purchase_service

#: 결과지가 견주는 직전 주 수 — 앱의 `kReportSheetHistoryWeeks` 와 같다.
COMPARISON_WEEKS = 4


def received(db: Session, member_id: str, week: date) -> bool:
    """트레이너가 [week] 주 리포트를 이 회원에게 보낸 적이 있는가.

    본문 전송과 PDF 전송 모두 `report_week_start` 를 남긴다. 어느 트레이너가
    보냈는지는 가리지 않는다. 대화가 지워졌으면(보낸 트레이너의 탈퇴) 수신
    기록이 근거다(#3348).
    """
    if received_reports.received(db, member_id, week):
        return True
    return (
        db.scalar(
            select(ChatMessage.id)
            .where(
                ChatMessage.member_id == member_id,
                ChatMessage.sender == "trainer",
                ChatMessage.report_week_start == week.isoformat(),
            )
            .limit(1)
        )
        is not None
    )


def can_open(db: Session, member_id: str, week: date) -> bool:
    """[week](월요일) 주 리포트를 회원이 열 수 있는가 — 받았거나 샀다."""
    return received(db, member_id, week) or weekly_report_purchase_service.owns(
        db, member_id, week
    )


def is_comparison_week(week: date, target: date) -> bool:
    """[week] 가 [target] 주 결과지의 비교 칸이 읽는 직전 주인가. 둘 다 월요일."""
    return week in {
        target - timedelta(weeks=back) for back in range(1, COMPARISON_WEEKS + 1)
    }


def comparison_only(report: WeeklyReportOut) -> WeeklyReportOut:
    """리포트에서 `4주 평균 대비` 가 읽는 값만 남긴다.

    비교 칸은 직전 주들의 칼로리(기록한 날 평균)·이행률 평균·나트륨 평균·끼니
    기록일을 쓴다. 나머지(요일별 운동 내역·영양 계열·목표·PT 횟수)는 그 주를
    열어야 보는 내용이라 비운다.
    """
    return WeeklyReportOut(
        member_id=report.member_id,
        member_name=report.member_name,
        week_start=report.week_start,
        week_end=report.week_end,
        sessions_booked=0,
        sessions_done=0,
        completion_avg=report.completion_avg,
        sodium_over_days=0,
        sodium_avg=report.sodium_avg,
        calories_week=report.calories_week,
        meal_counts=report.meal_counts,
        message="",
    )
