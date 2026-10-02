"""회원 한 명과 주고받은 피드백 모아 보기. (#2615)

회원 메모는 트레이너만 보는 글이고, 피드백은 상대에게 보이는 글이다(#2574).
피드백은 출처마다 따로 산다 — PT 세션 피드백은 스케줄 일정 하나씩, 보낸
리포트는 리포트 화면 주 단위, 회원 주간 피드백은 회원 행 주 단위. 회원 상세
메모 창의 `피드백` 탭이 이 셋을 한 목록으로 읽는다.

읽기 전용이다. 고치는 곳이 둘이 되면 어느 쪽이 최신인지 알 수 없어(#1011 과
같은 이유) 항목마다 원래 자리로 가는 값만 싣는다.
"""
from __future__ import annotations

from datetime import date, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core import clock
from app.core.week import monday_of
from app.models.models import (
    ChatMessage,
    MemberWeeklyFeedback,
    TrainerClient,
    TrainerSchedule,
)
from app.schemas.trainer_api import ClientFeedbackOut
from app.services.trainer_routine_options_service import CONSULT_SCHEDULE_TYPE

#: 얼마나 거슬러 올라가 읽는가. 회원 상세에서 "지난달에 뭐라고 했지" 를 찾는
#: 자리라 한 달보다 넉넉히 잡는다.
FEEDBACK_LOOKBACK_DAYS = 90

#: 한 번에 내려주는 최대 건수. 세 출처를 합친 뒤 최신순으로 자른다.
FEEDBACK_LIMIT = 100


def build_client_feedbacks(
    db: Session,
    trainer_id: str,
    link: TrainerClient,
    *,
    today: date | None = None,
) -> list[ClientFeedbackOut]:
    """[link] 회원과 주고받은 피드백, 최신 먼저.

    - PT 세션 피드백: **내가** 지도한 완료 PT(상담 제외)의 `note`
    - 보낸 리포트: **내가** 보낸 리포트 메시지, 주마다 가장 최근 전송 하나
    - 회원 주간 피드백: 이 담당이 시작된 주(`data_consent_at`)부터 — 담당이
      바뀐 회원이 이전 트레이너에게 쓴 피드백은 뺀다(AI 추천 #2587 과 같은 규칙)

    담당 확인은 라우터가 `_require_client` 로 먼저 한다.
    """
    today = today or clock.today()
    since = today - timedelta(days=FEEDBACK_LOOKBACK_DAYS - 1)
    member_id = link.member_id
    items: list[ClientFeedbackOut] = []
    items.extend(_pt_feedbacks(db, trainer_id, member_id, since, today))
    items.extend(_report_feedbacks(db, trainer_id, member_id, since))
    items.extend(_weekly_feedbacks(db, link, since))
    # 날짜가 같으면 PT → 리포트 → 주간 피드백 순으로, 흔들림 없이 둔다.
    order = {"pt_session": 0, "report": 1, "weekly": 2}
    items.sort(key=lambda item: (item.date, -order[item.kind], item.id), reverse=True)
    return items[:FEEDBACK_LIMIT]


def _pt_feedbacks(
    db: Session, trainer_id: str, member_id: str, since: date, today: date
) -> list[ClientFeedbackOut]:
    rows = db.scalars(
        select(TrainerSchedule)
        .where(
            TrainerSchedule.trainer_id == trainer_id,
            TrainerSchedule.member_id == member_id,
            TrainerSchedule.type != CONSULT_SCHEDULE_TYPE,
            TrainerSchedule.status == "완료",
            TrainerSchedule.note != "",
            # 날짜가 `YYYY-MM-DD` 문자열이라 사전순 비교가 곧 날짜 비교다.
            TrainerSchedule.date >= since.isoformat(),
            TrainerSchedule.date <= today.isoformat(),
        )
        .order_by(TrainerSchedule.date.desc(), TrainerSchedule.time.desc())
        .limit(FEEDBACK_LIMIT)
    ).all()
    return [
        ClientFeedbackOut(
            id=f"pt_session:{row.id}",
            kind="pt_session",
            direction="to_member",
            date=row.date,
            body=row.note.strip(),
            schedule_id=row.id,
        )
        for row in rows
        if row.note.strip()
    ]


def _report_feedbacks(
    db: Session, trainer_id: str, member_id: str, since: date
) -> list[ClientFeedbackOut]:
    rows = db.scalars(
        select(ChatMessage)
        .where(
            ChatMessage.trainer_id == trainer_id,
            ChatMessage.member_id == member_id,
            ChatMessage.sender == "trainer",
            ChatMessage.report_week_start.is_not(None),
            ChatMessage.report_week_start >= _monday(since).isoformat(),
        )
        .order_by(ChatMessage.created_at.desc(), ChatMessage.id.desc())
        .limit(FEEDBACK_LIMIT * 2)
    ).all()
    # 한 주에 여러 번 보냈으면 가장 최근 것 하나 — 회원별 지난 리포트 목록(#2393)과
    # 같은 접기다. 회원이 마지막으로 받은 글이 그 주의 피드백이다.
    latest: dict[str, ChatMessage] = {}
    for row in rows:
        latest.setdefault(row.report_week_start, row)
    return [
        ClientFeedbackOut(
            id=f"report:{week}",
            kind="report",
            direction="to_member",
            date=week,
            body=(msg.body or "").strip(),
            week_start=week,
            at=msg.created_at,
        )
        for week, msg in latest.items()
    ]


def _weekly_feedbacks(
    db: Session, link: TrainerClient, since: date
) -> list[ClientFeedbackOut]:
    first_week = _monday(since)
    if link.data_consent_at is not None:
        started = link.data_consent_at.astimezone(clock.SEOUL).date()
        first_week = max(first_week, _monday(started))
    rows = db.scalars(
        select(MemberWeeklyFeedback)
        .where(
            MemberWeeklyFeedback.user_id == link.member_id,
            MemberWeeklyFeedback.week_start >= first_week.isoformat(),
        )
        .order_by(MemberWeeklyFeedback.week_start.desc())
        .limit(FEEDBACK_LIMIT)
    ).all()
    return [
        ClientFeedbackOut(
            id=f"weekly:{row.week_start}",
            kind="weekly",
            direction="from_member",
            date=row.week_start,
            body=(row.note or "").strip(),
            week_start=row.week_start,
            at=row.updated_at or row.created_at,
            condition=row.condition or "",
            intensity=row.intensity or "",
            pain_area=row.pain_area or "",
            pain_on=row.pain_on or "",
        )
        for row in rows
    ]


def _monday(day: date) -> date:
    return monday_of(day)
