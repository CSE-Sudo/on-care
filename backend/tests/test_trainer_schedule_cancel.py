"""일정 취소·노쇼 — 상태 전이·기록 보존·기존 삭제와의 구분. (#871) DB 필요."""
from __future__ import annotations

from datetime import timedelta

import pytest
from sqlalchemy import select

from uuid import uuid4

from app.core import clock
from app.core.security import create_access_token
from app.models.models import RoutineHistory, TrainerSchedule, User


def _tok(client) -> str:
    return client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    ).json()["access_token"]


def _h(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _today() -> str:
    """서버가 쓰는 '오늘'과 같은 기준(KST)."""
    return clock.today().isoformat()


@pytest.fixture()
def make_pt_session(client):
    """PT 세션을 만들고 테스트 끝에 지우는 팩토리.

    정리하지 않으면 회원 이력·주간 집계가 테스트마다 쌓여 다른 테스트를 깨뜨린다
    (`test_trainer_schedule.py` 의 같은 이름 픽스처와 같은 이유).
    """
    created: list[tuple[str, str]] = []

    def _make(token: str, **over) -> str:
        body = {
            "date": _today(),
            "time": "20:00",
            "client_name": "이지수",
            "member_id": "user-jisu",
            "type": "1:1 PT",
            "duration_minutes": 60,
        }
        body.update(over)
        response = client.post("/v1/trainer/schedule", json=body, headers=_h(token))
        assert response.status_code == 201, response.text
        session_id = response.json()["id"]
        created.append((session_id, token))
        return session_id

    yield _make

    for session_id, token in created:
        client.delete(f"/v1/trainer/schedule/{session_id}", headers=_h(token))


def _cancel(client, token: str, session_id: str, **body):
    payload = {"source": "member"}
    payload.update(body)
    return client.post(
        f"/v1/trainer/schedule/{session_id}/cancel",
        json=payload,
        headers=_h(token),
    )


def _no_show(client, token: str, session_id: str):
    return client.post(
        f"/v1/trainer/schedule/{session_id}/no-show", headers=_h(token)
    )


def _complete(client, token: str, session_id: str):
    return client.post(
        f"/v1/trainer/schedule/{session_id}/complete",
        json={"note": ""},
        headers=_h(token),
    )


def test_cancelled_session_stays_as_a_record(client, make_pt_session):
    """취소한 일정은 사라지지 않는다 — 그 시간에 무슨 일이 있었는지가 남는다."""
    token = _tok(client)
    session_id = make_pt_session(token, time="20:10")

    cancelled = _cancel(
        client, token, session_id, source="member", reason="고객 사정"
    )
    assert cancelled.status_code == 200, cancelled.text
    body = cancelled.json()
    assert body["status"] == "취소"
    assert body["cancellation_source"] == "member"
    assert body["cancellation_reason"] == "고객 사정"
    assert body["cancelled_at"] is not None
    assert body["no_show_at"] is None

    # 새로고침·재로그인에 해당하는 재조회에도 그대로 남는다.
    listed = client.get(
        "/v1/trainer/schedule", params={"date": _today()}, headers=_h(_tok(client))
    ).json()
    stored = next(item for item in listed if item["id"] == session_id)
    assert stored["status"] == "취소"
    assert stored["cancellation_source"] == "member"


def test_no_show_is_recorded_apart_from_cancellation(client, make_pt_session):
    """노쇼는 취소와 다른 결말이다 — 약속은 그대로였고 회원이 오지 않았다."""
    token = _tok(client)
    session_id = make_pt_session(token, time="20:20")

    marked = _no_show(client, token, session_id)
    assert marked.status_code == 200, marked.text
    body = marked.json()
    assert body["status"] == "노쇼"
    assert body["no_show_at"] is not None
    assert body["cancelled_at"] is None
    assert body["cancellation_source"] == ""


def test_repeating_the_same_transition_keeps_the_first_timestamp(
    client, make_pt_session
):
    """중복 클릭·재시도에 409 를 주면 화면은 이미 취소한 일정에 오류를 띄운다."""
    token = _tok(client)
    session_id = make_pt_session(token, time="20:30")

    first = _cancel(client, token, session_id).json()
    second = _cancel(client, token, session_id, source="trainer")
    assert second.status_code == 200, second.text
    # 처음 기록을 지킨다 — 두 번째 요청의 주체로 덮어쓰지 않는다.
    assert second.json()["cancelled_at"] == first["cancelled_at"]
    assert second.json()["cancellation_source"] == first["cancellation_source"]

    other = make_pt_session(token, time="20:35")
    first_no_show = _no_show(client, token, other).json()
    again = _no_show(client, token, other)
    assert again.status_code == 200, again.text
    assert again.json()["no_show_at"] == first_no_show["no_show_at"]


@pytest.mark.parametrize(
    ("first", "second"),
    [
        ("complete", "cancel"),
        ("complete", "no_show"),
        ("cancel", "complete"),
        ("cancel", "no_show"),
        ("no_show", "complete"),
        ("no_show", "cancel"),
    ],
)
def test_finished_sessions_reject_another_ending(
    client, make_pt_session, first, second
):
    """한 번 마무리된 세션은 다른 결말로 바뀌지 않는다.

    되돌릴 수 있게 두면 이미 파생된 기록(회원 운동 기록·이행률)과 어긋난다.
    """
    token = _tok(client)
    session_id = make_pt_session(token, time="20:40")
    call = {"complete": _complete, "cancel": _cancel, "no_show": _no_show}

    assert call[first](client, token, session_id).status_code == 200
    blocked = call[second](client, token, session_id)
    assert blocked.status_code == 409, blocked.text


def test_cancelled_session_cannot_be_edited(client, make_pt_session):
    """취소는 그때의 기록이라, 나중에 시간을 고치면 다른 약속을 가리키게 된다."""
    token = _tok(client)
    session_id = make_pt_session(token, time="20:45")
    _cancel(client, token, session_id)

    edited = client.put(
        f"/v1/trainer/schedule/{session_id}",
        json={"time": "21:00"},
        headers=_h(token),
    )
    assert edited.status_code == 409, edited.text


def test_cancel_and_no_show_create_no_workout_record(
    client, db_session, make_pt_session
):
    """진행되지 않은 PT 는 회원 운동 기록으로 적재되지 않는다."""
    token = _tok(client)
    cancelled_id = make_pt_session(token, time="20:50", duration_minutes=5)
    no_show_id = make_pt_session(token, time="20:55", duration_minutes=5)

    _cancel(client, token, cancelled_id)
    _no_show(client, token, no_show_id)

    for session_id in (cancelled_id, no_show_id):
        assert db_session.get(RoutineHistory, f"sched-hist-{session_id}") is None


def test_future_session_cannot_be_marked_no_show(client, make_pt_session):
    """아직 오지 않은 약속에 불참을 적을 수는 없다."""
    token = _tok(client)
    future = (clock.today() + timedelta(days=2)).isoformat()
    session_id = make_pt_session(token, date=future, time="10:00")

    rejected = _no_show(client, token, session_id)
    assert rejected.status_code == 400, rejected.text
    # 미래 일정 취소는 정상이다 — 앞으로의 약속을 거두는 것이 취소다.
    assert _cancel(client, token, session_id).status_code == 200


def test_delete_still_removes_the_row(client, db_session, make_pt_session):
    """잘못 만든 일정은 여전히 삭제로 없앤다 — 취소와 다른 동작이다."""
    token = _tok(client)
    session_id = make_pt_session(token, time="21:05")

    deleted = client.delete(
        f"/v1/trainer/schedule/{session_id}", headers=_h(token)
    )
    assert deleted.status_code == 200, deleted.text
    db_session.expire_all()
    assert db_session.get(TrainerSchedule, session_id) is None


def test_cancelled_session_drops_out_of_the_weekly_booked_count(
    client, make_pt_session
):
    """트레이너 사정의 취소가 회원의 낮은 이행률로 보이면 안 된다."""
    token = _tok(client)
    week_start = clock.today() - timedelta(days=clock.today().weekday())
    params = {"week_start": week_start.isoformat()}

    before = client.get(
        "/v1/trainer/clients/user-jisu/report", params=params, headers=_h(token)
    )
    assert before.status_code == 200, before.text
    booked_before = before.json()["sessions_booked"]

    session_id = make_pt_session(token, time="21:10")
    after_create = client.get(
        "/v1/trainer/clients/user-jisu/report", params=params, headers=_h(token)
    ).json()
    assert after_create["sessions_booked"] == booked_before + 1

    _cancel(client, token, session_id, source="trainer")
    after_cancel = client.get(
        "/v1/trainer/clients/user-jisu/report", params=params, headers=_h(token)
    ).json()
    assert after_cancel["sessions_booked"] == booked_before


def test_member_reservation_cancel_leaves_a_cancelled_schedule(
    client, db_session
):
    """회원이 취소한 예약은 트레이너 일정에서 조용히 사라지지 않는다. (#871)

    좌석 복구 등 기존 예약 규칙은 그대로다 — 달라지는 것은 트레이너 쪽에 `취소`
    기록이 남는다는 점뿐이다.
    """
    trainer_token = _tok(client)
    member_token = client.post(
        "/v1/auth/login",
        data={"username": "jisu@oncare.com", "password": "oncare123"},
    ).json()["access_token"]

    # 시드에 남은 좌석이 있는지에 기대지 않고 이 테스트가 쓸 슬롯을 직접 연다.
    created_slot = client.post(
        "/v1/trainer/reservation-slots",
        json={
            "starts_at": (clock.now() + timedelta(days=3))
            .replace(minute=0, second=0, microsecond=0)
            .isoformat(),
            "capacity": 1,
        },
        headers=_h(trainer_token),
    )
    assert created_slot.status_code == 201, created_slot.text
    open_slot = created_slot.json()

    booked = client.post(
        "/v1/reservations",
        json={"slot_id": open_slot["id"]},
        headers=_h(member_token),
    )
    assert booked.status_code == 201, booked.text
    reservation_id = booked.json()["id"]

    schedule = db_session.scalar(
        select(TrainerSchedule).where(
            TrainerSchedule.trainer_id == "trainer-demo",
            TrainerSchedule.member_id == "user-jisu",
            TrainerSchedule.status == "예정",
        ).order_by(TrainerSchedule.created_at.desc())
    )
    assert schedule is not None
    schedule_id = schedule.id

    cancelled = client.delete(
        f"/v1/reservations/{reservation_id}", headers=_h(member_token)
    )
    assert cancelled.status_code == 200, cancelled.text

    db_session.expire_all()
    stored = db_session.get(TrainerSchedule, schedule_id)
    try:
        assert stored is not None, "예약 취소가 트레이너 일정을 지웠다"
        assert stored.status == "취소"
        assert stored.cancellation_source == "member"
        assert stored.cancelled_at is not None
        # 좌석은 그대로 돌아온다(기존 규칙).
        after = client.get(
            "/v1/trainers/trainer-demo/slots", headers=_h(member_token)
        ).json()
        same_slot = next(s for s in after if s["id"] == open_slot["id"])
        assert same_slot["remaining"] == open_slot["remaining"]
    finally:
        if stored is not None:
            db_session.delete(stored)
            db_session.commit()
        client.delete(
            f"/v1/trainer/reservation-slots/{open_slot['id']}",
            headers=_h(trainer_token),
        )


def test_another_trainer_cannot_end_my_session(client, db_session, make_pt_session):
    """남의 일정 상태를 바꿀 수 없다 — 없는 일정과 똑같이 404."""
    token = _tok(client)
    session_id = make_pt_session(token, time="21:20")

    other_id = f"trainer-{uuid4().hex[:10]}"
    other_trainer = User(
        id=other_id,
        email=f"{other_id}@oncare.com",
        name="다른 트레이너",
        hashed_password="unused",
        role="trainer",
    )
    db_session.add(other_trainer)
    db_session.commit()
    try:
        other_token = create_access_token(other_id)
        assert _cancel(client, other_token, session_id).status_code == 404
        assert _no_show(client, other_token, session_id).status_code == 404
    finally:
        db_session.delete(other_trainer)
        db_session.commit()
