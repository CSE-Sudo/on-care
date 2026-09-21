"""연속 기록 보호권 — 교환·사용·연속 일수 반영. (#1788)

하루를 놓쳐 연속 기록이 끊기는 순간이 PT 를 그만두는 계기가 되기 쉽다. 포인트로 산
보호권으로 아무것도 기록하지 못한 하루를 연속 기록에 이어 붙인다.

**기록 연속은 운동 연속과 다른 값이다.** 기록 연속은 식단 한 끼든 운동 한 건이든
남긴 날이 이어진 길이다(`record_activity`). 운동 탭의 `N일 연속 운동`
(`exercise_service._longest_streak`)은 운동만 세고 보호한 날도 넣지 않는다 —
보호권은 운동 연속을 건드리지 않는다.

규칙:

- **교환** 포인트 사용처에서 300P. 쓰지 않은 보호권은 최대 4장까지 가진다. 잔액 행을
  잠근 채 보유 개수와 잔액을 확인하므로, 같은 회원의 교환이 겹쳐도 한도를 넘지 않는다.
- **사용** 회원이 직접 한다. 보호할 수 있는 날은 **어제부터 거슬러 [PROTECT_WINDOW_DAYS]
  일(KST)** 안의 날이다 — 오늘과 그보다 오래된 날은 안 된다. 기록 그래프(#2075)에서 빈
  날을 눌러 쓰므로 어제 하나만 열어 두면 "어제를 놓친 뒤에야 산 보호권" 은 쓸 데가
  없다. 창을 30일로 묶는 이유는, 무제한이면 몇 달 전 기록까지 칠해 연속 숫자의 뜻이
  가벼워지기 때문이다. 식단이든 운동이든 기록이 있는 날은 보호하지 않는다.
  하루에 보호는 한 번이다. 가장 먼저 교환한 보호권부터 쓴다.
- **주 경계를 보지 않는다.** 기록 연속은 주 단위가 아니라 날짜를 거슬러 이어지므로,
  오늘이 월요일이어도 어제(일요일)를 보호하면 연속이 이어진다.
- **집계** 보호한 날은 기록 연속을 셀 때만 기록한 날로 본다. 운동 시간·칼로리·횟수
  합계에도, 운동 탭의 연속 일수에도 넣지 않는다.
- 같은 날을 다시 보호하려는 요청(더블 클릭·재전송)은 보호권을 더 쓰지 않고 같은
  응답을 준다.
- **되돌리기** 보호한 날에 기록이 생기면(식단 저장·수정, 운동 직접 추가·수정, 루틴
  완료, 트레이너 PT 완료) 보호를 풀고 그 보호권을 `held` 로 돌린다. 최대 보유 수는 교환에만 걸려
  3개가 될 수 있다. 되돌린 뒤 기록을 지워도 보호는 다시 걸리지 않는다
  ([refund_for_record]).
- 트레이너 화면은 보호한 날을 세지도 보여 주지도 않는다.
"""
from __future__ import annotations

import uuid
from datetime import date, timedelta

from sqlalchemy import func, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core import clock
from app.models.models import StreakShield
from app.schemas.points_api import ExchangeOut
from app.schemas.streak_shield_api import (
    StreakShieldOut,
    StreakShieldsOut,
    StreakShieldUseOut,
)
from app.services import points_service, record_activity

#: 포인트 사용처의 항목 id — `points_coupon_service.CATALOG` 에 선다.
ITEM_ID = "streak_shield"
#: 한 장의 가격과 쓰지 않은 보호권의 최대 보유 수.
COST = 300
MAX_HELD = 4

#: 상태.
HELD = "held"
USED = "used"

#: 사용·반환 내역의 근거 — 교환한 보호권.
SOURCE_STREAK_SHIELD = "streak_shield"

#: 보호할 수 있는 창 — 어제부터 거슬러 이만큼(오늘은 들지 않는다).
PROTECT_WINDOW_DAYS = 30

#: 사용을 막는 이유.
BLOCK_OUT_OF_WINDOW = "out_of_window"
BLOCK_ALREADY_PROTECTED = "already_protected"
BLOCK_HAS_RECORD = "has_record"
BLOCK_NO_SHIELD = "no_shield"

_BLOCK_MESSAGES = {
    BLOCK_OUT_OF_WINDOW: f"최근 {PROTECT_WINDOW_DAYS}일 안의 날만 보호할 수 있어요.",
    BLOCK_ALREADY_PROTECTED: "이미 보호한 날이에요.",
    BLOCK_HAS_RECORD: "기록이 있는 날은 보호하지 않아도 돼요.",
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


def status(db: Session, member_id: str) -> StreakShieldsOut:
    """보유 개수·보호한 날(최근 먼저)·기록 연속 일수·지금 보호할 수 있는 날.

    내 혜택의 보호권 구역과, 보호권을 쓰는 화면(#2075 포인트 화면 기록 그래프)이
    이 하나를 읽는다. 운동 주간 응답에는 보호권이 실리지 않는다 — 운동 탭의
    연속 일수는 운동만 센다.
    """
    rows = db.scalars(
        select(StreakShield)
        .where(StreakShield.user_id == member_id, StreakShield.status == USED)
        .order_by(StreakShield.protected_on.desc(), StreakShield.id.desc())
        .limit(_USED_LIMIT)
    ).all()
    held = held_count(db, member_id)
    protected_on = {row.protected_on for row in rows if row.protected_on}
    today = clock.today()
    # 창은 보유 수와 상관없이 늘 같다 — 보호권이 없으면 창만 비운다. 어느 날이
    # 실제로 보호 가능한지(기록 없음·아직 보호 안 함)는 그래프가 날짜별 기록으로
    # 가리고, 마지막 판정은 사용 요청이 [_block_reason] 으로 한다.
    window = protect_window(today)
    return StreakShieldsOut(
        held=held,
        max_held=MAX_HELD,
        cost=COST,
        used=[
            StreakShieldUseOut(date=row.protected_on or "", used_at=row.used_at)
            for row in rows
            if row.used_at is not None
        ],
        record_streak_days=record_activity.record_streak_days(
            db, member_id, today=today, protected=protected_on
        ),
        protectable_from=window[0].isoformat() if held > 0 else None,
        protectable_to=window[1].isoformat() if held > 0 else None,
    )


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


def refund_for_record(db: Session, member_id: str, day: date | None) -> bool:
    """[day] 에 기록이 생기면 그날 쓴 보호권을 되돌린다. 커밋하지 않는다.

    기록한 날은 보호가 필요 없다 — 보호를 풀고 그 보호권을 다시 `held` 로 돌린다.
    기록을 만들거나 그날로 옮기는 모든 경로(식단 저장·수정, 운동 직접 추가·수정,
    AI 추천·배정 루틴 완료, 트레이너 PT 완료)가 기록과 같은 트랜잭션에서 부른다.
    되돌린 뒤 그 기록을 지워도 보호는 다시 걸리지 않는다. 되돌렸으면 True.

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


def protect_window(today: date) -> tuple[date, date]:
    """보호할 수 있는 날의 구간(양끝 포함) — 어제부터 거슬러 30일.

    그래프(#2075)가 어느 칸을 누를 수 있는지 그릴 때와 사용 요청을 판정할 때가 같은
    구간을 봐야 한다. 앱이 창 길이를 따로 들고 있으면 규칙이 바뀔 때 화면만 옛
    창으로 남는다.
    """
    last = today - timedelta(days=1)
    return last - timedelta(days=PROTECT_WINDOW_DAYS - 1), last


def _block_reason(db: Session, member_id: str, day: date) -> str | None:
    """[day] 를 지금 보호할 수 없는 이유. 보유 수는 보지 않는다."""
    first, last = protect_window(clock.today())
    if not first <= day <= last:
        return BLOCK_OUT_OF_WINDOW
    if _protected(db, member_id, day):
        return BLOCK_ALREADY_PROTECTED
    if record_activity.has_record(db, member_id, day):
        return BLOCK_HAS_RECORD
    return None


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
