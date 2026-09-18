"""상담 요청 생성 한도 (#1628). DB 필요.

트래픽이 아니라 남에게 주는 피해를 막는다.

- **동시 대기 상한** — 답을 기다리는 요청 하나가 트레이너 자리 하나를 최대 24시간
  잠근다(#1873). 상한이 없으면 한 회원이 여러 트레이너의 자리를 한꺼번에 묶는다.
- **24시간 신청 한도** — 신청·취소를 되풀이하면 신청마다 트레이너 알림이 쌓인다.
  취소한 요청은 대기 상한에 세어지지 않아 따로 막는다.

둘 다 DB 에서 센다. 재기동하면 비워지는 메모리 창으로는 반복을 막지 못한다.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest

from app.core.config import get_settings
from app.models.models import (
    ConsultationRequest,
    Notification,
    Place,
    TrainerProfile,
    TrainerReservationSlot,
    User,
)

from tests.test_consultations import (
    TEST_EMAIL_PREFIX,
    TEST_PLACE_PREFIX,
    TEST_SLOT_PREFIX,
    _auth,
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


@pytest.fixture
def limits(monkeypatch):
    """한도를 작게 잡는다. 값을 바꿔 넣는 함수를 준다."""
    settings = get_settings()
    monkeypatch.setattr(settings, "rate_limit_enabled", True)

    def set_limits(*, max_pending: int, per_day: int) -> None:
        monkeypatch.setattr(settings, "consultation_max_pending", max_pending)
        monkeypatch.setattr(settings, "consultation_create_per_day", per_day)

    return set_limits


def _apply(client, db_session, token: str, trainer_id: str):
    return client.post(
        "/v1/consultations",
        headers=_auth(token),
        json=_payload(db_session, trainer_id=trainer_id),
    )


def _apply_to_new_trainer(client, db_session, token: str):
    trainer = _create_trainer(db_session)
    return _apply(client, db_session, token, trainer.id), trainer


def _cancel(client, token: str, consultation_id: str) -> None:
    response = client.delete(
        f"/v1/consultations/{consultation_id}", headers=_auth(token)
    )
    assert response.status_code == 200, response.text


# --- 동시 대기 상한 -----------------------------------------------------------


def test_pending_requests_are_capped_across_trainers(client, db_session, limits):
    """서로 다른 트레이너에게라도 답을 기다리는 요청은 상한까지만 둔다."""
    limits(max_pending=2, per_day=100)
    _, token = _register_member(client)
    for _ in range(2):
        created, _ = _apply_to_new_trainer(client, db_session, token)
        assert created.status_code == 201, created.text

    blocked, trainer = _apply_to_new_trainer(client, db_session, token)

    assert blocked.status_code == 409, blocked.text
    detail = blocked.json()["detail"]
    # 같은 409 인 "이미 대기 중" 과 코드로 가른다 — 앱이 섞으면 신청하지 않은
    # 트레이너를 대기 중으로 표시한다.
    assert detail["code"] == "too_many_pending"
    assert detail["limit"] == 2
    assert "2건" in detail["message"]
    # 막힌 신청은 자리를 잠그지 않는다.
    db_session.expire_all()
    assert (
        db_session.query(ConsultationRequest)
        .filter(ConsultationRequest.trainer_id == trainer.id)
        .count()
        == 0
    )
    slot = (
        db_session.query(TrainerReservationSlot)
        .filter(TrainerReservationSlot.trainer_id == trainer.id)
        .one()
    )
    assert slot.remaining == 1


def test_cancelling_a_pending_request_frees_room(client, db_session, limits):
    """대기 요청을 취소하면 그만큼 다시 신청할 수 있다 — 안내 문구가 약속하는 길이다."""
    limits(max_pending=1, per_day=100)
    _, token = _register_member(client)
    first, _ = _apply_to_new_trainer(client, db_session, token)
    assert first.status_code == 201, first.text
    blocked, _ = _apply_to_new_trainer(client, db_session, token)
    assert blocked.status_code == 409

    _cancel(client, token, first.json()["id"])
    again, _ = _apply_to_new_trainer(client, db_session, token)

    assert again.status_code == 201, again.text


def test_a_request_past_its_deadline_does_not_count(client, db_session, limits):
    """다른 트레이너에게 낸 요청이 이미 만료 시각을 지났으면 세지 않는다.

    만료 정리는 트레이너 단위로 읽는 시점에만 돈다. 그 트레이너의 화면을 아무도
    열지 않았으면 아직 `pending` 이라, 그대로 세면 이미 풀렸어야 할 요청이 회원을
    막는다.
    """
    limits(max_pending=1, per_day=100)
    _, token = _register_member(client)
    first, _ = _apply_to_new_trainer(client, db_session, token)
    assert first.status_code == 201, first.text
    # 신청 후 24시간이 지났다.
    stale = db_session.get(ConsultationRequest, first.json()["id"])
    stale.created_at = datetime.now(timezone.utc) - timedelta(hours=25)
    db_session.commit()

    again, _ = _apply_to_new_trainer(client, db_session, token)

    assert again.status_code == 201, again.text
    db_session.expire_all()
    assert db_session.get(ConsultationRequest, first.json()["id"]).status == "expired"



def test_the_same_trainer_can_be_asked_again_once_the_request_lapsed(
    client, db_session, limits
):
    """만료 시각이 지난 요청이 있는 트레이너에게 다시 신청하면 받아 준다.

    신청이 먼저 만료 정리를 돌리지만, 정리가 내보내지지 않으면 바로 뒤의 대기 중복
    검사가 그 요청을 아직 `pending` 으로 읽어 "이미 대기 중" 409 를 준다.
    """
    limits(max_pending=100, per_day=100)
    _, token = _register_member(client)
    first, trainer = _apply_to_new_trainer(client, db_session, token)
    assert first.status_code == 201, first.text
    stale = db_session.get(ConsultationRequest, first.json()["id"])
    stale.created_at = datetime.now(timezone.utc) - timedelta(hours=25)
    db_session.commit()

    again = _apply(client, db_session, token, trainer.id)

    assert again.status_code == 201, again.text

def test_a_duplicate_to_the_same_trainer_is_still_reported_as_duplicate(
    client, db_session, limits
):
    """같은 트레이너에게 또 내면 한도가 아니라 예전처럼 "이미 대기 중" 이다.

    앱은 그 409 를 받아 기존 신청을 보여 준다. 한도 코드로 바뀌면 그 안내를 잃는다.
    """
    limits(max_pending=1, per_day=100)
    _, token = _register_member(client)
    first, trainer = _apply_to_new_trainer(client, db_session, token)
    assert first.status_code == 201, first.text

    again = _apply(client, db_session, token, trainer.id)

    assert again.status_code == 409
    assert isinstance(again.json()["detail"], str)


def test_rejected_member_can_apply_again_right_away(client, db_session, limits):
    """거절된 트레이너에게 곧바로 다시 신청하는 길은 막지 않는다(#2067)."""
    limits(max_pending=1, per_day=100)
    _, token = _register_member(client)
    first, trainer = _apply_to_new_trainer(client, db_session, token)
    assert first.status_code == 201, first.text
    row = db_session.get(ConsultationRequest, first.json()["id"])
    row.status = "rejected"
    db_session.commit()

    again = _apply(client, db_session, token, trainer.id)

    assert again.status_code == 201, again.text


# --- 24시간 신청 한도 ---------------------------------------------------------


def test_apply_and_cancel_loops_are_capped_per_day(client, db_session, limits):
    """취소한 신청도 센다 — 신청·취소 반복이 트레이너 알림함을 채우는 길을 막는다."""
    limits(max_pending=100, per_day=3)
    _, token = _register_member(client)
    for _ in range(3):
        created, _ = _apply_to_new_trainer(client, db_session, token)
        assert created.status_code == 201, created.text
        _cancel(client, token, created.json()["id"])

    blocked, trainer = _apply_to_new_trainer(client, db_session, token)

    assert blocked.status_code == 429, blocked.text
    detail = blocked.json()["detail"]
    assert detail["code"] == "consultation_rate_limited"
    assert detail["limit"] == 3
    # 다시 시도할 수 있는 시점을 알린다 — 가장 오래된 신청이 24시간 창을 벗어나는
    # 순간이다. 방금 낸 신청들이라 24시간에 가깝다.
    retry_after = int(blocked.headers["Retry-After"])
    assert 23 * 3600 < retry_after <= 24 * 3600
    # 막힌 신청은 트레이너에게 알림을 남기지 않는다.
    assert (
        db_session.query(Notification)
        .filter(Notification.user_id == trainer.id)
        .count()
        == 0
    )


def test_the_window_frees_up_when_the_oldest_request_ages_out(
    client, db_session, limits
):
    """24시간이 지난 신청은 세지 않고, Retry-After 는 다음으로 빠질 신청을 가리킨다."""
    limits(max_pending=100, per_day=2)
    _, token = _register_member(client)
    ids = []
    for _ in range(2):
        created, _ = _apply_to_new_trainer(client, db_session, token)
        assert created.status_code == 201, created.text
        _cancel(client, token, created.json()["id"])
        ids.append(created.json()["id"])

    now = datetime.now(timezone.utc)
    oldest = db_session.get(ConsultationRequest, ids[0])
    oldest.created_at = now - timedelta(hours=23)
    db_session.commit()
    blocked, _ = _apply_to_new_trainer(client, db_session, token)
    assert blocked.status_code == 429
    # 23시간 전 신청이 1시간 뒤에 창을 벗어난다.
    assert 3500 < int(blocked.headers["Retry-After"]) <= 3600

    oldest.created_at = now - timedelta(hours=25)
    db_session.commit()
    freed, _ = _apply_to_new_trainer(client, db_session, token)
    assert freed.status_code == 201, freed.text


def test_limits_can_be_turned_off(client, db_session, limits, monkeypatch):
    """0 이면 그 한도를 끄고, RATE_LIMIT_ENABLED=false 면 신청 한도도 끈다."""
    limits(max_pending=0, per_day=1)
    monkeypatch.setattr(get_settings(), "rate_limit_enabled", False)
    _, token = _register_member(client)

    for _ in range(3):
        created, _ = _apply_to_new_trainer(client, db_session, token)
        assert created.status_code == 201, created.text


def test_the_limits_are_per_member(client, db_session, limits):
    """한 회원이 한도에 닿아도 다른 회원은 신청할 수 있다."""
    limits(max_pending=1, per_day=100)
    _, first = _register_member(client)
    _, second = _register_member(client)
    created, _ = _apply_to_new_trainer(client, db_session, first)
    assert created.status_code == 201, created.text

    other, _ = _apply_to_new_trainer(client, db_session, second)

    assert other.status_code == 201, other.text

