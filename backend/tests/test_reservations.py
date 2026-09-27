from __future__ import annotations

from datetime import datetime, timedelta, timezone
from unittest.mock import Mock, call
from uuid import uuid4

import pytest
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.models import (
    TrainerReservation,
    TrainerReservationSlot,
    TrainerSchedule,
    User,
)
from app.services import reservation_service, trainer_service


def test_reserve_flushes_schedule_before_reservation() -> None:
    """The schedule FK target must exist before PostgreSQL inserts a booking."""
    now = datetime.now(timezone.utc)
    slot = TrainerReservationSlot(
        id="slot-order-test",
        trainer_id="trainer-demo",
        starts_at=now + timedelta(days=1),
        duration_minutes=60,
        capacity=1,
        remaining=1,
        session_type="1:1 PT",
    )
    member = User(
        id="member-order-test",
        email="member-order-test@oncare.com",
        name="예약 순서 회원",
        role="member",
    )
    db = Mock(spec=Session)
    db.scalar.side_effect = [slot, "trainer-client-id", None]
    # 겹침 검사(#2284)가 읽는 트레이너의 그날 일정 — 비어 있다.
    db.scalars.return_value.all.return_value = []

    def set_database_defaults(instance) -> None:
        if isinstance(instance, TrainerReservation):
            instance.created_at = now

    db.refresh.side_effect = set_database_defaults

    result = reservation_service.reserve(db, member, slot.id, now=now)

    call_names = [entry[0] for entry in db.mock_calls]
    first_add = call_names.index("add")
    flush = call_names.index("flush")
    second_add = call_names.index("add", first_add + 1)
    commit = call_names.index("commit")
    assert first_add < flush < second_add < commit
    assert result.schedule_id.startswith("sched-")
    assert slot.remaining == 0


def test_reserved_schedule_is_blocked_from_regular_update_and_delete() -> None:
    schedule = TrainerSchedule(
        id="reserved-schedule-test",
        trainer_id="trainer-demo",
    )
    db = Mock(spec=Session)
    db.get.return_value = schedule
    db.scalar.return_value = "reservation-test"

    with pytest.raises(trainer_service.ScheduleConflict):
        trainer_service.update_session(
            db,
            "trainer-demo",
            schedule.id,
            {"time": "09:00"},
        )
    with pytest.raises(trainer_service.ScheduleConflict):
        trainer_service.delete_session(db, "trainer-demo", schedule.id)

    db.commit.assert_not_called()
    db.delete.assert_not_called()


def test_account_deletion_restores_seat_before_removing_booking() -> None:
    slot = TrainerReservationSlot(
        id="account-delete-slot",
        trainer_id="trainer-demo",
        capacity=2,
        remaining=1,
        starts_at=datetime.now(timezone.utc) + timedelta(days=1),
    )
    reservation = TrainerReservation(
        id="account-delete-reservation",
        member_id="account-delete-member",
        slot_id=slot.id,
        schedule_id="account-delete-schedule",
        status="booked",
    )
    schedule = TrainerSchedule(
        id=reservation.schedule_id,
        trainer_id="trainer-demo",
    )
    reservation_rows = Mock()
    reservation_rows.all.return_value = [reservation]
    slot_rows = Mock()
    slot_rows.all.return_value = [slot]
    db = Mock(spec=Session)
    db.scalars.side_effect = [reservation_rows, slot_rows]
    db.get.return_value = schedule

    reservation_service.cancel_member_reservations_for_account_deletion(
        db, reservation.member_id
    )

    assert slot.remaining == 2
    assert db.mock_calls.index(call.delete(reservation)) < db.mock_calls.index(
        call.flush()
    )
    assert db.mock_calls.index(call.flush()) < db.mock_calls.index(
        call.delete(schedule)
    )


def _login(client, email: str) -> str:
    response = client.post(
        "/v1/auth/login",
        data={"username": email, "password": "oncare123"},
    )
    assert response.status_code == 200, response.text
    return response.json()["access_token"]


def _headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def created_slots(db_session):
    ids: list[str] = []
    yield ids
    db_session.rollback()
    if not ids:
        return
    reservations = (
        db_session.query(TrainerReservation)
        .filter(TrainerReservation.slot_id.in_(ids))
        .all()
    )
    schedule_ids = [row.schedule_id for row in reservations]
    db_session.query(TrainerReservation).filter(
        TrainerReservation.slot_id.in_(ids)
    ).delete(synchronize_session=False)
    if schedule_ids:
        db_session.query(TrainerSchedule).filter(
            TrainerSchedule.id.in_(schedule_ids)
        ).delete(synchronize_session=False)
    db_session.query(TrainerReservationSlot).filter(
        TrainerReservationSlot.id.in_(ids)
    ).delete(synchronize_session=False)
    db_session.commit()


def _create_slot(
    client, trainer_token: str, created_slots, *, session_type: str = "1:1 PT"
):
    starts_at = datetime.now(timezone.utc) + timedelta(days=2)
    response = client.post(
        "/v1/trainer/reservation-slots",
        headers=_headers(trainer_token),
        json={"starts_at": starts_at.isoformat(), "session_type": session_type},
    )
    assert response.status_code == 201, response.text
    created_slots.append(response.json()["id"])
    return response.json()


def test_trainer_creates_and_member_lists_slots(client, created_slots):
    trainer_token = _login(client, "trainer@oncare.com")
    member_token = _login(client, "jisu@oncare.com")
    slot = _create_slot(client, trainer_token, created_slots)

    response = client.get(
        "/v1/trainers/trainer-demo/slots", headers=_headers(member_token)
    )

    assert response.status_code == 200, response.text
    selected = next(row for row in response.json() if row["id"] == slot["id"])
    # 슬롯은 늘 한 사람 몫이다(#1083) — 정원을 고를 자리가 없다.
    assert selected["capacity"] == 1
    assert selected["remaining"] == 1
    assert selected["session_type"] == "1:1 PT"


def test_reservation_persists_and_appears_in_trainer_schedule(
    client, db_session, created_slots
):
    trainer_token = _login(client, "trainer@oncare.com")
    member_token = _login(client, "jisu@oncare.com")
    slot = _create_slot(client, trainer_token, created_slots)

    booked = client.post(
        "/v1/reservations",
        headers=_headers(member_token),
        json={"slot_id": slot["id"]},
    )

    assert booked.status_code == 201, booked.text
    db_session.expire_all()
    reservation = db_session.get(TrainerReservation, booked.json()["id"])
    assert reservation is not None
    assert reservation.member_id == "user-jisu"
    persisted_slot = db_session.get(TrainerReservationSlot, slot["id"])
    assert persisted_slot.remaining == 0
    schedule = db_session.get(TrainerSchedule, booked.json()["schedule_id"])
    assert schedule is not None
    assert schedule.trainer_id == "trainer-demo"
    assert schedule.member_id == "user-jisu"
    assert schedule.client_name == "이지수"
    assert schedule.type == "1:1 PT"
    assert schedule.duration_minutes == 60

    timeline = client.get(
        "/v1/trainer/schedule",
        headers=_headers(trainer_token),
        params={"date": schedule.date},
    )
    assert timeline.status_code == 200
    assert any(row["id"] == schedule.id for row in timeline.json())


def test_trainer_slot_list_shows_booker_name_but_member_list_does_not(
    client, created_slots
):
    """트레이너는 자기 슬롯 목록에서 예약자 이름을 본다(#1394).

    같은 정보를 회원용 목록에는 싣지 않는다 — 남의 예약을 볼 이유가 없다.
    """
    trainer_token = _login(client, "trainer@oncare.com")
    member_token = _login(client, "jisu@oncare.com")
    slot = _create_slot(client, trainer_token, created_slots)

    booked = client.post(
        "/v1/reservations",
        headers=_headers(member_token),
        json={"slot_id": slot["id"]},
    )
    assert booked.status_code == 201, booked.text

    trainer_view = client.get(
        "/v1/trainer/reservation-slots", headers=_headers(trainer_token)
    )
    assert trainer_view.status_code == 200, trainer_view.text
    trainer_row = next(
        row for row in trainer_view.json() if row["id"] == slot["id"]
    )
    assert trainer_row["booked_by_name"] == "이지수"

    member_view = client.get(
        "/v1/trainers/trainer-demo/slots", headers=_headers(member_token)
    )
    assert member_view.status_code == 200, member_view.text
    member_row = next(row for row in member_view.json() if row["id"] == slot["id"])
    assert member_row["booked_by_name"] is None


def test_reserved_schedule_cannot_be_updated_or_deleted_as_regular_schedule(
    client, db_session, created_slots
):
    trainer_token = _login(client, "trainer@oncare.com")
    member_token = _login(client, "jisu@oncare.com")
    slot = _create_slot(client, trainer_token, created_slots)
    booked = client.post(
        "/v1/reservations",
        headers=_headers(member_token),
        json={"slot_id": slot["id"]},
    )
    assert booked.status_code == 201, booked.text

    reservation_id = booked.json()["id"]
    schedule_id = booked.json()["schedule_id"]
    updated = client.put(
        f"/v1/trainer/schedule/{schedule_id}",
        headers=_headers(trainer_token),
        json={"time": "09:00"},
    )
    deleted = client.delete(
        f"/v1/trainer/schedule/{schedule_id}",
        headers=_headers(trainer_token),
    )

    assert updated.status_code == 409, updated.text
    assert deleted.status_code == 409, deleted.text
    db_session.expire_all()
    assert db_session.get(TrainerReservation, reservation_id) is not None
    assert db_session.get(TrainerSchedule, schedule_id) is not None
    persisted_slot = db_session.get(TrainerReservationSlot, slot["id"])
    assert persisted_slot is not None
    assert persisted_slot.remaining == 0


def test_reserved_schedule_accepts_program_without_changing_booking(
    client, db_session, created_slots
):
    trainer_token = _login(client, "trainer@oncare.com")
    member_token = _login(client, "jisu@oncare.com")
    slot = _create_slot(client, trainer_token, created_slots)
    booked = client.post(
        "/v1/reservations",
        headers=_headers(member_token),
        json={"slot_id": slot["id"]},
    )
    assert booked.status_code == 201, booked.text

    schedule_id = booked.json()["schedule_id"]
    before = db_session.get(TrainerSchedule, schedule_id)
    assert before is not None
    original_time = before.time

    updated = client.put(
        f"/v1/trainer/schedule/{schedule_id}",
        headers=_headers(trainer_token),
        json={
            "program": [
                {
                    "name": "저강도 걷기",
                    "sets": 1,
                    "reps": "30분",
                    "weight": "-",
                }
            ]
        },
    )

    assert updated.status_code == 200, updated.text
    assert updated.json()["program"][0]["name"] == "저강도 걷기"
    db_session.expire_all()
    persisted = db_session.get(TrainerSchedule, schedule_id)
    assert persisted is not None
    assert persisted.time == original_time
    assert "저강도 걷기" in persisted.program_json
    persisted_slot = db_session.get(TrainerReservationSlot, slot["id"])
    assert persisted_slot is not None
    assert persisted_slot.remaining == 0


def test_member_account_deletion_restores_slot_and_removes_schedule(
    client, db_session
):
    suffix = uuid4().hex[:10]
    email = f"reservation-delete-{suffix}@oncare.com"
    password = "oncare123"
    registered = client.post(
        "/v1/auth/register",
        json={"email": email, "password": password, "name": "탈퇴 예약 회원"},
    )
    assert registered.status_code == 201, registered.text
    member_id = registered.json()["id"]
    member_token = _login(client, email)

    slot = TrainerReservationSlot(
        id=f"slot-delete-{suffix}",
        trainer_id="trainer-demo",
        starts_at=datetime.now(timezone.utc) + timedelta(days=2),
        capacity=1,
        remaining=0,
    )
    schedule = TrainerSchedule(
        id=f"sched-delete-{suffix}",
        trainer_id="trainer-demo",
        member_id=member_id,
        date=(datetime.now(timezone.utc) + timedelta(days=2)).date().isoformat(),
        time="10:00",
        client_name="탈퇴 예약 회원",
        type="1:1 PT",
        duration_minutes=60,
        status="예정",
        note="회원 직접 예약",
        program_json="[]",
        sort_order=0,
    )
    reservation = TrainerReservation(
        id=f"res-delete-{suffix}",
        member_id=member_id,
        slot_id=slot.id,
        schedule_id=schedule.id,
        status="booked",
    )
    db_session.add_all([slot, schedule])
    db_session.flush()
    db_session.add(reservation)
    db_session.commit()
    reservation_id = reservation.id
    schedule_id = schedule.id
    slot_id = slot.id

    deleted = client.delete("/v1/users/me", headers=_headers(member_token))

    assert deleted.status_code == 200, deleted.text
    db_session.expire_all()
    assert db_session.get(TrainerReservation, reservation_id) is None
    assert db_session.get(TrainerSchedule, schedule_id) is None
    persisted_slot = db_session.get(TrainerReservationSlot, slot_id)
    assert persisted_slot is not None
    assert persisted_slot.remaining == 1
    db_session.delete(persisted_slot)
    db_session.commit()


def test_duplicate_and_full_slot_return_409(client, created_slots):
    trainer_token = _login(client, "trainer@oncare.com")
    member_token = _login(client, "jisu@oncare.com")
    slot = _create_slot(client, trainer_token, created_slots)

    first = client.post(
        "/v1/reservations",
        headers=_headers(member_token),
        json={"slot_id": slot["id"]},
    )
    second = client.post(
        "/v1/reservations",
        headers=_headers(member_token),
        json={"slot_id": slot["id"]},
    )

    assert first.status_code == 201
    assert second.status_code == 409


def test_trainer_can_change_session_type_and_close_slot(client, created_slots):
    trainer_token = _login(client, "trainer@oncare.com")
    member_token = _login(client, "jisu@oncare.com")
    slot = _create_slot(client, trainer_token, created_slots, session_type="1:1 PT")

    updated = client.put(
        f"/v1/trainer/reservation-slots/{slot['id']}",
        headers=_headers(trainer_token),
        json={"session_type": "상담"},
    )
    assert updated.status_code == 200
    assert updated.json()["session_type"] == "상담"
    assert updated.json()["remaining"] == 1

    closed = client.delete(
        f"/v1/trainer/reservation-slots/{slot['id']}",
        headers=_headers(trainer_token),
    )
    assert closed.status_code == 200
    assert closed.json()["is_closed"] is True
    assert closed.json()["remaining"] == 0

    refused = client.post(
        "/v1/reservations",
        headers=_headers(member_token),
        json={"slot_id": slot["id"]},
    )
    assert refused.status_code == 409


def test_booked_slot_rejects_session_type_change(client, created_slots):
    """예약이 걸린 자리의 종류는 바꿀 수 없다 — 회원이 본 종류를 그대로 지킨다."""
    trainer_token = _login(client, "trainer@oncare.com")
    member_token = _login(client, "jisu@oncare.com")
    slot = _create_slot(client, trainer_token, created_slots, session_type="1:1 PT")
    booked = client.post(
        "/v1/reservations",
        headers=_headers(member_token),
        json={"slot_id": slot["id"]},
    )
    assert booked.status_code == 201, booked.text

    refused = client.put(
        f"/v1/trainer/reservation-slots/{slot['id']}",
        headers=_headers(trainer_token),
        json={"session_type": "상담"},
    )
    assert refused.status_code == 409, refused.text


def test_consultation_slot_reservation_creates_a_thirty_minute_session(
    client, db_session, created_slots
):
    """상담 슬롯을 예약하면 종류·소요 시간이 그 슬롯을 따라간다(#1083)."""
    trainer_token = _login(client, "trainer@oncare.com")
    member_token = _login(client, "jisu@oncare.com")
    slot = _create_slot(client, trainer_token, created_slots, session_type="상담")

    booked = client.post(
        "/v1/reservations",
        headers=_headers(member_token),
        json={"slot_id": slot["id"]},
    )

    assert booked.status_code == 201, booked.text
    schedule = db_session.get(TrainerSchedule, booked.json()["schedule_id"])
    assert schedule is not None
    assert schedule.type == "상담"
    assert schedule.duration_minutes == 30


def test_past_slots_are_not_returned(client, db_session, created_slots):
    slot = TrainerReservationSlot(
        id="slot-past-test",
        trainer_id="trainer-demo",
        starts_at=datetime.now(timezone.utc) - timedelta(hours=1),
        capacity=1,
        remaining=1,
    )
    db_session.add(slot)
    db_session.commit()
    created_slots.append(slot.id)
    member_token = _login(client, "jisu@oncare.com")

    response = client.get(
        "/v1/trainers/trainer-demo/slots", headers=_headers(member_token)
    )

    assert response.status_code == 200
    assert slot.id not in {row["id"] for row in response.json()}


def test_member_cannot_book_an_unassigned_trainer_slot(
    client, db_session, created_slots
):
    from app.core.security import hash_password
    from app.models.models import TrainerProfile, User

    trainer = User(
        id="reservation-other-trainer",
        email="reservation-other@oncare.com",
        name="다른 트레이너",
        hashed_password=hash_password("oncare123"),
        role="trainer",
        is_active=True,
    )
    db_session.add(trainer)
    db_session.flush()
    db_session.add(TrainerProfile(trainer_id=trainer.id))
    db_session.commit()
    try:
        token = _login(client, trainer.email)
        member_token = _login(client, "jisu@oncare.com")
        slot = _create_slot(client, token, created_slots)

        response = client.post(
            "/v1/reservations",
            headers=_headers(member_token),
            json={"slot_id": slot["id"]},
        )

        assert response.status_code == 409
    finally:
        db_session.rollback()
        db_session.query(TrainerProfile).filter(
            TrainerProfile.trainer_id == trainer.id
        ).delete(synchronize_session=False)
        db_session.query(User).filter(User.id == trainer.id).delete(
            synchronize_session=False
        )
        db_session.commit()


# ---- 회원 예약 취소 (#502) ----

def _register_member(client) -> str:
    """새 회원을 만들고 토큰을 준다. 시드 회원은 다른 테스트와 상태를 공유한다."""
    email = f"cancel-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register", json={"email": email, "password": "test-pw-1234", "name": "u"}
    )
    return client.post(
        "/v1/auth/login", data={"username": email, "password": "test-pw-1234"}
    ).json()["access_token"]


def test_member_cancels_and_the_seat_comes_back(client, db_session, created_slots):
    """취소하면 좌석이 돌아오고 트레이너 일정은 `취소` 기록으로 남는다. (#871)"""
    trainer_token = _login(client, "trainer@oncare.com")
    member_token = _login(client, "jisu@oncare.com")
    slot = _create_slot(client, trainer_token, created_slots)

    booked = client.post(
        "/v1/reservations",
        headers=_headers(member_token),
        json={"slot_id": slot["id"]},
    )
    assert booked.status_code == 201, booked.text
    reservation_id = booked.json()["id"]
    schedule_id = booked.json()["schedule_id"]

    after_booking = client.get(
        "/v1/trainers/trainer-demo/slots", headers=_headers(member_token)
    ).json()
    assert next(r for r in after_booking if r["id"] == slot["id"])["remaining"] == 0

    cancelled = client.delete(
        f"/v1/reservations/{reservation_id}", headers=_headers(member_token)
    )
    assert cancelled.status_code == 200, cancelled.text

    after_cancel = client.get(
        "/v1/trainers/trainer-demo/slots", headers=_headers(member_token)
    ).json()
    assert next(r for r in after_cancel if r["id"] == slot["id"])["remaining"] == 1

    db_session.expire_all()
    assert db_session.get(TrainerReservation, reservation_id) is None
    # 예약이 만든 트레이너 일정은 지워지지 않고 `취소` 로 남는다(#871). 예전에는
    # 지웠지만, 그러면 트레이너 화면에서 한 줄이 조용히 사라져 "그 시간에 무슨
    # 일이 있었나" 가 남지 않았다. 오지 않을 회원이 계속 잡혀 있는 문제는 상태가
    # `예정` 이 아니라는 사실이 막는다 — 오늘 처리할 일정으로 세지 않는다.
    schedule = db_session.get(TrainerSchedule, schedule_id)
    assert schedule is not None
    assert schedule.status == "취소"
    assert schedule.cancellation_source == "member"
    assert schedule.cancelled_at is not None


def test_cancelling_frees_the_slot_for_a_new_booking(client, created_slots):
    """취소한 자리는 다시 예약할 수 있다 — 유니크 제약에 걸리지 않는다."""
    trainer_token = _login(client, "trainer@oncare.com")
    member_token = _login(client, "jisu@oncare.com")
    slot = _create_slot(client, trainer_token, created_slots)

    first = client.post(
        "/v1/reservations",
        headers=_headers(member_token),
        json={"slot_id": slot["id"]},
    )
    client.delete(
        f"/v1/reservations/{first.json()['id']}", headers=_headers(member_token)
    )

    again = client.post(
        "/v1/reservations",
        headers=_headers(member_token),
        json={"slot_id": slot["id"]},
    )
    assert again.status_code == 201, again.text
    client.delete(
        f"/v1/reservations/{again.json()['id']}", headers=_headers(member_token)
    )


def test_cancelling_someone_elses_reservation_is_404(client, created_slots):
    """남의 예약은 존재조차 드러내지 않는다."""
    trainer_token = _login(client, "trainer@oncare.com")
    member_token = _login(client, "jisu@oncare.com")
    other_token = _register_member(client)
    slot = _create_slot(client, trainer_token, created_slots)

    booked = client.post(
        "/v1/reservations",
        headers=_headers(member_token),
        json={"slot_id": slot["id"]},
    )
    reservation_id = booked.json()["id"]

    stolen = client.delete(
        f"/v1/reservations/{reservation_id}", headers=_headers(other_token)
    )
    assert stolen.status_code == 404

    # 원래 주인은 여전히 취소할 수 있다.
    assert (
        client.delete(
            f"/v1/reservations/{reservation_id}", headers=_headers(member_token)
        ).status_code
        == 200
    )


def test_cancelling_twice_is_404(client, created_slots):
    trainer_token = _login(client, "trainer@oncare.com")
    member_token = _login(client, "jisu@oncare.com")
    slot = _create_slot(client, trainer_token, created_slots)

    booked = client.post(
        "/v1/reservations",
        headers=_headers(member_token),
        json={"slot_id": slot["id"]},
    )
    reservation_id = booked.json()["id"]

    assert (
        client.delete(
            f"/v1/reservations/{reservation_id}", headers=_headers(member_token)
        ).status_code
        == 200
    )
    assert (
        client.delete(
            f"/v1/reservations/{reservation_id}", headers=_headers(member_token)
        ).status_code
        == 404
    )


def test_cancelling_a_started_session_is_rejected(client, db_session, created_slots):
    """이미 시작한 수업은 취소할 수 없다 — 자리를 비우는 게 아니라 기록을 지우는 일이다."""
    trainer_token = _login(client, "trainer@oncare.com")
    member_token = _login(client, "jisu@oncare.com")
    slot = _create_slot(client, trainer_token, created_slots)

    booked = client.post(
        "/v1/reservations",
        headers=_headers(member_token),
        json={"slot_id": slot["id"]},
    )
    reservation_id = booked.json()["id"]

    # 슬롯 시각을 과거로 옮겨 '이미 시작한' 상태를 만든다.
    row = db_session.get(TrainerReservationSlot, slot["id"])
    row.starts_at = datetime.now(timezone.utc) - timedelta(minutes=5)
    db_session.commit()

    late = client.delete(
        f"/v1/reservations/{reservation_id}", headers=_headers(member_token)
    )
    assert late.status_code == 409, late.text

    db_session.expire_all()
    assert db_session.get(TrainerReservation, reservation_id) is not None


def test_my_reservations_lists_bookings_with_cancellable_flag(client, created_slots):
    """앱이 '내 예약'과 취소 가능 여부를 서버 판단으로 받는다."""
    trainer_token = _login(client, "trainer@oncare.com")
    member_token = _login(client, "jisu@oncare.com")
    slot = _create_slot(client, trainer_token, created_slots)

    booked = client.post(
        "/v1/reservations",
        headers=_headers(member_token),
        json={"slot_id": slot["id"]},
    )
    reservation_id = booked.json()["id"]

    mine = client.get("/v1/reservations/me", headers=_headers(member_token))
    assert mine.status_code == 200, mine.text
    row = next(r for r in mine.json() if r["id"] == reservation_id)
    assert row["slot_id"] == slot["id"]
    assert row["trainer_id"] == "trainer-demo"
    assert row["cancellable"] is True

    # 남의 예약은 보이지 않는다.
    other = client.get("/v1/reservations/me", headers=_headers(_register_member(client)))
    assert all(r["id"] != reservation_id for r in other.json())

    client.delete(
        f"/v1/reservations/{reservation_id}", headers=_headers(member_token)
    )


def test_cancel_leaves_a_notification_row_for_the_trainer(
    client, db_session, created_slots
):
    """트레이너는 일정에서 한 줄이 사라지는 것만으로는 취소를 알 수 없다.

    DB 행으로 확인하는 이유: `GET /notifications` 는 `get_current_user` 가 트레이너
    계정을 403 으로 막는 **회원 전용** 경로다(역할 분리). 트레이너가 이 행을 읽는
    경로는 인박스 작업에서 만든다(#503). 여기서는 취소가 알림을 남기는 것까지가
    범위다.
    """
    from app.models.models import Notification

    trainer_token = _login(client, "trainer@oncare.com")
    member_token = _login(client, "jisu@oncare.com")
    slot = _create_slot(client, trainer_token, created_slots)

    booked = client.post(
        "/v1/reservations",
        headers=_headers(member_token),
        json={"slot_id": slot["id"]},
    )
    before = db_session.scalars(
        select(Notification).where(Notification.user_id == "trainer-demo")
    ).all()

    client.delete(
        f"/v1/reservations/{booked.json()['id']}", headers=_headers(member_token)
    )

    db_session.expire_all()
    after = db_session.scalars(
        select(Notification).where(Notification.user_id == "trainer-demo")
    ).all()
    assert len(after) == len(before) + 1
    assert any("취소" in row.title for row in after)
