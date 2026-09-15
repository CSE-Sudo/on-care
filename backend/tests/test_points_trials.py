"""트레이너 빈 시간대 포인트 체험 예약 — 자격, 트레이너별 1회, 사용, 반환·소멸. (#1790)
DB 필요(로컬 skip, CI 실행).

테스트마다 트레이너를 새로 만들고 새로 가입한 회원에 포인트를 넣어 확인한다. 시드
트레이너(`trainer-demo`)의 슬롯·회원을 쓰면 다른 예약 테스트와 좌석·체험 기록이 섞인다.
"""
from __future__ import annotations

from collections.abc import Callable, Iterator
from datetime import datetime, timedelta, timezone
from uuid import uuid4

import pytest
from sqlalchemy import delete, func, select

from app.core import clock
from app.core.security import create_access_token
from app.models.models import (
    HealthProfile,
    Notification,
    PointsLedger,
    PointsTrial,
    TrainerClient,
    TrainerProfile,
    TrainerReservation,
    TrainerReservationSlot,
    TrainerSchedule,
    User,
)
from app.services import points_trial_service, trainer_service

TRIAL = points_trial_service.TRIAL_SESSION_TYPE


def _headers(user_id: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {create_access_token(user_id)}"}


@pytest.fixture
def make_trainer(db_session) -> Iterator[Callable[[], str]]:
    """이 테스트만 쓰는 트레이너를 만든다. 끝나면 예약을 먼저 치우고 지운다."""
    created: list[str] = []

    def _make() -> str:
        trainer_id = f"trainer-{uuid4().hex[:10]}"
        db_session.add(
            User(
                id=trainer_id,
                email=f"{trainer_id}@oncare.com",
                name="체험 트레이너",
                hashed_password="unused",
                role="trainer",
            )
        )
        db_session.commit()
        db_session.add(TrainerProfile(trainer_id=trainer_id, gym_name="체험 테스트짐"))
        db_session.commit()
        created.append(trainer_id)
        return trainer_id

    yield _make

    db_session.rollback()
    db_session.expire_all()
    for trainer_id in created:
        slot_ids = select(TrainerReservationSlot.id).where(
            TrainerReservationSlot.trainer_id == trainer_id
        )
        db_session.execute(
            delete(TrainerReservation).where(TrainerReservation.slot_id.in_(slot_ids))
        )
        db_session.commit()
        user = db_session.get(User, trainer_id)
        if user is not None:
            db_session.delete(user)
            db_session.commit()


def _new_member(client, db_session, points: int) -> tuple[str, dict[str, str]]:
    email = f"trial-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register", json={"email": email, "password": "pw!", "name": "체험회원"}
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "pw!"}
    ).json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    member_id = client.get("/v1/users/me", headers=headers).json()["id"]
    db_session.expire_all()
    profile = db_session.scalar(
        select(HealthProfile).where(HealthProfile.user_id == member_id)
    )
    if profile is None:
        db_session.add(HealthProfile(user_id=member_id, activity_points=points))
    else:
        profile.activity_points = points
    db_session.commit()
    return member_id, headers


def _open_slot(
    client,
    trainer_id: str,
    *,
    hours_ahead: float = 48,
    session_type: str = TRIAL,
    duration_minutes: int = 60,
) -> dict:
    starts_at = datetime.now(timezone.utc) + timedelta(hours=hours_ahead)
    response = client.post(
        "/v1/trainer/reservation-slots",
        headers=_headers(trainer_id),
        json={
            "starts_at": starts_at.isoformat(),
            "session_type": session_type,
            "duration_minutes": duration_minutes,
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


def _book(client, headers, slot_id: str):
    return client.post("/v1/reservations", headers=headers, json={"slot_id": slot_id})


def _balance(client, headers) -> int:
    response = client.get("/v1/users/me/health", headers=headers)
    assert response.status_code == 200, response.text
    return response.json()["activity_points"]


def _member_slots(client, headers, trainer_id: str) -> list[dict]:
    response = client.get(f"/v1/trainers/{trainer_id}/slots", headers=headers)
    assert response.status_code == 200, response.text
    return response.json()


def _trial(db_session, reservation_id: str) -> PointsTrial | None:
    db_session.expire_all()
    return db_session.scalar(
        select(PointsTrial).where(PointsTrial.reservation_id == reservation_id)
    )


def _ledger(db_session, member_id: str, kind: str) -> list[PointsLedger]:
    db_session.expire_all()
    return list(
        db_session.scalars(
            select(PointsLedger).where(
                PointsLedger.user_id == member_id,
                PointsLedger.kind == kind,
                PointsLedger.source_type == points_trial_service.SOURCE_POINTS_TRIAL,
            )
        ).all()
    )


def _move_schedule_to_yesterday(db_session, schedule_id: str) -> None:
    """노쇼·완료는 지난 일정에만 걸 수 있다 — 체험 일정 날짜만 어제로 옮긴다."""
    db_session.expire_all()
    schedule = db_session.get(TrainerSchedule, schedule_id)
    schedule.date = (clock.today() - timedelta(days=1)).isoformat()
    db_session.commit()


# ---- 트레이너 슬롯 ----


def test_trial_slot_is_twenty_minutes_and_costs_points(client, make_trainer):
    trainer_id = make_trainer()

    slot = _open_slot(client, trainer_id, duration_minutes=60)

    assert slot["session_type"] == TRIAL
    assert slot["duration_minutes"] == 20
    assert slot["points_cost"] == 500

    # 시간을 바꾸려 해도 20분이다.
    updated = client.put(
        f"/v1/trainer/reservation-slots/{slot['id']}",
        headers=_headers(trainer_id),
        json={"duration_minutes": 45},
    )
    assert updated.status_code == 200, updated.text
    assert updated.json()["duration_minutes"] == 20

    # 체험을 끄면 그 종류의 기본 시간으로 돌아가고 포인트도 들지 않는다.
    regular = client.put(
        f"/v1/trainer/reservation-slots/{slot['id']}",
        headers=_headers(trainer_id),
        json={"session_type": "1:1 PT"},
    )
    assert regular.status_code == 200, regular.text
    assert regular.json()["duration_minutes"] == 60
    assert regular.json()["points_cost"] == 0


# ---- 자격 ----


def test_member_without_trainer_books_trial_with_points(
    client, db_session, make_trainer
):
    trainer_id = make_trainer()
    member_id, headers = _new_member(client, db_session, 1000)
    slot = _open_slot(client, trainer_id)

    listed = next(s for s in _member_slots(client, headers, trainer_id) if s["id"] == slot["id"])
    assert listed["points_cost"] == 500
    assert listed["trial_blocked_reason"] is None

    booked = _book(client, headers, slot["id"])

    assert booked.status_code == 201, booked.text
    body = booked.json()
    assert body["session_type"] == TRIAL
    assert body["points_spent"] == 500
    assert body["points_balance"] == 500
    assert _balance(client, headers) == 500

    spent = _ledger(db_session, member_id, "spend")
    assert [(row.delta, row.reason) for row in spent] == [(-500, "trial_booking")]
    trial = _trial(db_session, body["id"])
    assert trial is not None and trial.status == "booked"
    assert trial.trainer_id == trainer_id

    # 기존 예약 흐름 그대로 트레이너 일정이 생긴다.
    schedule = db_session.get(TrainerSchedule, body["schedule_id"])
    assert schedule.type == TRIAL
    assert schedule.duration_minutes == 20
    assert schedule.member_id == member_id
    timeline = client.get(
        "/v1/trainer/schedule",
        headers=_headers(trainer_id),
        params={"date": schedule.date},
    )
    assert timeline.status_code == 200, timeline.text
    assert any(
        row["id"] == schedule.id and row["type"] == TRIAL for row in timeline.json()
    )

    mine = client.get("/v1/reservations/me", headers=headers).json()
    assert mine[0]["session_type"] == TRIAL
    assert mine[0]["points_cost"] == 500
    assert mine[0]["points_refundable"] is True


def test_member_with_a_trainer_neither_sees_nor_books_trials(
    client, db_session, make_trainer
):
    trial_trainer = make_trainer()
    my_trainer = make_trainer()
    member_id, headers = _new_member(client, db_session, 1000)
    db_session.add(
        TrainerClient(
            id=f"tc-{uuid4().hex[:12]}",
            trainer_id=my_trainer,
            member_id=member_id,
            active=True,
        )
    )
    db_session.commit()
    slot = _open_slot(client, trial_trainer)

    assert all(s["id"] != slot["id"] for s in _member_slots(client, headers, trial_trainer))

    booked = _book(client, headers, slot["id"])

    assert booked.status_code == 409
    assert _balance(client, headers) == 1000
    db_session.expire_all()
    assert db_session.get(TrainerReservationSlot, slot["id"]).remaining == 1


def test_regular_slot_still_needs_the_assigned_trainer(
    client, db_session, make_trainer
):
    trainer_id = make_trainer()
    _, headers = _new_member(client, db_session, 1000)
    slot = _open_slot(client, trainer_id, session_type="1:1 PT")

    assert _book(client, headers, slot["id"]).status_code == 409


def test_insufficient_points_blocks_trial_and_changes_nothing(
    client, db_session, make_trainer
):
    trainer_id = make_trainer()
    member_id, headers = _new_member(client, db_session, 499)
    slot = _open_slot(client, trainer_id)

    listed = next(s for s in _member_slots(client, headers, trainer_id) if s["id"] == slot["id"])
    assert listed["trial_blocked_reason"] == "insufficient_points"

    booked = _book(client, headers, slot["id"])

    assert booked.status_code == 409
    assert _balance(client, headers) == 499
    db_session.expire_all()
    assert db_session.get(TrainerReservationSlot, slot["id"]).remaining == 1
    assert (
        db_session.scalar(
            select(func.count())
            .select_from(PointsTrial)
            .where(PointsTrial.member_id == member_id)
        )
        == 0
    )


def test_one_trial_per_trainer(client, db_session, make_trainer):
    trainer_a = make_trainer()
    trainer_b = make_trainer()
    _, headers = _new_member(client, db_session, 2000)
    first = _open_slot(client, trainer_a, hours_ahead=48)
    second = _open_slot(client, trainer_a, hours_ahead=72)
    other = _open_slot(client, trainer_b, hours_ahead=48)

    assert _book(client, headers, first["id"]).status_code == 201

    listed = next(s for s in _member_slots(client, headers, trainer_a) if s["id"] == second["id"])
    assert listed["trial_blocked_reason"] == "trial_used"
    assert _book(client, headers, second["id"]).status_code == 409
    # 다른 트레이너 체험은 따로 센다.
    assert _book(client, headers, other["id"]).status_code == 201
    assert _balance(client, headers) == 1000


# ---- 취소·결말 ----


def test_member_cancel_a_day_ahead_refunds_and_frees_the_trial(
    client, db_session, make_trainer
):
    trainer_id = make_trainer()
    member_id, headers = _new_member(client, db_session, 1000)
    slot = _open_slot(client, trainer_id, hours_ahead=48)
    reservation_id = _book(client, headers, slot["id"]).json()["id"]

    cancelled = client.delete(f"/v1/reservations/{reservation_id}", headers=headers)

    assert cancelled.status_code == 200, cancelled.text
    assert cancelled.json() == {"status": "cancelled", "points_refunded": 500}
    assert _balance(client, headers) == 1000
    assert _trial(db_session, reservation_id).status == "refunded"
    assert [row.delta for row in _ledger(db_session, member_id, "refund")] == [500]
    # 반환된 체험은 1회에 세지 않는다 — 같은 트레이너 체험을 다시 잡을 수 있다.
    assert _book(client, headers, slot["id"]).status_code == 201


def test_member_cancel_within_a_day_forfeits_points(client, db_session, make_trainer):
    trainer_id = make_trainer()
    member_id, headers = _new_member(client, db_session, 1000)
    slot = _open_slot(client, trainer_id, hours_ahead=3)
    later = _open_slot(client, trainer_id, hours_ahead=72)
    reservation_id = _book(client, headers, slot["id"]).json()["id"]

    mine = client.get("/v1/reservations/me", headers=headers).json()
    assert next(r for r in mine if r["id"] == reservation_id)["points_refundable"] is False

    cancelled = client.delete(f"/v1/reservations/{reservation_id}", headers=headers)

    assert cancelled.status_code == 200, cancelled.text
    assert cancelled.json()["points_refunded"] == 0
    assert _balance(client, headers) == 500
    assert _trial(db_session, reservation_id).status == "forfeited"
    assert _ledger(db_session, member_id, "refund") == []
    # 늦은 취소는 1회로 센다.
    assert _book(client, headers, later["id"]).status_code == 409


def test_moved_trial_uses_the_new_start_for_refunds(
    client, db_session, make_trainer
):
    trainer_id = make_trainer()
    _, headers = _new_member(client, db_session, 1000)
    slot = _open_slot(client, trainer_id, hours_ahead=48)
    reservation_id = _book(client, headers, slot["id"]).json()["id"]

    # 트레이너가 예약된 체험을 3시간 뒤로 당긴다 — 이제 24시간 이내다.
    moved = client.put(
        f"/v1/trainer/reservation-slots/{slot['id']}",
        headers=_headers(trainer_id),
        json={
            "starts_at": (datetime.now(timezone.utc) + timedelta(hours=3)).isoformat()
        },
    )
    assert moved.status_code == 200, moved.text

    mine = client.get("/v1/reservations/me", headers=headers).json()
    assert next(r for r in mine if r["id"] == reservation_id)["points_refundable"] is False
    cancelled = client.delete(f"/v1/reservations/{reservation_id}", headers=headers)
    assert cancelled.json()["points_refunded"] == 0
    assert _balance(client, headers) == 500


def test_trainer_cancel_refunds_points(client, db_session, make_trainer):
    trainer_id = make_trainer()
    member_id, headers = _new_member(client, db_session, 1000)
    slot = _open_slot(client, trainer_id, hours_ahead=3)
    booked = _book(client, headers, slot["id"]).json()

    # 트레이너가 회원 사정이라고 적어도 이 경로의 행위자는 트레이너다.
    cancelled = client.post(
        f"/v1/trainer/schedule/{booked['schedule_id']}/cancel",
        headers=_headers(trainer_id),
        json={"source": "member", "reason": ""},
    )

    assert cancelled.status_code == 200, cancelled.text
    assert _balance(client, headers) == 1000
    trial = _trial(db_session, booked["id"])
    assert trial.status == "refunded"
    assert trial.settled_by == "trainer"
    assert (
        db_session.scalar(
            select(func.count())
            .select_from(Notification)
            .where(
                Notification.user_id == member_id,
                Notification.body.contains("500P 반환"),
            )
        )
        == 1
    )
    # 같은 취소를 다시 보내도 두 번 돌려주지 않는다.
    again = client.post(
        f"/v1/trainer/schedule/{booked['schedule_id']}/cancel",
        headers=_headers(trainer_id),
        json={"source": "trainer", "reason": ""},
    )
    assert again.status_code == 200
    assert _balance(client, headers) == 1000


def test_no_show_forfeits_points(client, db_session, make_trainer):
    trainer_id = make_trainer()
    member_id, headers = _new_member(client, db_session, 1000)
    slot = _open_slot(client, trainer_id, hours_ahead=48)
    later = _open_slot(client, trainer_id, hours_ahead=96)
    booked = _book(client, headers, slot["id"]).json()
    _move_schedule_to_yesterday(db_session, booked["schedule_id"])

    marked = client.post(
        f"/v1/trainer/schedule/{booked['schedule_id']}/no-show",
        headers=_headers(trainer_id),
    )

    assert marked.status_code == 200, marked.text
    assert _balance(client, headers) == 500
    assert _trial(db_session, booked["id"]).status == "no_show"
    assert _ledger(db_session, member_id, "refund") == []
    assert _book(client, headers, later["id"]).status_code == 409


def test_completed_trial_keeps_points_spent(client, db_session, make_trainer):
    trainer_id = make_trainer()
    member_id, headers = _new_member(client, db_session, 1000)
    slot = _open_slot(client, trainer_id, hours_ahead=48)
    booked = _book(client, headers, slot["id"]).json()
    _move_schedule_to_yesterday(db_session, booked["schedule_id"])

    done = client.post(
        f"/v1/trainer/schedule/{booked['schedule_id']}/complete",
        headers=_headers(trainer_id),
        json={"note": ""},
    )

    assert done.status_code == 200, done.text
    assert _balance(client, headers) == 500
    assert _trial(db_session, booked["id"]).status == "completed"
    assert _ledger(db_session, member_id, "refund") == []


def test_trainer_account_deletion_refunds_booked_trial(
    client, db_session, make_trainer
):
    trainer_id = make_trainer()
    _, headers = _new_member(client, db_session, 1000)
    slot = _open_slot(client, trainer_id, hours_ahead=48)
    assert _book(client, headers, slot["id"]).status_code == 201
    assert _balance(client, headers) == 500

    db_session.expire_all()
    trainer_service.delete_trainer_account(db_session, db_session.get(User, trainer_id))

    assert _balance(client, headers) == 1000
