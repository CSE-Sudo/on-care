from __future__ import annotations

import uuid
from datetime import datetime, timezone

from sqlalchemy import func, select, tuple_
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.clock import SEOUL
from app.core.pagination import DEFAULT_PAGE
from app.models.models import (
    TrainerClient,
    TrainerReservation,
    TrainerReservationSlot,
    TrainerSchedule,
    User,
)
from app.schemas.reservation_api import (
    MyReservationOut,
    ReservationOut,
    TrainerSlotOut,
)
from app.services import notification_service, trainer_service


class SlotNotFound(Exception):
    pass


class SlotUnavailable(Exception):
    pass


class DuplicateReservation(Exception):
    pass


class CapacityConflict(Exception):
    pass


def _aware(value: datetime) -> datetime:
    return value if value.tzinfo is not None else value.replace(tzinfo=timezone.utc)


#: 슬롯 종류별 기본 소요 시간(분). 회원 예약은 시각만 고를 뿐 시간을 따로
#: 고르지 않으므로, 슬롯을 열 때 트레이너가 고른 종류가 이 값을 정한다 —
#: 스케줄 탭에서 상담을 짧게 잡는 관례와 같다.
_SESSION_DURATION_MINUTES = {"1:1 PT": 60, "상담": 30}


#: 회원에게 보이는 예약 자리 종류. 헬스장 탭 목록도 상담 신청 폼도 이것만 쓴다
#: (#1849 유지). `상담` 종류는 코드에 남아 있지만 이 흐름에서는 쓰지 않는다.
CONSULTATION_SESSION_TYPE = "1:1 PT"


def consultation_slots(
    db: Session, trainer_id: str, *, after: datetime
) -> list[TrainerReservationSlot]:
    """상담 신청 폼이 보여 줄 빈 자리. [after] 이후에 시작하는 것만. (#1873)

    신청하는 순간 자리를 잠그므로, 트레이너가 확인할 틈이 남아 있는 자리만 보여야
    한다 — 하한은 호출자가 만료 기준보다 크게 잡아 넘긴다
    (`consultation_service.CONSULT_SLOT_MIN_LEAD_HOURS`).

    이미 잠겼거나(`remaining <= 0`) 트레이너가 닫은 자리는 빠진다.
    """
    return list(
        db.scalars(
            select(TrainerReservationSlot)
            .where(
                TrainerReservationSlot.trainer_id == trainer_id,
                TrainerReservationSlot.session_type == CONSULTATION_SESSION_TYPE,
                TrainerReservationSlot.is_closed.is_(False),
                TrainerReservationSlot.remaining > 0,
                TrainerReservationSlot.starts_at > after,
            )
            .order_by(TrainerReservationSlot.starts_at)
        ).all()
    )


def consultation_slot_options(
    db: Session, trainer_id: str, *, after: datetime
) -> list[TrainerSlotOut]:
    """[consultation_slots] 를 응답 스키마로. 하한은 호출자가 정한다."""
    return [_slot_out(slot) for slot in consultation_slots(db, trainer_id, after=after)]


def hold_slot_for_consultation(
    db: Session, trainer_id: str, slot_id: str, *, after: datetime
) -> TrainerReservationSlot:
    """상담 신청이 고른 자리를 잠근다(커밋 없음). (#1873)

    **승인이 아니라 신청할 때** 잠근다 — 승인할 때 잠그면 두 회원이 같은 자리를
    신청할 수 있고, 둘 중 하나는 트레이너가 수락한 뒤에야 거절당한다.

    예약([reserve])과 달리 `TrainerReservation` 행을 만들지 않는다. 그 행은
    `schedule_id` 가 필수라 일정이 있어야 하는데, 상담은 수락 전까지 일정이 없다.
    좌석만 줄여 두고 상담 요청이 `slot_id` 로 그 자리를 가리킨다.
    """
    slot = db.scalar(
        select(TrainerReservationSlot)
        .where(TrainerReservationSlot.id == slot_id)
        .with_for_update()
        # 세션이 이 자리를 이미 읽어 뒀으면 `with_for_update` 만으로는 값이
        # 갱신되지 않는다 — 잠금을 잡는 뜻은 **지금 커밋된 값**을 보겠다는 것이다.
        .execution_options(populate_existing=True)
    )
    if slot is None:
        raise SlotNotFound("예약 가능한 시간을 찾을 수 없습니다.")
    if (
        slot.trainer_id != trainer_id
        or slot.session_type != CONSULTATION_SESSION_TYPE
        or slot.is_closed
        or slot.remaining <= 0
        or _aware(slot.starts_at) <= after
    ):
        raise SlotUnavailable("예약할 수 없는 시간입니다.")
    slot.remaining -= 1
    return slot


def release_consultation_hold(db: Session, slot_id: str | None) -> None:
    """상담이 잡고 있던 자리를 되돌려 준다(커밋 없음). 거절·취소·만료가 부른다.

    [_release] 를 쓰지 않는 이유: 그 함수는 `TrainerReservation` 행과 그것이 만든
    일정까지 되돌린다. 상담이 잡은 자리에는 둘 다 없어 되돌릴 것이 좌석뿐이다.
    """
    if slot_id is None:
        return
    slot = db.scalar(
        select(TrainerReservationSlot)
        .where(TrainerReservationSlot.id == slot_id)
        .with_for_update()
        # 갱신 없이 잠그면 세션이 들고 있던 옛 `remaining` 에 1을 더하게 되고,
        # 그 값이 우연히 지금 값과 같으면 UPDATE 자체가 나가지 않아 자리가
        # 영영 풀리지 않는다.
        .execution_options(populate_existing=True)
    )
    if slot is None:
        return
    slot.remaining = min(slot.capacity, slot.remaining + 1)


def _slot_out(
    slot: TrainerReservationSlot, *, booked_by_name: str | None = None
) -> TrainerSlotOut:
    return TrainerSlotOut(
        id=slot.id,
        trainer_id=slot.trainer_id,
        starts_at=_aware(slot.starts_at),
        duration_minutes=slot.duration_minutes,
        capacity=slot.capacity,
        remaining=0 if slot.is_closed else slot.remaining,
        is_closed=slot.is_closed,
        session_type=slot.session_type,
        booked_by_name=booked_by_name,
    )


def _booked_names(db: Session, slot_ids: list[str]) -> dict[str, str]:
    """예약 슬롯 id → 그 자리를 잡은 회원 이름.

    트레이너용 슬롯 목록에서만 쓴다(#1394) — 회원용 목록은 남의 이름을 알 이유가
    없다. 취소된 예약(`status != "booked"`)은 자리를 비워 준 것이라 빼고 본다.
    """
    if not slot_ids:
        return {}
    rows = db.execute(
        select(TrainerReservation.slot_id, User.name)
        .join(User, User.id == TrainerReservation.member_id)
        .where(
            TrainerReservation.slot_id.in_(slot_ids),
            TrainerReservation.status == "booked",
        )
    ).all()
    return {slot_id: name for slot_id, name in rows}


def list_member_slots(
    db: Session, trainer_id: str, *, now: datetime | None = None
) -> list[TrainerSlotOut]:
    current = now or datetime.now(timezone.utc)
    rows = db.scalars(
        select(TrainerReservationSlot)
        .where(
            TrainerReservationSlot.trainer_id == trainer_id,
            TrainerReservationSlot.starts_at > current,
        )
        .order_by(TrainerReservationSlot.starts_at)
    ).all()
    return [_slot_out(row) for row in rows]


def list_trainer_slots(
    db: Session, trainer_id: str, *, include_past: bool = False
) -> list[TrainerSlotOut]:
    query = select(TrainerReservationSlot).where(
        TrainerReservationSlot.trainer_id == trainer_id
    )
    if not include_past:
        query = query.where(
            TrainerReservationSlot.starts_at > datetime.now(timezone.utc)
        )
    rows = db.scalars(query.order_by(TrainerReservationSlot.starts_at)).all()
    booked_names = _booked_names(db, [row.id for row in rows])
    return [
        _slot_out(row, booked_by_name=booked_names.get(row.id)) for row in rows
    ]


def create_slot(
    db: Session,
    trainer_id: str,
    starts_at: datetime,
    session_type: str,
    duration_minutes: int | None = None,
) -> TrainerSlotOut:
    if _aware(starts_at) <= datetime.now(timezone.utc):
        raise SlotUnavailable("지난 시간에는 예약 슬롯을 만들 수 없습니다.")
    # 슬롯은 늘 한 사람 몫이다 — 1:1 PT 이거나 상담이고, 여럿이 함께 듣는
    # 자리는 없다(#1012). 정원 대신 종류를 고른다(#1083).
    slot = TrainerReservationSlot(
        id=f"slot-{uuid.uuid4().hex[:12]}",
        trainer_id=trainer_id,
        starts_at=starts_at,
        duration_minutes=duration_minutes
        or _SESSION_DURATION_MINUTES.get(session_type, 60),
        capacity=1,
        remaining=1,
        session_type=session_type,
    )
    db.add(slot)
    db.commit()
    db.refresh(slot)
    return _slot_out(slot)


def update_slot(
    db: Session,
    trainer_id: str,
    slot_id: str,
    fields: dict,
) -> TrainerSlotOut:
    slot = db.scalar(
        select(TrainerReservationSlot)
        .where(
            TrainerReservationSlot.id == slot_id,
            TrainerReservationSlot.trainer_id == trainer_id,
        )
        .with_for_update()
    )
    if slot is None:
        raise SlotNotFound("예약 슬롯을 찾을 수 없습니다.")

    if "session_type" in fields:
        booked = (
            db.scalar(
                select(func.count())
                .select_from(TrainerReservation)
                .where(
                    TrainerReservation.slot_id == slot.id,
                    TrainerReservation.status == "booked",
                )
            )
            or 0
        )
        if booked:
            # 이미 예약이 걸린 자리는 종류를 바꾸지 않는다 — 회원은 예약할
            # 때 본 종류(1:1 PT/상담)를 그대로 믿고 그 시간을 비워 둔다.
            raise CapacityConflict("이미 예약된 자리의 종류는 바꿀 수 없습니다.")
        slot.session_type = fields["session_type"]
    if "starts_at" in fields:
        starts_at = fields["starts_at"]
        if _aware(starts_at) <= datetime.now(timezone.utc):
            raise SlotUnavailable("지난 시간으로 슬롯을 변경할 수 없습니다.")
        slot.starts_at = starts_at
        local = _aware(starts_at).astimezone(SEOUL)
        schedules = db.scalars(
            select(TrainerSchedule)
            .join(
                TrainerReservation, TrainerReservation.schedule_id == TrainerSchedule.id
            )
            .where(
                TrainerReservation.slot_id == slot.id,
                TrainerReservation.status == "booked",
            )
        ).all()
        for schedule in schedules:
            schedule.date = local.date().isoformat()
            schedule.time = local.strftime("%H:%M")
    if "duration_minutes" in fields:
        slot.duration_minutes = fields["duration_minutes"]
        schedules = db.scalars(
            select(TrainerSchedule)
            .join(TrainerReservation, TrainerReservation.schedule_id == TrainerSchedule.id)
            .where(
                TrainerReservation.slot_id == slot.id,
                TrainerReservation.status == "booked",
            )
        ).all()
        for schedule in schedules:
            schedule.duration_minutes = slot.duration_minutes
    if "is_closed" in fields:
        slot.is_closed = fields["is_closed"]
    db.commit()
    db.refresh(slot)
    return _slot_out(slot)


def close_slot(db: Session, trainer_id: str, slot_id: str) -> TrainerSlotOut:
    return update_slot(db, trainer_id, slot_id, {"is_closed": True})


class ReservationNotFound(Exception):
    pass


class ReservationTooLate(Exception):
    pass


def _release(
    db: Session,
    reservations: list[TrainerReservation],
    *,
    cancelled_by: str | None = None,
) -> None:
    """예약을 지우고 좌석과 생성된 일정을 되돌린다. **커밋하지 않는다.**

    회원 탈퇴와 개별 취소가 같은 일을 한다 — 좌석 복구, 예약 삭제, 그 예약이
    만든 트레이너 일정 정리. 두 곳에 따로 쓰면 한쪽만 고쳐지는 사고가 난다
    (실제로 취소 기능이 없던 동안 이 로직은 탈퇴 경로에만 있었다). (#502)

    [cancelled_by] 를 주면 트레이너 일정을 **지우지 않고 취소 기록으로 남긴다**
    (#871). 회원이 스스로 취소한 경우가 그렇다 — 트레이너 화면에서 한 줄이 조용히
    사라지면 "그 시간에 무슨 일이 있었나" 가 남지 않는다. 탈퇴 경로는 계정 자체가
    사라지므로 지금처럼 일정을 지운다: 남길 상대가 없는 기록이다.

    잠금·flush 순서는 그대로다: 예약과 슬롯을 id 순으로 잠가 데드락을 피하고,
    restrictive FK 때문에 예약 행을 먼저 flush 한 뒤 일정을 정리한다.
    """
    if not reservations:
        return

    booked_slot_ids = sorted(
        {row.slot_id for row in reservations if row.status == "booked"}
    )
    slots = (
        db.scalars(
            select(TrainerReservationSlot)
            .where(TrainerReservationSlot.id.in_(booked_slot_ids))
            .order_by(TrainerReservationSlot.id)
            .with_for_update()
        ).all()
        if booked_slot_ids
        else []
    )
    slots_by_id = {slot.id: slot for slot in slots}
    schedule_ids = [row.schedule_id for row in reservations]

    for reservation in reservations:
        if reservation.status == "booked":
            slot = slots_by_id.get(reservation.slot_id)
            if slot is not None:
                slot.remaining = min(slot.capacity, slot.remaining + 1)
        db.delete(reservation)

    # No ORM relationships describe this ordering; flush the restrictive FK
    # children before deleting their generated schedules or the member.
    db.flush()
    for schedule_id in schedule_ids:
        schedule = db.get(TrainerSchedule, schedule_id)
        if schedule is None:
            continue
        if cancelled_by is None:
            db.delete(schedule)
            continue
        # 이미 마무리된 세션(완료·취소·노쇼)은 그대로 둔다 — 지난 수업의 결말을
        # 예약 정리가 덮어쓰면 안 된다.
        if schedule.status != trainer_service.SCHEDULE_UPCOMING:
            continue
        schedule.status = trainer_service.SCHEDULE_CANCELLED
        schedule.cancelled_at = datetime.now(timezone.utc)
        schedule.cancellation_source = cancelled_by
    db.flush()


def cancel_member_reservations_for_account_deletion(
    db: Session, member_id: str
) -> None:
    """Cancel a member's bookings before deleting their account.

    The caller owns the transaction.
    """
    reservations = db.scalars(
        select(TrainerReservation)
        .where(TrainerReservation.member_id == member_id)
        .order_by(TrainerReservation.id)
        .with_for_update()
    ).all()
    _release(db, list(reservations))


def reserve(
    db: Session, member: User, slot_id: str, *, now: datetime | None = None
) -> ReservationOut:
    current = now or datetime.now(timezone.utc)
    slot = db.scalar(
        select(TrainerReservationSlot)
        .where(TrainerReservationSlot.id == slot_id)
        .with_for_update()
    )
    if slot is None:
        raise SlotNotFound("예약 슬롯을 찾을 수 없습니다.")
    if slot.is_closed or slot.remaining <= 0 or _aware(slot.starts_at) <= current:
        raise SlotUnavailable("예약할 수 없는 슬롯입니다.")

    assigned = db.scalar(
        select(TrainerClient.id).where(
            TrainerClient.trainer_id == slot.trainer_id,
            TrainerClient.member_id == member.id,
            TrainerClient.active.is_(True),
        )
    )
    if assigned is None:
        raise SlotUnavailable("담당 트레이너의 슬롯만 예약할 수 있습니다.")
    duplicate = db.scalar(
        select(TrainerReservation.id).where(
            TrainerReservation.member_id == member.id,
            TrainerReservation.slot_id == slot.id,
        )
    )
    if duplicate is not None:
        raise DuplicateReservation("이미 예약한 슬롯입니다.")

    reservation_id = f"res-{uuid.uuid4().hex[:12]}"
    schedule_id = f"sched-{uuid.uuid4().hex[:12]}"
    local = _aware(slot.starts_at).astimezone(SEOUL)
    schedule = TrainerSchedule(
        id=schedule_id,
        trainer_id=slot.trainer_id,
        member_id=member.id,
        date=local.date().isoformat(),
        time=local.strftime("%H:%M"),
        client_name=member.name,
        type=slot.session_type,
        duration_minutes=slot.duration_minutes,
        status="예정",
        note="회원 앱 예약",
        program_json="[]",
        sort_order=0,
    )
    reservation = TrainerReservation(
        id=reservation_id,
        member_id=member.id,
        slot_id=slot.id,
        schedule_id=schedule_id,
        status="booked",
    )
    slot.remaining -= 1
    # There is intentionally no ORM relationship between these persistence
    # models. Without an explicit flush SQLAlchemy is free to INSERT the
    # reservation before the schedule, which violates the schedule_id FK on
    # PostgreSQL even though both objects were added before commit (#492).
    db.add(schedule)
    try:
        db.flush()
        db.add(reservation)
        # 트레이너는 회원이 잡은 자리를 스케줄을 다시 열어야만 안다. (#503)
        # 일정→예약 순서 불변식과 무관하므로 그 뒤에 얹는다.
        notification_service.queue_for_trainer(
            db,
            trainer_id=slot.trainer_id,
            kind=notification_service.TRAINER_RESERVATION_KIND,
            title="새 예약이 들어왔어요",
            body=f"{member.name} 회원 · {local:%m월 %d일 %H:%M}",
        )
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        constraint = getattr(getattr(exc.orig, "diag", None), "constraint_name", None)
        if constraint == "uq_reservation_member_slot":
            raise DuplicateReservation("이미 예약한 슬롯입니다.") from exc
        # Do not turn an unexpected schema/programming error into a misleading
        # 409. Let the global error handler report it as a server failure.
        raise
    db.refresh(reservation)
    return ReservationOut(
        id=reservation.id,
        slot_id=reservation.slot_id,
        schedule_id=reservation.schedule_id,
        status=reservation.status,
        created_at=_aware(reservation.created_at),
    )


def list_member_reservations(
    db: Session,
    member_id: str,
    *,
    now: datetime | None = None,
    limit: int = DEFAULT_PAGE,
    before: datetime | None = None,
    before_id: str | None = None,
) -> list[MyReservationOut]:
    """회원의 예약 목록 한 쪽(다가오는 것부터). 지난 예약도 함께 준다.

    지난 것을 숨기지 않는 이유: 회원이 "내가 그 시간에 예약했었나" 를 확인하는
    자리이기도 하다. 대신 `cancellable` 로 취소 가능 여부를 서버가 판단해 준다.

    **순서가 늦은 것부터로 바뀌었다(#980).** 예약은 한 건씩 영구히 쌓이는데 예전에는
    상한 없이 `starts_at` 오름차순으로 전부 돌려줬다 — 여기에 상한만 씌우면 첫 쪽이
    **가장 오래된 지난 예약**으로 채워져, 정작 다가오는 예약이 화면에서 사라진다.
    내림차순이면 첫 쪽이 항상 예정된 예약이고, 지난 예약은 이어 받는 쪽으로 밀린다.

    커서는 알림·채팅 스레드와 같은 모양이다 — 받은 마지막 예약의
    `(starts_at, id)` 를 `(before, before_id)` 로 넘긴다. 한 트레이너가 같은 시각에
    슬롯을 여러 개 열어 둘 수 있어 동시각이 실제로 나오므로 복합 커서를 쓴다.
    """
    current = now or datetime.now(timezone.utc)
    query = (
        select(TrainerReservation, TrainerReservationSlot)
        .join(
            TrainerReservationSlot,
            TrainerReservationSlot.id == TrainerReservation.slot_id,
        )
        .where(TrainerReservation.member_id == member_id)
    )
    if before is not None:
        if before_id is not None:
            query = query.where(
                tuple_(TrainerReservationSlot.starts_at, TrainerReservation.id)
                < (before, before_id)
            )
        else:
            query = query.where(TrainerReservationSlot.starts_at < before)
    rows = db.execute(
        query.order_by(
            TrainerReservationSlot.starts_at.desc(), TrainerReservation.id.desc()
        ).limit(limit)
    ).all()
    return [
        MyReservationOut(
            id=reservation.id,
            slot_id=slot.id,
            trainer_id=slot.trainer_id,
            starts_at=_aware(slot.starts_at),
            cancellable=_aware(slot.starts_at) > current,
        )
        for reservation, slot in rows
    ]


def cancel(
    db: Session, member_id: str, reservation_id: str, *, now: datetime | None = None
) -> None:
    """회원이 자기 예약을 취소한다. 좌석과 트레이너 일정이 함께 돌아간다.

    - 없는 예약이거나 **남의 예약** → [ReservationNotFound]. 남의 것을 403 이 아니라
      404 로 두는 이유는 상담 요청과 같다 — 존재 여부조차 드러내지 않는다.
    - 이미 시작한 슬롯 → [ReservationTooLate]. 수업이 시작된 뒤의 취소는 자리를
      비워 주는 게 아니라 기록을 지우는 일이라, 트레이너가 판단할 몫이다.
    """
    current = now or datetime.now(timezone.utc)
    reservation = db.scalar(
        select(TrainerReservation)
        .where(
            TrainerReservation.id == reservation_id,
            TrainerReservation.member_id == member_id,
        )
        .with_for_update()
    )
    if reservation is None:
        raise ReservationNotFound("예약을 찾을 수 없습니다.")

    slot = db.get(TrainerReservationSlot, reservation.slot_id)
    starts_at = _aware(slot.starts_at) if slot is not None else None
    if starts_at is not None and starts_at <= current:
        raise ReservationTooLate("이미 시작한 수업은 취소할 수 없습니다.")

    member_name = db.scalar(select(User.name).where(User.id == member_id)) or ""
    trainer_id = slot.trainer_id if slot is not None else None

    # 회원이 스스로 취소한 예약이다 — 트레이너 일정은 지우지 않고 `취소` 기록으로
    # 남긴다(#871). 좌석 복구·예약 삭제 등 나머지 규칙은 그대로다.
    _release(db, [reservation], cancelled_by="member")

    # 트레이너는 이 취소를 앱에서 다시 보지 않으면 알 수 없다 — 자기 일정에서
    # 한 줄이 조용히 사라질 뿐이다. (#502, 인박스는 #503)
    if trainer_id is not None:
        local = starts_at.astimezone(SEOUL) if starts_at is not None else None
        notification_service.queue_for_trainer(
            db,
            trainer_id=trainer_id,
            kind=notification_service.TRAINER_RESERVATION_KIND,
            title="예약이 취소되었습니다",
            body=(
                f"{member_name} 회원 · {local:%m월 %d일 %H:%M}"
                if local is not None
                else f"{member_name} 회원"
            ),
        )
    db.commit()
