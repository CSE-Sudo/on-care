"""수락된 상담의 회원 취소. (#3359)

회원은 대기 중인 요청만 취소할 수 있었다. 수락된 뒤에는 못 가게 돼도 알릴 길이
없었고 — 담당이 아닌 회원은 그 트레이너와 대화할 수 없다 — 트레이너의 그 시간은
계속 잡혀 있었다. 이제 시작 전이면 취소할 수 있고, 취소는 상담 일정·자리·알림을
한 번에 정리한다.

DB 가 필요하므로 로컬에서는 skip 되고 CI(Postgres) 에서 실행된다.
"""
from __future__ import annotations

from datetime import timedelta

import pytest

from app.core import clock
from app.models.models import (
    ConsultationRequest,
    Notification,
    TrainerReservationSlot,
    TrainerSchedule,
)
from app.services import consultation_service, notification_templates
from app.services.trainer import _common as trainer_common_service
from app.services.trainer import schedule as trainer_schedule_service

from tests.test_consultation_decision import (  # noqa: F401 — `_cleanup` 은 정리 픽스처다
    _accept,
    _auth,
    _cleanup,
    _member,
    _request_consultation,
    _trainer,
)


def _accepted(client, db_session, *, hours_ahead: float = 48):
    """수락된 상담 하나. (trainer, trainer_token, member_id, member_token, 상담 id)"""
    trainer, trainer_token = _trainer(client, db_session)
    member_id, member_token = _member(client)
    consultation_id = _request_consultation(
        client, member_token, trainer_id=trainer.id, hours_ahead=hours_ahead
    )
    _accept(client, trainer_token, consultation_id)
    return trainer, trainer_token, member_id, member_token, consultation_id


def _cancel(client, member_token: str, consultation_id: str):
    return client.delete(
        f"/v1/consultations/{consultation_id}", headers=_auth(member_token)
    )


def _row(db_session, consultation_id: str) -> ConsultationRequest:
    db_session.expire_all()
    return db_session.get(ConsultationRequest, consultation_id)


def _schedule(db_session, consultation_id: str) -> TrainerSchedule:
    db_session.expire_all()
    return (
        db_session.query(TrainerSchedule)
        .filter(TrainerSchedule.consultation_id == consultation_id)
        .one()
    )


def _remaining(db_session, slot_id: str) -> int:
    db_session.expire_all()
    return db_session.get(TrainerReservationSlot, slot_id).remaining


def _trainer_templates(db_session, trainer_id: str) -> list[str | None]:
    db_session.expire_all()
    return [
        row[0]
        for row in db_session.query(Notification.template)
        .filter(Notification.user_id == trainer_id)
        .all()
    ]


# --- 시작 전 취소 --------------------------------------------------------------


def test_member_cancels_an_accepted_consultation_before_it_starts(client, db_session):
    """수락된 상담을 시작 전에 취소하면 카드가 취소 상태가 된다."""
    _, _, _, member_token, consultation_id = _accepted(client, db_session)

    response = _cancel(client, member_token, consultation_id)

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["status"] == "cancelled"
    # 내가 취소한 것이다 — 트레이너가 거둔 취소의 안내가 붙으면 안 된다.
    assert body["cancelled_by_trainer"] is False
    row = _row(db_session, consultation_id)
    assert row.status == "cancelled"
    assert row.decided_by is None

    mine = client.get("/v1/consultations/me", headers=_auth(member_token)).json()
    assert [item["status"] for item in mine] == ["cancelled"]


def test_cancel_takes_the_consultation_off_the_trainer_schedule(client, db_session):
    """취소하면 그 상담 일정이 `취소` 로 바뀌고, 회원이 거둔 것으로 남는다."""
    _, _, _, member_token, consultation_id = _accepted(client, db_session)
    assert (
        _schedule(db_session, consultation_id).status
        == trainer_common_service.SCHEDULE_UPCOMING
    )

    assert _cancel(client, member_token, consultation_id).status_code == 200

    schedule = _schedule(db_session, consultation_id)
    assert schedule.status == trainer_common_service.SCHEDULE_CANCELLED
    assert schedule.cancelled_at is not None
    assert schedule.cancellation_source == "member"
    assert (
        schedule.cancellation_reason
        == consultation_service.MEMBER_CONSULT_CANCEL_REASON
    )


def test_cancel_gives_the_slot_back(client, db_session):
    """신청 때 잠근 자리가 다시 열려 다른 회원이 고를 수 있다."""
    trainer, _, _, member_token, consultation_id = _accepted(client, db_session)
    slot_id = _row(db_session, consultation_id).slot_id
    assert _remaining(db_session, slot_id) == 0

    assert _cancel(client, member_token, consultation_id).status_code == 200

    assert _remaining(db_session, slot_id) == 1
    _, other_token = _member(client)
    slots = client.get(
        f"/v1/consultations/slots?trainer_id={trainer.id}",
        headers=_auth(other_token),
    )
    assert slots.status_code == 200, slots.text
    assert slot_id in [slot["id"] for slot in slots.json()]


def test_cancel_notifies_the_trainer_with_the_booked_time(client, db_session):
    """트레이너에게 확정 상담이 취소됐다는 알림이 간다 — 대기 요청 취소와 다른 틀이다."""
    trainer, trainer_token, member_id, member_token, consultation_id = _accepted(
        client, db_session
    )

    assert _cancel(client, member_token, consultation_id).status_code == 200

    templates = _trainer_templates(db_session, trainer.id)
    assert (
        templates.count(notification_templates.TRAINER_CONSULT_BOOKING_CANCELLED) == 1
    )
    assert notification_templates.TRAINER_CONSULT_CANCELLED not in templates
    db_session.expire_all()
    notification = (
        db_session.query(Notification)
        .filter(
            Notification.user_id == trainer.id,
            Notification.template
            == notification_templates.TRAINER_CONSULT_BOOKING_CANCELLED,
        )
        .one()
    )
    schedule = _schedule(db_session, consultation_id)
    assert notification.subject_id == member_id
    assert notification.target_date == schedule.date
    assert schedule.time in notification.body

    titles = [
        item["title"]
        for item in client.get(
            "/v1/trainer/notifications", headers=_auth(trainer_token)
        ).json()
    ]
    assert "확정된 상담이 취소됐어요" in titles


def test_cancel_follows_a_schedule_the_trainer_moved(client, db_session):
    """트레이너가 옮긴 상담은 옮긴 시각이 약속이다 — 자리는 한 번만 돌아간다."""
    trainer, _, _, member_token, consultation_id = _accepted(client, db_session)
    slot_id = _row(db_session, consultation_id).slot_id
    # 일정을 옮기면 옛 자리는 그때 놓아 주고 요청에서 끊는다(#2758).
    assert consultation_service.release_slot_for_moved_schedule(
        db_session, consultation_id
    )
    moved = clock.now() + timedelta(days=5)
    schedule = _schedule_in_session(db_session, consultation_id)
    schedule.date = moved.date().isoformat()
    schedule.time = "10:00"
    db_session.commit()
    assert _remaining(db_session, slot_id) == 1

    assert _cancel(client, member_token, consultation_id).status_code == 200

    assert (
        _schedule(db_session, consultation_id).status
        == trainer_common_service.SCHEDULE_CANCELLED
    )
    # 이미 돌려준 자리를 한 번 더 돌려주지 않는다.
    assert _remaining(db_session, slot_id) == 1
    notification = (
        db_session.query(Notification)
        .filter(
            Notification.user_id == trainer.id,
            Notification.template
            == notification_templates.TRAINER_CONSULT_BOOKING_CANCELLED,
        )
        .one()
    )
    assert notification.target_date == moved.date().isoformat()
    assert "10:00" in notification.body


def _schedule_in_session(db_session, consultation_id: str) -> TrainerSchedule:
    """세션을 비우지 않고 읽는다 — 아직 커밋하지 않은 변경을 지키려는 것이다."""
    return (
        db_session.query(TrainerSchedule)
        .filter(TrainerSchedule.consultation_id == consultation_id)
        .one()
    )


def test_member_can_request_again_after_cancelling(client, db_session):
    """취소한 뒤 같은 트레이너에게 다시 신청할 수 있다."""
    trainer, _, _, member_token, consultation_id = _accepted(client, db_session)
    assert _cancel(client, member_token, consultation_id).status_code == 200

    again = _request_consultation(client, member_token, trainer_id=trainer.id)

    assert again != consultation_id
    assert _row(db_session, again).status == "pending"


def test_trainer_cancelling_the_same_schedule_afterwards_changes_nothing(
    client, db_session
):
    """회원이 거둔 일정을 트레이너가 다시 취소해도 자리가 한 번 더 풀리지 않는다."""
    trainer, _, _, member_token, consultation_id = _accepted(client, db_session)
    slot_id = _row(db_session, consultation_id).slot_id
    assert _cancel(client, member_token, consultation_id).status_code == 200
    schedule_id = _schedule(db_session, consultation_id).id

    out = trainer_schedule_service.cancel_session(db_session, trainer.id, schedule_id)

    assert out is not None
    assert _remaining(db_session, slot_id) == 1
    row = _row(db_session, consultation_id)
    assert row.status == "cancelled"
    # 여전히 회원이 취소한 요청이다.
    assert row.decided_by is None


# --- 취소할 수 없는 경우 --------------------------------------------------------


def test_started_consultation_cannot_be_cancelled(client, db_session):
    """시작 시각이 지난 상담은 409 `consultation_started` 이고 아무것도 바뀌지 않는다."""
    trainer, _, _, member_token, consultation_id = _accepted(client, db_session)
    slot_id = _row(db_session, consultation_id).slot_id
    started = clock.now() - timedelta(minutes=1)
    schedule = _schedule(db_session, consultation_id)
    schedule.date = started.date().isoformat()
    schedule.time = started.strftime("%H:%M")
    db_session.commit()

    response = _cancel(client, member_token, consultation_id)

    assert response.status_code == 409, response.text
    assert response.json()["detail"]["code"] == "consultation_started"
    assert _row(db_session, consultation_id).status == "accepted"
    assert (
        _schedule(db_session, consultation_id).status
        == trainer_common_service.SCHEDULE_UPCOMING
    )
    assert _remaining(db_session, slot_id) == 0
    assert (
        notification_templates.TRAINER_CONSULT_BOOKING_CANCELLED
        not in _trainer_templates(db_session, trainer.id)
    )


@pytest.mark.parametrize(
    "finished",
    [trainer_common_service.SCHEDULE_DONE, trainer_common_service.SCHEDULE_NO_SHOW],
)
def test_finished_consultation_cannot_be_cancelled(client, db_session, finished):
    """완료·노쇼로 끝난 상담은 시각과 관계없이 취소할 수 없다."""
    _, _, _, member_token, consultation_id = _accepted(client, db_session)
    schedule = _schedule(db_session, consultation_id)
    schedule.status = finished
    db_session.commit()

    response = _cancel(client, member_token, consultation_id)

    assert response.status_code == 409, response.text
    assert response.json()["detail"]["code"] == "consultation_started"
    assert _row(db_session, consultation_id).status == "accepted"
    assert _schedule(db_session, consultation_id).status == finished


def test_service_refuses_exactly_at_the_start_time(client, db_session):
    """경계 — 시작 시각 정각에는 이미 취소할 수 없고, 직전에는 취소된다."""
    _, _, member_id, _, consultation_id = _accepted(client, db_session)
    slot = db_session.get(
        TrainerReservationSlot, _row(db_session, consultation_id).slot_id
    )
    starts_at = consultation_service._aware(slot.starts_at).replace(
        second=0, microsecond=0
    )

    with pytest.raises(consultation_service.ConsultationAlreadyStarted):
        consultation_service.cancel_my_consultation(
            db_session, member_id, consultation_id, now=starts_at
        )
    assert _row(db_session, consultation_id).status == "accepted"

    out = consultation_service.cancel_my_consultation(
        db_session, member_id, consultation_id, now=starts_at - timedelta(minutes=1)
    )
    assert out.status == "cancelled"


def test_second_cancel_conflicts(client, db_session):
    """이미 취소한 상담을 다시 취소하면 409 — 알림도 자리도 한 번뿐이다."""
    trainer, _, _, member_token, consultation_id = _accepted(client, db_session)
    slot_id = _row(db_session, consultation_id).slot_id
    assert _cancel(client, member_token, consultation_id).status_code == 200

    response = _cancel(client, member_token, consultation_id)

    assert response.status_code == 409, response.text
    # 시작 시각 때문이 아니다 — 코드 없는 일반 409.
    assert isinstance(response.json()["detail"], str)
    assert _remaining(db_session, slot_id) == 1
    assert (
        _trainer_templates(db_session, trainer.id).count(
            notification_templates.TRAINER_CONSULT_BOOKING_CANCELLED
        )
        == 1
    )


def test_rejected_consultation_still_cannot_be_cancelled(client, db_session):
    trainer, trainer_token = _trainer(client, db_session)
    _, member_token = _member(client)
    consultation_id = _request_consultation(
        client, member_token, trainer_id=trainer.id
    )
    rejected = client.post(
        f"/v1/trainer/consultations/{consultation_id}/reject",
        headers=_auth(trainer_token),
        json={"note": "일정이 맞지 않아요"},
    )
    assert rejected.status_code == 200, rejected.text

    response = _cancel(client, member_token, consultation_id)

    assert response.status_code == 409, response.text
    assert _row(db_session, consultation_id).status == "rejected"


def test_another_member_cannot_cancel_my_accepted_consultation(client, db_session):
    """남의 상담은 404 다 — 일정도 자리도 그대로다."""
    _, _, _, _, consultation_id = _accepted(client, db_session)
    slot_id = _row(db_session, consultation_id).slot_id
    _, stranger_token = _member(client)

    response = _cancel(client, stranger_token, consultation_id)

    assert response.status_code == 404, response.text
    assert _row(db_session, consultation_id).status == "accepted"
    assert _remaining(db_session, slot_id) == 0


# --- 재사용 서비스 함수 ---------------------------------------------------------


def test_cancel_accepted_booking_ignores_a_pending_request(client, db_session):
    """수락 상태가 아니면 아무것도 하지 않는다(멱등) — 대기 요청은 다른 경로가 맡는다."""
    trainer, _ = _trainer(client, db_session)
    _, member_token = _member(client)
    consultation_id = _request_consultation(
        client, member_token, trainer_id=trainer.id
    )

    assert (
        consultation_service.cancel_accepted_booking(db_session, consultation_id)
        is None
    )
    db_session.rollback()
    assert _row(db_session, consultation_id).status == "pending"


def test_cancel_accepted_booking_neither_commits_nor_notifies(client, db_session):
    """부르는 쪽의 트랜잭션에 얹힌다 — 되돌리면 흔적이 없고, 알림은 따로 정한다."""
    trainer, _, _, _, consultation_id = _accepted(client, db_session)
    slot_id = _row(db_session, consultation_id).slot_id

    cancelled = consultation_service.cancel_accepted_booking(
        db_session, consultation_id, source="other", reason="정리"
    )

    assert cancelled is not None
    row, starts_at = cancelled
    assert row.status == "cancelled"
    assert starts_at is not None
    schedule = _schedule_in_session(db_session, consultation_id)
    assert schedule.cancellation_source == "other"
    assert schedule.cancellation_reason == "정리"

    db_session.rollback()
    assert _row(db_session, consultation_id).status == "accepted"
    assert _remaining(db_session, slot_id) == 0
    assert (
        notification_templates.TRAINER_CONSULT_BOOKING_CANCELLED
        not in _trainer_templates(db_session, trainer.id)
    )
