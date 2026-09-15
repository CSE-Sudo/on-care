"""배정 루틴 수행 기록과 트레이너 피드백의 양방향 연결. (#638) DB 필요."""
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


def test_completion_feedback_and_history_share_one_record(client, assigned_routine):
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

    feedback = client.put(
        f"/v1/trainer/clients/{MEMBER_ID}/history/{history_row['id']}/feedback",
        headers=trainer_headers,
        json={"feedback": "자세가 안정적이었어요. 다음엔 40분으로 늘려요."},
    )
    assert feedback.status_code == 200, feedback.text

    member_routine = next(
        row for row in client.get(
            "/v1/me/coach/routines", headers=member_headers
        ).json()
        if row["id"] == routine["id"]
    )
    assert member_routine["completed"] is True
    assert member_routine["trainer_feedback"].startswith("자세가 안정적")
    refreshed_session = next(
        row for row in client.get(
            "/v1/exercise/weeks/current", headers=member_headers
        ).json()["sessions"]
        if row["id"] == session["id"]
    )
    assert refreshed_session["trainer_feedback"] == member_routine["trainer_feedback"]

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


def test_snapshot_and_feedback_survive_routine_deletion(client, assigned_routine):
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

    updated = client.put(
        f"/v1/trainer/clients/{MEMBER_ID}/history/{row['id']}/feedback",
        headers=trainer_headers,
        json={"feedback": "삭제 후에도 남는 피드백"},
    )
    assert updated.status_code == 200, updated.text
    sessions = client.get(
        "/v1/exercise/weeks/current", headers=member_headers
    ).json()["sessions"]
    saved = next(item for item in sessions if item["assigned_routine_id"] == routine["id"])
    assert saved["assigned_routine_name"] == routine["name"]
    assert saved["trainer_feedback"] == "삭제 후에도 남는 피드백"


def test_only_owner_can_complete_or_write_feedback(
    client, db_session, assigned_routine
):
    from app.core.security import create_access_token
    from app.models.models import TrainerClient, User

    trainer_token, routine = assigned_routine
    other_member = _login(client, "sungho@oncare.com")
    denied_completion = client.post(
        f"/v1/me/coach/routines/{routine['id']}/complete",
        headers=_headers(other_member),
        json={"minutes": 30},
    )
    assert denied_completion.status_code == 404

    member_headers = _headers(_login(client, "jisu@oncare.com"))
    completed = client.post(
        f"/v1/me/coach/routines/{routine['id']}/complete",
        headers=member_headers,
        json={"minutes": 30},
    ).json()
    history = client.get(
        f"/v1/trainer/clients/{MEMBER_ID}/history",
        headers=_headers(trainer_token),
    ).json()
    history_id = next(
        item["id"] for item in history
        if item["assigned_routine_id"] == routine["id"]
    )
    assert completed["completed"] is True

    other_trainer_id = f"trainer-{uuid4().hex[:10]}"
    other_trainer = User(
        id=other_trainer_id,
        email=f"{other_trainer_id}@oncare.com",
        name="다른 트레이너",
        hashed_password="unused",
        role="trainer",
    )
    db_session.add(other_trainer)
    db_session.flush()  # TrainerClient.trainer_id FK 부모를 먼저 반영한다.
    link = TrainerClient(
        id=f"tc-{uuid4().hex[:12]}",
        trainer_id=other_trainer_id,
        member_id=MEMBER_ID,
        active=False,
    )
    db_session.add(link)
    db_session.commit()
    try:
        denied_feedback = client.put(
            f"/v1/trainer/clients/{MEMBER_ID}/history/{history_id}/feedback",
            headers=_headers(create_access_token(other_trainer_id)),
            json={"feedback": "보이면 안 됨"},
        )
        assert denied_feedback.status_code == 404
    finally:
        db_session.delete(link)
        db_session.delete(other_trainer)
        db_session.commit()


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
