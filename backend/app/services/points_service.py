"""활동 포인트 적립·회수. (#1786)

포인트는 서버에 숫자 하나(`HealthProfile.activity_points`)로만 있었고 올리는 코드가
없었다. 적립 안내창에 적힌 규칙을 실제로 적용한다.

- 식단 기록 +50P(하루 3회), 운동 직접 추가 +20P(하루 3회), AI 추천 운동 완료
  +50P(하루 1회). 하루는 **KST 달력 날짜**다 — 서버 로컬 시각을 쓰면 아침 기록이
  전날 한도에 잡힌다([clock]).
- 같은 기록(source)은 한 번만 받는다. 내역 표의 유니크 제약이 마지막 방어선이다.
- 기록을 지우면 받은 만큼 회수한다. 잔액은 0 아래로 내려가지 않는다 — 그사이
  포인트를 써서 잔액이 모자라면 남은 만큼만 회수하고, 내역에는 실제로 뺀 값을
  적는다.
- 회수된 적립은 하루 한도에서 빠진다. 잘못 올린 기록을 지우고 다시 올린 회원이
  그날 한도를 잃지 않게 하려는 것이다. 지웠다 다시 올려도 잔액은 한 번 적립한
  것과 같으므로 한도를 우회하는 이득은 없다.

이 모듈의 함수는 **커밋하지 않는다.** 부르는 쪽이 기록 저장·삭제와 같은
트랜잭션에서 커밋해야 잔액·내역·기록이 함께 움직인다.
"""
from __future__ import annotations

import uuid
from dataclasses import dataclass

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, aliased

from app.core import clock
from app.models.models import HealthProfile, PointsLedger

#: 데모 회원의 시작 잔액. 회원 앱 목업(`MockMyHealthRepository`·로컬 목업 API)과
#: 같은 값이다. 실제 가입 회원은 0 에서 시작한다.
DEMO_OPENING_POINTS = 1240

#: 내역 종류. 사용(`spend`)은 사용처가 붙을 때 쓴다.
EARN = "earn"
SPEND = "spend"
REVOKE = "revoke"

#: 적립의 근거가 된 기록 종류 — 내역의 `source_type`.
SOURCE_DIET_ENTRY = "diet_entry"
SOURCE_EXERCISE_SESSION = "exercise_session"


@dataclass(frozen=True)
class EarnRule:
    """적립 규칙 하나. [reason] 이 하루 한도를 세는 단위다."""

    reason: str
    source_type: str
    points: int
    daily_cap: int


#: 식단 기록 — 사진 분석으로 끼니가 새로 저장될 때.
DIET_ENTRY = EarnRule("diet_entry", SOURCE_DIET_ENTRY, 50, 3)
#: 회원이 직접 추가한 운동 기록.
EXERCISE_MANUAL = EarnRule("exercise_manual", SOURCE_EXERCISE_SESSION, 20, 3)
#: AI 가 추천한 루틴(`TrainerRoutine.source == "ai"`)을 완료해 생긴 운동 기록.
AI_ROUTINE_COMPLETE = EarnRule(
    "ai_routine_complete", SOURCE_EXERCISE_SESSION, 50, 1
)


@dataclass(frozen=True)
class PointsResult:
    """이번 동작으로 받은 포인트와 그 뒤의 잔액. 한도를 넘었으면 `awarded` 는 0."""

    awarded: int
    balance: int


def balance(db: Session, user_id: str) -> int:
    """현재 잔액. 프로필 행이 없으면(온보딩 전) 0 이다."""
    value = db.scalar(
        select(HealthProfile.activity_points).where(
            HealthProfile.user_id == user_id
        )
    )
    return value or 0


def award(db: Session, user_id: str, rule: EarnRule, source_id: str) -> PointsResult:
    """[source_id] 기록에 [rule] 대로 적립한다. 커밋하지 않는다.

    이미 적립한 기록이면 새로 적립하지 않고 그때 받은 값을 돌려준다 — 재시도가
    첫 응답과 같은 결과를 보게 한다. 그날 한도를 채웠으면 0 이다.
    """
    profile = _locked_profile(db, user_id)
    earned = _row(db, user_id, EARN, rule.source_type, source_id)
    if earned is not None:
        return PointsResult(
            awarded=_live_delta(db, earned), balance=profile.activity_points or 0
        )
    today = clock.today_iso()
    if _live_awards_on(db, user_id, rule.reason, today) >= rule.daily_cap:
        return PointsResult(awarded=0, balance=profile.activity_points or 0)
    db.add(
        PointsLedger(
            id=_new_id(),
            user_id=user_id,
            kind=EARN,
            delta=rule.points,
            reason=rule.reason,
            source_type=rule.source_type,
            source_id=source_id,
            kst_date=today,
        )
    )
    profile.activity_points = (profile.activity_points or 0) + rule.points
    db.flush()
    return PointsResult(awarded=rule.points, balance=profile.activity_points)


def awarded_for(
    db: Session, user_id: str, rule: EarnRule, source_id: str
) -> PointsResult:
    """이미 저장된 기록이 받은 적립. 아무것도 쓰지 않는다.

    멱등키로 되돌아온 재시도처럼 **새로 저장하지 않은** 응답에 싣는다. 그 기록이
    적립을 받지 못했거나(한도·이 기능 이전 기록) 회수됐으면 0 이다.
    """
    earned = _row(db, user_id, EARN, rule.source_type, source_id)
    return PointsResult(
        awarded=_live_delta(db, earned) if earned is not None else 0,
        balance=balance(db, user_id),
    )


def revoke(db: Session, user_id: str, source_type: str, source_id: str) -> int:
    """지워지는 기록이 받은 적립을 회수한다. 커밋하지 않는다.

    회수한 포인트(0 이상)를 돌려준다. 적립을 받은 적 없는 기록이면 아무 일도 하지
    않는다. 잔액이 모자라면 남은 만큼만 빼고, 내역에는 실제로 뺀 값을 남긴다 —
    잔액이 음수가 되면 이후 적립이 빚을 갚는 데 먼저 쓰여 회원 화면이 설명되지
    않는다.
    """
    earned = _row(db, user_id, EARN, source_type, source_id)
    if earned is None:
        return 0
    profile = _locked_profile(db, user_id)
    if _row(db, user_id, REVOKE, source_type, source_id) is not None:
        return 0
    current = max(profile.activity_points or 0, 0)
    taken = min(earned.delta, current)
    db.add(
        PointsLedger(
            id=_new_id(),
            user_id=user_id,
            kind=REVOKE,
            delta=-taken,
            reason=earned.reason,
            source_type=source_type,
            source_id=source_id,
            kst_date=clock.today_iso(),
        )
    )
    profile.activity_points = current - taken
    db.flush()
    return taken


def _new_id() -> str:
    return f"pts-{uuid.uuid4().hex[:12]}"


def _locked_profile(db: Session, user_id: str) -> HealthProfile:
    """잔액 행을 잠가 가져온다.

    한 회원의 적립이 동시에 두 건 들어와도 한도를 차례로 세게 하려는 잠금이다 —
    잠그지 않으면 둘 다 "오늘 2회" 를 보고 4회째까지 적립된다.

    온보딩 전 회원은 프로필 행이 없어 잔액 자리를 만든다. 같은 순간 다른 요청이
    먼저 만들었으면 그 행을 쓴다.
    """
    stmt = (
        select(HealthProfile)
        .where(HealthProfile.user_id == user_id)
        .with_for_update()
    )
    profile = db.scalar(stmt)
    if profile is not None:
        return profile
    try:
        with db.begin_nested():
            db.add(HealthProfile(user_id=user_id, activity_points=0))
    except IntegrityError:
        pass
    return db.scalars(stmt).one()


def _row(
    db: Session, user_id: str, kind: str, source_type: str, source_id: str
) -> PointsLedger | None:
    return db.scalar(
        select(PointsLedger).where(
            PointsLedger.user_id == user_id,
            PointsLedger.kind == kind,
            PointsLedger.source_type == source_type,
            PointsLedger.source_id == source_id,
        )
    )


def _live_delta(db: Session, earned: PointsLedger) -> int:
    """적립 행이 아직 살아 있으면 그 값, 회수됐으면 0."""
    revoked = _row(
        db, earned.user_id, REVOKE, earned.source_type or "", earned.source_id or ""
    )
    return 0 if revoked is not None else earned.delta


def _live_awards_on(db: Session, user_id: str, reason: str, day: str) -> int:
    """그날 [reason] 으로 받은 적립 중 회수되지 않은 건수."""
    revoked = aliased(PointsLedger)
    still_live = ~(
        select(revoked.id)
        .where(
            revoked.user_id == PointsLedger.user_id,
            revoked.kind == REVOKE,
            revoked.source_type == PointsLedger.source_type,
            revoked.source_id == PointsLedger.source_id,
        )
        .exists()
    )
    return (
        db.scalar(
            select(func.count())
            .select_from(PointsLedger)
            .where(
                PointsLedger.user_id == user_id,
                PointsLedger.kind == EARN,
                PointsLedger.reason == reason,
                PointsLedger.kst_date == day,
                still_live,
            )
        )
        or 0
    )
