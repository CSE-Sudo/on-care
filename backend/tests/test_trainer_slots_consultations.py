"""예약 자리와 상담 일정·트레이너 일정 사이의 정합. (#2758, #2761)

- #2758 상담 요청을 수락해 생긴 상담 일정을 취소·삭제·이동해도 상담 요청과 그
  요청이 잡아 둔 자리가 그대로 남았다. 자리는 영영 풀리지 않았고, 회원 앱 카드는
  계속 `수락됨` 이었으며 옮긴 뒤에도 옛 시각을 보여 줬다.
- #2761 자리를 연 뒤 트레이너가 같은 시간에 일정을 잡거나 옮겨 와도, 자리는 회원
  목록과 트레이너 슬롯 창에 빈 자리로 남았다.

경로마다 트레이너를 새로 만들어 시드 타임라인·다른 테스트의 일정과 섞이지 않게
한다. 날짜는 시드가 닿지 않는 먼 미래를 쓴다.
"""
from __future__ import annotations

from datetime import datetime, timedelta
from uuid import uuid4

import pytest

from app.core.clock import SEOUL
from app.core.security import hash_password
from app.models.models import (
    ConsultationRequest,
    Notification,
    TrainerClient,
    TrainerProfile,
    TrainerReservation,
    TrainerReservationSlot,
    TrainerRoutine,
    TrainerSchedule,
    User,
)
from app.services import consultation_service, reservation_service
from app.services.trainer import _common as trainer_common_service

EMAIL_PREFIX = "slots-2758-"
PASSWORD = "slots-pw-1234"
DAY = "2031-04-14"
NEXT_DAY = "2031-04-15"


# ---- 준비 ----


@pytest.fixture(autouse=True)
def _cleanup(db_session):
    yield
    db_session.rollback()
    user_ids = [
        row[0]
        for row in db_session.query(User.id)
        .filter(User.email.like(f"{EMAIL_PREFIX}%"))
        .all()
    ]
    if not user_ids:
        return
    db_session.query(TrainerReservation).filter(
        TrainerReservation.member_id.in_(user_ids)
    ).delete(synchronize_session=False)
    db_session.query(TrainerRoutine).filter(
        (TrainerRoutine.trainer_id.in_(user_ids))
        | (TrainerRoutine.member_id.in_(user_ids))
    ).delete(synchronize_session=False)
    db_session.query(TrainerSchedule).filter(
        (TrainerSchedule.trainer_id.in_(user_ids))
        | (TrainerSchedule.member_id.in_(user_ids))
    ).delete(synchronize_session=False)
    db_session.query(ConsultationRequest).filter(
        (ConsultationRequest.member_id.in_(user_ids))
        | (ConsultationRequest.trainer_id.in_(user_ids))
    ).delete(synchronize_session=False)
    db_session.query(TrainerReservationSlot).filter(
        TrainerReservationSlot.trainer_id.in_(user_ids)
    ).delete(synchronize_session=False)
    db_session.query(TrainerClient).filter(
        (TrainerClient.trainer_id.in_(user_ids))
        | (TrainerClient.member_id.in_(user_ids))
    ).delete(synchronize_session=False)
    db_session.query(Notification).filter(
        Notification.user_id.in_(user_ids)
    ).delete(synchronize_session=False)
    db_session.query(TrainerProfile).filter(
        TrainerProfile.trainer_id.in_(user_ids)
    ).delete(synchronize_session=False)
    db_session.query(User).filter(User.id.in_(user_ids)).delete(
        synchronize_session=False
    )
    db_session.commit()


def _auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _login(client, email: str) -> str:
    response = client.post(
        "/v1/auth/login", data={"username": email, "password": PASSWORD}
    )
    assert response.status_code == 200, response.text
    return response.json()["access_token"]


def _trainer(client, db_session) -> tuple[str, str]:
    """로그인 가능한 새 트레이너. (id, token)"""
    suffix = uuid4().hex[:10]
    email = f"{EMAIL_PREFIX}trainer-{suffix}@oncare.com"
    trainer = User(
        id=f"slots-trainer-{suffix}",
        email=email,
        name="자리 테스트 트레이너",
        hashed_password=hash_password(PASSWORD),
        role="trainer",
        is_active=True,
    )
    db_session.add(trainer)
    db_session.flush()
    db_session.add(TrainerProfile(trainer_id=trainer.id))
    db_session.commit()
    return trainer.id, _login(client, email)


def _member(
    client, db_session, trainer_id: str | None = None, *, name: str = "자리 회원"
) -> tuple[str, str]:
    """회원 계정. [trainer_id] 를 주면 그 트레이너의 담당으로 묶는다."""
    email = f"{EMAIL_PREFIX}member-{uuid4().hex[:10]}@oncare.com"
    response = client.post(
        "/v1/auth/register",
        json={"email": email, "password": PASSWORD, "name": name},
    )
    assert response.status_code == 201, response.text
    member_id = response.json()["id"]
    if trainer_id is not None:
        db_session.add(
            TrainerClient(
                id=f"tc-{uuid4().hex[:12]}",
                trainer_id=trainer_id,
                member_id=member_id,
                active=True,
            )
        )
        db_session.commit()
    return member_id, _login(client, email)


def _kst(day: str, time: str) -> datetime:
    return datetime.fromisoformat(f"{day}T{time}:00").replace(tzinfo=SEOUL)


def _open_slot(client, token: str, *, day: str = DAY, time: str = "10:00") -> dict:
    response = client.post(
        "/v1/trainer/reservation-slots",
        json={"starts_at": _kst(day, time).isoformat(), "session_type": "1:1 PT"},
        headers=_auth(token),
    )
    assert response.status_code == 201, response.text
    return response.json()


def _create(client, token: str, **over) -> dict:
    body = {
        "date": DAY,
        "time": "10:00",
        "client_name": "직접 잡은 일정",
        "type": "1:1 PT",
        "duration_minutes": 60,
    }
    body.update(over)
    response = client.post("/v1/trainer/schedule", json=body, headers=_auth(token))
    assert response.status_code == 201, response.text
    return response.json()


def _consultation(db_session, trainer_id: str, member_id: str, slot_id: str) -> str:
    """회원이 그 자리를 골라 넣은 대기 중 상담 요청(자리를 잠근다)."""
    slot = db_session.get(TrainerReservationSlot, slot_id)
    reservation_service.hold_slot_for_consultation(
        db_session,
        trainer_id,
        slot_id,
        after=slot.starts_at - timedelta(days=1),
    )
    request_id = f"consult-{uuid4().hex[:12]}"
    local = slot.starts_at.astimezone(SEOUL)
    db_session.add(
        ConsultationRequest(
            id=request_id,
            member_id=member_id,
            trainer_id=trainer_id,
            target_type="trainer",
            exercise_goal="weight_loss",
            health_purpose_type="general",
            slot_id=slot_id,
            preferred_date=local.date().isoformat(),
            preferred_time_slot=local.strftime("%H:%M"),
            message="상담 부탁드립니다.",
            status="pending",
        )
    )
    db_session.commit()
    return request_id


def _accepted(client, db_session, token: str, trainer_id: str, member_id: str):
    """10:00 자리로 신청해 수락된 상담. (slot, request_id, schedule_id)"""
    slot = _open_slot(client, token, time="10:00")
    request_id = _consultation(db_session, trainer_id, member_id, slot["id"])
    response = client.post(
        f"/v1/trainer/consultations/{request_id}/accept",
        json={},
        headers=_auth(token),
    )
    assert response.status_code == 200, response.text
    return slot, request_id, response.json()["schedule_id"]


def _remaining(db_session, slot_id: str) -> int:
    db_session.expire_all()
    return db_session.get(TrainerReservationSlot, slot_id).remaining


def _trainer_slot(client, token: str, slot_id: str) -> dict:
    response = client.get("/v1/trainer/reservation-slots", headers=_auth(token))
    assert response.status_code == 200, response.text
    return next(row for row in response.json() if row["id"] == slot_id)


def _member_slot(client, member_token: str, trainer_id: str, slot_id: str) -> dict:
    response = client.get(
        f"/v1/trainers/{trainer_id}/slots", headers=_auth(member_token)
    )
    assert response.status_code == 200, response.text
    return next(row for row in response.json() if row["id"] == slot_id)


def _my_consultation(client, member_token: str, request_id: str) -> dict:
    response = client.get(
        f"/v1/consultations/{request_id}", headers=_auth(member_token)
    )
    assert response.status_code == 200, response.text
    return response.json()


def _cancel(client, token: str, schedule_id: str):
    return client.post(
        f"/v1/trainer/schedule/{schedule_id}/cancel",
        json={"source": "trainer"},
        headers=_auth(token),
    )


# ---- #2758 상담 일정 취소·삭제 ----


def test_cancelling_a_consultation_session_frees_its_slot(client, db_session):
    trainer_id, token = _trainer(client, db_session)
    member_id, member_token = _member(client, db_session)
    slot, request_id, schedule_id = _accepted(
        client, db_session, token, trainer_id, member_id
    )
    assert _remaining(db_session, slot["id"]) == 0

    response = _cancel(client, token, schedule_id)

    assert response.status_code == 200, response.text
    assert response.json()["status"] == trainer_common_service.SCHEDULE_CANCELLED
    assert _remaining(db_session, slot["id"]) == 1
    request = db_session.get(ConsultationRequest, request_id)
    assert request.status == "cancelled"
    assert request.decided_by == trainer_id


def test_cancelled_consultation_reads_as_trainer_cancelled_for_the_member(
    client, db_session
):
    trainer_id, token = _trainer(client, db_session)
    member_id, member_token = _member(client, db_session)
    _, request_id, schedule_id = _accepted(
        client, db_session, token, trainer_id, member_id
    )

    assert _cancel(client, token, schedule_id).status_code == 200
    body = _my_consultation(client, member_token, request_id)

    assert body["status"] == "cancelled"
    assert body["cancelled_by_trainer"] is True
    # 처리자 id 는 여전히 회원 응답에 실리지 않는다.
    assert "decided_by" not in body


def test_member_cancel_is_not_marked_as_trainer_cancelled(client, db_session):
    trainer_id, token = _trainer(client, db_session)
    member_id, member_token = _member(client, db_session)
    slot = _open_slot(client, token)
    request_id = _consultation(db_session, trainer_id, member_id, slot["id"])

    response = client.delete(
        f"/v1/consultations/{request_id}", headers=_auth(member_token)
    )

    assert response.status_code == 200, response.text
    assert response.json()["status"] == "cancelled"
    assert response.json()["cancelled_by_trainer"] is False


def test_another_member_can_book_the_freed_slot(client, db_session):
    trainer_id, token = _trainer(client, db_session)
    member_id, _ = _member(client, db_session)
    slot, _, schedule_id = _accepted(client, db_session, token, trainer_id, member_id)
    assert _cancel(client, token, schedule_id).status_code == 200
    _, other_token = _member(client, db_session, trainer_id)

    assert _member_slot(client, other_token, trainer_id, slot["id"])["remaining"] == 1
    response = client.post(
        "/v1/reservations", json={"slot_id": slot["id"]}, headers=_auth(other_token)
    )

    assert response.status_code == 201, response.text
    assert _remaining(db_session, slot["id"]) == 0


def test_cancelled_consultation_leaves_no_nameless_booked_slot(client, db_session):
    trainer_id, token = _trainer(client, db_session)
    member_id, _ = _member(client, db_session)
    slot, _, schedule_id = _accepted(client, db_session, token, trainer_id, member_id)

    assert _cancel(client, token, schedule_id).status_code == 200
    row = _trainer_slot(client, token, slot["id"])

    assert row["remaining"] == 1
    assert row["booked_by_name"] is None
    assert row["overlapped"] is False


def test_cancelling_twice_releases_the_slot_once(client, db_session):
    trainer_id, token = _trainer(client, db_session)
    member_id, _ = _member(client, db_session)
    slot, _, schedule_id = _accepted(client, db_session, token, trainer_id, member_id)
    assert _cancel(client, token, schedule_id).status_code == 200
    # 풀린 자리를 다른 회원이 잡았다.
    _, other_token = _member(client, db_session, trainer_id)
    booked = client.post(
        "/v1/reservations", json={"slot_id": slot["id"]}, headers=_auth(other_token)
    )
    assert booked.status_code == 201, booked.text

    again = _cancel(client, token, schedule_id)

    assert again.status_code == 200, again.text
    # 이미 돌려준 자리를 한 번 더 돌려주면 다른 회원이 잡은 좌석이 늘어난다.
    assert _remaining(db_session, slot["id"]) == 0


def test_deleting_a_consultation_session_frees_its_slot(client, db_session):
    trainer_id, token = _trainer(client, db_session)
    member_id, member_token = _member(client, db_session)
    slot, request_id, schedule_id = _accepted(
        client, db_session, token, trainer_id, member_id
    )

    response = client.delete(
        f"/v1/trainer/schedule/{schedule_id}", headers=_auth(token)
    )

    assert response.status_code == 200, response.text
    assert _remaining(db_session, slot["id"]) == 1
    body = _my_consultation(client, member_token, request_id)
    assert body["status"] == "cancelled"
    assert body["cancelled_by_trainer"] is True
    # 일정이 사라지면 시각은 자리 사본으로 돌아간다.
    assert datetime.fromisoformat(body["slot_starts_at"]) == _kst(DAY, "10:00")


def test_deleting_a_cancelled_consultation_session_does_not_release_again(
    client, db_session
):
    trainer_id, token = _trainer(client, db_session)
    member_id, _ = _member(client, db_session)
    slot, _, schedule_id = _accepted(client, db_session, token, trainer_id, member_id)
    assert _cancel(client, token, schedule_id).status_code == 200
    _, other_token = _member(client, db_session, trainer_id)
    assert (
        client.post(
            "/v1/reservations", json={"slot_id": slot["id"]}, headers=_auth(other_token)
        ).status_code
        == 201
    )

    response = client.delete(
        f"/v1/trainer/schedule/{schedule_id}", headers=_auth(token)
    )

    assert response.status_code == 200, response.text
    assert _remaining(db_session, slot["id"]) == 0


def test_cancelling_a_consultation_session_notifies_the_member(client, db_session):
    trainer_id, token = _trainer(client, db_session)
    member_id, _ = _member(client, db_session)
    _, _, schedule_id = _accepted(client, db_session, token, trainer_id, member_id)
    before = (
        db_session.query(Notification).filter(Notification.user_id == member_id).count()
    )

    assert _cancel(client, token, schedule_id).status_code == 200

    db_session.expire_all()
    after = (
        db_session.query(Notification).filter(Notification.user_id == member_id).count()
    )
    assert after == before + 1


def test_plain_session_cancel_leaves_consultations_alone(client, db_session):
    """상담 출처가 없는 일정의 취소는 상담 요청을 건드리지 않는다."""
    trainer_id, token = _trainer(client, db_session)
    member_id, _ = _member(client, db_session)
    slot = _open_slot(client, token, time="10:00")
    request_id = _consultation(db_session, trainer_id, member_id, slot["id"])
    plain = _create(client, token, time="15:00")

    assert _cancel(client, token, plain["id"]).status_code == 200

    db_session.expire_all()
    assert db_session.get(ConsultationRequest, request_id).status == "pending"
    assert _remaining(db_session, slot["id"]) == 0


# ---- #2758 상담 일정 이동 ----


def test_moving_a_consultation_session_moves_the_member_card_time(
    client, db_session
):
    trainer_id, token = _trainer(client, db_session)
    member_id, member_token = _member(client, db_session)
    _, request_id, schedule_id = _accepted(
        client, db_session, token, trainer_id, member_id
    )

    moved = client.put(
        f"/v1/trainer/schedule/{schedule_id}",
        json={"date": NEXT_DAY, "time": "15:30"},
        headers=_auth(token),
    )

    assert moved.status_code == 200, moved.text
    body = _my_consultation(client, member_token, request_id)
    assert body["status"] == "accepted"
    assert datetime.fromisoformat(body["slot_starts_at"]) == _kst(NEXT_DAY, "15:30")


def test_moving_a_consultation_session_frees_the_old_slot(client, db_session):
    trainer_id, token = _trainer(client, db_session)
    member_id, _ = _member(client, db_session)
    slot, request_id, schedule_id = _accepted(
        client, db_session, token, trainer_id, member_id
    )

    moved = client.put(
        f"/v1/trainer/schedule/{schedule_id}",
        json={"time": "15:00"},
        headers=_auth(token),
    )

    assert moved.status_code == 200, moved.text
    assert _remaining(db_session, slot["id"]) == 1
    assert db_session.get(ConsultationRequest, request_id).slot_id is None
    row = _trainer_slot(client, token, slot["id"])
    assert row["booked_by_name"] is None


def test_cancelling_after_a_move_does_not_release_the_old_slot_twice(
    client, db_session
):
    trainer_id, token = _trainer(client, db_session)
    member_id, _ = _member(client, db_session)
    slot, request_id, schedule_id = _accepted(
        client, db_session, token, trainer_id, member_id
    )
    assert (
        client.put(
            f"/v1/trainer/schedule/{schedule_id}",
            json={"time": "15:00"},
            headers=_auth(token),
        ).status_code
        == 200
    )
    _, other_token = _member(client, db_session, trainer_id)
    assert (
        client.post(
            "/v1/reservations", json={"slot_id": slot["id"]}, headers=_auth(other_token)
        ).status_code
        == 201
    )

    assert _cancel(client, token, schedule_id).status_code == 200

    assert _remaining(db_session, slot["id"]) == 0
    assert db_session.get(ConsultationRequest, request_id).status == "cancelled"


def test_note_only_edit_keeps_the_consultation_slot(client, db_session):
    trainer_id, token = _trainer(client, db_session)
    member_id, _ = _member(client, db_session)
    slot, request_id, schedule_id = _accepted(
        client, db_session, token, trainer_id, member_id
    )

    response = client.put(
        f"/v1/trainer/schedule/{schedule_id}",
        json={"note": "첫 상담 메모"},
        headers=_auth(token),
    )

    assert response.status_code == 200, response.text
    assert _remaining(db_session, slot["id"]) == 0
    assert db_session.get(ConsultationRequest, request_id).slot_id == slot["id"]


def test_pending_consultation_slot_shows_the_member_name(client, db_session):
    """상담 신청이 잡은 자리는 이름 없는 `예약됨` 이 아니다."""
    trainer_id, token = _trainer(client, db_session)
    member_id, _ = _member(client, db_session, name="상담 신청 회원")
    slot = _open_slot(client, token)
    _consultation(db_session, trainer_id, member_id, slot["id"])

    row = _trainer_slot(client, token, slot["id"])

    assert row["remaining"] == 0
    assert row["booked_by_name"] == "상담 신청 회원"


# ---- #2761 일정과 겹친 열린 자리 ----


def test_slot_overlapped_by_a_later_session_reads_as_full_for_members(
    client, db_session
):
    trainer_id, token = _trainer(client, db_session)
    _, member_token = _member(client, db_session, trainer_id)
    slot = _open_slot(client, token, time="10:00")
    _create(client, token, time="10:30", duration_minutes=30)

    row = _member_slot(client, member_token, trainer_id, slot["id"])

    assert row["remaining"] == 0
    assert row["overlapped"] is True


def test_slot_overlapped_by_a_later_session_is_flagged_for_the_trainer(
    client, db_session
):
    trainer_id, token = _trainer(client, db_session)
    slot = _open_slot(client, token, time="10:00")
    _create(client, token, time="10:00")

    row = _trainer_slot(client, token, slot["id"])

    # 좌석 수는 그대로 — 예약된 자리가 아니라 겹친 자리다.
    assert row["remaining"] == 1
    assert row["overlapped"] is True
    assert row["booked_by_name"] is None


def test_slot_next_to_a_session_is_not_overlapped(client, db_session):
    trainer_id, token = _trainer(client, db_session)
    slot = _open_slot(client, token, time="10:00")
    _create(client, token, time="11:00")

    assert _trainer_slot(client, token, slot["id"])["overlapped"] is False


def test_cancelling_the_overlapping_session_reopens_the_slot(client, db_session):
    trainer_id, token = _trainer(client, db_session)
    _, member_token = _member(client, db_session, trainer_id)
    slot = _open_slot(client, token, time="10:00")
    blocker = _create(client, token, time="10:00")
    assert _cancel(client, token, blocker["id"]).status_code == 200

    row = _member_slot(client, member_token, trainer_id, slot["id"])

    assert row["remaining"] == 1
    assert row["overlapped"] is False


def test_moving_the_overlapping_session_away_reopens_the_slot(client, db_session):
    trainer_id, token = _trainer(client, db_session)
    slot = _open_slot(client, token, time="10:00")
    blocker = _create(client, token, time="10:00")
    assert _trainer_slot(client, token, slot["id"])["overlapped"] is True

    moved = client.put(
        f"/v1/trainer/schedule/{blocker['id']}",
        json={"time": "16:00"},
        headers=_auth(token),
    )

    assert moved.status_code == 200, moved.text
    assert _trainer_slot(client, token, slot["id"])["overlapped"] is False


def test_moving_a_session_onto_an_open_slot_flags_it(client, db_session):
    trainer_id, token = _trainer(client, db_session)
    slot = _open_slot(client, token, time="10:00")
    session = _create(client, token, time="16:00")

    moved = client.put(
        f"/v1/trainer/schedule/{session['id']}",
        json={"time": "10:00"},
        headers=_auth(token),
    )

    assert moved.status_code == 200, moved.text
    assert _trainer_slot(client, token, slot["id"])["overlapped"] is True


def test_reserve_still_rejects_an_overlapped_slot(client, db_session):
    """목록이 마감으로 보여도 옛 화면이 보낸 예약은 마지막 검사가 막는다."""
    trainer_id, token = _trainer(client, db_session)
    _, member_token = _member(client, db_session, trainer_id)
    slot = _open_slot(client, token, time="10:00")
    _create(client, token, time="10:00")

    response = client.post(
        "/v1/reservations", json={"slot_id": slot["id"]}, headers=_auth(member_token)
    )

    assert response.status_code == 409, response.text
    assert _remaining(db_session, slot["id"]) == 1


def test_booked_slot_is_not_overlapped_by_its_own_session(client, db_session):
    trainer_id, token = _trainer(client, db_session)
    _, member_token = _member(client, db_session, trainer_id)
    slot = _open_slot(client, token, time="10:00")
    assert (
        client.post(
            "/v1/reservations", json={"slot_id": slot["id"]}, headers=_auth(member_token)
        ).status_code
        == 201
    )

    row = _trainer_slot(client, token, slot["id"])

    assert row["overlapped"] is False
    assert row["remaining"] == 0


def test_consultation_form_hides_an_overlapped_slot(client, db_session):
    trainer_id, token = _trainer(client, db_session)
    _, member_token = _member(client, db_session)
    free = _open_slot(client, token, time="08:00")
    covered = _open_slot(client, token, time="10:00")
    _create(client, token, time="10:00")

    response = client.get(
        "/v1/consultations/slots",
        params={"trainer_id": trainer_id},
        headers=_auth(member_token),
    )

    assert response.status_code == 200, response.text
    ids = {row["id"] for row in response.json()}
    assert free["id"] in ids
    assert covered["id"] not in ids


def test_consultation_hold_refuses_an_overlapped_slot(client, db_session):
    trainer_id, token = _trainer(client, db_session)
    slot = _open_slot(client, token, time="10:00")
    _create(client, token, time="10:00")
    row = db_session.get(TrainerReservationSlot, slot["id"])

    with pytest.raises(reservation_service.SlotUnavailable):
        reservation_service.hold_slot_for_consultation(
            db_session, trainer_id, slot["id"], after=row.starts_at - timedelta(days=1)
        )
    db_session.rollback()
    assert _remaining(db_session, slot["id"]) == 1


def test_overlap_reaches_back_across_midnight(client, db_session):
    """전날 늦게 시작해 자정을 넘긴 일정도 다음 날 이른 자리를 차지한다."""
    trainer_id, token = _trainer(client, db_session)
    slot = _open_slot(client, token, day=NEXT_DAY, time="00:00")
    _create(client, token, date=DAY, time="23:30", duration_minutes=90)

    assert _trainer_slot(client, token, slot["id"])["overlapped"] is True


def test_overlapped_slot_ids_ignores_closed_and_full_slots(client, db_session):
    trainer_id, token = _trainer(client, db_session)
    slot = _open_slot(client, token, time="10:00")
    _create(client, token, time="10:00")
    row = db_session.get(TrainerReservationSlot, slot["id"])

    assert reservation_service.overlapped_slot_ids(db_session, trainer_id, [row]) == {
        row.id
    }
    row.is_closed = True
    assert reservation_service.overlapped_slot_ids(db_session, trainer_id, [row]) == set()
    row.is_closed = False
    row.remaining = 0
    assert reservation_service.overlapped_slot_ids(db_session, trainer_id, [row]) == set()
    db_session.rollback()


def test_accepted_consultation_session_does_not_flag_its_own_slot(client, db_session):
    trainer_id, token = _trainer(client, db_session)
    member_id, _ = _member(client, db_session)
    slot, _, _ = _accepted(client, db_session, token, trainer_id, member_id)

    row = _trainer_slot(client, token, slot["id"])

    assert row["overlapped"] is False
    assert row["remaining"] == 0


def test_withdraw_helper_is_a_no_op_for_pending_requests(client, db_session):
    """대기 중 요청은 일정이 없다 — 일정 정리가 그 요청을 건드릴 일이 없다."""
    trainer_id, token = _trainer(client, db_session)
    member_id, _ = _member(client, db_session)
    slot = _open_slot(client, token)
    request_id = _consultation(db_session, trainer_id, member_id, slot["id"])

    assert (
        consultation_service.withdraw_for_trainer_schedule(
            db_session, request_id, trainer_id
        )
        is False
    )
    assert (
        consultation_service.release_slot_for_moved_schedule(db_session, request_id)
        is False
    )
    db_session.commit()
    assert db_session.get(ConsultationRequest, request_id).status == "pending"
    assert _remaining(db_session, slot["id"]) == 0
