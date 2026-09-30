"""배정 루틴 수행 기록이 회원 운동 기록과 트레이너 이력을 잇는다. (#638) DB 필요."""
from __future__ import annotations

from uuid import uuid4

import pytest


MEMBER_ID = "user-jisu"
TRAINER_ID = "trainer-demo"


def _headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _login(client, email: str) -> str:
    response = client.post(
        "/v1/auth/login",
        data={"username": email, "password": "oncare123"},
    )
    assert response.status_code == 200, response.text
    return response.json()["access_token"]


@pytest.fixture()
def assigned_routine(client, db_session):
    """독립적인 루틴을 하나 배정하고 파생 운동 기록까지 정리한다."""
    from app.models.models import ExerciseSession, TrainerRoutine

    trainer_token = _login(client, "trainer@oncare.com")
    name = f"양방향 테스트 {uuid4().hex[:6]}"
    created = client.post(
        f"/v1/trainer/clients/{MEMBER_ID}/routines",
        headers=_headers(trainer_token),
        json={
            "name": name,
            "minutes": 30,
            "type": "근력",
            "reason": "완료 기록 연결 테스트",
        },
    )
    assert created.status_code == 201, created.text
    routine = created.json()
    yield trainer_token, routine

    db_session.rollback()
    completion = db_session.query(ExerciseSession).filter_by(
        assigned_routine_id=routine["id"]
    ).one_or_none()
    if completion is not None:
        db_session.delete(completion)
    stored_routine = db_session.get(TrainerRoutine, routine["id"])
    if stored_routine is not None:
        db_session.delete(stored_routine)
    db_session.commit()


def test_completion_and_history_share_one_record(client, assigned_routine):
    trainer_token, routine = assigned_routine
    member_token = _login(client, "jisu@oncare.com")
    member_headers = _headers(member_token)
    trainer_headers = _headers(trainer_token)

    before = client.get(
        "/v1/exercise/weeks/current", headers=member_headers
    ).json()["total_minutes"]
    completed = client.post(
        f"/v1/me/coach/routines/{routine['id']}/complete",
        headers=member_headers,
        json={
            "minutes": 37,
            "intensity": "high",
            "member_note": "마지막 세트가 힘들었어요.",
        },
    )
    assert completed.status_code == 200, completed.text
    assert completed.json()["completed"] is True
    assert completed.json()["completed_minutes"] == 37
    assert completed.json()["completed_intensity"] == "high"
    completion_time = completed.json()["completed_at"]

    # 더블 탭·재시도는 새 기록이나 새 값을 만들지 않는다.
    retried = client.post(
        f"/v1/me/coach/routines/{routine['id']}/complete",
        headers=member_headers,
        json={"minutes": 10, "intensity": "light", "member_note": "재시도"},
    )
    assert retried.status_code == 200, retried.text
    assert retried.json()["completed_at"] == completion_time
    # 개인 운동 피드백은 받기만 하고 저장·노출하지 않는다(#1825).
    assert retried.json()["member_note"] == ""

    week = client.get("/v1/exercise/weeks/current", headers=member_headers).json()
    assert week["total_minutes"] == before + 37
    session = next(
        row for row in week["sessions"]
        if row["assigned_routine_id"] == routine["id"]
    )
    assert session["source"] == "assigned_routine"
    assert session["assigned_routine_name"] == routine["name"]
    assert session["member_note"] == ""

    history = client.get(
        f"/v1/trainer/clients/{MEMBER_ID}/history", headers=trainer_headers
    ).json()
    history_row = next(
        row for row in history if row["assigned_routine_id"] == routine["id"]
    )
    assert history_row["id"] == session["id"]
    assert history_row["client_feedback"] == ""
    # 개인 운동 트레이너 피드백도 없앴다(#2517) — 응답 칸은 늘 비어 있다.
    assert history_row["trainer_note"] == ""
    assert session["trainer_feedback"] == ""
    member_routine = next(
        row for row in client.get(
            "/v1/me/coach/routines", headers=member_headers
        ).json()
        if row["id"] == routine["id"]
    )
    assert member_routine["completed"] is True
    assert member_routine["trainer_feedback"] == ""

    # 파생 기록은 회원이 일반 수기 기록처럼 고치거나 지울 수 없다.
    edit = client.put(
        f"/v1/exercise/sessions/{session['id']}",
        headers=member_headers,
        json={"type": "strength", "minutes": 1, "calories": 1},
    )
    assert edit.status_code == 409
    assert client.delete(
        f"/v1/exercise/sessions/{session['id']}", headers=member_headers
    ).status_code == 409


@pytest.mark.parametrize("minutes", [0, -5, 601])
def test_completion_rejects_out_of_range_minutes(
    client, assigned_routine, minutes
):
    """앱을 거치지 않은 완료 요청도 서버의 1~600분 계약을 지킨다."""
    _, routine = assigned_routine
    member_headers = _headers(_login(client, "jisu@oncare.com"))

    response = client.post(
        f"/v1/me/coach/routines/{routine['id']}/complete",
        headers=member_headers,
        json={"minutes": minutes},
    )

    assert response.status_code == 422, response.text


def test_snapshot_survives_routine_deletion(client, assigned_routine):
    trainer_token, routine = assigned_routine
    member_headers = _headers(_login(client, "jisu@oncare.com"))
    trainer_headers = _headers(trainer_token)

    completed = client.post(
        f"/v1/me/coach/routines/{routine['id']}/complete",
        headers=member_headers,
        json={"minutes": 30, "member_note": "완료"},
    )
    assert completed.status_code == 200, completed.text

    changed = client.put(
        f"/v1/trainer/clients/{MEMBER_ID}/routines/{routine['id']}",
        headers=trainer_headers,
        json={"name": "나중에 바꾼 이름"},
    )
    assert changed.status_code == 200, changed.text
    deleted = client.delete(
        f"/v1/trainer/clients/{MEMBER_ID}/routines/{routine['id']}",
        headers=trainer_headers,
    )
    assert deleted.status_code == 200, deleted.text

    history = client.get(
        f"/v1/trainer/clients/{MEMBER_ID}/history", headers=trainer_headers
    ).json()
    row = next(item for item in history if item["assigned_routine_id"] == routine["id"])
    assert row["label"] == routine["name"]

    sessions = client.get(
        "/v1/exercise/weeks/current", headers=member_headers
    ).json()["sessions"]
    saved = next(item for item in sessions if item["assigned_routine_id"] == routine["id"])
    assert saved["assigned_routine_name"] == routine["name"]


def test_routine_feedback_endpoint_is_gone(client, assigned_routine):
    """개인 운동 트레이너 피드백 저장 경로는 없다(#2517). 개인운동에 할 말은 채팅으로 한다."""
    trainer_token, routine = assigned_routine
    member_headers = _headers(_login(client, "jisu@oncare.com"))
    trainer_headers = _headers(trainer_token)
    completed = client.post(
        f"/v1/me/coach/routines/{routine['id']}/complete",
        headers=member_headers,
        json={"minutes": 30},
    )
    assert completed.status_code == 200, completed.text
    history = client.get(
        f"/v1/trainer/clients/{MEMBER_ID}/history", headers=trainer_headers
    ).json()
    row = next(item for item in history if item["assigned_routine_id"] == routine["id"])

    response = client.put(
        f"/v1/trainer/clients/{MEMBER_ID}/history/{row['id']}/feedback",
        headers=trainer_headers,
        json={"feedback": "저장되면 안 됨"},
    )

    assert response.status_code in (404, 405), response.text


def test_only_owner_can_complete(client, assigned_routine):
    _, routine = assigned_routine
    other_member = _login(client, "sungho@oncare.com")
    denied_completion = client.post(
        f"/v1/me/coach/routines/{routine['id']}/complete",
        headers=_headers(other_member),
        json={"minutes": 30},
    )
    assert denied_completion.status_code == 404


def test_member_can_undo_a_completion(client, assigned_routine):
    """체크를 잘못 눌렀으면 되돌릴 수 있다 — 운동 기록도 함께 빠진다. (#1131)"""
    _, routine = assigned_routine
    member_headers = _headers(_login(client, "jisu@oncare.com"))

    before = client.get(
        "/v1/exercise/weeks/current", headers=member_headers
    ).json()["total_minutes"]

    completed = client.post(
        f"/v1/me/coach/routines/{routine['id']}/complete",
        headers=member_headers,
        json={"minutes": 25, "intensity": "moderate", "member_note": ""},
    )
    assert completed.status_code == 200, completed.text
    assert (
        client.get("/v1/exercise/weeks/current", headers=member_headers).json()[
            "total_minutes"
        ]
        == before + 25
    )

    undone = client.delete(
        f"/v1/me/coach/routines/{routine['id']}/complete",
        headers=member_headers,
    )
    assert undone.status_code == 200, undone.text
    assert undone.json()["completed"] is False
    assert undone.json()["completed_at"] is None

    week = client.get("/v1/exercise/weeks/current", headers=member_headers).json()
    assert week["total_minutes"] == before
    assert all(
        row["assigned_routine_id"] != routine["id"] for row in week["sessions"]
    )

    # 배정 자체는 남는다 — 되돌린 것은 `수행`이지 `할 일`이 아니다.
    listed = client.get("/v1/me/coach/routines", headers=member_headers).json()
    assert any(row["id"] == routine["id"] for row in listed)

    # 같은 요청을 두 번 보내도 결과가 같다.
    again = client.delete(
        f"/v1/me/coach/routines/{routine['id']}/complete",
        headers=member_headers,
    )
    assert again.status_code == 200, again.text
    assert again.json()["completed"] is False

    # 되돌린 뒤에는 다시 완료할 수 있다.
    redone = client.post(
        f"/v1/me/coach/routines/{routine['id']}/complete",
        headers=member_headers,
        json={"minutes": 12, "intensity": "light", "member_note": "다시"},
    )
    assert redone.status_code == 200, redone.text
    assert redone.json()["completed_minutes"] == 12


def test_the_trainers_sets_and_weight_reach_the_members_record(client, db_session):
    """트레이너가 정한 세트·중량이 회원 기록까지 그대로 간다. (#1276)

    회원 앱은 완료할 때 세트·중량을 따로 묻지 않는다 — 트레이너가 이미 정해
    보낸 값이 있는데 기록에서 비면, 그래프가 분에서 세트를 되짚어 아무도 적은
    적 없는 수를 그린다.
    """
    from app.models.models import ExerciseSession, TrainerRoutine

    trainer_token = _login(client, "trainer@oncare.com")
    created = client.post(
        f"/v1/trainer/clients/{MEMBER_ID}/routines",
        headers=_headers(trainer_token),
        json={
            "name": f"중량 전달 {uuid4().hex[:6]}",
            "minutes": 36,
            "type": "근력",
            "sets": 12,
            "weight": 62.5,
            "intensity": "high",
            "exercise_date": "2026-08-24",
        },
    )
    assert created.status_code == 201, created.text
    routine = created.json()
    # 배정 응답에도 그대로 실린다 — 트레이너 화면이 방금 보낸 값을 다시 읽는다.
    assert routine["sets"] == 12
    assert routine["weight"] == 62.5
    assert routine["intensity"] == "high"
    assert routine["exercise_date"] == "2026-08-24"

    try:
        member_headers = _headers(_login(client, "jisu@oncare.com"))
        completed = client.post(
            f"/v1/me/coach/routines/{routine['id']}/complete",
            headers=member_headers,
            # 회원은 세트·중량을 적지 않았다.
            json={"minutes": 36, "intensity": "high", "member_note": ""},
        )
        assert completed.status_code == 200, completed.text

        week = client.get(
            "/v1/exercise/weeks/current", headers=member_headers
        ).json()
        session = next(
            row for row in week["sessions"]
            if row["assigned_routine_id"] == routine["id"]
        )
        assert session["sets"] == 12
        assert session["weight"] == 62.5
        assert session["name"] == routine["name"]
    finally:
        db_session.rollback()
        stale = db_session.query(ExerciseSession).filter_by(
            assigned_routine_id=routine["id"]
        ).one_or_none()
        if stale is not None:
            db_session.delete(stale)
        stored = db_session.get(TrainerRoutine, routine["id"])
        if stored is not None:
            db_session.delete(stored)
        db_session.commit()


def test_completion_keeps_the_seconds_the_member_sends(client, db_session):
    """초로 완료한 시간은 회원 기록에 초까지 남는다. (#2221)

    트레이너가 `45초` 로 정한 개인운동을 회원이 완료하면 `1분` 이 아니라 적힌
    대로 남아야 한다. 분도 함께 받는다 — 옛 앱과 분을 더하는 집계가 읽는다.
    초를 적지 않은 배정은 분 × 60 으로 읽힌다.
    """
    from app.models.models import ExerciseSession, TrainerRoutine

    trainer_token = _login(client, "trainer@oncare.com")
    created = client.post(
        f"/v1/trainer/clients/{MEMBER_ID}/routines",
        headers=_headers(trainer_token),
        json={"name": f"초 완료 {uuid4().hex[:6]}", "minutes": 1, "type": "유산소"},
    )
    assert created.status_code == 201, created.text
    routine = created.json()
    assert routine["duration_seconds"] == 60

    try:
        member_headers = _headers(_login(client, "jisu@oncare.com"))
        completed = client.post(
            f"/v1/me/coach/routines/{routine['id']}/complete",
            headers=member_headers,
            json={"minutes": 1, "duration_seconds": 45, "intensity": "moderate"},
        )
        assert completed.status_code == 200, completed.text

        week = client.get(
            "/v1/exercise/weeks/current", headers=member_headers
        ).json()
        session = next(
            row for row in week["sessions"]
            if row["assigned_routine_id"] == routine["id"]
        )
        assert (session["duration_seconds"], session["minutes"]) == (45, 1)

        mine = client.get("/v1/me/coach/routines", headers=member_headers).json()
        listed = next(row for row in mine if row["id"] == routine["id"])
        assert listed["completed_duration_seconds"] == 45
    finally:
        db_session.rollback()
        stale = db_session.query(ExerciseSession).filter_by(
            assigned_routine_id=routine["id"]
        ).one_or_none()
        if stale is not None:
            db_session.delete(stale)
        stored = db_session.get(TrainerRoutine, routine["id"])
        if stored is not None:
            db_session.delete(stored)
        db_session.commit()
