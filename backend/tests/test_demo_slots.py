"""데모 트레이너의 예약 자리 (#2067).

상담 신청은 트레이너가 연 자리를 고르는 방식이라(#1873), 데모 트레이너에게 자리가
없으면 새로 띄운 서버에서 아무도 신청할 수 없다. 기동할 때 깔고, 목록을 읽을 때
떨어졌으면 다시 깐다.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest

from app.core.clock import SEOUL
from app.core.config import get_settings
from app.db import seed_slots
from app.models.models import TrainerReservationSlot
from app.services.consultation_service import slot_visibility_cutoff

#: 이 파일이 직접 만드는 자리. 데모 자리(`slot-demo-`)와 구분해 지운다.
OWN_SLOT_PREFIX = "demo-slots-test-"

#: 읽을 때 채우는지 볼 데모 트레이너. 담당 회원이 없어 다른 테스트가 이 트레이너의
#: 자리를 쓰지 않는다.
TOP_UP_TRAINER = "trainer-cho"


def _login(client, email: str) -> str:
    response = client.post(
        "/v1/auth/login", data={"username": email, "password": "oncare123"}
    )
    assert response.status_code == 200, response.text
    return response.json()["access_token"]


def _auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _consult_slots(client, token: str, trainer_id: str) -> list[dict]:
    response = client.get(
        "/v1/consultations/slots",
        headers=_auth(token),
        params={"trainer_id": trainer_id},
    )
    assert response.status_code == 200, response.text
    return response.json()


def _demo_slots(db_session, trainer_id: str) -> list[TrainerReservationSlot]:
    return list(
        db_session.query(TrainerReservationSlot)
        .filter(
            TrainerReservationSlot.trainer_id == trainer_id,
            TrainerReservationSlot.id.like(f"slot-demo-{trainer_id}-%"),
        )
        .all()
    )


@pytest.fixture
def emptied_trainer(db_session):
    """[TOP_UP_TRAINER] 의 고를 자리를 모두 닫아 둔다. 끝나면 되돌린다.

    이 테스트들이 새로 깐 데모 자리는 지운다 — 남기면 뒤 테스트가 "고를 자리가
    있다" 에서 출발해 채우는 경로를 보지 못한다.
    """
    db_session.expire_all()
    before = {slot.id for slot in _demo_slots(db_session, TOP_UP_TRAINER)}
    cutoff = slot_visibility_cutoff(datetime.now(timezone.utc))
    closed: list[str] = []
    for slot in db_session.query(TrainerReservationSlot).filter(
        TrainerReservationSlot.trainer_id == TOP_UP_TRAINER,
        TrainerReservationSlot.is_closed.is_(False),
        TrainerReservationSlot.starts_at > cutoff,
    ):
        slot.is_closed = True
        closed.append(slot.id)
    db_session.commit()

    yield set(closed)

    db_session.rollback()
    db_session.expire_all()
    db_session.query(TrainerReservationSlot).filter(
        TrainerReservationSlot.id.like(f"{OWN_SLOT_PREFIX}%")
    ).delete(synchronize_session=False)
    for slot in _demo_slots(db_session, TOP_UP_TRAINER):
        if slot.id not in before:
            db_session.delete(slot)
    if closed:
        db_session.query(TrainerReservationSlot).filter(
            TrainerReservationSlot.id.in_(closed)
        ).update({"is_closed": False}, synchronize_session=False)
    db_session.commit()


# --- 기동 시드 ----------------------------------------------------------------


def test_every_demo_trainer_but_yoon_has_a_slot_to_pick(client, db_session):
    """새로 띄운 서버에서도 데모 트레이너마다 상담 폼에 고를 자리가 있다."""
    token = _login(client, "jisu@oncare.com")

    for trainer_id in seed_slots.DEMO_SLOT_TRAINER_IDS:
        slots = _consult_slots(client, token, trainer_id)
        assert slots, f"{trainer_id} 에게 고를 자리가 없습니다."
        assert all(slot["session_type"] == "1:1 PT" for slot in slots)

    # 빈 상태(헬스장 전화 안내)도 데모에서 보여야 한다.
    assert "trainer-yoon" not in seed_slots.DEMO_SLOT_TRAINER_IDS
    assert _demo_slots(db_session, "trainer-yoon") == []
    assert _consult_slots(client, token, "trainer-yoon") == []


def test_restarting_does_not_pile_up_slots(client, db_session):
    """다시 기동해도 자리가 쌓이지 않는다 — 고를 자리가 있으면 건너뛴다."""
    def count() -> int:
        db_session.expire_all()
        return (
            db_session.query(TrainerReservationSlot)
            .filter(TrainerReservationSlot.id.like("slot-demo-%"))
            .count()
        )

    before = count()
    seed_slots.seed_demo_slots()
    seed_slots.seed_demo_slots()

    assert count() == before


def test_demo_slots_start_tomorrow_at_one_and_the_day_after_at_half_past_seven(
    db_session,
):
    """빈 달력이면 내일 13:00, 모레 19:30 에 60분짜리 `1:1 PT` 두 개를 깐다.

    지금 달력과 겹치지 않게 먼 미래를 '지금' 으로 두고 본다.
    """
    now = datetime(2031, 3, 10, 9, 0, tzinfo=SEOUL)
    try:
        created = seed_slots.top_up_demo_slots(
            db_session,
            TOP_UP_TRAINER,
            after=slot_visibility_cutoff(now),
            now=now,
        )
        db_session.flush()

        assert created == 2
        slots = sorted(
            (
                slot
                for slot in _demo_slots(db_session, TOP_UP_TRAINER)
                if slot.starts_at > now
            ),
            key=lambda slot: slot.starts_at,
        )
        assert [slot.starts_at.astimezone(SEOUL) for slot in slots] == [
            datetime(2031, 3, 11, 13, 0, tzinfo=SEOUL),
            datetime(2031, 3, 12, 19, 30, tzinfo=SEOUL),
        ]
        for slot in slots:
            assert slot.session_type == "1:1 PT"
            assert slot.duration_minutes == 60
            assert (slot.capacity, slot.remaining, slot.is_closed) == (1, 1, False)
    finally:
        db_session.rollback()


def test_a_taken_or_closed_time_is_skipped_not_reopened(db_session):
    """앞쪽 시각에 자리가 있으면(잡혔거나 닫혔으면) 그 뒤 시각으로 민다.

    그 자리를 다시 열면 누군가 잡은 자리나 트레이너가 닫은 자리가 되살아난다.
    """
    now = datetime(2031, 3, 10, 9, 0, tzinfo=SEOUL)
    try:
        db_session.add(
            TrainerReservationSlot(
                id=f"{OWN_SLOT_PREFIX}closed",
                trainer_id=TOP_UP_TRAINER,
                starts_at=datetime(2031, 3, 11, 13, 0, tzinfo=SEOUL),
                duration_minutes=60,
                capacity=1,
                remaining=1,
                session_type="1:1 PT",
                is_closed=True,
            )
        )
        db_session.flush()

        seed_slots.top_up_demo_slots(
            db_session,
            TOP_UP_TRAINER,
            after=slot_visibility_cutoff(now),
            now=now,
        )
        db_session.flush()

        starts = sorted(
            slot.starts_at.astimezone(SEOUL)
            for slot in _demo_slots(db_session, TOP_UP_TRAINER)
            if slot.starts_at > now
        )
        assert starts == [
            datetime(2031, 3, 12, 19, 30, tzinfo=SEOUL),
            datetime(2031, 3, 13, 13, 0, tzinfo=SEOUL),
        ]
        closed = db_session.get(TrainerReservationSlot, f"{OWN_SLOT_PREFIX}closed")
        assert closed.is_closed is True
    finally:
        db_session.rollback()


# --- 읽을 때 채우기 -----------------------------------------------------------


def test_consultation_form_refills_a_demo_trainer_who_ran_out(
    client, db_session, emptied_trainer
):
    """기동할 때 깐 자리가 다 잡히거나 지나도, 폼을 여는 순간 다시 깐다.

    기동할 때만 깔면 재기동 없이 며칠 켜 둔 서버에서 자리가 다시 빈다.
    """
    token = _login(client, "jisu@oncare.com")

    slots = _consult_slots(client, token, TOP_UP_TRAINER)

    assert len(slots) == 2
    assert not {slot["id"] for slot in slots} & emptied_trainer
    cutoff = slot_visibility_cutoff(datetime.now(timezone.utc))
    for slot in slots:
        assert slot["id"].startswith(f"slot-demo-{TOP_UP_TRAINER}-")
        assert datetime.fromisoformat(slot["starts_at"]) > cutoff

    # 한 번 채운 뒤에는 읽어도 더 늘지 않는다.
    again = _consult_slots(client, token, TOP_UP_TRAINER)
    assert {slot["id"] for slot in again} == {slot["id"] for slot in slots}


def test_gym_tab_slot_list_refills_too(client, db_session, emptied_trainer):
    """헬스장 탭의 예약 가능 시간도 같은 자리를 본다."""
    token = _login(client, "jisu@oncare.com")

    response = client.get(
        f"/v1/trainers/{TOP_UP_TRAINER}/slots", headers=_auth(token)
    )

    assert response.status_code == 200, response.text
    open_ids = {
        slot["id"]
        for slot in response.json()
        if not slot["is_closed"] and slot["remaining"] > 0
    }
    assert open_ids
    assert all(i.startswith(f"slot-demo-{TOP_UP_TRAINER}-") for i in open_ids)


def test_a_slot_the_trainer_opened_is_left_alone(
    client, db_session, emptied_trainer
):
    """트레이너가 연 자리가 하나라도 있으면 채우지 않는다."""
    starts_at = datetime.now(timezone.utc) + timedelta(days=3)
    db_session.add(
        TrainerReservationSlot(
            id=f"{OWN_SLOT_PREFIX}own",
            trainer_id=TOP_UP_TRAINER,
            starts_at=starts_at,
            duration_minutes=30,
            capacity=1,
            remaining=1,
            session_type="1:1 PT",
        )
    )
    db_session.commit()
    token = _login(client, "jisu@oncare.com")

    slots = _consult_slots(client, token, TOP_UP_TRAINER)

    assert [slot["id"] for slot in slots] == [f"{OWN_SLOT_PREFIX}own"]


def test_nothing_is_refilled_when_demo_data_is_off(
    client, db_session, emptied_trainer, monkeypatch
):
    """`SEED_DEMO_DATA` 가 꺼진 서버에는 지어낸 자리를 넣지 않는다."""
    monkeypatch.setattr(get_settings(), "seed_demo_data", False)
    token = _login(client, "jisu@oncare.com")

    assert _consult_slots(client, token, TOP_UP_TRAINER) == []


def test_a_trainer_outside_the_demo_roster_is_never_refilled(db_session):
    """실제로 가입한 트레이너의 달력에는 지어낸 자리를 넣지 않는다."""
    now = datetime.now(timezone.utc)

    assert (
        seed_slots.top_up_demo_slots(
            db_session, "trainer-not-in-demo", after=slot_visibility_cutoff(now)
        )
        == 0
    )
    assert (
        seed_slots.top_up_demo_slots(
            db_session, "trainer-yoon", after=slot_visibility_cutoff(now)
        )
        == 0
    )
