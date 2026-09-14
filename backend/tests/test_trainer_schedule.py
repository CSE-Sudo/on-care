"""트레이너 스케줄 CRUD + 예약→수업→기록 완료 루프(#252). DB 필요."""
from __future__ import annotations

import time
from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta
from threading import Barrier

import pytest
from pydantic import ValidationError
from sqlalchemy import select

from app.core import clock
from app.models.models import TrainerClient, TrainerRoutine, TrainerSchedule
from app.schemas.trainer_api import ProgramScheduleRequest


def _tok(client) -> str:
    return client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    ).json()["access_token"]


def _h(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _today() -> str:
    """서버가 쓰는 '오늘'과 같은 기준(KST). 러너 로컬 타임존이 UTC 여도 어긋나지 않는다."""
    return clock.today().isoformat()


def test_schedule_seeded_timeline(client):
    token = _tok(client)
    r = client.get("/v1/trainer/schedule", headers=_h(token))
    assert r.status_code == 200, r.text
    slots = r.json()
    assert len(slots) >= 6
    # 시간순 정렬
    times = [s["time"] for s in slots]
    assert times == sorted(times)
    # 공백 슬롯 + program 포함 슬롯 존재
    assert any(s["status"] == "공백" for s in slots)
    assert any(len(s["program"]) > 0 for s in slots)


_PROGRAM_SCHEDULE_URL = "/v1/trainer/clients/user-jisu/program-schedule"


def _program_command_body(
    day: str, exercise: str, request_id: str | None = None
) -> dict:
    return {
        "name": f"일정 추가 테스트 {exercise}",
        "sessions": [
            {
                "id": "session-1",
                "name": "세션 A",
                "exercises": [{"id": "ex-1", "name": exercise, "sets": 1}],
            }
        ],
        "date": day,
        "time": "16:00",
        "duration_minutes": 75,
        "client_name": "이지수",
        "client_request_id": request_id,
    }


def test_program_schedule_payload_requires_positive_duration():
    body = _program_command_body(_today(), "걷기")
    payload = ProgramScheduleRequest.model_validate(body)
    assert payload.time == "16:00"
    assert payload.duration_minutes == 75

    with pytest.raises(ValidationError):
        ProgramScheduleRequest.model_validate({**body, "duration_minutes": 0})


def test_program_schedule_rejects_a_past_date():
    """자정을 넘겨 전날 날짜가 와도 일정을 만들지 않는다. 오늘은 받는다. (#1582)"""
    yesterday = (clock.today() - timedelta(days=1)).isoformat()
    with pytest.raises(ValidationError):
        ProgramScheduleRequest.model_validate(_program_command_body(yesterday, "걷기"))
    ProgramScheduleRequest.model_validate(_program_command_body(_today(), "걷기"))


def _delete_program_test_sessions(db_session, day: str) -> None:
    rows = db_session.scalars(
        select(TrainerSchedule).where(
            TrainerSchedule.trainer_id == "trainer-demo",
            TrainerSchedule.member_id == "user-jisu",
            TrainerSchedule.date == day,
        )
    ).all()
    for row in rows:
        db_session.delete(row)
    for routine in db_session.scalars(
        select(TrainerRoutine).where(
            TrainerRoutine.member_id == "user-jisu",
            TrainerRoutine.name.like("일정 추가 테스트%"),
        )
    ).all():
        db_session.delete(routine)
    db_session.commit()


def _program_test_routines(db_session) -> list[TrainerRoutine]:
    db_session.expire_all()
    return list(
        db_session.scalars(
            select(TrainerRoutine).where(
                TrainerRoutine.member_id == "user-jisu",
                TrainerRoutine.name.like("일정 추가 테스트%"),
            )
        ).all()
    )


def test_program_schedule_retry_with_same_key_creates_nothing_twice(
    client, db_session
):
    """응답을 잃고 같은 키로 다시 보내도 배정·일정이 한 벌만 남는다. (#1580)"""
    token = _tok(client)
    day = (clock.today() + timedelta(days=60)).isoformat()
    _delete_program_test_sessions(db_session, day)
    body = _program_command_body(day, "걷기", request_id="req-1580-retry")

    try:
        first = client.post(_PROGRAM_SCHEDULE_URL, json=body, headers=_h(token))
        retry = client.post(_PROGRAM_SCHEDULE_URL, json=body, headers=_h(token))

        assert first.status_code == 201, first.text
        assert retry.status_code == 201, retry.text
        assert first.json()["attached_to_existing"] is False
        assert retry.json() == first.json()
        assert len(_program_test_routines(db_session)) == 1
        rows = db_session.scalars(
            select(TrainerSchedule).where(
                TrainerSchedule.member_id == "user-jisu",
                TrainerSchedule.date == day,
            )
        ).all()
        assert [(row.time, row.duration_minutes) for row in rows] == [("16:00", 75)]
    finally:
        _delete_program_test_sessions(db_session, day)


def test_program_schedule_rolls_back_assignment_when_schedule_fails(
    client, db_session, monkeypatch
):
    """일정 쓰기가 실패하면 배정도 남지 않는다 — 반쪽 성공이 없다. (#1580)"""
    from app.services import trainer_service

    token = _tok(client)
    day = (clock.today() + timedelta(days=63)).isoformat()
    _delete_program_test_sessions(db_session, day)

    def fail(*_args, **_kwargs):
        raise RuntimeError("schedule write failed")

    monkeypatch.setattr(trainer_service, "_add_session", fail)
    try:
        with pytest.raises(RuntimeError):
            client.post(
                _PROGRAM_SCHEDULE_URL,
                json=_program_command_body(day, "걷기", request_id="req-1580-fail"),
                headers=_h(token),
            )
        assert _program_test_routines(db_session) == []
    finally:
        _delete_program_test_sessions(db_session, day)


def test_program_schedule_attaches_to_the_created_session(client, db_session):
    token = _tok(client)
    day = (clock.today() + timedelta(days=61)).isoformat()
    url = _PROGRAM_SCHEDULE_URL
    _delete_program_test_sessions(db_session, day)

    try:
        first = client.post(
            url,
            json=_program_command_body(day, "걷기"),
            headers=_h(token),
        )
        second = client.post(
            url,
            json={
                **_program_command_body(day, "플랭크"),
                # 16:00–17:15 세션과 부분 겹침 — 거기에 붙는다(#1581).
                "time": "16:30",
                "duration_minutes": 30,
            },
            headers=_h(token),
        )

        assert first.status_code == 201, first.text
        assert second.status_code == 201, second.text
        assert first.json()["attached_to_existing"] is False
        assert second.json()["attached_to_existing"] is True
        assert first.json()["session"]["id"] == second.json()["session"]["id"]
        assert second.json()["session"]["program"][0]["name"] == "플랭크"
        assert first.json()["session"]["time"] == "16:00"
        assert first.json()["session"]["duration_minutes"] == 75
        assert second.json()["session"]["time"] == "16:00"
        assert second.json()["session"]["duration_minutes"] == 75

        db_session.expire_all()
        rows = db_session.scalars(
            select(TrainerSchedule).where(
                TrainerSchedule.trainer_id == "trainer-demo",
                TrainerSchedule.member_id == "user-jisu",
                TrainerSchedule.date == day,
                TrainerSchedule.status == "예정",
            )
        ).all()
        assert len(rows) == 1
        assert rows[0].time == "16:00"
        assert rows[0].duration_minutes == 75
    finally:
        _delete_program_test_sessions(db_session, day)


def test_program_schedule_attach_target_follows_the_selected_time(
    client, db_session
):
    """기존 PT 연결은 고른 시간대와 겹치는 예정 세션만 대상으로 한다. (#1581)"""
    token = _tok(client)
    day = (clock.today() + timedelta(days=64)).isoformat()
    _delete_program_test_sessions(db_session, day)

    def book(time_: str) -> str:
        booked = client.post(
            "/v1/trainer/schedule",
            json={
                "date": day,
                "time": time_,
                "client_name": "이지수",
                "member_id": "user-jisu",
                "type": "1:1 PT",
                "duration_minutes": 60,
            },
            headers=_h(token),
        )
        assert booked.status_code == 201, booked.text
        return booked.json()["id"]

    def add(time_: str, minutes: int = 60, session_id: str | None = None):
        return client.post(
            _PROGRAM_SCHEDULE_URL,
            json={
                **_program_command_body(day, "걷기"),
                "time": time_,
                "duration_minutes": minutes,
                "session_id": session_id,
            },
            headers=_h(token),
        )

    try:
        morning = book("09:00")
        evening = book("18:00")

        exact = add("09:00")
        assert exact.status_code == 201, exact.text
        assert exact.json()["attached_to_existing"] is True
        assert exact.json()["session"]["id"] == morning

        partial = add("17:30")  # 17:30–18:30 이 18:00 세션과 겹친다.
        assert partial.status_code == 201, partial.text
        assert partial.json()["session"]["id"] == evening

        none = add("13:00")  # 겹치는 세션이 없으면 가장 이른 회차가 아니라 새 일정.
        assert none.status_code == 201, none.text
        assert none.json()["attached_to_existing"] is False
        assert none.json()["session"]["time"] == "13:00"

        # 08:30–18:30 은 09:00·13:00·18:00 세션과 모두 겹친다.
        ambiguous = add("08:30", minutes=600)
        assert ambiguous.status_code == 409, ambiguous.text
        assert len(ambiguous.json()["detail"]["candidates"]) == 3

        chosen = add("08:30", minutes=600, session_id=evening)
        assert chosen.status_code == 201, chosen.text
        assert chosen.json()["session"]["id"] == evening
    finally:
        _delete_program_test_sessions(db_session, day)


def test_concurrent_program_schedule_commands_create_one_session(
    client, db_session
):
    token = _tok(client)
    day = (clock.today() + timedelta(days=62)).isoformat()
    url = _PROGRAM_SCHEDULE_URL
    _delete_program_test_sessions(db_session, day)

    # Hold the same row used as the service's mutex until both HTTP requests
    # have started. Once released, they must serialize and converge on one row.
    link = db_session.scalar(
        select(TrainerClient)
        .where(
            TrainerClient.trainer_id == "trainer-demo",
            TrainerClient.member_id == "user-jisu",
        )
        .with_for_update()
    )
    assert link is not None
    barrier = Barrier(3)

    def register(exercise: str):
        barrier.wait()
        return client.post(
            url,
            json=_program_command_body(day, exercise),
            headers=_h(token),
        )

    try:
        with ThreadPoolExecutor(max_workers=2) as pool:
            futures = [pool.submit(register, name) for name in ("걷기", "플랭크")]
            barrier.wait()
            time.sleep(0.2)
            db_session.commit()
            responses = [future.result(timeout=10) for future in futures]

        assert [response.status_code for response in responses] == [201, 201]
        assert sorted(
            response.json()["attached_to_existing"] for response in responses
        ) == [False, True]

        db_session.expire_all()
        rows = db_session.scalars(
            select(TrainerSchedule).where(
                TrainerSchedule.trainer_id == "trainer-demo",
                TrainerSchedule.member_id == "user-jisu",
                TrainerSchedule.date == day,
                TrainerSchedule.status == "예정",
            )
        ).all()
        assert len(rows) == 1
    finally:
        db_session.rollback()
        _delete_program_test_sessions(db_session, day)


def test_schedule_crud(client):
    token = _tok(client)
    # 생성(예정)
    c = client.post(
        "/v1/trainer/schedule",
        json={
            "date": _today(), "time": "16:00", "client_name": "이지수",
            "member_id": "user-jisu", "type": "1:1 PT", "duration_minutes": 45,
            "program": [{"name": "스쿼트", "sets": 3, "reps": "10회", "weight": "40kg"}],
        },
        headers=_h(token),
    )
    assert c.status_code == 201, c.text
    sid = c.json()["id"]
    assert c.json()["status"] == "예정"

    # 수정
    u = client.put(
        f"/v1/trainer/schedule/{sid}",
        json={"time": "16:30", "duration_minutes": 50},
        headers=_h(token),
    )
    assert u.status_code == 200, u.text
    assert u.json()["time"] == "16:30"
    assert u.json()["duration_minutes"] == 50

    # 삭제
    d = client.delete(f"/v1/trainer/schedule/{sid}", headers=_h(token))
    assert d.status_code == 200
    # 삭제 후 다시 삭제 → 404
    assert client.delete(f"/v1/trainer/schedule/{sid}", headers=_h(token)).status_code == 404


def test_schedule_update_member_id_empty_unassigns(client, db_session):
    """빈 member_id 로 수정하면 실제로 member_id IS NULL 로 저장되고(FK 위반 500 아님),
    이후 완료해도 배정이 없으므로 회원 운동기록(sched-hist-{sid})이 생성되지 않는다."""
    from app.models import models

    token = _tok(client)
    c = client.post(
        "/v1/trainer/schedule",
        json={
            "date": _today(), "time": "16:45", "client_name": "이지수",
            "member_id": "user-jisu", "type": "1:1 PT", "duration_minutes": 40,
        },
        headers=_h(token),
    )
    sid = c.json()["id"]

    # 빈 member_id 로 수정 → 200, 그리고 DB 에 실제로 NULL 로 저장(빈 값 무시하고 유지하면 실패)
    u = client.put(
        f"/v1/trainer/schedule/{sid}", json={"member_id": ""}, headers=_h(token)
    )
    assert u.status_code == 200, u.text
    db_session.expire_all()
    assert db_session.get(models.TrainerSchedule, sid).member_id is None

    # 완료해도 배정된 회원이 없으므로 운동기록이 만들어지지 않는다
    done = client.post(f"/v1/trainer/schedule/{sid}/complete", json={}, headers=_h(token))
    assert done.status_code == 200
    db_session.expire_all()
    assert db_session.get(models.RoutineHistory, f"sched-hist-{sid}") is None

    client.delete(f"/v1/trainer/schedule/{sid}", headers=_h(token))


@pytest.mark.parametrize(
    "field",
    ["time", "client_name", "type", "duration_minutes", "note", "program"],
)
def test_schedule_update_rejects_null_for_non_nullable_fields(
    client, field, make_pt_session
):
    """명시적 null이 NOT NULL 컬럼까지 도달해 500을 만들지 않고 API 경계에서 422가 된다."""
    token = _tok(client)
    # 파라미터마다 세션이 하나씩 생긴다 — 지우지 않으면 실행 한 번에 여섯 건이
    # 그대로 남아 이 파일에서 가장 크게 누적된다(#558).
    sid = make_pt_session(token, time="16:50", duration_minutes=40)

    r = client.put(
        f"/v1/trainer/schedule/{sid}",
        json={field: None},
        headers=_h(token),
    )
    assert r.status_code == 422, r.text


def test_delete_completed_session_removes_derived_history(client, db_session):
    """완료 세션을 삭제하면 완료 시 파생된 운동기록(sched-hist-{id})도 함께 제거되어
    회원 이력에 고아 레코드가 남지 않는다."""
    from app.models import models

    token = _tok(client)
    c = client.post(
        "/v1/trainer/schedule",
        json={
            "date": _today(), "time": "07:15", "client_name": "이지수",
            "member_id": "user-jisu", "type": "1:1 PT",
            "program": [{"name": "스쿼트", "sets": 3, "reps": "10회", "weight": "40kg"}],
        },
        headers=_h(token),
    )
    sid = c.json()["id"]
    client.post(f"/v1/trainer/schedule/{sid}/complete", json={"note": "완료"}, headers=_h(token))
    db_session.expire_all()
    assert db_session.get(models.RoutineHistory, f"sched-hist-{sid}") is not None

    d = client.delete(f"/v1/trainer/schedule/{sid}", headers=_h(token))
    assert d.status_code == 200
    db_session.expire_all()
    assert db_session.get(models.RoutineHistory, f"sched-hist-{sid}") is None  # 고아 없음


def test_schedule_create_with_unlinked_member_404(client):
    token = _tok(client)
    r = client.post(
        "/v1/trainer/schedule",
        json={"date": _today(), "time": "11:00", "member_id": "user-nobody"},
        headers=_h(token),
    )
    assert r.status_code == 404


def test_complete_session_logs_history_and_is_idempotent(
    client, db_session, make_pt_session
):
    """완료 처리가 운동기록을 남기고, 재호출해도 중복되지 않는다.

    목록 **개수**로 세지 않는다 — 이력 조회는 최신 60건 상한이라, 회원 이력이
    상한에 닿으면 기록이 늘어도 개수가 그대로여서 단언이 엉뚱하게 깨진다(#558).
    파생 기록의 id 는 `sched-hist-{sid}` 로 결정론적이니 그 행을 직접 본다.
    """
    from app.models import models

    token = _tok(client)
    # 오늘 예정 세션 생성(user-jisu 매칭). 픽스처가 테스트 끝에 지워 이력이 쌓이지 않는다.
    sid = make_pt_session(
        token,
        time="18:30",
        duration_minutes=40,
        program=[
            {"name": "레그프레스", "type": "근력", "sets": 3, "weight": 80.0},
            {"name": "카프레이즈", "type": "근력", "sets": 1},
        ],
    )
    hist_id = f"sched-hist-{sid}"
    assert db_session.get(models.RoutineHistory, hist_id) is None

    # 완료 처리 → 완료 상태 + 이 세션의 운동기록 생성
    done = client.post(
        f"/v1/trainer/schedule/{sid}/complete",
        json={"note": "잘 마쳤어요"}, headers=_h(token),
    )
    assert done.status_code == 200, done.text
    assert done.json()["status"] == "완료"

    db_session.expire_all()
    logged = db_session.get(models.RoutineHistory, hist_id)
    assert logged is not None, "완료 처리가 회원 운동기록을 남기지 않았다"
    assert logged.trainer_note == "잘 마쳤어요"

    after = client.get("/v1/trainer/clients/user-jisu/history", headers=_h(token)).json()
    assert after[0]["label"] == "PT 세션 · 트레이너 지도"
    assert after[0]["trainer_note"] == "잘 마쳤어요"
    # 근력은 세트와 중량으로 읽는다 — 무게가 있어야 다음 무게를 정할 수 있다(#1276).
    assert "레그프레스 3세트 80kg" in after[0]["exercises"]

    # 재호출(멱등) → 상태 유지, 기록도 그 한 건 그대로(노트가 덮이지 않는다)
    again = client.post(
        f"/v1/trainer/schedule/{sid}/complete", json={"note": "x"}, headers=_h(token)
    )
    assert again.status_code == 200
    db_session.expire_all()
    assert db_session.get(models.RoutineHistory, hist_id).trainer_note == "잘 마쳤어요"


def test_complete_future_session_rejected(client, make_pt_session):
    from datetime import timedelta

    token = _tok(client)
    future = (clock.today() + timedelta(days=3)).isoformat()
    sid = make_pt_session(token, date=future, time="10:00")
    r = client.post(f"/v1/trainer/schedule/{sid}/complete", json={}, headers=_h(token))
    assert r.status_code == 400  # 미래 일정 완료 불가


def test_schedule_ownership_and_role(client):
    token = _tok(client)
    # 없는 일정 완료/수정 → 404
    assert client.post(
        "/v1/trainer/schedule/nope/complete", json={}, headers=_h(token)
    ).status_code == 404
    assert client.put(
        "/v1/trainer/schedule/nope", json={"time": "09:00"}, headers=_h(token)
    ).status_code == 404

    # 회원 계정 → 403
    from uuid import uuid4
    email = f"m-{uuid4().hex[:8]}@oncare.com"
    client.post("/v1/auth/register", json={"email": email, "password": "pw!", "name": "u"})
    mtok = client.post(
        "/v1/auth/login", data={"username": email, "password": "pw!"}
    ).json()["access_token"]
    assert client.get("/v1/trainer/schedule", headers=_h(mtok)).status_code == 403


def test_booked_dates(client):
    token = _tok(client)
    r = client.get("/v1/trainer/schedule/booked-dates", headers=_h(token))
    assert r.status_code == 200, r.text
    dates = r.json()
    assert _today() in dates  # 오늘 시드에 예약(공백 아님)이 있음


def test_completed_session_cannot_be_edited(client, make_pt_session):
    """완료된 세션 수정은 409 — 스케줄과 운동기록이 어긋나지 않게 한다(리뷰 재-#2)."""
    token = _tok(client)
    # 픽스처로 만들어 테스트 끝에 지운다 — 완료가 남기는 이력이 쌓이면 60건 상한에
    # 닿아 다른 테스트가 깨진다(#558).
    sid = make_pt_session(
        token,
        time="08:30",
        program=[{"name": "스쿼트", "sets": 3, "reps": "10회", "weight": "40kg"}],
    )
    client.post(f"/v1/trainer/schedule/{sid}/complete", json={"note": "완료"}, headers=_h(token))

    # 완료 후 다른 회원으로 재배정 시도 → 409(데이터 분리 방지)
    r = client.put(
        f"/v1/trainer/schedule/{sid}", json={"member_id": "user-sungho"}, headers=_h(token)
    )
    assert r.status_code == 409
    # note 등 다른 필드 수정도 409
    assert client.put(
        f"/v1/trainer/schedule/{sid}", json={"note": "바꿈"}, headers=_h(token)
    ).status_code == 409
    # 기록은 여전히 원래 회원(user-jisu)에 남아 있고 sungho 로 옮겨가지 않았다
    jisu_hist = client.get("/v1/trainer/clients/user-jisu/history", headers=_h(token)).json()
    assert any(h["label"] == "PT 세션 · 트레이너 지도" for h in jisu_hist)


def test_schedule_invalid_date_time_422(client):
    """달력상 불가능한 날짜/시간은 create·update 모두 422(DB 저장 방지, 리뷰 재-#4)."""
    token = _tok(client)
    base = {"date": _today(), "time": "10:00", "type": "1:1 PT"}
    url = "/v1/trainer/schedule"
    # 잘못된 날짜
    assert client.post(url, json={**base, "date": "2026-99-99"}, headers=_h(token)).status_code == 422
    assert client.post(url, json={**base, "date": "2026-02-31"}, headers=_h(token)).status_code == 422
    # 잘못된/빈 시간
    assert client.post(url, json={**base, "time": "25:99"}, headers=_h(token)).status_code == 422
    assert client.post(url, json={**base, "time": ""}, headers=_h(token)).status_code == 422
    # update 도 잘못된 시간 422. 여기만 실제로 한 건이 만들어지므로 끝에 지운다(#558).
    sid = client.post(url, json=base, headers=_h(token)).json()["id"]
    try:
        assert client.put(
            f"{url}/{sid}", json={"time": "99:99"}, headers=_h(token)
        ).status_code == 422
    finally:
        client.delete(f"{url}/{sid}", headers=_h(token))


# ---- 기간·고객 조회 (#378) ----

def _sched_token(client) -> str:
    return client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    ).json()["access_token"]


def _sched_auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def test_schedule_range_returns_every_day_in_one_request(client):
    """주 캘린더가 7일치를 한 번에 읽는다 — 하루짜리 요청 7번이 아니라."""
    token = _sched_token(client)
    made = []
    for day in ("2026-09-07", "2026-09-09", "2026-09-13"):
        r = client.post(
            "/v1/trainer/schedule",
            json={"date": day, "time": "10:00", "client_name": "범위테스트",
                  "type": "1:1 PT", "duration_minutes": 60},
            headers=_sched_auth(token),
        )
        assert r.status_code == 201, r.text
        made.append(r.json()["id"])
    try:
        r = client.get(
            "/v1/trainer/schedule",
            params={"from": "2026-09-07", "to": "2026-09-13"},
            headers=_sched_auth(token),
        )
        assert r.status_code == 200, r.text
        dates = [s["date"] for s in r.json() if s["client_name"] == "범위테스트"]
        # 경계 포함(from/to 양끝), 날짜순.
        assert dates == ["2026-09-07", "2026-09-09", "2026-09-13"]
    finally:
        for sid in made:
            client.delete(f"/v1/trainer/schedule/{sid}", headers=_sched_auth(token))


def test_schedule_range_excludes_days_outside_the_window(client):
    token = _sched_token(client)
    r = client.post(
        "/v1/trainer/schedule",
        json={"date": "2026-09-20", "time": "10:00", "client_name": "창밖",
              "type": "1:1 PT", "duration_minutes": 60},
        headers=_sched_auth(token),
    )
    sid = r.json()["id"]
    try:
        r = client.get(
            "/v1/trainer/schedule",
            params={"from": "2026-09-07", "to": "2026-09-13"},
            headers=_sched_auth(token),
        )
        assert all(s["client_name"] != "창밖" for s in r.json())
    finally:
        client.delete(f"/v1/trainer/schedule/{sid}", headers=_sched_auth(token))


def test_schedule_range_needs_both_ends(client):
    """한쪽만 오면 조용히 하루로 떨어뜨리지 않는다 — 클라이언트는 구간을
    받았다고 믿는다."""
    token = _sched_token(client)
    r = client.get(
        "/v1/trainer/schedule", params={"from": "2026-09-07"},
        headers=_sched_auth(token),
    )
    assert r.status_code == 422
    r = client.get(
        "/v1/trainer/schedule", params={"to": "2026-09-13"},
        headers=_sched_auth(token),
    )
    assert r.status_code == 422


def test_schedule_range_rejects_reversed_and_malformed_bounds(client):
    token = _sched_token(client)
    r = client.get(
        "/v1/trainer/schedule",
        params={"from": "2026-09-13", "to": "2026-09-07"},
        headers=_sched_auth(token),
    )
    assert r.status_code == 422
    r = client.get(
        "/v1/trainer/schedule",
        params={"from": "2026-09", "to": "2026-09-13"},
        headers=_sched_auth(token),
    )
    assert r.status_code == 422


def test_schedule_member_filter_returns_only_that_clients_sessions(client):
    token = _sched_token(client)
    roster = client.get("/v1/trainer/clients", headers=_sched_auth(token)).json()
    member_id = roster[0]["id"]

    r = client.get(
        "/v1/trainer/schedule",
        params={"from": "2026-01-01", "to": "2027-01-01", "member_id": member_id},
        headers=_sched_auth(token),
    )
    assert r.status_code == 200, r.text
    # 공백 슬롯은 배정된 회원이 없으므로 자연히 빠진다.
    assert all(s["status"] != "공백" for s in r.json())


def test_schedule_member_only_returns_every_session_no_date_bound(client):
    """`member_id` 만 주면 날짜 제한 없이 그 고객의 전체 세션.

    구간으로 흉내내면 구간 밖의 오래된 세션이 조용히 빠지고, 고객 상세의
    루틴 이력은 그걸 '기록 없음' 으로 읽는다.
    """
    token = _sched_token(client)
    roster = client.get("/v1/trainer/clients", headers=_sched_auth(token)).json()
    member_id = roster[0]["id"]

    # 아주 오래된 세션 하나 — 어떤 '최근 N일' 구간에도 걸리지 않는다.
    created = client.post(
        "/v1/trainer/schedule",
        json={
            "date": "2020-01-02", "time": "07:00", "client_name": roster[0]["name"],
            "member_id": member_id, "type": "1:1 PT", "duration_minutes": 30,
        },
        headers=_sched_auth(token),
    )
    assert created.status_code == 201, created.text
    old_id = created.json()["id"]

    # 지우지 않으면 이 고객의 세션이 실행마다 쌓인다. 회원별 조회는 최신 100건
    # 상한이라, 상한에 닿는 순간 가장 오래된 이 2020 세션이 먼저 밀려나 여기서
    # 깨진다 — 정확히 이 테스트가 증명하려는 것이 사라지는 셈이다(#558).
    try:
        r = client.get(
            "/v1/trainer/schedule",
            params={"member_id": member_id},
            headers=_sched_auth(token),
        )
        assert r.status_code == 200, r.text
        ids = [s["id"] for s in r.json()]
        assert old_id in ids
        # 여전히 그 고객 것만.
        assert all(s["status"] != "공백" for s in r.json())
    finally:
        client.delete(f"/v1/trainer/schedule/{old_id}", headers=_sched_auth(token))


def test_schedule_member_filter_rejects_someone_elses_client(client):
    token = _sched_token(client)
    r = client.get(
        "/v1/trainer/schedule",
        params={"member_id": "user-nobody"},
        headers=_sched_auth(token),
    )
    assert r.status_code == 404


def test_schedule_rejects_a_malformed_date(client):
    token = _sched_token(client)
    r = client.get(
        "/v1/trainer/schedule", params={"date": "2026-09"},
        headers=_sched_auth(token),
    )
    assert r.status_code == 422


# ---- PT 완료 → 회원 쪽 운동 기록 파생 (#499) ----

def _member_h(client) -> dict:
    """회원(user-jisu) 헤더. 시드가 demo_login_password 로 만든 계정."""
    token = client.post(
        "/v1/auth/login",
        data={"username": "jisu@oncare.com", "password": "oncare123"},
    ).json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture()
def make_pt_session(client):
    """PT 세션을 만들고 테스트 끝에 지우는 팩토리.

    정리하지 않으면 회원 이력이 테스트마다 쌓여, 최신 60건만 내려주는
    `build_client_history` 의 상한에 닿는 순간 **다른 테스트**가 깨진다
    (#484 와 같은 누적 데이터 취약성). 세션을 지우면 파생 기록도 함께
    사라지므로 회원의 주간 집계도 원래대로 돌아온다.
    """
    created: list[tuple[str, str]] = []

    def _make(token: str, **over) -> str:
        body = {
            "date": _today(), "time": "20:00", "client_name": "이지수",
            "member_id": "user-jisu", "type": "1:1 PT", "duration_minutes": 60,
        }
        body.update(over)
        r = client.post("/v1/trainer/schedule", json=body, headers=_h(token))
        assert r.status_code == 201, r.text
        sid = r.json()["id"]
        created.append((sid, token))
        return sid

    yield _make

    for sid, token in created:
        client.delete(f"/v1/trainer/schedule/{sid}", headers=_h(token))


def test_complete_session_adds_member_exercise_log(client, make_pt_session):
    """PT 완료가 트레이너 이력뿐 아니라 **회원 쪽** 운동 기록으로도 잡힌다.

    RoutineHistory 는 트레이너 화면 전용이라, 이것만으로는 회원의 운동 탭·홈
    대시보드 주간 집계에 아무것도 늘지 않았다.
    """
    token = _tok(client)
    mh = _member_h(client)

    before = client.get("/v1/exercise/weeks/current", headers=mh).json()
    sid = make_pt_session(token, time="20:05", duration_minutes=45)

    done = client.post(f"/v1/trainer/schedule/{sid}/complete", json={}, headers=_h(token))
    assert done.status_code == 200, done.text

    after = client.get("/v1/exercise/weeks/current", headers=mh).json()
    assert after["total_minutes"] == before["total_minutes"] + 45
    # 칼로리는 회원 앱과 같은 표(strength=6kcal/분, moderate=1.0)로 추정한다.
    assert after["total_calories"] == before["total_calories"] + 270

    derived = [s for s in after["sessions"] if s["id"] == f"sched-ex-{sid}"]
    assert len(derived) == 1
    assert derived[0]["source"] == "trainer_pt"
    assert derived[0]["type"] == "strength"


def test_complete_session_exercise_log_uses_program_item_duration_and_type(
    client, make_pt_session
):
    """프로그램 항목에 분·유형을 적으면 자동 기록이 슬롯 전체 길이·고정
    유형('근력') 대신 그 값을 쓴다(#1233).

    근력 항목의 분은 세트에서 환산한다(#1276) — 유형마다 재는 단위가 달라서,
    근력에 적힌 시간은 아예 저장되지 않는다. 여기서도 `duration` 을 함께 보내
    그 값이 집계에 끼지 않는 것까지 본다.
    """
    token = _tok(client)
    mh = _member_h(client)

    before = client.get("/v1/exercise/weeks/current", headers=mh).json()
    sid = make_pt_session(
        token,
        time="20:35",
        duration_minutes=60,
        program=[
            {
                "name": "달리기", "sets": 1, "reps": "", "weight": "",
                "type": "유산소", "duration": "10",
            },
            {
                "name": "사이클", "sets": 1, "reps": "", "weight": "",
                "type": "유산소", "duration": "15",
            },
            {
                "name": "스쿼트", "sets": 3, "reps": "12회", "weight": "40kg",
                "type": "근력", "duration": "10",
            },
        ],
    )

    # 근력에 적어 보낸 시간은 저장되지 않는다 — 세트로 재는 유형이다.
    day = client.get(f"/v1/trainer/schedule?date={_today()}", headers=_h(token))
    assert day.status_code == 200, day.text
    stored = next(s for s in day.json() if s["id"] == sid)["program"]
    assert [(i["duration"], i["sets"]) for i in stored] == [
        (10, None), (15, None), (None, 3),
    ]

    done = client.post(f"/v1/trainer/schedule/{sid}/complete", json={}, headers=_h(token))
    assert done.status_code == 200, done.text

    after = client.get("/v1/exercise/weeks/current", headers=mh).json()
    # 슬롯은 60분이지만 항목 분의 합을 쓴다: 유산소 10+15, 근력은 3세트를
    # 환산한 9분(세트당 3분) — 항목에 적혀 온 10분이 아니다.
    assert after["total_minutes"] == before["total_minutes"] + 34
    # 유산소 2건 > 근력 1건 — 가장 많은 유형을 쓴다(cardio=9kcal/분 x moderate 1.0).
    assert after["total_calories"] == before["total_calories"] + 306

    derived = [s for s in after["sessions"] if s["id"] == f"sched-ex-{sid}"]
    assert len(derived) == 1
    assert derived[0]["type"] == "cardio"
    assert derived[0]["minutes"] == 34


def test_complete_session_exercise_log_is_idempotent(client, make_pt_session):
    """재호출해도 회원 기록이 중복되지 않는다(결정론적 id)."""
    token = _tok(client)
    mh = _member_h(client)
    sid = make_pt_session(token, time="20:10", duration_minutes=30)

    client.post(f"/v1/trainer/schedule/{sid}/complete", json={}, headers=_h(token))
    once = client.get("/v1/exercise/weeks/current", headers=mh).json()["total_minutes"]
    client.post(f"/v1/trainer/schedule/{sid}/complete", json={}, headers=_h(token))
    twice = client.get("/v1/exercise/weeks/current", headers=mh).json()["total_minutes"]

    assert once == twice


def test_completed_consultation_makes_no_exercise_log(client, db_session, make_pt_session):
    """상담은 운동이 아니다 — 회원 주간 운동량으로 잡히면 집계가 거짓이 된다."""
    from app.models import models

    token = _tok(client)
    sid = make_pt_session(token, time="20:15", type="상담", duration_minutes=30)
    client.post(f"/v1/trainer/schedule/{sid}/complete", json={}, headers=_h(token))

    db_session.expire_all()
    assert db_session.get(models.ExerciseSession, f"sched-ex-{sid}") is None
    # 트레이너 쪽 이력은 기존대로 남는다 — 이 변경은 회원 기록만 다룬다.
    assert db_session.get(models.RoutineHistory, f"sched-hist-{sid}") is not None


def test_past_session_lands_in_its_own_week(client, db_session, make_pt_session):
    """지난 주 세션을 오늘 완료해도 그 주의 집계로 들어간다.

    완료 시점의 월요일을 쓰면 지난 주 PT 가 이번 주 운동량으로 잡힌다.
    """
    from datetime import date, timedelta

    from app.models import models

    token = _tok(client)
    past = clock.today() - timedelta(days=9)
    sid = make_pt_session(token, date=past.isoformat(), time="20:20")
    client.post(f"/v1/trainer/schedule/{sid}/complete", json={}, headers=_h(token))

    db_session.expire_all()
    row = db_session.get(models.ExerciseSession, f"sched-ex-{sid}")
    assert row is not None
    assert row.week_start == (past - timedelta(days=past.weekday())).isoformat()
    assert row.day_label == ["월", "화", "수", "목", "금", "토", "일"][past.weekday()]


def test_delete_completed_session_removes_member_exercise_log(client, db_session, make_pt_session):
    """세션을 지우면 회원 쪽 파생 기록도 사라진다 — 회원 집계에만 유령 PT 가 남지 않도록."""
    from app.models import models

    token = _tok(client)
    sid = make_pt_session(token, time="20:25")
    client.post(f"/v1/trainer/schedule/{sid}/complete", json={}, headers=_h(token))
    db_session.expire_all()
    assert db_session.get(models.ExerciseSession, f"sched-ex-{sid}") is not None

    assert client.delete(f"/v1/trainer/schedule/{sid}", headers=_h(token)).status_code == 200
    db_session.expire_all()
    assert db_session.get(models.ExerciseSession, f"sched-ex-{sid}") is None


def test_reopen_completed_session_clears_derived_logs_and_moves_to_upcoming(
    client, db_session, make_pt_session
):
    """완료 세션을 미래 날짜의 예정으로 되돌리면 파생 기록도 함께 지워진다.

    지우지 않으면 되돌린 뒤에도 "이미 했던 운동"으로 남아 회원 운동기록·
    트레이너 이력이 실제로 하지 않은 PT 를 계속 잡는다.
    """
    from datetime import timedelta

    from app.models import models

    token = _tok(client)
    sid = make_pt_session(token, time="20:40")
    done = client.post(f"/v1/trainer/schedule/{sid}/complete", json={}, headers=_h(token))
    assert done.status_code == 200, done.text
    db_session.expire_all()
    assert db_session.get(models.ExerciseSession, f"sched-ex-{sid}") is not None
    assert db_session.get(models.RoutineHistory, f"sched-hist-{sid}") is not None

    future = (clock.today() + timedelta(days=7)).isoformat()
    reopened = client.post(
        f"/v1/trainer/schedule/{sid}/reopen",
        json={"date": future},
        headers=_h(token),
    )
    assert reopened.status_code == 200, reopened.text
    assert reopened.json()["status"] == "예정"
    assert reopened.json()["date"] == future

    db_session.expire_all()
    assert db_session.get(models.ExerciseSession, f"sched-ex-{sid}") is None
    assert db_session.get(models.RoutineHistory, f"sched-hist-{sid}") is None


def test_reopen_rejects_past_dates_and_non_completed_sessions(client, make_pt_session):
    token = _tok(client)
    sid = make_pt_session(token, time="20:45")

    # 아직 완료 전인 세션은 되돌릴 것이 없다.
    still_upcoming = client.post(
        f"/v1/trainer/schedule/{sid}/reopen",
        json={"date": _today()},
        headers=_h(token),
    )
    assert still_upcoming.status_code == 409, still_upcoming.text

    client.post(f"/v1/trainer/schedule/{sid}/complete", json={}, headers=_h(token))

    # 오늘·과거로는 "되돌리기"가 아니라 그냥 완료 취소가 된다 — 막는다.
    not_future = client.post(
        f"/v1/trainer/schedule/{sid}/reopen",
        json={"date": _today()},
        headers=_h(token),
    )
    assert not_future.status_code == 409, not_future.text


def test_member_cannot_edit_or_delete_derived_log(client, make_pt_session):
    """파생 기록의 근거는 트레이너에게 있다 — 회원이 고치면 리포트가 딛고 선 값이 흔들린다."""
    token = _tok(client)
    mh = _member_h(client)
    sid = make_pt_session(token, time="20:30")
    client.post(f"/v1/trainer/schedule/{sid}/complete", json={}, headers=_h(token))

    ex_id = f"sched-ex-{sid}"
    put = client.put(
        f"/v1/exercise/sessions/{ex_id}",
        json={"type": "cardio", "minutes": 5, "calories": 10, "intensity": "light"},
        headers=mh,
    )
    assert put.status_code == 409, put.text
    assert client.delete(f"/v1/exercise/sessions/{ex_id}", headers=mh).status_code == 409


def test_member_own_log_still_editable(client):
    """회원이 직접 남긴 기록은 그대로 수정·삭제된다(가드가 과잉 적용되지 않는다)."""
    mh = _member_h(client)
    sid = client.post(
        "/v1/exercise/sessions",
        json={"type": "cardio", "minutes": 20, "calories": 180, "day_label": "월"},
        headers=mh,
    ).json()["id"]

    put = client.put(
        f"/v1/exercise/sessions/{sid}",
        json={"type": "cardio", "minutes": 25, "calories": 200, "intensity": "moderate"},
        headers=mh,
    )
    assert put.status_code == 200, put.text
    assert put.json()["source"] == "member"
    assert client.delete(f"/v1/exercise/sessions/{sid}", headers=mh).status_code == 200


def test_send_completed_program_assigns_routine_once(client, db_session, make_pt_session):
    """완료한 세션의 프로그램이 회원 루틴으로 가고, 두 번 눌러도 한 번만 간다. (#822)

    수업 뒤 "오늘 이걸 했습니다" 를 넘기는 자리다. 새 배정 경로가 아니라 코칭
    탭과 같은 배정을 타므로, 회원 화면에는 출처마다 다른 루틴이 생기지 않는다.
    """
    token = _tok(client)
    sid = make_pt_session(
        token,
        time="19:30",
        duration_minutes=50,
        program=[
            {"name": "레그프레스", "sets": 3, "reps": "12회", "weight": "80kg"},
            {"name": "코어 강화", "sets": 3, "reps": "10회", "weight": ""},
        ],
    )

    # 시드에 이미 배정된 루틴이 있으므로 개수의 **변화**로 센다.
    before = client.get("/v1/trainer/clients/user-jisu/routines", headers=_h(token))
    assert before.status_code == 200
    before_count = len(before.json())

    # 완료 전에는 보낼 수 없다 — 아직 한 것이 아니라 할 것이다.
    early = client.post(
        f"/v1/trainer/schedule/{sid}/program/send", json={}, headers=_h(token)
    )
    assert early.status_code == 400

    done = client.post(
        f"/v1/trainer/schedule/{sid}/complete", json={"note": ""}, headers=_h(token)
    )
    assert done.status_code == 200
    assert done.json()["program_sent"] is False

    sent = client.post(
        f"/v1/trainer/schedule/{sid}/program/send",
        json={"client_request_id": "send-1"},
        headers=_h(token),
    )
    assert sent.status_code == 200, sent.text
    assert sent.json()["program_sent"] is True

    routines = client.get(
        "/v1/trainer/clients/user-jisu/routines", headers=_h(token)
    ).json()
    assert len(routines) == before_count + 1, "전송이 회원 루틴을 만들지 않았다"

    # 두 번째 호출은 멱등 — 회원 루틴이 겹치지 않는다.
    again = client.post(
        f"/v1/trainer/schedule/{sid}/program/send",
        json={"client_request_id": "send-1"},
        headers=_h(token),
    )
    assert again.status_code == 200
    assert again.json()["program_sent"] is True
    after = client.get(
        "/v1/trainer/clients/user-jisu/routines", headers=_h(token)
    ).json()
    assert len(after) == len(routines), "재전송이 회원 루틴을 늘렸다"

    # 조회 경로도 전송 사실을 그대로 말한다.
    listed = client.get(
        "/v1/trainer/schedule", params={"date": _today()}, headers=_h(token)
    ).json()
    row = next(s for s in listed if s["id"] == sid)
    assert row["program_sent"] is True


def test_send_completed_program_forwards_item_type_and_duration(
    client, make_pt_session
):
    """전송된 프로그램의 운동 항목도 트레이너가 적은 type/분을 그대로 옮긴다(#1233).

    이전에는 항목의 type/duration 이 배정 계약으로 넘어가지 않아, 서버가 늘
    '근력'·분 0 으로 요약했다.
    """
    token = _tok(client)
    sid = make_pt_session(
        token,
        time="19:40",
        duration_minutes=50,
        program=[
            {
                "name": "달리기", "sets": 1, "reps": "", "weight": "",
                "type": "유산소", "duration": "20",
            },
        ],
    )
    client.post(f"/v1/trainer/schedule/{sid}/complete", json={"note": ""}, headers=_h(token))
    sent = client.post(
        f"/v1/trainer/schedule/{sid}/program/send",
        json={"client_request_id": "send-type-1"},
        headers=_h(token),
    )
    assert sent.status_code == 200, sent.text

    routines = client.get(
        "/v1/trainer/clients/user-jisu/routines", headers=_h(token)
    ).json()
    routine = next(r for r in routines if r["reason"] == "달리기")
    assert routine["type"] == "유산소"
    assert routine["minutes"] == 20


def test_send_program_requires_a_linked_member_and_a_program(client, make_pt_session):
    """보낼 상대나 보낼 내용이 없으면 400 — 빈 루틴이 회원에게 가지 않는다. (#822)"""
    token = _tok(client)

    # 프로그램이 없는 세션
    empty = make_pt_session(token, time="20:30", duration_minutes=30, program=[])
    client.post(
        f"/v1/trainer/schedule/{empty}/complete", json={"note": ""}, headers=_h(token)
    )
    r = client.post(
        f"/v1/trainer/schedule/{empty}/program/send", json={}, headers=_h(token)
    )
    assert r.status_code == 400

    # 없는 일정
    missing = client.post(
        "/v1/trainer/schedule/no-such-session/program/send", json={}, headers=_h(token)
    )
    assert missing.status_code == 404
