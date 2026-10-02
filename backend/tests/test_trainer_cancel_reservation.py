"""트레이너가 취소한 예약 세션 — 예약 정리·좌석 반환·회원 목록 반영. (#2283)

회원이 예약한 자리를 트레이너가 스케줄 화면에서 취소하면 일정만 `취소` 가 되고
예약 행과 좌석은 그대로 남았다. 회원 앱에는 '예약됨·취소 가능'으로 계속 보였고
그 시간은 다시 예약할 수 없었다. 여기서는 트레이너 취소가 회원 취소와 같은
결과(예약 삭제·좌석 복구·일정은 `취소` 기록으로 유지)를 내는지를 본다.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from unittest.mock import Mock, call
from uuid import uuid4

import pytest
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.security import create_access_token
from app.models.models import (
    Notification,
    TrainerReservation,
    TrainerReservationSlot,
    TrainerSchedule,
    User,
)
from app.services import reservation_service
from app.services.trainer import _common as trainer_common_service

TRAINER_EMAIL = "trainer@oncare.com"
MEMBER_EMAIL = "jisu@oncare.com"
MEMBER_ID = "user-jisu"
CANCELLED_TITLE = "일정이 취소되었어요"


# ---------------------------------------------------------------------------
# 서비스 단위 — DB 없이 호출 순서와 좌석 계산만 본다
# ---------------------------------------------------------------------------


def _rows(values: list) -> Mock:
    rows = Mock()
    rows.all.return_value = values
    return rows


def _unit_fixture(*, schedule_status: str):
    slot = TrainerReservationSlot(
        id="unit-slot",
        trainer_id="trainer-demo",
        capacity=1,
        remaining=0,
        starts_at=datetime.now(timezone.utc) + timedelta(days=1),
    )
    reservation = TrainerReservation(
        id="unit-reservation",
        member_id="unit-member",
        slot_id=slot.id,
        schedule_id="unit-schedule",
        status="booked",
    )
    schedule = TrainerSchedule(
        id=reservation.schedule_id,
        trainer_id="trainer-demo",
        status=schedule_status,
        cancellation_source="trainer",
        cancellation_reason="개인 사정",
    )
    return slot, reservation, schedule


def test_release_for_cancelled_schedule_restores_seat_and_keeps_record() -> None:
    """이미 `취소` 로 바뀐 일정은 그대로 두고 좌석과 예약만 정리한다."""
    slot, reservation, schedule = _unit_fixture(
        schedule_status=trainer_common_service.SCHEDULE_CANCELLED
    )
    cancelled_at = datetime.now(timezone.utc) - timedelta(minutes=1)
    schedule.cancelled_at = cancelled_at
    db = Mock(spec=Session)
    db.scalars.side_effect = [_rows([reservation]), _rows([slot])]
    db.get.return_value = schedule

    released = reservation_service.release_for_cancelled_schedule(
        db, schedule.id, cancelled_by="trainer"
    )

    assert released == [reservation]
    assert slot.remaining == 1
    db.delete.assert_called_once_with(reservation)
    # 일정은 지우지 않는다 — 트레이너 화면에 취소 기록으로 남아야 한다.
    assert call.delete(schedule) not in db.mock_calls
    # 트레이너가 남긴 사유·시각을 덮어쓰지 않는다.
    assert schedule.cancellation_reason == "개인 사정"
    assert schedule.cancelled_at == cancelled_at
    db.commit.assert_not_called()


def test_release_for_cancelled_schedule_never_exceeds_capacity() -> None:
    """좌석이 이미 차 있지 않아도(정합이 어긋난 행) 정원을 넘지 않는다."""
    slot, reservation, schedule = _unit_fixture(
        schedule_status=trainer_common_service.SCHEDULE_CANCELLED
    )
    slot.remaining = 1
    db = Mock(spec=Session)
    db.scalars.side_effect = [_rows([reservation]), _rows([slot])]
    db.get.return_value = schedule

    reservation_service.release_for_cancelled_schedule(
        db, schedule.id, cancelled_by="trainer"
    )

    assert slot.remaining == slot.capacity == 1


def test_release_for_cancelled_schedule_without_reservation_is_noop() -> None:
    """일반 일정(예약 없음)은 아무것도 건드리지 않는다."""
    db = Mock(spec=Session)
    db.scalars.return_value = _rows([])

    released = reservation_service.release_for_cancelled_schedule(
        db, "plain-schedule", cancelled_by="trainer"
    )

    assert released == []
    db.delete.assert_not_called()
    db.flush.assert_not_called()
    db.commit.assert_not_called()


def test_release_marks_upcoming_schedule_with_given_source() -> None:
    """호출 순서상 일정이 아직 `예정` 이면 넘겨받은 주체로 취소 기록을 남긴다."""
    slot, reservation, schedule = _unit_fixture(
        schedule_status=trainer_common_service.SCHEDULE_UPCOMING
    )
    schedule.cancellation_source = None
    db = Mock(spec=Session)
    db.scalars.side_effect = [_rows([reservation]), _rows([slot])]
    db.get.return_value = schedule

    reservation_service.release_for_cancelled_schedule(
        db, schedule.id, cancelled_by="other"
    )

    assert schedule.status == trainer_common_service.SCHEDULE_CANCELLED
    assert schedule.cancellation_source == "other"
    assert schedule.cancelled_at is not None


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
    """테스트가 만든 슬롯과 예약 일정 id."""

    def __init__(self) -> None:
        self.slots: list[str] = []
        self.schedules: list[str] = []


@pytest.fixture
def created_slots(db_session):
    """테스트가 만든 슬롯·예약·일정을 지운다.

    트레이너 취소는 예약 행을 지우고 일정만 남기므로, 예약으로 일정을 찾는
    것만으로는 정리가 끝나지 않는다 — 예약할 때 일정 id 를 따로 모아 둔다.
    """
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


def _create_slot(client, trainer_token: str, created: _Created) -> dict:
    # 같은 테스트 안의 슬롯끼리 시간 구간이 겹치지 않게 민다 — 기본 길이가
    # 60분이라 몇 분 차이로는 겹침(#2284)으로 예약이 막힌다.
    starts_at = datetime.now(timezone.utc) + timedelta(
        days=3, hours=2 * len(created.slots)
    )
    response = client.post(
        "/v1/trainer/reservation-slots",
        headers=_headers(trainer_token),
        json={"starts_at": starts_at.isoformat(), "session_type": "1:1 PT"},
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


def _trainer_cancel(client, token: str, schedule_id: str, **body):
    payload = {"source": "trainer"}
    payload.update(body)
    return client.post(
        f"/v1/trainer/schedule/{schedule_id}/cancel",
        json=payload,
        headers=_headers(token),
    )


def _member_slot(client, member_token: str, slot_id: str) -> dict:
    rows = client.get(
        "/v1/trainers/trainer-demo/slots", headers=_headers(member_token)
    ).json()
    return next(row for row in rows if row["id"] == slot_id)


def _my_reservation_ids(client, member_token: str) -> set[str]:
    response = client.get("/v1/reservations/me", headers=_headers(member_token))
    assert response.status_code == 200, response.text
    return {row["id"] for row in response.json()}


def _member_cancel_notices(db_session) -> int:
    db_session.expire_all()
    return len(
        db_session.scalars(
            select(Notification).where(
                Notification.user_id == MEMBER_ID,
                Notification.title == CANCELLED_TITLE,
            )
        ).all()
    )


def test_trainer_cancel_releases_reservation_and_seat(
    client, db_session, created_slots
):
    """트레이너가 취소하면 예약이 지워지고 좌석이 돌아오며 일정은 기록으로 남는다."""
    trainer_token = _login(client, TRAINER_EMAIL)
    member_token = _login(client, MEMBER_EMAIL)
    slot = _create_slot(client, trainer_token, created_slots)
    booked = _book(client, member_token, slot["id"], created_slots)
    assert _member_slot(client, member_token, slot["id"])["remaining"] == 0
    assert booked["id"] in _my_reservation_ids(client, member_token)

    cancelled = _trainer_cancel(
        client, trainer_token, booked["schedule_id"], reason="트레이너 개인 사정"
    )

    assert cancelled.status_code == 200, cancelled.text
    body = cancelled.json()
    assert body["status"] == "취소"
    assert body["cancellation_source"] == "trainer"
    assert body["cancellation_reason"] == "트레이너 개인 사정"
    assert body["cancelled_at"] is not None

    assert _member_slot(client, member_token, slot["id"])["remaining"] == 1
    assert booked["id"] not in _my_reservation_ids(client, member_token)

    db_session.expire_all()
    assert db_session.get(TrainerReservation, booked["id"]) is None
    schedule = db_session.get(TrainerSchedule, booked["schedule_id"])
    assert schedule is not None
    assert schedule.status == "취소"
    assert schedule.cancellation_source == "trainer"
    assert schedule.cancellation_reason == "트레이너 개인 사정"


def test_trainer_cancel_keeps_the_source_the_trainer_chose(
    client, db_session, created_slots
):
    """회원 사정으로 고른 취소는 예약 정리 뒤에도 `member` 로 남는다."""
    trainer_token = _login(client, TRAINER_EMAIL)
    member_token = _login(client, MEMBER_EMAIL)
    slot = _create_slot(client, trainer_token, created_slots)
    booked = _book(client, member_token, slot["id"], created_slots)

    cancelled = _trainer_cancel(
        client, trainer_token, booked["schedule_id"], source="member"
    )

    assert cancelled.status_code == 200, cancelled.text
    assert cancelled.json()["cancellation_source"] == "member"
    db_session.expire_all()
    schedule = db_session.get(TrainerSchedule, booked["schedule_id"])
    assert schedule.cancellation_source == "member"
    assert _member_slot(client, member_token, slot["id"])["remaining"] == 1


def test_member_can_rebook_the_slot_after_trainer_cancel(client, created_slots):
    """트레이너가 취소한 시간은 다시 예약할 수 있다 — 유니크 제약에 걸리지 않는다."""
    trainer_token = _login(client, TRAINER_EMAIL)
    member_token = _login(client, MEMBER_EMAIL)
    slot = _create_slot(client, trainer_token, created_slots)
    booked = _book(client, member_token, slot["id"], created_slots)
    assert _trainer_cancel(client, trainer_token, booked["schedule_id"]).status_code == 200

    again = _book(client, member_token, slot["id"], created_slots)

    assert again["id"] != booked["id"]
    assert again["schedule_id"] != booked["schedule_id"]
    assert again["id"] in _my_reservation_ids(client, member_token)
    assert _member_slot(client, member_token, slot["id"])["remaining"] == 0


def test_trainer_slot_list_drops_booker_after_trainer_cancel(client, created_slots):
    """트레이너 슬롯 목록의 예약자 이름도 사라진다 — 빈 자리로 보인다."""
    trainer_token = _login(client, TRAINER_EMAIL)
    member_token = _login(client, MEMBER_EMAIL)
    slot = _create_slot(client, trainer_token, created_slots)
    booked = _book(client, member_token, slot["id"], created_slots)

    def trainer_row() -> dict:
        rows = client.get(
            "/v1/trainer/reservation-slots", headers=_headers(trainer_token)
        ).json()
        return next(row for row in rows if row["id"] == slot["id"])

    assert trainer_row()["booked_by_name"]
    assert _trainer_cancel(client, trainer_token, booked["schedule_id"]).status_code == 200
    row = trainer_row()
    assert row["booked_by_name"] is None
    assert row["remaining"] == 1


def test_trainer_cancel_notifies_the_member_once(client, db_session, created_slots):
    """회원은 취소 알림을 한 번 받는다. 다시 눌러도 알림이 겹치지 않는다."""
    trainer_token = _login(client, TRAINER_EMAIL)
    member_token = _login(client, MEMBER_EMAIL)
    slot = _create_slot(client, trainer_token, created_slots)
    booked = _book(client, member_token, slot["id"], created_slots)
    before = _member_cancel_notices(db_session)

    assert _trainer_cancel(client, trainer_token, booked["schedule_id"]).status_code == 200
    assert _member_cancel_notices(db_session) == before + 1

    repeated = _trainer_cancel(client, trainer_token, booked["schedule_id"])
    assert repeated.status_code == 200, repeated.text
    assert repeated.json()["status"] == "취소"
    assert _member_cancel_notices(db_session) == before + 1
    assert _member_slot(client, member_token, slot["id"])["remaining"] == 1


def test_member_cancel_after_trainer_cancel_is_404(client, created_slots):
    """트레이너가 먼저 거둔 예약은 회원 쪽에서 다시 취소할 대상이 없다."""
    trainer_token = _login(client, TRAINER_EMAIL)
    member_token = _login(client, MEMBER_EMAIL)
    slot = _create_slot(client, trainer_token, created_slots)
    booked = _book(client, member_token, slot["id"], created_slots)
    assert _trainer_cancel(client, trainer_token, booked["schedule_id"]).status_code == 200

    late = client.delete(
        f"/v1/reservations/{booked['id']}", headers=_headers(member_token)
    )

    assert late.status_code == 404
    assert _member_slot(client, member_token, slot["id"])["remaining"] == 1


def test_trainer_cancel_after_member_cancel_stays_idempotent(
    client, db_session, created_slots
):
    """회원이 먼저 취소한 일정을 트레이너가 다시 취소해도 주체·좌석이 흔들리지 않는다."""
    trainer_token = _login(client, TRAINER_EMAIL)
    member_token = _login(client, MEMBER_EMAIL)
    slot = _create_slot(client, trainer_token, created_slots)
    booked = _book(client, member_token, slot["id"], created_slots)
    assert (
        client.delete(
            f"/v1/reservations/{booked['id']}", headers=_headers(member_token)
        ).status_code
        == 200
    )

    repeated = _trainer_cancel(client, trainer_token, booked["schedule_id"])

    assert repeated.status_code == 200, repeated.text
    assert repeated.json()["cancellation_source"] == "member"
    assert _member_slot(client, member_token, slot["id"])["remaining"] == 1


def test_legacy_cancelled_booking_is_hidden_and_released_on_retry(
    client, db_session, created_slots
):
    """고치기 전에 트레이너가 취소해 예약이 남은 경우.

    회원 목록에서는 바로 빠지고, 트레이너가 취소를 다시 누르면 남은 좌석까지
    풀린다. 회원에게 같은 취소 알림이 또 가지는 않는다.
    """
    trainer_token = _login(client, TRAINER_EMAIL)
    member_token = _login(client, MEMBER_EMAIL)
    slot = _create_slot(client, trainer_token, created_slots)
    booked = _book(client, member_token, slot["id"], created_slots)

    # 예전 동작 재현: 일정만 `취소` 로 바뀌고 예약·좌석은 그대로.
    schedule = db_session.get(TrainerSchedule, booked["schedule_id"])
    schedule.status = "취소"
    schedule.cancellation_source = "trainer"
    schedule.cancelled_at = datetime.now(timezone.utc)
    db_session.commit()
    before = _member_cancel_notices(db_session)

    assert booked["id"] not in _my_reservation_ids(client, member_token)
    assert _member_slot(client, member_token, slot["id"])["remaining"] == 0

    retried = _trainer_cancel(client, trainer_token, booked["schedule_id"])

    assert retried.status_code == 200, retried.text
    assert retried.json()["status"] == "취소"
    assert _member_slot(client, member_token, slot["id"])["remaining"] == 1
    db_session.expire_all()
    assert db_session.get(TrainerReservation, booked["id"]) is None
    assert _member_cancel_notices(db_session) == before


def test_my_reservations_skip_rows_not_booked(client, db_session, created_slots):
    """예약 상태가 `booked` 가 아닌 행은 회원 목록에 '취소 가능'으로 나오지 않는다."""
    trainer_token = _login(client, TRAINER_EMAIL)
    member_token = _login(client, MEMBER_EMAIL)
    slot = _create_slot(client, trainer_token, created_slots)
    booked = _book(client, member_token, slot["id"], created_slots)

    row = db_session.get(TrainerReservation, booked["id"])
    row.status = "cancelled"
    db_session.commit()

    assert booked["id"] not in _my_reservation_ids(client, member_token)


def test_other_reservations_survive_a_trainer_cancel(client, db_session, created_slots):
    """한 세션을 취소해도 같은 회원의 다른 예약은 그대로다."""
    trainer_token = _login(client, TRAINER_EMAIL)
    member_token = _login(client, MEMBER_EMAIL)
    first_slot = _create_slot(client, trainer_token, created_slots)
    second_slot = _create_slot(client, trainer_token, created_slots)
    first = _book(client, member_token, first_slot["id"], created_slots)
    second = _book(client, member_token, second_slot["id"], created_slots)

    assert _trainer_cancel(client, trainer_token, first["schedule_id"]).status_code == 200

    mine = _my_reservation_ids(client, member_token)
    assert first["id"] not in mine
    assert second["id"] in mine
    assert _member_slot(client, member_token, second_slot["id"])["remaining"] == 0
    db_session.expire_all()
    kept = db_session.get(TrainerSchedule, second["schedule_id"])
    assert kept.status == "예정"


def test_another_trainer_cannot_cancel_a_booked_session(
    client, db_session, created_slots
):
    """남의 예약 세션은 404 — 예약과 좌석이 그대로 남는다."""
    trainer_token = _login(client, TRAINER_EMAIL)
    member_token = _login(client, MEMBER_EMAIL)
    slot = _create_slot(client, trainer_token, created_slots)
    booked = _book(client, member_token, slot["id"], created_slots)

    other_id = f"trainer-{uuid4().hex[:10]}"
    other = User(
        id=other_id,
        email=f"{other_id}@oncare.com",
        name="다른 트레이너",
        hashed_password="unused",
        role="trainer",
    )
    db_session.add(other)
    db_session.commit()
    try:
        denied = _trainer_cancel(
            client, create_access_token(other_id), booked["schedule_id"]
        )
        assert denied.status_code == 404
    finally:
        db_session.delete(other)
        db_session.commit()

    assert booked["id"] in _my_reservation_ids(client, member_token)
    assert _member_slot(client, member_token, slot["id"])["remaining"] == 0


@pytest.mark.parametrize("terminal", ["완료", "노쇼"])
def test_finished_booked_session_cannot_be_cancelled(
    client, db_session, created_slots, terminal
):
    """이미 마무리된 예약 세션은 409 — 예약·좌석을 건드리지 않는다."""
    trainer_token = _login(client, TRAINER_EMAIL)
    member_token = _login(client, MEMBER_EMAIL)
    slot = _create_slot(client, trainer_token, created_slots)
    booked = _book(client, member_token, slot["id"], created_slots)

    schedule = db_session.get(TrainerSchedule, booked["schedule_id"])
    schedule.status = terminal
    db_session.commit()

    refused = _trainer_cancel(client, trainer_token, booked["schedule_id"])

    assert refused.status_code == 409, refused.text
    db_session.expire_all()
    assert db_session.get(TrainerReservation, booked["id"]) is not None
    assert _member_slot(client, member_token, slot["id"])["remaining"] == 0


def test_invalid_source_leaves_the_booking_alone(client, db_session, created_slots):
    """취소 주체가 잘못되면 400 이고 예약은 그대로다."""
    trainer_token = _login(client, TRAINER_EMAIL)
    member_token = _login(client, MEMBER_EMAIL)
    slot = _create_slot(client, trainer_token, created_slots)
    booked = _book(client, member_token, slot["id"], created_slots)

    refused = _trainer_cancel(
        client, trainer_token, booked["schedule_id"], source="unknown"
    )

    assert refused.status_code in (400, 422), refused.text
    db_session.expire_all()
    assert db_session.get(TrainerReservation, booked["id"]) is not None
    assert db_session.get(TrainerSchedule, booked["schedule_id"]).status == "예정"
    assert _member_slot(client, member_token, slot["id"])["remaining"] == 0
