"""포인트 내역 — 무엇으로 얼마가 쌓이고 쓰였는가. (#2146)

원장(`points_ledger`)은 적립·사용·회수·반환을 한 줄씩 남긴다. 회원 앱에는 잔액만
보여서, 쿠폰·보호권·펫·주간 리포트에 쓴 포인트도, 기록을 지워 회수된 포인트도
확인할 곳이 없었다.

- **날짜 단위로 넘긴다.** 한 번에 최근 [PAGE_DAYS] 일치를 주고, 그 앞은 `before`
  (그 날짜보다 앞)로 이어 받는다. 줄 단위로 자르면 아래의 하루 묶음과 경계가
  어긋난다. 하루에 생기는 줄은 적립 한도와 사용처 수로 묶여 있어 한 번에 준다.
- **AI 코치 대화는 하루 한 줄로 묶는다**(#2145). 한 통마다 한 줄이면 내역이 채팅
  기록처럼 길어진다 — `count` 에 대화 수, `delta` 에 합계가 온다.
- 사유는 코드(`reason`)로 준다. 앱이 ko/en 문구로 바꾼다.
"""
from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.models import PointsLedger
from app.schemas.points_api import PointsHistoryItemOut, PointsHistoryOut
from app.services import ai_chat_quota_service, points_service

#: 한 번에 주는 날 수.
PAGE_DAYS = 14


def history(db: Session, user_id: str, *, before: str | None = None) -> PointsHistoryOut:
    """[before] 날짜(`YYYY-MM-DD`)보다 앞의 최근 [PAGE_DAYS] 일치 내역. 최신순."""
    days_q = (
        select(PointsLedger.kst_date)
        .where(PointsLedger.user_id == user_id)
        .group_by(PointsLedger.kst_date)
        .order_by(PointsLedger.kst_date.desc())
        .limit(PAGE_DAYS + 1)
    )
    if before:
        days_q = days_q.where(PointsLedger.kst_date < before)
    days = list(db.scalars(days_q).all())
    has_more = len(days) > PAGE_DAYS
    days = days[:PAGE_DAYS]
    rows = (
        db.scalars(
            select(PointsLedger)
            .where(PointsLedger.user_id == user_id, PointsLedger.kst_date.in_(days))
            .order_by(PointsLedger.created_at.desc(), PointsLedger.id.desc())
        ).all()
        if days
        else []
    )
    items: list[PointsHistoryItemOut] = []
    # 날짜 → 그날 AI 코치 대화 묶음. 그날의 가장 최근 대화 자리에 선다.
    chats: dict[str, PointsHistoryItemOut] = {}
    for row in rows:
        if (
            row.kind == "spend"
            and row.reason == ai_chat_quota_service.REASON_AI_CHAT
        ):
            grouped = chats.get(row.kst_date)
            if grouped is None:
                grouped = PointsHistoryItemOut(
                    id=row.id,
                    kind=row.kind,
                    reason=row.reason,
                    delta=0,
                    count=0,
                    kst_date=row.kst_date,
                    created_at=row.created_at,
                )
                chats[row.kst_date] = grouped
                items.append(grouped)
            grouped.delta += row.delta
            grouped.count += 1
            continue
        items.append(
            PointsHistoryItemOut(
                id=row.id,
                kind=row.kind,
                reason=row.reason,
                delta=row.delta,
                count=1,
                kst_date=row.kst_date,
                created_at=row.created_at,
            )
        )
    return PointsHistoryOut(
        balance=points_service.balance(db, user_id),
        items=items,
        next_before=days[-1] if has_more and days else None,
    )
