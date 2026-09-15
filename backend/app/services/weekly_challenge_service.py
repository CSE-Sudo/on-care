"""주간 운동 챌린지 — 참가·진행·주 마감 판정. (#1789)

포인트를 걸고 한 주 목표를 채우면 더 돌려받는다. 앱 안에서 끝나 외부 협력이 필요
없고, 트레이너 연결 여부와 상관없이 꾸준히 운동할 이유를 만든다.

규칙:

- **한 주는 KST 월요일~일요일**이다. 참가는 그 주 월·화요일에만, 한 주에 한 번이다
  (`(user_id, week_start)` 유니크).
- **참가할 때 100P 를 건다** — 포인트 내역 `spend`(`challenge_stake`). 잔액이
  모자라면 참가할 수 없다.
- **목표는 참가 시점의 주간 운동 횟수 목표로 고정한다.** 목표가 없으면 주 3회다.
  참가 뒤에 목표를 바꿔도 그 주 챌린지의 목표는 그대로다. 한 주에 운동한 날은 7일이
  최대라 목표가 7을 넘으면 7로 둔다 — 넘긴 채 두면 건 포인트를 반드시 잃는다.
- **진행은 운동 기록이 있는 날 수**다. 같은 날 여러 번 기록해도 1회다. 날짜는 회원
  화면이 보는 논리 운동일(`exercise_activity.activity_date_of`)이고, 기록의 출처(직접
  추가·PT·배정 루틴)는 가리지 않는다.
- **판정은 주가 끝난 뒤 한 번이다.** 일요일까지 목표를 채웠으면 200P 를 돌려받고
  (내역 `earn`, `challenge_reward`), 못 채웠으면 건 포인트는 사라진다. 주 중간에
  목표를 채워도 바로 주지 않는다 — 그 뒤 기록을 지우면 진행이 줄어드는데, 먼저 준
  보상은 되돌릴 근거가 없다. 주가 끝나야 그 주의 기록이 확정된다.
- **스케줄러 없이 늦게 판정한다.** 백엔드에 주기 작업이 없다(쿠폰 만료와 같은 사정).
  회원이 챌린지·포인트 사용처·포인트 잔액(`/users/me/health`)·알림함을 읽을 때 지난
  주의 진행 중 챌린지를 판정한다. 판정은 `active` 일 때만 바꾸는 조건부 UPDATE 한
  번이라, 두 경로가 동시에 읽어도 보상과 결과 알림은 한 번뿐이다.
"""
from __future__ import annotations

import uuid
from datetime import date, timedelta

from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core import clock
from app.models.models import ExerciseSession, HealthProfile, WeeklyChallenge
from app.schemas.challenge_api import (
    ChallengeJoinOut,
    ChallengeOut,
    WeeklyChallengeOut,
)
from app.services import exercise_activity, notification_service, points_service

#: 참가할 때 거는 포인트와, 목표를 채우면 돌려받는 포인트.
STAKE = 100
REWARD = 200

#: 주간 운동 횟수 목표가 없을 때의 목표와, 한 주에 셀 수 있는 최대 날 수.
DEFAULT_GOAL = 3
MAX_GOAL = 7

#: 참가할 수 있는 요일(월=0, 화=1).
JOIN_WEEKDAYS = frozenset({0, 1})

#: 챌린지 상태.
ACTIVE = "active"
SUCCEEDED = "succeeded"
FAILED = "failed"

#: 참가 버튼을 막는 이유 — 앱이 이 값으로 안내 문구를 고른다.
BLOCK_ALREADY_JOINED = "already_joined"
BLOCK_JOIN_CLOSED = "join_closed"
BLOCK_INSUFFICIENT = "insufficient_points"

#: 포인트 내역의 `reason`.
REASON_STAKE = "challenge_stake"
REASON_REWARD = "challenge_reward"

#: 내 혜택에 싣는 챌린지 수 상한. 한 주에 한 줄씩 쌓이기만 한다.
_HISTORY_LIMIT = 20


class ChallengeError(Exception):
    """챌린지 규칙 위반. 라우터가 상태코드로 옮긴다."""


class JoinWindowClosed(ChallengeError):
    """월·화요일이 아니라 참가할 수 없다."""


class AlreadyJoined(ChallengeError):
    """이번 주 챌린지에 이미 참가했다."""


# ---- 조회 ----


def weekly_state(db: Session, member_id: str) -> WeeklyChallengeOut:
    """이번 주 챌린지와 지금 참가할 수 있는지. 읽기 전에 지난 주를 판정한다."""
    if settle_due(db, member_id):
        db.commit()
    today = clock.today()
    monday = week_monday(today)
    row = _for_week(db, member_id, monday)
    balance = points_service.balance(db, member_id)
    progress = progress_days(db, member_id, monday)
    blocked: str | None = None
    if row is not None:
        blocked = BLOCK_ALREADY_JOINED
    elif today.weekday() not in JOIN_WEEKDAYS:
        blocked = BLOCK_JOIN_CLOSED
    elif balance < STAKE:
        blocked = BLOCK_INSUFFICIENT
    return WeeklyChallengeOut(
        week_start=monday.isoformat(),
        week_end=(monday + timedelta(days=6)).isoformat(),
        join_until=(monday + timedelta(days=max(JOIN_WEEKDAYS))).isoformat(),
        stake=row.stake if row is not None else STAKE,
        reward=row.reward if row is not None else REWARD,
        goal=row.goal if row is not None else goal_for(db, member_id),
        progress=progress,
        balance=balance,
        joinable=blocked is None,
        blocked_reason=blocked,
        shortfall=max(STAKE - balance, 0),
        challenge=challenge_out(row, progress=progress) if row is not None else None,
    )


def list_challenges(db: Session, member_id: str) -> list[ChallengeOut]:
    """내 챌린지 — 최근 주 먼저. 읽기 전에 지난 주를 판정한다."""
    if settle_due(db, member_id):
        db.commit()
    rows = db.scalars(
        select(WeeklyChallenge)
        .where(WeeklyChallenge.user_id == member_id)
        .order_by(WeeklyChallenge.week_start.desc())
        .limit(_HISTORY_LIMIT)
    ).all()
    return [
        challenge_out(
            row,
            progress=(
                progress_days(db, member_id, date.fromisoformat(row.week_start))
                if row.status == ACTIVE
                else None
            ),
        )
        for row in rows
    ]


def goal_for(db: Session, member_id: str) -> int:
    """지금 참가하면 걸릴 목표 — 회원의 주간 운동 횟수 목표(없으면 3, 7 초과는 7)."""
    value = db.scalar(
        select(HealthProfile.weekly_workout_goal).where(
            HealthProfile.user_id == member_id
        )
    )
    if value is None or value < 1:
        return DEFAULT_GOAL
    return min(value, MAX_GOAL)


def progress_days(
    db: Session, member_id: str, monday: date, *, until: date | None = None
) -> int:
    """[monday] 주에 운동 기록이 있는 날 수. [until](기본 오늘)까지만 센다.

    같은 날 기록이 여러 건이어도 하루다. 아직 오지 않은 날에 적어 둔 기록은 한 운동이
    아니라 세지 않는다 — 주가 끝난 뒤 판정할 때는 일요일까지 모두 센다.
    """
    sunday = monday + timedelta(days=6)
    last = min(sunday, until if until is not None else clock.today())
    if last < monday:
        return 0
    rows = db.scalars(
        select(ExerciseSession).where(
            ExerciseSession.user_id == member_id,
            ExerciseSession.week_start == monday.isoformat(),
        )
    ).all()
    days = {
        day
        for row in rows
        if (day := exercise_activity.activity_date_of(row)) is not None
        and monday <= day <= last
    }
    return len(days)


# ---- 참가 ----


def join(
    db: Session, member_id: str, *, client_request_id: str | None = None
) -> ChallengeJoinOut:
    """이번 주 챌린지에 참가한다 — 100P 를 걸고 목표를 고정한다. 커밋한다.

    [client_request_id] 로 이미 참가했으면 새로 걸지 않고 그 기록을 돌려준다 — 응답을
    못 받고 다시 누른 참가가 포인트를 두 번 쓰지 않는다.

    지난 주를 먼저 판정한다. 지난 주 보상이 잔액에 들어온 뒤에 이번 주 참가 잔액을 본다.
    """
    if client_request_id:
        existing = _by_request(db, member_id, client_request_id)
        if existing is not None:
            return _join_out(db, member_id, existing)
    if settle_due(db, member_id):
        db.commit()

    points_service.lock_balance(db, member_id)
    today = clock.today()
    monday = week_monday(today)
    if _for_week(db, member_id, monday) is not None:
        raise AlreadyJoined("이번 주 챌린지에 이미 참가했어요.")
    if today.weekday() not in JOIN_WEEKDAYS:
        raise JoinWindowClosed("주간 챌린지는 월·화요일에만 참가할 수 있어요.")
    current = points_service.balance(db, member_id)
    if current < STAKE:
        raise points_service.InsufficientPoints(STAKE - current)

    row = WeeklyChallenge(
        id=f"chl-{uuid.uuid4().hex[:12]}",
        user_id=member_id,
        week_start=monday.isoformat(),
        goal=goal_for(db, member_id),
        stake=STAKE,
        reward=REWARD,
        status=ACTIVE,
        client_request_id=client_request_id,
        joined_at=clock.now(),
    )
    try:
        db.add(row)
        db.flush()
        points_service.spend(
            db,
            member_id,
            reason=REASON_STAKE,
            source_type=points_service.SOURCE_WEEKLY_CHALLENGE,
            source_id=row.id,
            cost=STAKE,
        )
        db.commit()
    except IntegrityError:
        db.rollback()
        if client_request_id:
            existing = _by_request(db, member_id, client_request_id)
            if existing is not None:
                return _join_out(db, member_id, existing)
        if _for_week(db, member_id, monday) is not None:
            raise AlreadyJoined("이번 주 챌린지에 이미 참가했어요.") from None
        raise
    db.refresh(row)
    return _join_out(db, member_id, row)


# ---- 판정 ----


def settle_due(db: Session, member_id: str) -> int:
    """주가 끝난 진행 중 챌린지를 판정한다. 판정한 건수. 커밋하지 않는다.

    성공이면 보상을 적립하고, 결과와 상관없이 결과 알림을 한 번 만든다. 판정은
    `active` 일 때만 바꾸는 조건부 UPDATE 라 이번 요청이 바꾼 행만 적립·알림을 만든다.
    잔액 행을 먼저 잠근다 — 참가·쿠폰 교환과 같은 잠금 순서다.
    """
    this_monday = week_monday()
    due = db.scalars(
        select(WeeklyChallenge)
        .where(
            WeeklyChallenge.user_id == member_id,
            WeeklyChallenge.status == ACTIVE,
            WeeklyChallenge.week_start < this_monday.isoformat(),
        )
        .order_by(WeeklyChallenge.week_start)
    ).all()
    if not due:
        return 0
    points_service.lock_balance(db, member_id)
    now = clock.now()
    settled = 0
    for row in due:
        start = date.fromisoformat(row.week_start)
        days = progress_days(db, member_id, start, until=start + timedelta(days=6))
        succeeded = days >= row.goal
        claimed = db.execute(
            update(WeeklyChallenge)
            .where(
                WeeklyChallenge.id == row.id,
                WeeklyChallenge.status == ACTIVE,
            )
            .values(
                status=SUCCEEDED if succeeded else FAILED,
                final_days=days,
                settled_at=now,
            )
            .execution_options(synchronize_session=False)
        )
        if claimed.rowcount != 1:
            continue
        if succeeded:
            points_service.credit(
                db,
                member_id,
                reason=REASON_REWARD,
                source_type=points_service.SOURCE_WEEKLY_CHALLENGE,
                source_id=row.id,
                amount=row.reward,
            )
        title, body = _result_message(row, days=days, succeeded=succeeded)
        notification_service.queue(
            db,
            member_id=member_id,
            kind=notification_service.WEEKLY_CHALLENGE,
            category=notification_service.MEMBER_BENEFITS,
            title=title,
            body=body,
        )
        settled += 1
    db.flush()
    return settled


def settle_quietly(db: Session, member_id: str) -> None:
    """읽기 경로(사용처·잔액·알림함)가 부르는 판정. 실패해도 원래 응답을 막지 않는다."""
    try:
        if settle_due(db, member_id):
            db.commit()
    except Exception:  # noqa: BLE001 — 판정 실패가 잔액·알림 조회를 막지 않는다
        db.rollback()


# ---- 응답 ----


def challenge_out(row: WeeklyChallenge, *, progress: int | None = None) -> ChallengeOut:
    """[progress] 는 진행 중일 때의 지금까지 날 수. 판정했으면 판정 때 값을 쓴다."""
    start = date.fromisoformat(row.week_start)
    if row.status != ACTIVE and row.final_days is not None:
        days = row.final_days
    else:
        days = progress or 0
    return ChallengeOut(
        id=row.id,
        week_start=row.week_start,
        week_end=(start + timedelta(days=6)).isoformat(),
        goal=row.goal,
        progress=days,
        stake=row.stake,
        reward=row.reward,
        status=row.status,
        achieved=days >= row.goal,
        rewarded=row.reward if row.status == SUCCEEDED else 0,
        joined_at=row.joined_at,
        settled_at=row.settled_at,
    )


# ---- 내부 ----


def week_monday(day: date | None = None) -> date:
    """[day](기본 오늘, KST)가 속한 주의 월요일."""
    target = day if day is not None else clock.today()
    return target - timedelta(days=target.weekday())


def _for_week(db: Session, member_id: str, monday: date) -> WeeklyChallenge | None:
    return db.scalar(
        select(WeeklyChallenge).where(
            WeeklyChallenge.user_id == member_id,
            WeeklyChallenge.week_start == monday.isoformat(),
        )
    )


def _by_request(
    db: Session, member_id: str, client_request_id: str
) -> WeeklyChallenge | None:
    return db.scalar(
        select(WeeklyChallenge).where(
            WeeklyChallenge.user_id == member_id,
            WeeklyChallenge.client_request_id == client_request_id,
        )
    )


def _join_out(db: Session, member_id: str, row: WeeklyChallenge) -> ChallengeJoinOut:
    progress = (
        progress_days(db, member_id, date.fromisoformat(row.week_start))
        if row.status == ACTIVE
        else None
    )
    return ChallengeJoinOut(
        challenge=challenge_out(row, progress=progress),
        spent=row.stake,
        balance=points_service.balance(db, member_id),
    )


def _result_message(
    row: WeeklyChallenge, *, days: int, succeeded: bool
) -> tuple[str, str]:
    """결과 알림의 제목과 본문."""
    start = date.fromisoformat(row.week_start)
    end = start + timedelta(days=6)
    period = f"{start.month}월 {start.day}일~{end.month}월 {end.day}일"
    if succeeded:
        return (
            f"주간 챌린지 성공! {row.reward:,}P를 받았어요",
            f"{period} 목표 {row.goal}회를 채워 {row.reward:,}P를 돌려받았어요.",
        )
    return (
        "주간 챌린지 목표를 채우지 못했어요",
        f"{period} 목표 {row.goal}회 중 {days}회 운동해 건 {row.stake:,}P는 사라졌어요. "
        "다음 주 월·화요일에 다시 참가할 수 있어요.",
    )
