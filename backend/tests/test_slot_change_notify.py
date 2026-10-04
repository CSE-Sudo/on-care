"""예약된 슬롯의 시각·길이를 바꾸면 회원에게 알린다. (#2290)

트레이너가 예약이 걸린 자리를 옮기거나 늘리고 줄이면 회원 일정은 함께 바뀌었지만
알림이 가지 않았다. 회원은 예약할 때 본 시각을 믿고 그대로 나간다. 일반 일정
수정과 같은 알림(`일정이 변경됐어요`)이 같은 기준으로 가는지를 본다 — 실제로
시각·길이가 달라진 경우만, 예약이 걸린 자리만.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from unittest.mock import Mock

import pytest
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.clock import SEOUL
from app.models.models import (
    Notification,
    TrainerReservation,
    TrainerReservationSlot,
    TrainerSchedule,
)
from app.services import notification_service, reservation_service
from app.services.trainer import _common as trainer_common_service
from app.services.trainer import schedule as trainer_schedule_service

TRAINER_EMAIL = "trainer@oncare.com"
MEMBER_EMAIL = "jisu@oncare.com"
MEMBER_ID = "user-jisu"
CHANGED_TITLE = "일정이 변경됐어요"


# ---------------------------------------------------------------------------
# 서비스 단위 — DB 없이 알림 큐잉 여부만 본다
# ---------------------------------------------------------------------------


def _future(days: int = 2, hours: int = 0) -> datetime:
    return (datetime.now(timezone.utc) + timedelta(days=days, hours=hours)).replace(
        second=0, microsecond=0
    )


def _local(value: datetime) -> tuple[str, str]:
    local = value.astimezone(SEOUL)
    return local.date().isoformat(), local.strftime("%H:%M")


def _slot(starts_at: datetime, *, duration: int = 60) -> TrainerReservationSlot:
    return TrainerReservationSlot(
        id="unit-slot",
        trainer_id="trainer-demo",
        starts_at=starts_at,
        duration_minutes=duration,
        capacity=1,
        remaining=0,
        session_type="1:1 PT",
        is_closed=False,
    )


def _schedule(
    starts_at: datetime,
    *,
    duration: int = 60,
    schedule_id: str = "unit-schedule",
    member_id: str | None = "unit-member",
) -> TrainerSchedule:
    date, time = _local(starts_at)
    return TrainerSchedule(
        id=schedule_id,
        trainer_id="trainer-demo",
        member_id=member_id,
        date=date,
        time=time,
        client_name="회원",
        type="1:1 PT",
        duration_minutes=duration,
        status=trainer_common_service.SCHEDULE_UPCOMING,
    )


def _mentions(row: dict, *texts: str) -> bool:
    """알림 인자 어딘가에 [texts] 가 모두 실렸는가 — 본문이든 문장 틀 인자든."""
    flat = repr(row)
    return all(text in flat for text in texts)


@pytest.fixture
def unit(monkeypatch):
    """슬롯 하나와 그 자리에 걸린 일정 목록, 큐잉된 알림을 들고 있는 단위 환경."""

    class Env:
        def __init__(self) -> None:
            self.starts_at = _future()
            self.slot = _slot(self.starts_at)
            self.schedules = [_schedule(self.starts_at)]
            self.queued: list[dict] = []
            self.db = Mock(spec=Session)
            self.db.scalar.return_value = self.slot

    env = Env()
    monkeypatch.setattr(
        reservation_service, "_booked_schedules", lambda db, slot_id: env.schedules
    )
    monkeypatch.setattr(reservation_service, "_ensure_slot_free", lambda *a, **k: None)
    monkeypatch.setattr(reservation_service, "_slot_out", lambda slot: slot)
    monkeypatch.setattr(
        notification_service, "queue", lambda db, **kwargs: env.queued.append(kwargs)
    )
    return env


def test_moving_a_booked_slot_notifies_the_member(unit) -> None:
    """시각을 옮기면 회원에게 새 시각으로 변경 알림이 간다."""
    moved = unit.starts_at + timedelta(hours=3)

    reservation_service.update_slot(
        unit.db, "trainer-demo", unit.slot.id, {"starts_at": moved}
    )

    date, time = _local(moved)
    assert len(unit.queued) == 1
    row = unit.queued[0]
    assert row["member_id"] == "unit-member"
    assert row["kind"] == notification_service.PT_LINK_NOTICE
    assert row["category"] == notification_service.MEMBER_SCHEDULE
    assert _mentions(row, date, time)
    unit.db.commit.assert_called_once()


def test_moving_to_another_day_uses_the_new_date(unit) -> None:
    """날짜가 바뀌는 이동은 알림 본문에 새 날짜가 실린다."""
    moved = unit.starts_at + timedelta(days=2)

    reservation_service.update_slot(
        unit.db, "trainer-demo", unit.slot.id, {"starts_at": moved}
    )

    date, time = _local(moved)
    assert len(unit.queued) == 1
    assert _mentions(unit.queued[0], date, time)


def test_changing_duration_notifies_the_member(unit) -> None:
    """길이만 바꿔도 회원이 머무를 시간이 달라지므로 알린다."""
    reservation_service.update_slot(
        unit.db, "trainer-demo", unit.slot.id, {"duration_minutes": 90}
    )

    assert [row["member_id"] for row in unit.queued] == ["unit-member"]
    assert unit.schedules[0].duration_minutes == 90


def test_moving_and_resizing_together_notifies_once(unit) -> None:
    """시각과 길이를 한 번에 바꾸면 알림은 한 번이다."""
    reservation_service.update_slot(
        unit.db,
        "trainer-demo",
        unit.slot.id,
        {"starts_at": unit.starts_at + timedelta(hours=1), "duration_minutes": 30},
    )

    assert len(unit.queued) == 1


def test_same_time_and_duration_is_silent(unit) -> None:
    """같은 값을 다시 보내면(실제 변경 없음) 알리지 않는다."""
    reservation_service.update_slot(
        unit.db,
        "trainer-demo",
        unit.slot.id,
        {"starts_at": unit.starts_at, "duration_minutes": 60},
    )

    assert unit.queued == []
    unit.db.commit.assert_called_once()


def test_slot_without_booking_is_silent(unit) -> None:
    """예약이 없는 자리는 옮겨도 알릴 회원이 없다."""
    unit.schedules = []

    reservation_service.update_slot(
        unit.db,
        "trainer-demo",
        unit.slot.id,
        {"starts_at": unit.starts_at + timedelta(hours=2), "duration_minutes": 45},
    )

    assert unit.queued == []
    assert unit.slot.duration_minutes == 45


def test_closing_a_booked_slot_is_silent(unit) -> None:
    """자리를 닫는 것은 잡힌 예약을 건드리지 않으므로 알리지 않는다."""
    reservation_service.update_slot(
        unit.db, "trainer-demo", unit.slot.id, {"is_closed": True}
    )

    assert unit.queued == []
    assert unit.slot.is_closed is True


def test_every_booked_member_is_notified(unit) -> None:
    """한 자리에 걸린 예약이 여럿이면 각 회원에게 한 번씩 알린다."""
    unit.schedules = [
        _schedule(unit.starts_at, schedule_id="s-a", member_id="member-a"),
        _schedule(unit.starts_at, schedule_id="s-b", member_id="member-b"),
    ]

    reservation_service.update_slot(
        unit.db,
        "trainer-demo",
        unit.slot.id,
        {"starts_at": unit.starts_at + timedelta(hours=4)},
    )

    assert sorted(row["member_id"] for row in unit.queued) == ["member-a", "member-b"]


def test_schedule_without_member_is_silent(unit) -> None:
    """회원이 비어 있는 일정(정합이 어긋난 행)은 알림 대상이 없다."""
    unit.schedules = [_schedule(unit.starts_at, member_id=None)]

    reservation_service.update_slot(
        unit.db,
        "trainer-demo",
        unit.slot.id,
        {"starts_at": unit.starts_at + timedelta(hours=1)},
    )

    assert unit.queued == []


def test_past_time_rejection_queues_nothing(unit) -> None:
    """지난 시간으로 옮기려다 거절되면 알림도 없고 커밋도 없다."""
    with pytest.raises(reservation_service.SlotUnavailable):
        reservation_service.update_slot(
            unit.db,
            "trainer-demo",
            unit.slot.id,
            {"starts_at": datetime.now(timezone.utc) - timedelta(hours=1)},
        )

    assert unit.queued == []
    unit.db.commit.assert_not_called()


def test_overlap_rejection_queues_nothing(unit, monkeypatch) -> None:
    """겹침으로 거절되면 일정도 알림도 그대로다."""

    def overlap(*args, **kwargs):
        raise trainer_schedule_service.ScheduleOverlap([])

    monkeypatch.setattr(reservation_service, "_ensure_slot_free", overlap)
    before = (unit.schedules[0].date, unit.schedules[0].time)

    with pytest.raises(trainer_schedule_service.ScheduleOverlap):
        reservation_service.update_slot(
            unit.db,
            "trainer-demo",
            unit.slot.id,
            {"starts_at": unit.starts_at + timedelta(hours=1)},
        )

    assert unit.queued == []
    assert (unit.schedules[0].date, unit.schedules[0].time) == before
    unit.db.commit.assert_not_called()


def test_uses_the_shared_schedule_change_helper(unit, monkeypatch) -> None:
    """일반 일정 수정과 같은 헬퍼로, 바꾸기 전 값을 넘겨 알린다."""
    calls: list[dict] = []
    monkeypatch.setattr(
        trainer_schedule_service,
        "_notify_schedule_changed",
        lambda db, **kwargs: calls.append(kwargs),
    )
    before_slot = trainer_schedule_service._member_visible_slot(unit.schedules[0])

    reservation_service.update_slot(
        unit.db,
        "trainer-demo",
        unit.slot.id,
        {"starts_at": unit.starts_at + timedelta(hours=2)},
    )

    assert len(calls) == 1
    assert calls[0]["session"] is unit.schedules[0]
    assert calls[0]["before_member_id"] == "unit-member"
    assert calls[0]["before_slot"] == before_slot


# ---------------------------------------------------------------------------
# API 경로 — DB 필요
# ---------------------------------------------------------------------------


def _login(client, email: str) -> str:
    response = client.post(
        "/v1/auth/login",
        data={"username": email, "password": "oncare123"},
    )
    assert response.status_code == 200, response.text
    return response.json()["access_token"]


def _headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


class _Created:
    def __init__(self) -> None:
        self.slots: list[str] = []
        self.schedules: list[str] = []


@pytest.fixture
def created_slots(db_session):
    """테스트가 만든 슬롯·예약·일정을 지운다."""
    created = _Created()
    yield created
    db_session.rollback()
    if not created.slots:
        return
    db_session.query(TrainerReservation).filter(
        TrainerReservation.slot_id.in_(created.slots)
    ).delete(synchronize_session=False)
    if created.schedules:
        db_session.query(TrainerSchedule).filter(
            TrainerSchedule.id.in_(created.schedules)
        ).delete(synchronize_session=False)
    db_session.query(TrainerReservationSlot).filter(
        TrainerReservationSlot.id.in_(created.slots)
    ).delete(synchronize_session=False)
    db_session.commit()


def _slot_start(created: _Created) -> datetime:
    # 같은 테스트 안의 슬롯끼리, 그리고 옮길 자리까지 겹치지 않게 넉넉히 민다.
    return (
        datetime.now(timezone.utc) + timedelta(days=11, hours=4 * len(created.slots))
    ).replace(second=0, microsecond=0)


def _create_slot(client, trainer_token: str, created: _Created) -> dict:
    response = client.post(
        "/v1/trainer/reservation-slots",
        headers=_headers(trainer_token),
        json={"starts_at": _slot_start(created).isoformat(), "session_type": "1:1 PT"},
    )
    assert response.status_code == 201, response.text
    created.slots.append(response.json()["id"])
    return response.json()


def _book(client, member_token: str, slot_id: str, created: _Created) -> dict:
    response = client.post(
        "/v1/reservations",
        headers=_headers(member_token),
        json={"slot_id": slot_id},
    )
    assert response.status_code == 201, response.text
    booked = response.json()
    created.schedules.append(booked["schedule_id"])
    return booked


def _update(client, token: str, slot_id: str, **body):
    return client.put(
        f"/v1/trainer/reservation-slots/{slot_id}",
        headers=_headers(token),
        json=body,
    )


def _changed_notices(db_session) -> list[Notification]:
    db_session.expire_all()
    return list(
        db_session.scalars(
            select(Notification).where(
                Notification.user_id == MEMBER_ID,
                Notification.title == CHANGED_TITLE,
            )
        ).all()
    )


def _starts(slot: dict) -> datetime:
    return datetime.fromisoformat(slot["starts_at"])


def test_api_moving_booked_slot_notifies_member(client, db_session, created_slots):
    """예약된 자리를 옮기면 회원 알림함에 새 시각의 변경 알림이 생긴다."""
    trainer_token = _login(client, TRAINER_EMAIL)
    member_token = _login(client, MEMBER_EMAIL)
    slot = _create_slot(client, trainer_token, created_slots)
    booked = _book(client, member_token, slot["id"], created_slots)
    before = len(_changed_notices(db_session))
    moved = _starts(slot) + timedelta(hours=1, minutes=30)

    response = _update(client, trainer_token, slot["id"], starts_at=moved.isoformat())

    assert response.status_code == 200, response.text
    notices = _changed_notices(db_session)
    assert len(notices) == before + 1
    date, time = _local(moved)
    assert f"{date} {time} · 1:1 PT" in {row.body for row in notices}
    schedule = db_session.get(TrainerSchedule, booked["schedule_id"])
    assert (schedule.date, schedule.time) == (date, time)


def test_api_resizing_booked_slot_notifies_member(client, db_session, created_slots):
    """예약된 자리의 길이를 바꾸면 알린다."""
    trainer_token = _login(client, TRAINER_EMAIL)
    member_token = _login(client, MEMBER_EMAIL)
    slot = _create_slot(client, trainer_token, created_slots)
    booked = _book(client, member_token, slot["id"], created_slots)
    before = len(_changed_notices(db_session))

    response = _update(client, trainer_token, slot["id"], duration_minutes=90)

    assert response.status_code == 200, response.text
    assert len(_changed_notices(db_session)) == before + 1
    schedule = db_session.get(TrainerSchedule, booked["schedule_id"])
    assert schedule.duration_minutes == 90


def test_api_same_values_do_not_notify(client, db_session, created_slots):
    """같은 시각·길이를 다시 저장하면 알림이 쌓이지 않는다."""
    trainer_token = _login(client, TRAINER_EMAIL)
    member_token = _login(client, MEMBER_EMAIL)
    slot = _create_slot(client, trainer_token, created_slots)
    _book(client, member_token, slot["id"], created_slots)
    before = len(_changed_notices(db_session))

    response = _update(
        client,
        trainer_token,
        slot["id"],
        starts_at=slot["starts_at"],
        duration_minutes=slot["duration_minutes"],
    )

    assert response.status_code == 200, response.text
    assert len(_changed_notices(db_session)) == before


def test_api_unbooked_slot_does_not_notify(client, db_session, created_slots):
    """예약이 없는 자리를 옮기면 아무에게도 알리지 않는다."""
    trainer_token = _login(client, TRAINER_EMAIL)
    slot = _create_slot(client, trainer_token, created_slots)
    before = len(_changed_notices(db_session))

    response = _update(
        client,
        trainer_token,
        slot["id"],
        starts_at=(_starts(slot) + timedelta(hours=1)).isoformat(),
        duration_minutes=45,
    )

    assert response.status_code == 200, response.text
    assert len(_changed_notices(db_session)) == before


def test_api_cancelled_reservation_does_not_notify(client, db_session, created_slots):
    """회원이 취소한 예약의 자리를 옮기면, 떠난 회원에게 알리지 않는다."""
    trainer_token = _login(client, TRAINER_EMAIL)
    member_token = _login(client, MEMBER_EMAIL)
    slot = _create_slot(client, trainer_token, created_slots)
    booked = _book(client, member_token, slot["id"], created_slots)
    cancelled = client.delete(
        f"/v1/reservations/{booked['id']}", headers=_headers(member_token)
    )
    assert cancelled.status_code == 200, cancelled.text
    before = len(_changed_notices(db_session))

    response = _update(
        client,
        trainer_token,
        slot["id"],
        starts_at=(_starts(slot) + timedelta(hours=2)).isoformat(),
    )

    assert response.status_code == 200, response.text
    assert len(_changed_notices(db_session)) == before
    # 취소 기록으로 남은 일정은 옛 시각 그대로다.
    schedule = db_session.get(TrainerSchedule, booked["schedule_id"])
    assert (schedule.date, schedule.time) == _local(_starts(slot))


def test_api_trainer_cancelled_reservation_does_not_notify(
    client, db_session, created_slots
):
    """트레이너가 취소해 풀린 자리도 옮길 때 알리지 않는다."""
    trainer_token = _login(client, TRAINER_EMAIL)
    member_token = _login(client, MEMBER_EMAIL)
    slot = _create_slot(client, trainer_token, created_slots)
    booked = _book(client, member_token, slot["id"], created_slots)
    cancelled = client.post(
        f"/v1/trainer/schedule/{booked['schedule_id']}/cancel",
        json={"source": "trainer"},
        headers=_headers(trainer_token),
    )
    assert cancelled.status_code == 200, cancelled.text
    before = len(_changed_notices(db_session))

    response = _update(client, trainer_token, slot["id"], duration_minutes=30)

    assert response.status_code == 200, response.text
    assert len(_changed_notices(db_session)) == before


def test_api_closing_booked_slot_does_not_notify(client, db_session, created_slots):
    """예약된 자리를 닫아도 잡힌 약속은 그대로라 알리지 않는다."""
    trainer_token = _login(client, TRAINER_EMAIL)
    member_token = _login(client, MEMBER_EMAIL)
    slot = _create_slot(client, trainer_token, created_slots)
    _book(client, member_token, slot["id"], created_slots)
    before = len(_changed_notices(db_session))

    response = client.delete(
        f"/v1/trainer/reservation-slots/{slot['id']}", headers=_headers(trainer_token)
    )

    assert response.status_code == 200, response.text
    assert len(_changed_notices(db_session)) == before


def test_api_overlap_rejection_does_not_notify(client, db_session, created_slots):
    """다른 예약 일정과 겹쳐 409 로 거절되면 알림도 일정 변경도 없다."""
    trainer_token = _login(client, TRAINER_EMAIL)
    member_token = _login(client, MEMBER_EMAIL)
    first = _create_slot(client, trainer_token, created_slots)
    second = _create_slot(client, trainer_token, created_slots)
    booked = _book(client, member_token, first["id"], created_slots)
    _book(client, member_token, second["id"], created_slots)
    before = len(_changed_notices(db_session))

    response = _update(
        client, trainer_token, first["id"], starts_at=second["starts_at"]
    )

    assert response.status_code == 409, response.text
    assert len(_changed_notices(db_session)) == before
    schedule = db_session.get(TrainerSchedule, booked["schedule_id"])
    assert (schedule.date, schedule.time) == _local(_starts(first))


def test_api_unknown_slot_does_not_notify(client, db_session, created_slots):
    """없는 슬롯은 404 이고 알림도 없다."""
    trainer_token = _login(client, TRAINER_EMAIL)
    before = len(_changed_notices(db_session))

    response = _update(
        client,
        trainer_token,
        "slot-does-not-exist",
        starts_at=_slot_start(created_slots).isoformat(),
    )

    assert response.status_code == 404, response.text
    assert len(_changed_notices(db_session)) == before
