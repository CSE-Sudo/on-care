"""회원이 받은 주간 리포트 — 회원 쪽 수신 기록을 읽는다. (#3348)

리포트 전송은 대화 메시지와 함께 수신 기록(`MemberReceivedReport`)을 남긴다
(`trainer.chat.send_message`). 대화는 보낸 트레이너가 탈퇴하면 CASCADE 로 사라지고,
회원 앱의 대화 조회는 지금의 담당 것만 준다. 수신 기록은 회원에게만 달려 있어
담당이 끊기거나 바뀌거나 트레이너가 탈퇴해도 남는다.

여기서 읽는 것은 세 가지다.

- **목록**(`GET /me/coach/reports`): 받은 리포트를 주별로, 최신 주부터.
- **받았는가**: 열람 판정(`weekly_report_access.received`)이 대화가 지워진 주를
  이 기록으로 확인한다.
- **굳힌 값**: 대화가 지워진 전송의 스냅샷(`report_snapshot_service`).
"""
from __future__ import annotations

from datetime import date, datetime

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.week import monday_of
from app.models.models import ChatMessage, MemberReceivedReport, User
from app.schemas.trainer_api import MemberReceivedReportOut, MemberReceivedReportsOut
from app.services.trainer import chat as trainer_chat_service
from app.services.trainer._common import _iso


def _sends_query(member_id: str):
    """이 회원의 수신 기록, 최신 전송이 먼저."""
    return (
        select(MemberReceivedReport)
        .where(MemberReceivedReport.member_id == member_id)
        .order_by(
            MemberReceivedReport.created_at.desc(), MemberReceivedReport.id.desc()
        )
    )


def received(db: Session, member_id: str, week: date) -> bool:
    """[week](월요일) 주 리포트를 받은 기록이 있는가. 누가 보냈는지는 가리지 않는다."""
    return (
        db.scalar(
            select(MemberReceivedReport.id)
            .where(
                MemberReceivedReport.member_id == member_id,
                MemberReceivedReport.week_start == week.isoformat(),
            )
            .limit(1)
        )
        is not None
    )


def latest_with_snapshot(
    db: Session,
    member_id: str,
    week: date,
    *,
    message_id: str | None = None,
    sent_from: datetime | None = None,
) -> MemberReceivedReport | None:
    """[week] 주를 굳힌 값과 함께 받은 가장 최근 기록. 없으면 None.

    [message_id] 를 주면 그 전송만 본다. [sent_from] 을 주면 그 시각부터 보낸
    것만 본다 — `report_snapshot_service.member_snapshot` 이 대화 메시지에 거는
    조건과 같다.
    """
    query = _sends_query(member_id).where(
        MemberReceivedReport.week_start == week.isoformat(),
        MemberReceivedReport.report_snapshot_json.is_not(None),
    )
    if message_id:
        query = query.where(MemberReceivedReport.id == message_id)
    if sent_from is not None:
        query = query.where(MemberReceivedReport.created_at >= sent_from)
    return db.scalars(query.limit(1)).first()


def list_received(
    db: Session, member_id: str, *, limit: int, before: date | None = None
) -> MemberReceivedReportsOut:
    """[member_id] 가 받은 리포트를 주별로, 최신 주부터.

    한 주를 여러 번 받았으면 **가장 최근 것 하나**만 싣는다 — 회원이 받은 것은
    마지막 글이고, 같은 주가 두 줄로 서면 어느 것을 열지 알 수 없다. 트레이너
    화면의 회원별 전송 목록(`list_member_report_sends`)과 접는 규칙·쪽 나눔이
    같다: 쪽은 **주** 단위이고 커서는 주 시작일 하나(`before`, 그 주 제외)다.

    보낸 트레이너가 지금의 담당인지는 묻지 않는다. 이름은 계정이 남아 있을 때만
    싣고, PDF 는 그 대화 메시지가 남아 있을 때만 싣는다.
    """
    week_q = (
        select(MemberReceivedReport.week_start)
        .where(MemberReceivedReport.member_id == member_id)
        .group_by(MemberReceivedReport.week_start)
        .order_by(MemberReceivedReport.week_start.desc())
        .limit(limit + 1)
    )
    if before is not None:
        # 저장값이 `YYYY-MM-DD` 라 문자열 비교가 곧 날짜 비교다.
        week_q = week_q.where(
            MemberReceivedReport.week_start < monday_of(before).isoformat()
        )
    weeks = [w for w in db.scalars(week_q).all() if w]
    has_more = len(weeks) > limit
    weeks = weeks[:limit]
    if not weeks:
        return MemberReceivedReportsOut()

    latest: dict[str, MemberReceivedReport] = {}
    for row in db.scalars(
        _sends_query(member_id).where(MemberReceivedReport.week_start.in_(weeks))
    ):
        # 최신순으로 오므로 주마다 처음 만난 것이 가장 최근 전송이다.
        latest.setdefault(row.week_start, row)

    picked = list(latest.values())
    trainer_ids = {r.trainer_id for r in picked if r.trainer_id}
    names: dict[str, str] = {}
    if trainer_ids:
        names = {
            user_id: name
            for user_id, name in db.execute(
                select(User.id, User.name).where(User.id.in_(trainer_ids))
            )
        }
    messages = {
        m.id: m
        for m in db.scalars(
            select(ChatMessage).where(
                ChatMessage.id.in_([r.id for r in picked]),
                # id 가 같아도 남의 대화면 싣지 않는다 — 수신 기록의 id 는 FK 가
                # 아니다.
                ChatMessage.member_id == member_id,
            )
        )
    }
    reports: list[MemberReceivedReportOut] = []
    for week in weeks:
        row = latest[week]
        message = messages.get(row.id)
        attachment = (
            trainer_chat_service.chat_attachment_out(message)
            if message is not None
            else None
        )
        reports.append(
            MemberReceivedReportOut(
                id=row.id,
                week_start=week,
                sent_at=_iso(row.created_at),
                trainer_name=names.get(row.trainer_id or "") or None,
                body=row.body,
                # 리포트 전송에는 PDF 만 붙는다. 다른 종류가 와도 리포트 파일은
                # 아니다.
                attachment=(
                    attachment
                    if attachment is not None and attachment.type == "pdf"
                    else None
                ),
            )
        )
    return MemberReceivedReportsOut(
        reports=reports, next_before=weeks[-1] if has_more else None
    )
