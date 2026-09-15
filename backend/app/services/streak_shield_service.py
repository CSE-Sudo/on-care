"""연속 기록 보호권 — 교환·사용·연속 일수 반영. (#1788)

하루를 놓쳐 연속 기록이 끊기는 순간이 PT 를 그만두는 계기가 되기 쉽다. 포인트로 산
보호권으로 운동을 못 한 하루를 연속 기록에 이어 붙인다.

규칙:

- **교환** 포인트 사용처에서 300P. 쓰지 않은 보호권은 최대 2장까지 가진다. 잔액 행을
  잠근 채 보유 개수와 잔액을 확인하므로, 같은 회원의 교환이 겹쳐도 한도를 넘지 않는다.
- **사용** 회원이 직접 한다. 보호할 수 있는 날은 **어제(KST)** 하나뿐이다 — 오늘이나
  그보다 오래된 날은 안 된다. 운동 기록이 있는 날은 보호하지 않는다. 하루에 보호는
  한 번이다. 가장 먼저 교환한 보호권부터 쓴다.
- **이번 주 안에서만** 동작한다. 연속 기록은 이번 주 안에서 운동한 날이 이어진 가장
  긴 구간이라, 오늘이 월요일이면 어제(지난 일요일)를 보호해도 이번 주 연속 일수는
  달라지지 않는다. 그런 날에 보호권을 쓰게 두면 포인트만 사라지므로 막는다.
- **집계** 보호한 날은 연속 일수를 셀 때만 운동한 날로 본다. 운동 시간·칼로리·횟수
  합계에는 넣지 않는다(`exercise_service.build_current_week`).
- 같은 날을 다시 보호하려는 요청(더블 클릭·재전송)은 보호권을 더 쓰지 않고 같은
  응답을 준다.
- **되돌리기** 보호한 날에 운동 기록이 생기면(직접 추가·수정, 루틴 완료, 트레이너
  PT 완료) 보호를 풀고 그 보호권을 `held` 로 돌린다. 최대 보유 수는 교환에만 걸려
  3개가 될 수 있다. 되돌린 뒤 기록을 지워도 보호는 다시 걸리지 않는다
  ([refund_for_exercise]).
- 트레이너 화면은 보호한 날을 세지도 보여 주지도 않는다.
"""
from __future__ import annotations

import uuid
from datetime import date, timedelta

from sqlalchemy import func, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core import clock
from app.models.models import ExerciseSession, StreakShield
from app.schemas.points_api import ExchangeOut
from app.schemas.streak_shield_api import (
    StreakShieldOut,
    StreakShieldsOut,
    StreakShieldUseOut,
    StreakShieldWeekOut,
)
from app.services import exercise_activity, points_service

#: 포인트 사용처의 항목 id — `points_coupon_service.CATALOG` 에 선다.
ITEM_ID = "streak_shield"
#: 한 장의 가격과 쓰지 않은 보호권의 최대 보유 수.
COST = 300
MAX_HELD = 2

#: 상태.
HELD = "held"
USED = "used"

#: 사용·반환 내역의 근거 — 교환한 보호권.
SOURCE_STREAK_SHIELD = "streak_shield"

#: 사용을 막는 이유.
BLOCK_NOT_YESTERDAY = "not_yesterday"
BLOCK_OUTSIDE_WEEK = "outside_week"
BLOCK_ALREADY_PROTECTED = "already_protected"
BLOCK_HAS_EXERCISE = "has_exercise"
BLOCK_NO_SHIELD = "no_shield"

_BLOCK_MESSAGES = {
    BLOCK_NOT_YESTERDAY: "어제만 보호할 수 있어요.",
    BLOCK_OUTSIDE_WEEK: "지난주 날짜는 이번 주 연속 기록에 이어지지 않아요.",
    BLOCK_ALREADY_PROTECTED: "이미 보호한 날이에요.",
    BLOCK_HAS_EXERCISE: "운동 기록이 있는 날은 보호하지 않아도 돼요.",
    BLOCK_NO_SHIELD: "보호권이 없어요.",
}

#: 내 혜택의 `사용한 날` 목록 상한. 보호한 날은 쌓이기만 하므로 응답 크기를 묶는다.
_USED_LIMIT = 100


class ShieldError(Exception):
    """보호권 규칙 위반. 라우터가 409 로 옮긴다."""


class ShieldLimitReached(ShieldError):
    """쓰지 않은 보호권을 이미 최대로 가지고 있다."""


class ShieldNotUsable(ShieldError):
    """이 날은 보호할 수 없다. [reason] 이 막힌 이유다."""

    def __init__(self, reason: str) -> None:
        super().__init__(_BLOCK_MESSAGES.get(reason, "보호할 수 없는 날이에요."))
        self.reason = reason


# ---- 조회 ----


def held_count(db: Session, member_id: str) -> int:
    """쓰지 않은 보호권 수."""
    return (
        db.scalar(
            select(func.count())
            .select_from(StreakShield)
            .where(StreakShield.user_id == member_id, StreakShield.status == HELD)
        )
        or 0
    )


def protected_days_of_week(db: Session, member_id: str, week_start: str) -> list[bool]:
    """[week_start](월요일) 주의 요일별 보호 여부 — 월=0 … 일=6."""
    monday = date.fromisoformat(week_start)
    sunday = monday + timedelta(days=6)
    dates = set(
        db.scalars(
            select(StreakShield.protected_on).where(
                StreakShield.user_id == member_id,
                StreakShield.protected_on >= monday.isoformat(),
                StreakShield.protected_on <= sunday.isoformat(),
            )
        ).all()
    )
    return [(monday + timedelta(days=i)).isoformat() in dates for i in range(7)]


def status(db: Session, member_id: str) -> StreakShieldsOut:
    """보유 개수와 보호한 날(최근 먼저). 내 혜택의 보호권 구역이 읽는다."""
    rows = db.scalars(
        select(StreakShield)
        .where(StreakShield.user_id == member_id, StreakShield.status == USED)
        .order_by(StreakShield.protected_on.desc(), StreakShield.id.desc())
        .limit(_USED_LIMIT)
    ).all()
    return StreakShieldsOut(
        held=held_count(db, member_id),
        max_held=MAX_HELD,
        cost=COST,
        used=[
            StreakShieldUseOut(date=row.protected_on or "", used_at=row.used_at)
            for row in rows
            if row.used_at is not None
        ],
    )


def week_state(db: Session, member_id: str) -> StreakShieldWeekOut:
    """이번 주 운동 현황에 싣는 상태 — 보유 수와 지금 보호할 수 있는 날."""
    held = held_count(db, member_id)
    yesterday = clock.today() - timedelta(days=1)
    protectable = (
        yesterday.isoformat()
        if held > 0 and _block_reason(db, member_id, yesterday) is None
        else None
    )
    return StreakShieldWeekOut(held=held, protectable_date=protectable)


# ---- 교환 ----


def exchange(
    db: Session, member_id: str, *, client_request_id: str | None = None
) -> ExchangeOut:
    """포인트를 써서 보호권 한 장을 받는다. 커밋한다.

    [client_request_id] 로 이미 받은 보호권이 있으면 새로 쓰지 않고 그 보호권을
    돌려준다. 최대 보유 수면 [ShieldLimitReached], 잔액이 모자라면
    [points_service.InsufficientPoints] 다.
    """
    if client_request_id:
        existing = _by_request(db, member_id, client_request_id)
        if existing is not None:
            return _exchange_out(db, member_id, existing)

    points_service.lock_balance(db, member_id)
    if held_count(db, member_id) >= MAX_HELD:
        db.rollback()
        raise ShieldLimitReached(f"보호권은 최대 {MAX_HELD}개까지 가질 수 있어요.")
    current = points_service.balance(db, member_id)
    if current < COST:
        db.rollback()
        raise points_service.InsufficientPoints(COST - current)

    shield = StreakShield(
        id=f"shd-{uuid.uuid4().hex[:12]}",
        user_id=member_id,
        cost=COST,
        status=HELD,
        client_request_id=client_request_id,
        acquired_at=clock.now(),
    )
    try:
        db.add(shield)
        db.flush()
        points_service.spend(
            db,
            member_id,
            reason=ITEM_ID,
            source_type=SOURCE_STREAK_SHIELD,
            source_id=shield.id,
            cost=COST,
        )
        db.commit()
    except IntegrityError:
        db.rollback()
        if client_request_id:
            existing = _by_request(db, member_id, client_request_id)
            if existing is not None:
                return _exchange_out(db, member_id, existing)
        raise
    db.refresh(shield)
    return _exchange_out(db, member_id, shield)


# ---- 사용 ----


def use(db: Session, member_id: str, day: date) -> StreakShieldsOut:
    """[day] 를 연속 기록에 이어 붙이고 보호권 한 장을 쓴다. 커밋한다.

    이미 보호한 날이면 보호권을 더 쓰지 않고 같은 응답이다. 규칙에 막히면
    [ShieldNotUsable] 이고 아무것도 쓰지 않는다.

    잔액 행을 먼저 잠근다 — 교환과 같은 순서라, 교환과 사용이 겹쳐도 보유 수를
    차례로 본다.
    """
    points_service.lock_balance(db, member_id)
    if _protected(db, member_id, day):
        db.commit()
        return status(db, member_id)
    reason = _block_reason(db, member_id, day)
    if reason is not None:
        db.rollback()
        raise ShieldNotUsable(reason)
    shield = db.scalar(
        select(StreakShield)
        .where(StreakShield.user_id == member_id, StreakShield.status == HELD)
        .order_by(StreakShield.acquired_at, StreakShield.id)
        .limit(1)
        .with_for_update()
    )
    if shield is None:
        db.rollback()
        raise ShieldNotUsable(BLOCK_NO_SHIELD)
    shield.status = USED
    shield.protected_on = day.isoformat()
    shield.used_at = clock.now()
    try:
        db.commit()
    except IntegrityError:
        # 같은 날을 보호한 요청이 먼저 커밋했다 — 그 결과가 곧 이 요청의 결과다.
        db.rollback()
        if _protected(db, member_id, day):
            return status(db, member_id)
        raise
    return status(db, member_id)


# ---- 되돌리기 ----


def refund_for_exercise(db: Session, member_id: str, day: date | None) -> bool:
    """[day] 에 운동 기록이 생기면 그날 쓴 보호권을 되돌린다. 커밋하지 않는다.

    운동한 날은 보호가 필요 없다 — 보호를 풀고 그 보호권을 다시 `held` 로 돌린다.
    기록을 만들거나 그날로 옮기는 모든 경로(회원 직접 추가·수정, AI 추천·배정 루틴
    완료, 트레이너 PT 완료)가 기록과 같은 트랜잭션에서 부른다. 되돌린 뒤 그 기록을
    지워도 보호는 다시 걸리지 않는다. 되돌렸으면 True.

    - 멱등이다. 보호한 날이 아니거나 이미 되돌렸으면 아무것도 하지 않는다.
    - 최대 보유 수(2개)는 **교환**의 규칙이라 여기서는 보지 않는다. 쓰지 않은
      보호권이 이미 2개인 회원도 되돌려 받아 3개가 될 수 있다 — 포인트를 내고 산
      것을 한도 때문에 없애면 안 되고, 2개를 넘는 동안은 사용처에서 더 교환하지
      못한다.
    - 잔액 행을 먼저 잠근다. 보호권 사용이 같은 행을 잠근 채 "그날 기록이 있나" 를
      보므로, 사용과 기록 저장이 겹쳐도 뒤에 온 쪽이 앞선 쪽의 커밋을 보고 판단한다
      (자정 무렵 완료 시각이 어제로 찍힌 루틴 완료가 보호보다 늦게 커밋되는 경우).
    """
    if day is None:
        return False
    points_service.lock_balance(db, member_id)
    result = db.execute(
        update(StreakShield)
        .where(
            StreakShield.user_id == member_id,
            StreakShield.protected_on == day.isoformat(),
            StreakShield.status == USED,
        )
        .values(status=HELD, protected_on=None, used_at=None)
        .execution_options(synchronize_session=False)
    )
    return result.rowcount > 0


# ---- 내부 ----


def _block_reason(db: Session, member_id: str, day: date) -> str | None:
    """[day] 를 지금 보호할 수 없는 이유. 보유 수는 보지 않는다."""
    today = clock.today()
    if day != today - timedelta(days=1):
        return BLOCK_NOT_YESTERDAY
    if _monday(day) != _monday(today):
        return BLOCK_OUTSIDE_WEEK
    if _protected(db, member_id, day):
        return BLOCK_ALREADY_PROTECTED
    if _has_exercise(db, member_id, day):
        return BLOCK_HAS_EXERCISE
    return None


def _monday(day: date) -> date:
    return day - timedelta(days=day.weekday())


def _protected(db: Session, member_id: str, day: date) -> bool:
    return (
        db.scalar(
            select(StreakShield.id).where(
                StreakShield.user_id == member_id,
                StreakShield.protected_on == day.isoformat(),
            )
        )
        is not None
    )


def _has_exercise(db: Session, member_id: str, day: date) -> bool:
    """그날 운동 기록이 있는가. 주간 집계와 같은 (주 시작, 요일) 로 찾는다."""
    return (
        db.scalar(
            select(ExerciseSession.id)
            .where(
                ExerciseSession.user_id == member_id,
                ExerciseSession.week_start == _monday(day).isoformat(),
                ExerciseSession.day_label
                == exercise_activity.WEEKDAY_LABELS[day.weekday()],
                ExerciseSession.minutes > 0,
            )
            .limit(1)
        )
        is not None
    )


def _by_request(
    db: Session, member_id: str, client_request_id: str
) -> StreakShield | None:
    return db.scalar(
        select(StreakShield).where(
            StreakShield.user_id == member_id,
            StreakShield.client_request_id == client_request_id,
        )
    )


def shield_out(row: StreakShield) -> StreakShieldOut:
    return StreakShieldOut(
        id=row.id,
        cost=row.cost,
        status=row.status,
        acquired_at=row.acquired_at,
        protected_on=row.protected_on,
        used_at=row.used_at,
    )


def _exchange_out(db: Session, member_id: str, row: StreakShield) -> ExchangeOut:
    return ExchangeOut(
        shield=shield_out(row),
        spent=row.cost,
        balance=points_service.balance(db, member_id),
    )
