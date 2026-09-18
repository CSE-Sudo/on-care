"""상담 신청이 트레이너의 빈 자리를 잡는다. (#1873) DB 필요.

여기서 확인하는 것은 넷이다 — 목록에 보이는 자리의 조건, 신청이 자리를 잠그는가,
거절·취소·만료가 자리를 되돌리는가, 그리고 만료 규칙의 경계.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest

from app.models.models import (
    ConsultationRequest,
    Notification,
    Place,
    TrainerProfile,
    TrainerReservationSlot,
    User,
)
from app.services import consultation_service

from tests.test_consultations import (
    TEST_EMAIL_PREFIX,
    TEST_PLACE_PREFIX,
    TEST_SLOT_PREFIX,
    _auth,
    _create_slot,
    _create_trainer,
    _payload,
    _register_member,
)


@pytest.fixture(autouse=True)
def _cleanup(db_session):
    yield
    db_session.rollback()
    user_ids = [
        row[0]
        for row in db_session.query(User.id)
        .filter(User.email.like(f"{TEST_EMAIL_PREFIX}%"))
        .all()
    ]
    if user_ids:
        db_session.query(Notification).filter(
            Notification.user_id.in_(user_ids)
        ).delete(synchronize_session=False)
        db_session.query(ConsultationRequest).filter(
            (ConsultationRequest.member_id.in_(user_ids))
            | (ConsultationRequest.trainer_id.in_(user_ids))
        ).delete(synchronize_session=False)
        db_session.query(TrainerProfile).filter(
            TrainerProfile.trainer_id.in_(user_ids)
        ).delete(synchronize_session=False)
    db_session.query(TrainerReservationSlot).filter(
        TrainerReservationSlot.id.like(f"{TEST_SLOT_PREFIX}%")
    ).delete(synchronize_session=False)
    if user_ids:
        db_session.query(User).filter(User.id.in_(user_ids)).delete(
            synchronize_session=False
        )
    db_session.query(Place).filter(
        Place.id.like(f"{TEST_PLACE_PREFIX}%")
    ).delete(synchronize_session=False)
    db_session.commit()


def _slots(client, token: str, trainer_id: str) -> list[dict]:
    response = client.get(
        "/v1/consultations/slots",
        headers=_auth(token),
        params={"trainer_id": trainer_id},
    )
    assert response.status_code == 200, response.text
    return response.json()


def _apply(client, token: str, trainer_id: str, slot_id: str, db_session):
    return client.post(
        "/v1/consultations",
        headers=_auth(token),
        json=_payload(db_session, trainer_id=trainer_id, slot_id=slot_id),
    )


# --- 목록에 보이는 자리 -------------------------------------------------------


def test_only_open_personal_training_slots_far_enough_ahead_are_offered(
    client, db_session
):
    """`1:1 PT` 이고, 닫히지 않았고, 비어 있고, 4시간 이상 남은 자리만 보인다.

    헬스장 탭 목록이 `1:1 PT` 만 보여 주는 결정(#1849)을 상담 폼도 그대로 따른다.
    """
    _, token = _register_member(client)
    trainer = _create_trainer(db_session)
    good = _create_slot(db_session, trainer.id, hours_ahead=48)
    too_soon = _create_slot(db_session, trainer.id, hours_ahead=1)
    consultation_type = _create_slot(db_session, trainer.id)
    consultation_type.session_type = "상담"
    taken = _create_slot(db_session, trainer.id)
    taken.remaining = 0
    closed = _create_slot(db_session, trainer.id)
    closed.is_closed = True
    db_session.commit()

    offered = {slot["id"] for slot in _slots(client, token, trainer.id)}

    assert good.id in offered
    for hidden in (too_soon, consultation_type, taken, closed):
        assert hidden.id not in offered


def test_a_trainer_with_no_open_slots_offers_an_empty_list(client, db_session):
    """열린 자리가 없으면 빈 목록이다 — 앱은 그때 헬스장 전화를 안내한다."""
    _, token = _register_member(client)
    trainer = _create_trainer(db_session)

    assert _slots(client, token, trainer.id) == []


# --- 자리 잠금 ---------------------------------------------------------------


def test_applying_locks_the_slot_for_everyone_else(client, db_session):
    """신청하는 순간 그 자리가 닫힌다 — 다른 회원이 고를 수 없다."""
    _, first = _register_member(client)
    _, second = _register_member(client)
    trainer = _create_trainer(db_session)
    slot = _create_slot(db_session, trainer.id)

    assert _apply(client, first, trainer.id, slot.id, db_session).status_code == 201
    # 목록에서 사라지고,
    assert slot.id not in {s["id"] for s in _slots(client, second, trainer.id)}
    # 그래도 보내면 409 다 — 대기 중복 409 와 **구분되는 코드**를 싣는다. 앱이 둘을
    # 섞으면 자리를 놓친 회원을 "이미 대기 중" 으로 잘못 표시한다.
    taken = _apply(client, second, trainer.id, slot.id, db_session)
    assert taken.status_code == 409
    assert taken.json()["detail"]["code"] == "slot_unavailable"


def test_rejecting_reopens_the_slot(client, db_session):
    """거절하면 자리가 다시 열린다."""
    _, member_token = _register_member(client)
    trainer = _create_trainer(db_session)
    slot = _create_slot(db_session, trainer.id)
    created = _apply(client, member_token, trainer.id, slot.id, db_session)
    assert created.status_code == 201, created.text

    consultation_service.reject(
        db_session, trainer.id, created.json()["id"], "죄송합니다"
    )

    db_session.expire_all()
    assert db_session.get(TrainerReservationSlot, slot.id).remaining == 1


def test_member_cancelling_reopens_the_slot(client, db_session):
    """회원이 취소해도 자리가 다시 열린다."""
    _, member_token = _register_member(client)
    trainer = _create_trainer(db_session)
    slot = _create_slot(db_session, trainer.id)
    created = _apply(client, member_token, trainer.id, slot.id, db_session)
    assert created.status_code == 201, created.text

    cancelled = client.delete(
        f"/v1/consultations/{created.json()['id']}", headers=_auth(member_token)
    )

    assert cancelled.status_code == 200, cancelled.text
    db_session.expire_all()
    assert db_session.get(TrainerReservationSlot, slot.id).remaining == 1


def test_member_deleting_the_account_reopens_the_slot(client, db_session):
    """대기 신청을 둔 채 탈퇴해도 자리가 잠긴 채 남지 않는다.

    요청 행은 회원과 함께 CASCADE 로 지워지지만 자리는 남는다 — 되돌리지 않으면
    `remaining = 0` 으로 영영 잠긴다.
    """
    _, member_token = _register_member(client)
    trainer = _create_trainer(db_session)
    slot = _create_slot(db_session, trainer.id)
    created = _apply(client, member_token, trainer.id, slot.id, db_session)
    assert created.status_code == 201, created.text

    deleted = client.delete("/v1/users/me", headers=_auth(member_token))

    assert deleted.status_code == 200, deleted.text
    db_session.expire_all()
    assert db_session.get(TrainerReservationSlot, slot.id).remaining == 1


# --- 만료 --------------------------------------------------------------------


def test_expiry_is_the_earlier_of_24h_and_2h_before_the_slot():
    """만료 시각은 신청 후 24시간과 자리 시작 2시간 전 중 이른 쪽이다."""
    created = datetime(2026, 3, 5, 9, 0, tzinfo=timezone.utc)
    row = ConsultationRequest(created_at=created)

    # 먼 자리 — 24시간 규칙이 먼저 온다.
    far = created + timedelta(days=7)
    assert consultation_service._expires_at(row, far) == created + timedelta(hours=24)
    # 오늘 저녁 자리 — 시작 2시간 전이 먼저 온다.
    tonight = created + timedelta(hours=6)
    assert consultation_service._expires_at(row, tonight) == tonight - timedelta(
        hours=2
    )


def test_the_form_never_offers_a_slot_that_would_expire_at_once():
    """목록 하한이 만료 기준보다 커야 트레이너에게 확인할 시간이 남는다.

    둘이 같으면 경계에서 확인 시간이 0 이 된다 — 19:30 자리가 17:29 에 보이는데
    만료가 17:30 이라 신청 1분 뒤에 만료된다.
    """
    assert (
        consultation_service.CONSULT_SLOT_MIN_LEAD_HOURS
        > consultation_service.CONSULT_EXPIRE_BEFORE_START_HOURS
    )


def test_a_slot_that_passed_its_deadline_expires_and_reopens(client, db_session):
    """만료되면 상태가 `expired` 가 되고, 자리가 풀리고, 회원에게 알림이 간다.

    `rejected`(트레이너의 판단)와 구분한다 — 회원 화면 문구가 다르다.
    """
    member_id, member_token = _register_member(client)
    trainer = _create_trainer(db_session)
    slot = _create_slot(db_session, trainer.id, hours_ahead=5)
    created = _apply(client, member_token, trainer.id, slot.id, db_session)
    assert created.status_code == 201, created.text
    consultation_id = created.json()["id"]
    before = db_session.query(Notification).filter_by(user_id=member_id).count()

    # 자리 시작 2시간 전을 막 지난 시점.
    passed = slot.starts_at - timedelta(hours=2) + timedelta(minutes=1)
    assert (
        consultation_service.expire_stale_requests(db_session, trainer.id, now=passed)
        == 1
    )
    db_session.commit()

    db_session.expire_all()
    assert db_session.get(ConsultationRequest, consultation_id).status == "expired"
    assert db_session.get(TrainerReservationSlot, slot.id).remaining == 1
    assert (
        db_session.query(Notification).filter_by(user_id=member_id).count()
        == before + 1
    )


def test_a_live_request_is_left_alone(client, db_session):
    """아직 시간이 남은 요청은 건드리지 않는다."""
    _, member_token = _register_member(client)
    trainer = _create_trainer(db_session)
    slot = _create_slot(db_session, trainer.id, hours_ahead=48)
    created = _apply(client, member_token, trainer.id, slot.id, db_session)
    assert created.status_code == 201, created.text

    assert consultation_service.expire_stale_requests(db_session, trainer.id) == 0
    db_session.expire_all()
    assert db_session.get(ConsultationRequest, created.json()["id"]).status == "pending"


def test_reading_the_badge_expires_and_drops_it_from_the_count(client, db_session):
    """스케줄러가 없으므로 읽는 시점에 정리한다 — 배지 조회도 그 자리다."""
    _, member_token = _register_member(client)
    trainer = _create_trainer(db_session)
    slot = _create_slot(db_session, trainer.id, hours_ahead=5)
    created = _apply(client, member_token, trainer.id, slot.id, db_session)
    assert created.status_code == 201, created.text
    # 시계를 돌리는 대신 자리를 만료 시점 뒤로 당겨 놓는다.
    db_session.get(TrainerReservationSlot, slot.id).starts_at = datetime.now(
        timezone.utc
    ) + timedelta(hours=1)
    db_session.commit()

    assert consultation_service.pending_count_for_trainer(db_session, trainer.id) == 0
    db_session.expire_all()
    assert db_session.get(ConsultationRequest, created.json()["id"]).status == "expired"


# --- 응답에 실리는 확정 일시 ---------------------------------------------------


def test_the_response_carries_the_chosen_slot(client, db_session):
    """회원 화면이 확정된 일시를 그릴 수 있어야 한다."""
    _, member_token = _register_member(client)
    trainer = _create_trainer(db_session)
    slot = _create_slot(db_session, trainer.id)

    body = _apply(client, member_token, trainer.id, slot.id, db_session).json()

    assert body["slot_id"] == slot.id
    assert body["slot_duration_minutes"] == slot.duration_minutes
    assert body["slot_starts_at"]
