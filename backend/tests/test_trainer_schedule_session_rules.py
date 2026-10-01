"""트레이너 일정 세션 규칙 — 마무리 세션 메모(#2754)·예약 출처(#2756)·
되돌리기 겹침(#2757)·시작 전 완료·노쇼(#2760). DB 필요."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import select

from app.core import clock
from app.models.models import (
    ExerciseSession,
    RoutineHistory,
    TrainerReservation,
    TrainerReservationSlot,
    TrainerSchedule,
)
from app.services import trainer_service

_PROGRAM = [{"name": "스쿼트", "sets": 3, "reps": "10회", "weight": "40kg"}]


def _login(client, email: str = "trainer@oncare.com") -> str:
    response = client.post(
        "/v1/auth/login", data={"username": email, "password": "oncare123"}
    )
    assert response.status_code == 200, response.text
    return response.json()["access_token"]


def _h(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _today() -> str:
    return clock.today().isoformat()


def _future(days: int) -> str:
    return (clock.today() + timedelta(days=days)).isoformat()


def _pin_now(monkeypatch, hour: int, minute: int = 0) -> None:
    """시작 판정 시각을 오늘 KST [hour]:[minute] 로 고정한다."""
    monkeypatch.setattr(
        trainer_service,
        "_now_kst",
        lambda: clock.now().replace(
            hour=hour, minute=minute, second=0, microsecond=0
        ),
    )


@pytest.fixture()
def make_session(client):
    """일정을 만들고 테스트 끝에 지우는 팩토리(쌓이면 다른 테스트가 깨진다, #558)."""
    created: list[tuple[str, str]] = []

    def _make(token: str, **over) -> str:
        body = {
            "date": _today(),
            "time": "20:00",
            "client_name": "이지수",
            "member_id": "user-jisu",
            "type": "1:1 PT",
            "duration_minutes": 30,
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


def _finish(client, token: str, session_id: str, how: str):
    if how == "완료":
        return client.post(
            f"/v1/trainer/schedule/{session_id}/complete",
            json={},
            headers=_h(token),
        )
    if how == "취소":
        return client.post(
            f"/v1/trainer/schedule/{session_id}/cancel",
            json={"source": "member"},
            headers=_h(token),
        )
    return client.post(
        f"/v1/trainer/schedule/{session_id}/no-show", headers=_h(token)
    )


# ---- #2754 마무리 세션의 메모·미전송 프로그램 ----


@pytest.mark.parametrize("how", ["완료", "취소", "노쇼"])
def test_finished_session_accepts_note_only(client, make_session, how):
    token = _login(client)
    sid = make_session(token, time="20:00")
    assert _finish(client, token, sid, how).status_code == 200

    noted = client.put(
        f"/v1/trainer/schedule/{sid}",
        json={"note": "끝난 뒤 남긴 메모"},
        headers=_h(token),
    )

    assert noted.status_code == 200, noted.text
    assert noted.json()["note"] == "끝난 뒤 남긴 메모"
    assert noted.json()["status"] == how


@pytest.mark.parametrize("how", ["완료", "취소", "노쇼"])
@pytest.mark.parametrize(
    "change",
    [
        {"time": "06:30"},
        {"date": "2026-01-05"},
        {"member_id": "user-7d4e9a2c5f18"},
        {"client_name": "다른 이름"},
        {"type": "상담"},
        {"duration_minutes": 45},
        {"note": "메모와 함께", "time": "06:30"},
    ],
)
def test_finished_session_still_rejects_booking_changes(
    client, db_session, make_session, how, change
):
    token = _login(client)
    sid = make_session(token, time="20:30")
    assert _finish(client, token, sid, how).status_code == 200

    rejected = client.put(
        f"/v1/trainer/schedule/{sid}", json=change, headers=_h(token)
    )

    assert rejected.status_code == 409, rejected.text
    db_session.expire_all()
    stored = db_session.get(TrainerSchedule, sid)
    assert stored.status == how
    assert stored.time == "20:30"
    assert stored.member_id == "user-jisu"


def test_completed_session_accepts_unsent_program_with_note(
    client, db_session, make_session
):
    token = _login(client)
    sid = make_session(token, time="21:00")
    assert _finish(client, token, sid, "완료").status_code == 200

    saved = client.put(
        f"/v1/trainer/schedule/{sid}",
        json={"program": _PROGRAM, "note": "다음엔 무게 올리기"},
        headers=_h(token),
    )

    assert saved.status_code == 200, saved.text
    body = saved.json()
    assert body["program"][0]["name"] == "스쿼트"
    assert body["note"] == "다음엔 무게 올리기"
    assert body["program_sent"] is False


def test_completed_session_rejects_changing_a_sent_program(
    client, db_session, make_session
):
    token = _login(client)
    sid = make_session(token, time="21:30", program=_PROGRAM)
    assert _finish(client, token, sid, "완료").status_code == 200
    stored = db_session.get(TrainerSchedule, sid)
    stored.program_sent_at = datetime.now(timezone.utc)
    db_session.commit()

    changed = client.put(
        f"/v1/trainer/schedule/{sid}",
        json={"program": [{**_PROGRAM[0], "name": "런지"}]},
        headers=_h(token),
    )
    assert changed.status_code == 409, changed.text

    # 같은 프로그램을 그대로 실어 메모만 고치는 요청은 막지 않는다.
    same = client.put(
        f"/v1/trainer/schedule/{sid}",
        json={"program": _PROGRAM, "note": "보낸 뒤 메모"},
        headers=_h(token),
    )
    assert same.status_code == 200, same.text
    assert same.json()["note"] == "보낸 뒤 메모"
    assert same.json()["program"][0]["name"] == "스쿼트"


# ---- #2756 예약 출처 ----


@pytest.fixture()
def reserved_schedule(client, db_session):
    """회원이 예약 슬롯으로 잡은 일정 하나. 끝나면 예약·일정·슬롯을 지운다."""
    trainer_token = _login(client)
    member_token = _login(client, "jisu@oncare.com")
    starts_at = (datetime.now(timezone.utc) + timedelta(days=5)).replace(
        minute=0, second=0, microsecond=0
    )
    slot = client.post(
        "/v1/trainer/reservation-slots",
        headers=_h(trainer_token),
        json={"starts_at": starts_at.isoformat()},
    )
    assert slot.status_code == 201, slot.text
    slot_id = slot.json()["id"]
    booked = client.post(
        "/v1/reservations", headers=_h(member_token), json={"slot_id": slot_id}
    )
    assert booked.status_code == 201, booked.text
    yield trainer_token, booked.json()["schedule_id"]

    db_session.rollback()
    reservations = db_session.scalars(
        select(TrainerReservation).where(TrainerReservation.slot_id == slot_id)
    ).all()
    schedule_ids = [row.schedule_id for row in reservations]
    for row in reservations:
        db_session.delete(row)
    db_session.flush()
    for schedule_id in schedule_ids:
        row = db_session.get(TrainerSchedule, schedule_id)
        if row is not None:
            db_session.delete(row)
    slot_row = db_session.get(TrainerReservationSlot, slot_id)
    if slot_row is not None:
        db_session.delete(slot_row)
    db_session.commit()


def test_trainer_schedule_marks_reservation_sessions(
    client, db_session, reserved_schedule, make_session
):
    token, schedule_id = reserved_schedule
    reserved = db_session.get(TrainerSchedule, schedule_id)
    day = reserved.date
    # 예약 시각과 겹치지 않는 이른 시각(겹치면 생성이 409 다).
    free_time = "03:00" if reserved.time[:2] in {"04", "05"} else "05:00"
    ordinary = make_session(token, date=day, time=free_time)

    rows = client.get(
        "/v1/trainer/schedule", params={"date": day}, headers=_h(token)
    ).json()

    by_id = {row["id"]: row for row in rows}
    assert by_id[schedule_id]["is_reservation"] is True
    assert by_id[ordinary]["is_reservation"] is False


def test_single_session_response_carries_reservation_flag(
    client, reserved_schedule
):
    token, schedule_id = reserved_schedule

    noted = client.put(
        f"/v1/trainer/schedule/{schedule_id}",
        json={"note": "예약 PT 메모"},
        headers=_h(token),
    )

    assert noted.status_code == 200, noted.text
    assert noted.json()["is_reservation"] is True
    assert noted.json()["note"] == "예약 PT 메모"


def test_reservation_session_edit_and_delete_explain_why(
    client, reserved_schedule
):
    token, schedule_id = reserved_schedule

    edited = client.put(
        f"/v1/trainer/schedule/{schedule_id}",
        json={"time": "06:00"},
        headers=_h(token),
    )
    deleted = client.delete(
        f"/v1/trainer/schedule/{schedule_id}", headers=_h(token)
    )

    assert edited.status_code == 409, edited.text
    assert "예약" in edited.json()["detail"]
    assert deleted.status_code == 409, deleted.text
    assert "예약" in deleted.json()["detail"]


def test_client_schedule_marks_reservation_sessions(client, reserved_schedule):
    token, schedule_id = reserved_schedule

    rows = client.get(
        "/v1/trainer/schedule",
        params={"member_id": "user-jisu"},
        headers=_h(token),
    )

    assert rows.status_code == 200, rows.text
    hit = next(row for row in rows.json() if row["id"] == schedule_id)
    assert hit["is_reservation"] is True


# ---- #2757 되돌리기 겹침 ----


def test_reopen_into_an_overlap_changes_nothing(client, db_session, make_session):
    token = _login(client)
    sid = make_session(token, time="20:00")
    assert _finish(client, token, sid, "완료").status_code == 200
    target_day = _future(41)
    blocker = make_session(token, date=target_day, time="07:00")

    reopened = client.post(
        f"/v1/trainer/schedule/{sid}/reopen",
        json={"date": target_day, "time": "07:00", "duration_minutes": 30},
        headers=_h(token),
    )

    assert reopened.status_code == 409, reopened.text
    detail = reopened.json()["detail"]
    assert detail["code"] == trainer_service.SCHEDULE_OVERLAP_CODE
    assert [c["id"] for c in detail["conflicts"]] == [blocker]
    db_session.expire_all()
    stored = db_session.get(TrainerSchedule, sid)
    assert stored.status == "완료"
    assert stored.date == _today()
    assert stored.time == "20:00"
    assert db_session.get(RoutineHistory, f"sched-hist-{sid}") is not None
    assert db_session.get(ExerciseSession, f"sched-ex-{sid}") is not None


def test_reopen_without_time_checks_the_current_slot(
    client, db_session, make_session
):
    """시각을 넘기지 않아도 지금 시각·길이로 겹침을 먼저 본다(최소안)."""
    token = _login(client)
    sid = make_session(token, time="20:00")
    assert _finish(client, token, sid, "완료").status_code == 200
    target_day = _future(42)
    make_session(token, date=target_day, time="20:15")

    reopened = client.post(
        f"/v1/trainer/schedule/{sid}/reopen",
        json={"date": target_day},
        headers=_h(token),
    )

    assert reopened.status_code == 409, reopened.text
    db_session.expire_all()
    assert db_session.get(TrainerSchedule, sid).status == "완료"
    assert db_session.get(ExerciseSession, f"sched-ex-{sid}") is not None


def test_reopen_into_a_free_slot_moves_time_and_clears_records(
    client, db_session, make_session
):
    token = _login(client)
    sid = make_session(token, time="20:00")
    assert _finish(client, token, sid, "완료").status_code == 200
    target_day = _future(43)
    make_session(token, date=target_day, time="07:00")

    reopened = client.post(
        f"/v1/trainer/schedule/{sid}/reopen",
        json={"date": target_day, "time": "08:00", "duration_minutes": 50},
        headers=_h(token),
    )

    assert reopened.status_code == 200, reopened.text
    body = reopened.json()
    assert body["status"] == "예정"
    assert body["date"] == target_day
    assert body["time"] == "08:00"
    assert body["duration_minutes"] == 50
    db_session.expire_all()
    assert db_session.get(RoutineHistory, f"sched-hist-{sid}") is None
    assert db_session.get(ExerciseSession, f"sched-ex-{sid}") is None


def test_reopen_rejects_malformed_time(client, make_session):
    token = _login(client)
    sid = make_session(token, time="20:00")
    assert _finish(client, token, sid, "완료").status_code == 200

    reopened = client.post(
        f"/v1/trainer/schedule/{sid}/reopen",
        json={"date": _future(44), "time": "25:99"},
        headers=_h(token),
    )

    assert reopened.status_code == 422, reopened.text


# ---- #2760 시작 전 완료·노쇼 ----


def _kst(day: str, hour: int, minute: int = 0) -> datetime:
    parsed = datetime.fromisoformat(day)
    return parsed.replace(hour=hour, minute=minute, tzinfo=clock.SEOUL)


@pytest.mark.parametrize(
    ("day_offset", "time", "now", "started"),
    [
        (0, "20:00", (9, 0), False),
        (0, "20:00", (19, 59), False),
        (0, "20:00", (20, 0), True),
        (0, "20:00", (20, 1), True),
        (0, "08:00", (9, 0), True),
        (-1, "23:30", (0, 5), True),
        (1, "00:10", (23, 59), False),
        (0, "깨짐", (9, 0), True),
    ],
)
def test_session_has_started(day_offset, time, now, started):
    today = "2026-10-01"
    day = (datetime.fromisoformat(today) + timedelta(days=day_offset)).date()
    assert (
        trainer_service.session_has_started(
            day.isoformat(), time, now=_kst(today, *now)
        )
        is started
    )


def test_today_session_cannot_complete_before_it_starts(
    client, db_session, make_session, monkeypatch
):
    token = _login(client)
    sid = make_session(token, time="20:00", program=_PROGRAM)
    _pin_now(monkeypatch, 9)

    early = _finish(client, token, sid, "완료")

    assert early.status_code == 400, early.text
    db_session.expire_all()
    assert db_session.get(TrainerSchedule, sid).status == "예정"
    assert db_session.get(ExerciseSession, f"sched-ex-{sid}") is None
    assert db_session.get(RoutineHistory, f"sched-hist-{sid}") is None

    _pin_now(monkeypatch, 20, 5)
    started = _finish(client, token, sid, "완료")
    assert started.status_code == 200, started.text
    assert started.json()["status"] == "완료"


def test_today_session_cannot_be_no_show_before_it_starts(
    client, db_session, make_session, monkeypatch
):
    token = _login(client)
    sid = make_session(token, time="20:00")
    _pin_now(monkeypatch, 19, 59)

    early = _finish(client, token, sid, "노쇼")

    assert early.status_code == 400, early.text
    db_session.expire_all()
    assert db_session.get(TrainerSchedule, sid).status == "예정"

    _pin_now(monkeypatch, 20)
    started = _finish(client, token, sid, "노쇼")
    assert started.status_code == 200, started.text
    assert started.json()["status"] == "노쇼"


def test_cancel_is_still_allowed_before_start(client, make_session, monkeypatch):
    """취소 가능 시점은 바꾸지 않는다 — 시작 전에 약속을 거두는 자리다."""
    token = _login(client)
    sid = make_session(token, time="20:00")
    _pin_now(monkeypatch, 9)

    cancelled = _finish(client, token, sid, "취소")

    assert cancelled.status_code == 200, cancelled.text
