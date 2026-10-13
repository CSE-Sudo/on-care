"""주간 리포트 스냅샷 — 보내거나 산 시점의 내용을 고정한다. (#3349)

트레이너가 글로 보낸 리포트와 포인트로 받은 리포트는 수치를 저장하지 않고 회원이
열 때마다 `build_weekly_report` 로 다시 계산했다. 그래서 같은 리포트가 여는 날에
따라 달라졌다.

- 보낸 뒤 회원이 그 주 식단·운동을 고치면 값이 바뀐다.
- 건강 목표를 바꾸면 지난 리포트의 부족·초과 판정이 뒤집힌다.
- 진행 중인 주를 보낸 리포트는 날마다 달라진다.
- 구매 리포트의 감지 기록은 최근 30일 대화에서 계산해, 한 달 뒤에는 사라진다.

PDF 로 보낸 리포트는 파일이라 처음부터 고정이었다. 여기서는 나머지 길도 같게
만든다 — 전송 메시지와 구매 기록에 그때의 값을 남기고, 회원 조회가 그것을 먼저
읽는다. 스냅샷이 없는 옛 리포트는 소급해 채우지 않고 지금처럼 다시 계산한다.

남기는 것은 **회원이 읽는 값**이다. PT 횟수·이행률을 회원 기준으로 세고(#3347)
트레이너의 자동 초안(`message`)은 비운다 — `GET /me/coach/weekly-report` 가 주던
모양 그대로다.
"""
from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import date, datetime, timedelta

from pydantic import ValidationError
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core import clock
from app.core.week import monday_of
from app.models.models import ChatMessage, WeeklyReportPurchase
from app.schemas.trainer_api import WeeklyReportOut
from app.schemas.weekly_report_api import WeeklyReportInsightOut
from app.services.coach import insights
from app.services.trainer import _common as trainer_common_service
from app.services.trainer import reports as trainer_reports_service


@dataclass(frozen=True)
class MemberReportSnapshot:
    """고정된 리포트 한 주와 그것을 남긴 시각."""

    report: WeeklyReportOut
    taken_at: datetime


def build_report_snapshot(
    db: Session, member_id: str, week_start: date, *, trainer_id: str | None = None
) -> str:
    """지금 회원이 읽을 [week_start] 주 리포트를 JSON 으로 굳힌다.

    [trainer_id] 를 주지 않으면 지금의 담당을 찾는다(없으면 빈 값). 회원 기준으로
    세므로 담당이 누구인지는 값을 바꾸지 않는다.
    """
    owner = trainer_id
    if owner is None:
        owner = trainer_common_service.get_member_trainer_id(db, member_id) or ""
    report = trainer_reports_service.build_weekly_report(
        db, owner, member_id, week_start, member_scope=True
    )
    return report.model_copy(update={"message": ""}).model_dump_json()


def build_insights_snapshot(
    db: Session, member_id: str, week_start: date, *, now: datetime | None = None
) -> str:
    """[week_start] 주(KST 월~일)의 감지 기록을 JSON 목록으로 굳힌다. 오래된 것 먼저.

    회원이 쓴 문장은 남기지 않는다 — 리포트가 적는 것은 종류별 횟수뿐이고, 문장은
    대화에 이미 있다. 감지가 없던 주는 빈 목록(`[]`)이다.
    """
    monday = monday_of(week_start)
    sunday = monday + timedelta(days=6)
    rows = [
        r
        for r in insights.recent_insights(db, member_id, now=now)
        if monday <= clock.to_seoul(r.created_at).date() <= sunday
    ]
    rows.sort(key=lambda r: r.created_at)
    return json.dumps(
        [
            {
                "kind": r.kind,
                "body_part": r.body_part,
                "created_at": r.created_at.isoformat(),
            }
            for r in rows
        ],
        ensure_ascii=False,
    )


def read_insights(raw: str | None) -> list[WeeklyReportInsightOut] | None:
    """구매 기록의 감지 스냅샷. 남긴 것이 없거나 읽을 수 없으면 None.

    None 과 빈 목록은 다르다 — None 은 "모른다" 이고 빈 목록은 "그 주에 감지가
    없었다" 다.
    """
    if raw is None:
        return None
    try:
        rows = json.loads(raw)
        if not isinstance(rows, list):
            return None
        return [WeeklyReportInsightOut.model_validate(row) for row in rows]
    except (ValueError, ValidationError):
        return None


def member_snapshot(
    db: Session, member_id: str, week_start: date, *, message_id: str | None = None
) -> MemberReportSnapshot | None:
    """회원이 [week_start] 주를 열 때 읽을 스냅샷. 없으면 None(다시 계산한다).

    고르는 순서:

    1. [message_id] 가 가리키는 리포트 전송 — 같은 주를 두 번 보냈어도 회원이 누른
       그 전송의 값이 열린다.
    2. 그 주를 포인트로 산 기록.
    3. 그 주를 실어 보낸 전송 중 **그 주가 끝난 뒤에 보낸** 가장 최근 것 — 결과지가
       견주는 직전 주들도 회원이 받았던 값으로 선다. 진행 중에 굳힌 값은 여기서
       쓰지 않는다: 수요일까지의 값이 그 주 전체인 것처럼 직전 주 비교에 들어간다.
       그 값은 1 처럼 그 전송을 직접 열 때만 읽는다.

    스냅샷이 없는 옛 전송을 가리키면 2·3 으로 내려간다. 저장된 값이 지금의
    응답 모양으로 읽히지 않으면 없는 것으로 친다 — 깨진 한 줄 때문에 리포트가
    열리지 않으면 안 된다.
    """
    monday = monday_of(week_start)
    week_iso = monday.isoformat()
    sent = (
        select(ChatMessage)
        .where(
            ChatMessage.member_id == member_id,
            ChatMessage.sender == "trainer",
            ChatMessage.report_week_start == week_iso,
            ChatMessage.report_snapshot_json.is_not(None),
        )
        .order_by(ChatMessage.created_at.desc(), ChatMessage.id.desc())
        .limit(1)
    )
    if message_id:
        picked = db.scalars(sent.where(ChatMessage.id == message_id)).first()
        found = _message_snapshot(picked)
        if found is not None:
            return found

    purchase = db.scalars(
        select(WeeklyReportPurchase).where(
            WeeklyReportPurchase.user_id == member_id,
            WeeklyReportPurchase.week_start == week_iso,
            WeeklyReportPurchase.report_snapshot_json.is_not(None),
        )
    ).first()
    if purchase is not None:
        report = _read_report(purchase.report_snapshot_json)
        if report is not None:
            return MemberReportSnapshot(report=report, taken_at=purchase.created_at)

    next_monday = monday + timedelta(days=7)
    week_over = datetime(
        next_monday.year, next_monday.month, next_monday.day, tzinfo=clock.SEOUL
    )
    return _message_snapshot(
        db.scalars(sent.where(ChatMessage.created_at >= week_over)).first()
    )


def _message_snapshot(msg: ChatMessage | None) -> MemberReportSnapshot | None:
    if msg is None:
        return None
    report = _read_report(msg.report_snapshot_json)
    if report is None:
        return None
    return MemberReportSnapshot(report=report, taken_at=msg.created_at)


def _read_report(raw: str | None) -> WeeklyReportOut | None:
    if raw is None:
        return None
    try:
        return WeeklyReportOut.model_validate_json(raw)
    except (ValueError, ValidationError):
        return None
