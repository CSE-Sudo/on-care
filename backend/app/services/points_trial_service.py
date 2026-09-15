"""트레이너 빈 시간대 포인트 체험 예약. (#1790)

트레이너가 `포인트 체험 허용` 으로 연 빈 시간(`session_type == "체험"`)에만, 담당
트레이너가 없는 회원이 500P 로 20분 자세 점검 체험을 예약한다. 트레이너는 원래
비던 시간으로 신규 회원을 만나고, 회원은 비용 없이 트레이너를 경험한다.

규칙:

- **담당 트레이너가 있는 회원은 예약할 수 없다.** 다른 트레이너가 기존 회원을
  데려가는 갈등을 막는다. 목록에서도 체험 자리를 내주지 않는다.
- **트레이너별로 회원 1인 1회.** 반환된 체험(트레이너 취소·24시간 전 회원 취소)은
  세지 않는다 — 포인트를 돌려받은 예약은 쓴 적이 없는 것과 같다. 진행 중·완료·노쇼·
  늦은 취소는 1회로 센다. partial unique index 가 마지막 방어선이다.
- **포인트는 예약과 같은 트랜잭션에서 뺀다**(`points_service.spend`). 예약이 실패하면
  사용도 함께 롤백된다.
- **결말**
  - 트레이너가 일정을 취소 → 반환(`refund`).
  - 회원이 시작 24시간 전까지 취소 → 반환. 그보다 늦으면 반환하지 않는다(소멸).
  - 노쇼 → 소멸. 완료 → 더 할 일이 없다.
  - 트레이너 탈퇴로 예약이 사라짐 → 반환.

체험 기록(`PointsTrial`)을 예약 행과 따로 두는 까닭: 회원이 취소하면 예약 행은
지워진다(`reservation_service._release`). 그 뒤에도 "이 트레이너 체험을 이미
했나" 와 "포인트가 어떻게 끝났나" 는 남아야 한다.

이 모듈의 함수는 **커밋하지 않는다.** 예약·취소·일정 전이와 같은 트랜잭션에서
부르는 쪽이 커밋한다.
"""
from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.models import PointsTrial, TrainerClient, TrainerSchedule
from app.services import points_service

#: 체험 슬롯의 종류 계약값. `TrainerSchedule.type` 에도 그대로 들어간다.
TRIAL_SESSION_TYPE = "체험"
#: 체험 시간(분). 트레이너가 시간을 고르지 않는다 — 20분 자세 점검으로 고정한다.
TRIAL_MINUTES = 20
#: 체험 예약에 쓰는 포인트.
TRIAL_COST = 500
#: 이만큼 전까지 취소하면 포인트를 돌려준다.
REFUND_NOTICE = timedelta(hours=24)

#: 포인트 내역의 규칙 이름과 근거 종류.
REASON = "trial_booking"
SOURCE_POINTS_TRIAL = "points_trial"

#: 체험 기록 상태.
BOOKED = "booked"
COMPLETED = "completed"
NO_SHOW = "no_show"
REFUNDED = "refunded"
FORFEITED = "forfeited"

#: 체험 예약을 막는 이유 — 앱이 이 값으로 안내 문구를 고른다.
BLOCK_HAS_TRAINER = "has_trainer"
BLOCK_TRIAL_USED = "trial_used"
BLOCK_INSUFFICIENT = "insufficient_points"

#: 1회 판정에서 빠지는 상태가 이것 하나다 — 인덱스 조건과 같아야 한다.
UNIQUE_INDEX = "uq_points_trials_member_trainer"


class TrialError(Exception):
    """체험 예약 규칙 위반. 라우터가 409 로 옮긴다."""

    code = ""


class TrialHasTrainer(TrialError):
    code = BLOCK_HAS_TRAINER

    def __init__(self) -> None:
        super().__init__("담당 트레이너가 있는 회원은 포인트 체험을 예약할 수 없어요.")


class TrialAlreadyUsed(TrialError):
    code = BLOCK_TRIAL_USED

    def __init__(self) -> None:
        super().__init__("이 트레이너의 포인트 체험은 이미 이용했어요.")


class TrialInsufficientPoints(TrialError):
    code = BLOCK_INSUFFICIENT

    def __init__(self, shortfall: int) -> None:
        super().__init__(f"포인트가 {shortfall}P 부족해요.")
        self.shortfall = shortfall


def is_trial(session_type: str | None) -> bool:
    return session_type == TRIAL_SESSION_TYPE


def has_active_trainer(db: Session, member_id: str) -> bool:
    """활성 담당 링크가 하나라도 있는가. 어느 트레이너든 상관없다."""
    return (
        db.scalar(
            select(TrainerClient.id)
            .where(
                TrainerClient.member_id == member_id,
                TrainerClient.active.is_(True),
            )
            .limit(1)
        )
        is not None
    )


def trial_schedule_clause(trainer_id: str):
    """[trainer_id] 의 포인트 체험 예약이 만든 일정인가 — 일정 조회 WHERE 조각.

    트레이너 일정 조회는 담당 회원의 세션만 보여 준다. 체험 회원은 담당이 아니라서
    이 조건을 함께 걸어야 트레이너가 자기 체험 일정을 본다. 체험 기록은 지우지
    않으므로 취소·노쇼·완료로 끝난 체험도 일정 기록으로 남는다.
    """
    return (
        select(PointsTrial.id)
        .where(
            PointsTrial.schedule_id == TrainerSchedule.id,
            PointsTrial.trainer_id == trainer_id,
        )
        .exists()
    )


def blocked_reason(db: Session, member_id: str, trainer_id: str) -> str | None:
    """이 회원이 [trainer_id] 의 체험을 지금 예약할 수 없는 이유. 가능하면 None.

    `has_trainer` → `trial_used` → `insufficient_points` 순으로 하나만 준다.
    """
    if has_active_trainer(db, member_id):
        return BLOCK_HAS_TRAINER
    if _counted(db, member_id, trainer_id) is not None:
        return BLOCK_TRIAL_USED
    if points_service.balance(db, member_id) < TRIAL_COST:
        return BLOCK_INSUFFICIENT
    return None


def begin(
    db: Session,
    member_id: str,
    trainer_id: str,
    *,
    slot_id: str,
    reservation_id: str,
    schedule_id: str,
    starts_at: datetime,
) -> tuple[PointsTrial, int]:
    """체험 기록을 만들고 포인트를 쓴다. (기록, 사용 뒤 잔액). 커밋하지 않는다.

    잔액 행을 먼저 잠가 같은 회원의 체험 예약을 차례로 세운다 — 두 트레이너
    자리를 동시에 눌러도 잔액·1회 판정이 순서대로 읽힌다. 동시에 같은 트레이너
    자리 둘을 잡는 경합은 unique index 가 IntegrityError 로 막는다(부르는 쪽이
    [UNIQUE_INDEX] 로 [TrialAlreadyUsed] 에 옮긴다).
    """
    if has_active_trainer(db, member_id):
        raise TrialHasTrainer()
    points_service.lock_balance(db, member_id)
    if _counted(db, member_id, trainer_id) is not None:
        raise TrialAlreadyUsed()
    current = points_service.balance(db, member_id)
    if current < TRIAL_COST:
        raise TrialInsufficientPoints(TRIAL_COST - current)

    trial = PointsTrial(
        id=f"trial-{uuid.uuid4().hex[:12]}",
        member_id=member_id,
        trainer_id=trainer_id,
        slot_id=slot_id,
        reservation_id=reservation_id,
        schedule_id=schedule_id,
        cost=TRIAL_COST,
        status=BOOKED,
        starts_at=starts_at,
    )
    db.add(trial)
    db.flush()
    remaining = points_service.spend(
        db,
        member_id,
        reason=REASON,
        source_type=SOURCE_POINTS_TRIAL,
        source_id=trial.id,
        cost=TRIAL_COST,
    )
    return trial, remaining


def refundable(trial: PointsTrial | None, now: datetime | None = None) -> bool:
    """지금 회원이 취소하면 포인트를 돌려받는가."""
    if trial is None or trial.status != BOOKED:
        return False
    current = now or datetime.now(timezone.utc)
    return _aware(trial.starts_at) - current >= REFUND_NOTICE


def settle_member_cancel(
    db: Session, reservation_id: str, *, now: datetime | None = None
) -> int:
    """회원이 취소한 체험의 포인트를 정리한다. 돌려준 포인트(0 이상).

    시작 24시간 전까지는 반환, 그보다 늦으면 소멸이다. 체험 예약이 아니면 0.
    """
    trial = _booked(db, PointsTrial.reservation_id == reservation_id)
    if trial is None:
        return 0
    if refundable(trial, now):
        return _refund(db, trial, by="member")
    _settle(trial, FORFEITED, by="member")
    db.flush()
    return 0


def settle_trainer_cancel(db: Session, schedule_id: str) -> int:
    """트레이너가 취소한 체험 일정의 포인트를 돌려준다. 돌려준 포인트(0 이상)."""
    trial = _booked(db, PointsTrial.schedule_id == schedule_id)
    if trial is None:
        return 0
    return _refund(db, trial, by="trainer")


def settle_no_show(db: Session, schedule_id: str) -> None:
    """노쇼로 끝난 체험 — 포인트는 소멸한다(이미 썼으므로 돌려주지 않는다)."""
    trial = _booked(db, PointsTrial.schedule_id == schedule_id)
    if trial is not None:
        _settle(trial, NO_SHOW, by="trainer")
        db.flush()


def settle_completed(db: Session, schedule_id: str) -> None:
    """완료한 체험 — 포인트는 그대로 쓴 것으로 끝난다."""
    trial = _booked(db, PointsTrial.schedule_id == schedule_id)
    if trial is not None:
        _settle(trial, COMPLETED, by="trainer")
        db.flush()


def move_start(db: Session, slot_id: str, starts_at: datetime) -> None:
    """트레이너가 예약된 체험 자리의 시각을 옮기면 체험 기록도 따라간다.

    회원 취소의 24시간 판정이 이 시각을 본다 — 옛 시각을 두면 옮긴 뒤에도 옛
    기준으로 반환 여부가 갈린다. 커밋하지 않는다.
    """
    trials = db.scalars(
        select(PointsTrial).where(
            PointsTrial.slot_id == slot_id, PointsTrial.status == BOOKED
        )
    ).all()
    for trial in trials:
        trial.starts_at = starts_at


def refund_for_trainer_deletion(db: Session, trainer_id: str) -> int:
    """트레이너 탈퇴로 사라지는 체험 예약의 포인트를 돌려준다. 돌려준 합계.

    체험 기록은 트레이너 행과 함께 CASCADE 로 지워지지만, 포인트 내역은 회원 것이라
    남는다. 트레이너 사정으로 약속이 없어진 것이니 트레이너 취소와 같게 반환한다.
    """
    trials = db.scalars(
        select(PointsTrial)
        .where(PointsTrial.trainer_id == trainer_id, PointsTrial.status == BOOKED)
        .order_by(PointsTrial.id)
        .with_for_update()
    ).all()
    return sum(_refund(db, trial, by="trainer") for trial in trials)


def trials_by_reservation(
    db: Session, reservation_ids: list[str]
) -> dict[str, PointsTrial]:
    """예약 id → 그 예약의 체험 기록. 체험이 아닌 예약은 빠진다."""
    if not reservation_ids:
        return {}
    rows = db.scalars(
        select(PointsTrial).where(PointsTrial.reservation_id.in_(reservation_ids))
    ).all()
    return {row.reservation_id: row for row in rows if row.reservation_id}


def _counted(db: Session, member_id: str, trainer_id: str) -> PointsTrial | None:
    """1회로 세는 체험 — 반환되지 않은 것."""
    return db.scalar(
        select(PointsTrial)
        .where(
            PointsTrial.member_id == member_id,
            PointsTrial.trainer_id == trainer_id,
            PointsTrial.status != REFUNDED,
        )
        .limit(1)
    )


def _booked(db: Session, condition) -> PointsTrial | None:
    return db.scalar(
        select(PointsTrial)
        .where(condition, PointsTrial.status == BOOKED)
        .with_for_update()
    )


def _refund(db: Session, trial: PointsTrial, *, by: str) -> int:
    amount = points_service.refund(
        db, trial.member_id, SOURCE_POINTS_TRIAL, trial.id
    )
    _settle(trial, REFUNDED, by=by)
    db.flush()
    return amount


def _settle(trial: PointsTrial, status: str, *, by: str) -> None:
    trial.status = status
    trial.settled_by = by
    trial.settled_at = datetime.now(timezone.utc)


def _aware(value: datetime) -> datetime:
    return value if value.tzinfo is not None else value.replace(tzinfo=timezone.utc)
