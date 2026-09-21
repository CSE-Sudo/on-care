"""포인트로 받는 주간 리포트 — 담당 트레이너가 없는 회원의 한 주 돌아보기. (#2022)

주간 리포트는 트레이너가 등록해 주는 것이라 **담당이 없는 회원은 받을 길이 없었다.**
AI 코치만 쓰는 회원에게 한 주를 돌아보는 자리를 포인트 교환으로 연다.

- **담당이 없는 회원만** 산다. 담당이 있으면 트레이너가 등록해 주므로 살 이유가 없다 —
  사용처 목록에서 항목이 빠지고, 교환도 막는다([TrainerAssigned]).
- 사는 주는 **지난주**(가장 최근에 끝난 KST 월~일)다. 진행 중인 주는 기록이 반쯤이라
  돌아보기에 맞지 않고, 트레이너도 끝난 주를 등록한다.
- **같은 주는 한 번만** 산다([WeekAlreadyOwned], `uq_weekly_report_purchase_week`).
- 리포트 내용은 저장하지 않는다. 앱이 회원이 쌓은 식단·운동 기록과 감지 기록으로
  세우고, 트레이너 리포트와 같은 문서로 연다. 트레이너 코멘트 자리는 비운다.
  여기에는 어느 주를 샀는지만 남는다.
- 산 뒤에 담당이 생겨도 산 리포트는 그대로 본다 — 회원 자신의 기록이다.
"""
from __future__ import annotations

import uuid
from datetime import date, timedelta

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core import clock
from app.models.models import WeeklyReportPurchase
from app.schemas.points_api import ExchangeOut
from app.schemas.weekly_report_api import (
    WeeklyReportListOut,
    WeeklyReportPurchaseOut,
)
from app.services import points_service

#: 포인트 사용처의 항목 id — `points_coupon_service.CATALOG` 에 선다.
ITEM_ID = "weekly_report"
SOURCE_WEEKLY_REPORT = "weekly_report"

COST = 300

#: 목록 상한. 한 주에 하나라 1년치면 충분하다.
_LIST_LIMIT = 60


class WeeklyReportError(Exception):
    """주간 리포트 교환 규칙 위반. 라우터가 상태코드로 옮긴다."""


class TrainerAssigned(WeeklyReportError):
    """담당 트레이너가 있다 — 리포트는 트레이너가 등록해 준다."""


class WeekAlreadyOwned(WeeklyReportError):
    """이 주의 리포트는 이미 받았다."""


def target_week(today: date | None = None) -> date:
    """지금 교환하면 받는 주 — 지난주 월요일(KST)."""
    day = today or clock.today()
    return day - timedelta(days=day.weekday() + 7)


def owns(db: Session, member_id: str, week_start: date) -> bool:
    return (
        db.scalar(
            select(WeeklyReportPurchase.id).where(
                WeeklyReportPurchase.user_id == member_id,
                WeeklyReportPurchase.week_start == week_start.isoformat(),
            )
        )
        is not None
    )


def list_reports(db: Session, member_id: str) -> WeeklyReportListOut:
    """산 주(최근 주 먼저)와 지금 살 수 있는 주."""
    rows = db.scalars(
        select(WeeklyReportPurchase)
        .where(WeeklyReportPurchase.user_id == member_id)
        .order_by(WeeklyReportPurchase.week_start.desc())
        .limit(_LIST_LIMIT)
    ).all()
    return WeeklyReportListOut(
        reports=[
            WeeklyReportPurchaseOut(
                week_start=row.week_start, purchased_at=row.created_at
            )
            for row in rows
        ],
        next_week_start=target_week().isoformat(),
        cost=COST,
    )


def exchange(
    db: Session,
    member_id: str,
    *,
    client_request_id: str | None = None,
) -> ExchangeOut:
    """포인트를 써서 지난주 리포트를 받는다. 커밋한다.

    [client_request_id] 가 같은 재시도는 두 번 쓰지 않는다. 담당이 있으면
    [TrainerAssigned], 이미 받은 주면 [WeekAlreadyOwned], 잔액이 모자라면
    [points_service.InsufficientPoints] 다.
    """
    from app.services import trainer_service

    if client_request_id and _by_request(db, member_id, client_request_id):
        return _exchange_out(db, member_id)
    if trainer_service.get_member_trainer_id(db, member_id) is not None:
        raise TrainerAssigned("담당 트레이너가 리포트를 등록해 줘요.")

    week = target_week()
    points_service.lock_balance(db, member_id)
    if owns(db, member_id, week):
        db.rollback()
        raise WeekAlreadyOwned("이 주의 리포트는 이미 받았어요.")
    current = points_service.balance(db, member_id)
    if current < COST:
        db.rollback()
        raise points_service.InsufficientPoints(COST - current)

    row = WeeklyReportPurchase(
        id=f"wrp-{uuid.uuid4().hex[:12]}",
        user_id=member_id,
        week_start=week.isoformat(),
        cost=COST,
        client_request_id=client_request_id,
    )
    try:
        db.add(row)
        db.flush()
        points_service.spend(
            db,
            member_id,
            reason=ITEM_ID,
            source_type=SOURCE_WEEKLY_REPORT,
            source_id=row.id,
            cost=COST,
        )
        db.commit()
    except IntegrityError:
        db.rollback()
        if client_request_id and _by_request(db, member_id, client_request_id):
            return _exchange_out(db, member_id)
        if owns(db, member_id, week):
            raise WeekAlreadyOwned("이 주의 리포트는 이미 받았어요.") from None
        raise
    return _exchange_out(db, member_id, week)


def _by_request(
    db: Session, member_id: str, client_request_id: str
) -> WeeklyReportPurchase | None:
    return db.scalar(
        select(WeeklyReportPurchase).where(
            WeeklyReportPurchase.user_id == member_id,
            WeeklyReportPurchase.client_request_id == client_request_id,
        )
    )


def _exchange_out(
    db: Session, member_id: str, week: date | None = None
) -> ExchangeOut:
    return ExchangeOut(
        weekly_report_week=(week or target_week()).isoformat(),
        spent=COST,
        balance=points_service.balance(db, member_id),
    )
