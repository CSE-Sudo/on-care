"""상담 요청 상태 전이의 경합. (#3091) DB(Postgres) 필요.

수락만 행을 잠그고 회원 취소·트레이너 거절·만료 정리는 잠그지 않던 때에는, 수락과
겹치면 이미 커밋된 `accepted` 를 `cancelled`·`rejected`·`expired` 로 덮어썼다 —
수락이 만든 상담 일정은 남고, 자리는 한 번 더 풀리고, 양쪽에 서로 다른 알림이 갔다.

세션을 둘 열고 순서를 고정해 재현한다. 한쪽이 행을 잡은 지점에서 다른 쪽을 스레드로
출발시키고, 그 스레드가 실제로 행 잠금을 기다리는 것(`pg_locks`)을 본 뒤에 먼저 간
쪽을 마저 진행한다 — 시간 간격에 기대지 않는다.
"""
from __future__ import annotations

import time
from datetime import timedelta
from threading import Thread
from typing import Any, Callable

import pytest
from sqlalchemy import text

from app.models.models import (
    ConsultationRequest,
    Notification,
    Place,
    TrainerProfile,
    TrainerReservationSlot,
    TrainerSchedule,
    User,
)
from app.services import consultation_service, notification_templates
from app.services import reservation_service
from app.services.trainer import schedule as trainer_schedule_service

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
        db_session.query(TrainerSchedule).filter(
            (TrainerSchedule.trainer_id.in_(user_ids))
            | (TrainerSchedule.member_id.in_(user_ids))
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


# --- 준비 ---------------------------------------------------------------------


def _pending(client, db_session, *, hours_ahead: float = 48):
    """대기 중인 상담 요청 하나. (member_id, trainer_id, consultation_id, slot)"""
    member_id, token = _register_member(client)
    trainer = _create_trainer(db_session)
    slot = _create_slot(db_session, trainer.id, hours_ahead=hours_ahead)
    created = client.post(
        "/v1/consultations",
        headers=_auth(token),
        json=_payload(db_session, trainer_id=trainer.id, slot_id=slot.id),
    )
    assert created.status_code == 201, created.text
    return member_id, trainer.id, created.json()["id"], slot


def _wait_for_lock_waiter(timeout: float = 5.0) -> None:
    """다른 세션이 행 잠금을 기다리기 시작할 때까지 본다.

    시간이 다 돼도 그냥 돌아간다 — 기다리지 않고 끝난 경우도 판정은 뒤의 단언이 한다.
    """
    from app.db.session import SessionLocal

    deadline = time.monotonic() + timeout
    with SessionLocal() as probe:
        while time.monotonic() < deadline:
            waiting = probe.scalar(
                text("SELECT count(*) FROM pg_locks WHERE NOT granted")
            )
            probe.rollback()
            if waiting:
                return
            time.sleep(0.02)


class _Contender:
    """다른 세션에서 한 번 돌리는 호출. 결과나 예외를 남긴다."""

    def __init__(self, fn: Callable[[Any], Any]):
        self._fn = fn
        self.result: Any = None
        self.error: BaseException | None = None
        self._thread = Thread(target=self._run, daemon=True)

    def _run(self) -> None:
        from app.db.session import SessionLocal

        with SessionLocal() as session:
            try:
                self.result = self._fn(session)
            except BaseException as exc:  # noqa: BLE001 — 판정은 테스트가 한다
                session.rollback()
                self.error = exc

    def start(self) -> None:
        self._thread.start()

    def join(self) -> None:
        self._thread.join(timeout=15)
        assert not self._thread.is_alive(), "경합 상대가 끝나지 않았다(교착?)"


def _cancel(member_id: str, consultation_id: str):
    return lambda s: consultation_service.cancel_my_consultation(
        s, member_id, consultation_id
    )


def _reject(trainer_id: str, consultation_id: str):
    return lambda s: consultation_service.reject(
        s, trainer_id, consultation_id, "죄송합니다"
    )


def _expire(trainer_id: str, slot: TrainerReservationSlot):
    """만료 기준(자리 시작 2시간 전)을 막 지난 시각으로 정리한다."""
    passed = slot.starts_at - timedelta(hours=1)

    def run(s):
        count = consultation_service.expire_stale_requests(s, trainer_id, now=passed)
        s.commit()
        return count

    return run


#: 경합 상대 → (만들기, 그 상대가 이겼을 때의 상태, 졌을 때 내는 예외 — 없으면 0건)
CONTENDERS = {
    "cancel": (
        lambda m, t, c, slot: _cancel(m, c),
        "cancelled",
        consultation_service.ConsultationNotCancellable,
    ),
    "reject": (
        lambda m, t, c, slot: _reject(t, c),
        "rejected",
        consultation_service.ConsultationAlreadyDecided,
    ),
    "expire": (
        lambda m, t, c, slot: _expire(t, slot),
        "expired",
        None,
    ),
}

#: 진 쪽이 보내면 안 되는 알림 틀.
LOSER_TEMPLATES = (
    notification_templates.TRAINER_CONSULT_CANCELLED,
    notification_templates.MEMBER_CONSULT_REJECTED,
    notification_templates.MEMBER_CONSULT_EXPIRED,
)


def _state(db_session, consultation_id: str, slot_id: str, user_ids: list[str]):
    db_session.expire_all()
    status = db_session.get(ConsultationRequest, consultation_id).status
    remaining = db_session.get(TrainerReservationSlot, slot_id).remaining
    schedules = (
        db_session.query(TrainerSchedule)
        .filter(TrainerSchedule.consultation_id == consultation_id)
        .count()
    )
    templates = [
        row[0]
        for row in db_session.query(Notification.template)
        .filter(Notification.user_id.in_(user_ids))
        .all()
    ]
    return status, remaining, schedules, templates


# --- 수락이 먼저 잠근다 → 상대는 덮어쓰지 못한다 --------------------------------


@pytest.mark.parametrize("kind", sorted(CONTENDERS))
def test_accept_holding_the_row_wins_and_the_contender_changes_nothing(
    client, db_session, monkeypatch, kind
):
    """수락이 행을 잡은 사이 들어온 취소·거절·만료는 `accepted` 를 덮어쓰지 않는다.

    진 쪽은 지금과 같은 409(만료는 0건)이고, 자리를 풀지 않고, 알림도 보내지 않는다.
    """
    from app.db.session import SessionLocal

    member_id, trainer_id, consultation_id, slot = _pending(
        client, db_session, hours_ahead=5
    )
    make, _, loser_error = CONTENDERS[kind]
    contender = _Contender(make(member_id, trainer_id, consultation_id, slot))

    real_overlap = trainer_schedule_service.ensure_no_overlap

    def hooked_overlap(*args, **kwargs):
        # 수락이 `FOR UPDATE` 로 행을 잡은 직후다.
        contender.start()
        _wait_for_lock_waiter()
        return real_overlap(*args, **kwargs)

    monkeypatch.setattr(trainer_schedule_service, "ensure_no_overlap", hooked_overlap)

    with SessionLocal() as session:
        consultation_service.accept(session, trainer_id, consultation_id)
    contender.join()

    if loser_error is None:
        assert contender.error is None, contender.error
        assert contender.result == 0
    else:
        assert isinstance(contender.error, loser_error), contender.error

    status, remaining, schedules, templates = _state(
        db_session, consultation_id, slot.id, [member_id, trainer_id]
    )
    assert status == "accepted"
    assert schedules == 1
    # 신청 때 잡은 자리 그대로 — 해제 0회.
    assert remaining == 0
    assert notification_templates.MEMBER_CONSULT_APPROVED in templates
    assert not set(templates) & set(LOSER_TEMPLATES)


# --- 상대가 먼저 바꾼다 → 수락이 409 --------------------------------------------


@pytest.mark.parametrize("kind", sorted(CONTENDERS))
def test_a_transition_holding_the_row_wins_and_accept_conflicts(
    client, db_session, monkeypatch, kind
):
    """취소·거절·만료가 먼저 바꾸면 기다리던 수락은 바뀐 상태를 읽고 409 로 멈춘다.

    수락이 세션 캐시의 옛 `pending` 을 쓰면 취소된 요청에 상담 일정을 잡는다.
    """
    from app.db.session import SessionLocal

    member_id, trainer_id, consultation_id, slot = _pending(
        client, db_session, hours_ahead=5
    )
    make, winner_status, _ = CONTENDERS[kind]
    acceptor = _Contender(
        lambda s: consultation_service.accept(s, trainer_id, consultation_id)
    )

    real_release = reservation_service.release_consultation_hold
    started = False

    def hooked_release(*args, **kwargs):
        # 조건부 전이로 행을 잡은 직후다.
        nonlocal started
        if not started:
            started = True
            acceptor.start()
            _wait_for_lock_waiter()
        return real_release(*args, **kwargs)

    monkeypatch.setattr(
        reservation_service, "release_consultation_hold", hooked_release
    )

    with SessionLocal() as session:
        make(member_id, trainer_id, consultation_id, slot)(session)
    acceptor.join()

    assert isinstance(
        acceptor.error, consultation_service.ConsultationAlreadyDecided
    ), acceptor.error

    status, remaining, schedules, templates = _state(
        db_session, consultation_id, slot.id, [member_id, trainer_id]
    )
    assert status == winner_status
    assert schedules == 0
    # 해제 1회 — 정원 1인 자리가 다시 열린다.
    assert remaining == 1
    assert notification_templates.MEMBER_CONSULT_APPROVED not in templates


# --- 만료 정리끼리 --------------------------------------------------------------


def test_two_concurrent_expiry_sweeps_notify_the_member_once(
    client, db_session, monkeypatch
):
    """인박스 목록과 대기 배지가 함께 정리해도 회원 만료 알림은 한 번이다."""
    from app.db.session import SessionLocal

    member_id, trainer_id, consultation_id, slot = _pending(
        client, db_session, hours_ahead=5
    )
    second = _Contender(_expire(trainer_id, slot))

    real_release = reservation_service.release_consultation_hold
    started = False

    def hooked_release(*args, **kwargs):
        nonlocal started
        if not started:
            started = True
            second.start()
            _wait_for_lock_waiter()
        return real_release(*args, **kwargs)

    monkeypatch.setattr(
        reservation_service, "release_consultation_hold", hooked_release
    )

    with SessionLocal() as session:
        first = _expire(trainer_id, slot)(session)
    second.join()

    assert second.error is None, second.error
    assert first + second.result == 1

    status, remaining, _, templates = _state(
        db_session, consultation_id, slot.id, [member_id]
    )
    assert status == "expired"
    assert remaining == 1
    assert templates.count(notification_templates.MEMBER_CONSULT_EXPIRED) == 1
