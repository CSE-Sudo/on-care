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


def _personal_line(history: list[dict], session_id: str | None, *, name: str = ""):
    """하루치 `개인운동` 카드에서 그 완료 줄을 찾는다(#2510). (카드, 줄)."""
    for row in history:
        if row.get("kind") != "personal_routine":
            continue
        for item in row["exercise_items"]:
            if not item["done"]:
                continue
            if (session_id and item["session_id"] == session_id) or (
                not session_id and name and item["name"] == name
            ):
                return row, item
    raise AssertionError("개인운동 카드에서 그 완료 줄을 찾지 못했다")


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
    # 개인 운동 회원 피드백은 없앴다(#1825, #2624) — 옛 앱이 보내도 무시하고
    # 응답 칸은 빈 문자열로 남는다.
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
    # 개인운동 완료는 하루 한 장 `개인운동` 카드의 한 줄이다(#2510). 줄이 그
    # 운동 기록을 가리킨다 — 트레이너 메모가 이 id 로 단다.
    history_row, line = _personal_line(history, session["id"])
    assert history_row["kind"] == "personal_routine"
    assert line["name"] == routine["name"]
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
        json={"minutes": 30},
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
    _, line = _personal_line(history, None, name=routine["name"])
    assert line["name"] == routine["name"]

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
    row, _ = _personal_line(history, None, name=routine["name"])

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
        json={"minutes": 25, "intensity": "moderate"},
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
        json={"minutes": 12, "intensity": "light"},
    )
    assert redone.status_code == 200, redone.text
    assert redone.json()["completed_minutes"] == 12


def test_the_trainers_sets_and_weight_reach_the_members_record(client, db_session):
    """트레이너가 정한 세트·중량이 회원 기록까지 그대로 간다. (#1276)

    회원이 완료하며 세트·중량을 비워 보내도(옛 앱) 트레이너가 정해 보낸 값이
    남는다 — 기록에서 비면, 그래프가 분에서 세트를 되짚어 아무도 적은 적 없는
    수를 그린다.
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
            json={"minutes": 36, "intensity": "high"},
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


@pytest.fixture()
def strength_routine(client, db_session):
    """분 없이 세트·횟수·중량만 정한 근력 배정 — 파생 기록까지 정리한다. (#3364)"""
    from app.models.models import ExerciseSession, TrainerRoutine

    created_ids: list[str] = []

    def _assign(**fields) -> dict:
        created = client.post(
            f"/v1/trainer/clients/{MEMBER_ID}/routines",
            headers=_headers(_login(client, "trainer@oncare.com")),
            json={
                "name": f"근력 완료 {uuid4().hex[:6]}",
                "type": "근력",
                **fields,
            },
        )
        assert created.status_code == 201, created.text
        created_ids.append(created.json()["id"])
        return created.json()

    yield _assign

    db_session.rollback()
    for routine_id in created_ids:
        for row in db_session.query(ExerciseSession).filter_by(
            assigned_routine_id=routine_id
        ):
            db_session.delete(row)
        stored = db_session.get(TrainerRoutine, routine_id)
        if stored is not None:
            db_session.delete(stored)
    db_session.commit()


def _points_balance(client, headers) -> int:
    health = client.get("/v1/users/me/health", headers=headers)
    assert health.status_code == 200, health.text
    return health.json()["activity_points"]


def _completion_session(client, headers, routine_id: str) -> dict:
    week = client.get("/v1/exercise/weeks/current", headers=headers).json()
    return next(
        row for row in week["sessions"] if row["assigned_routine_id"] == routine_id
    )


def test_strength_completion_without_minutes_reads_time_from_sets(
    client, strength_routine
):
    """분 없이 완료한 근력 배정은 세트 수에서 시간을 얻는다 — 1분이 아니다. (#3364)"""
    routine = strength_routine(sets=4, reps=12, weight=40)
    member_headers = _headers(_login(client, "jisu@oncare.com"))

    completed = client.post(
        f"/v1/me/coach/routines/{routine['id']}/complete",
        headers=member_headers,
        json={"intensity": "moderate"},
    )

    assert completed.status_code == 200, completed.text
    body = completed.json()
    assert body["completed_minutes"] == 12
    assert (
        body["completed_sets"], body["completed_reps"], body["completed_weight"]
    ) == (4, 12, 40)
    session = _completion_session(client, member_headers, routine["id"])
    assert session["minutes"] == 12
    assert (session["sets"], session["reps"], session["weight"]) == (4, 12, 40)


def test_strength_completion_keeps_what_the_member_actually_did(
    client, strength_routine
):
    """회원이 고쳐 적은 세트·횟수·중량이 배정 값 대신 남는다. (#3364)"""
    routine = strength_routine(sets=3, reps=10, weight=20)
    member_headers = _headers(_login(client, "jisu@oncare.com"))

    completed = client.post(
        f"/v1/me/coach/routines/{routine['id']}/complete",
        headers=member_headers,
        json={"sets": 5, "reps": 8, "weight": 27.5, "intensity": "high"},
    )

    assert completed.status_code == 200, completed.text
    body = completed.json()
    # 배정 값은 그대로이고, 완료 값이 따로 온다.
    assert (body["sets"], body["reps"], body["weight"]) == (3, 10, 20)
    assert (
        body["completed_sets"], body["completed_reps"], body["completed_weight"]
    ) == (5, 8, 27.5)
    assert body["completed_minutes"] == 15
    session = _completion_session(client, member_headers, routine["id"])
    assert (session["sets"], session["reps"], session["weight"]) == (5, 8, 27.5)
    assert session["minutes"] == 15

    mine = client.get("/v1/me/coach/routines", headers=member_headers).json()
    listed = next(row for row in mine if row["id"] == routine["id"])
    assert (listed["completed_sets"], listed["completed_weight"]) == (5, 27.5)


def test_strength_completion_passes_hold_seconds_through(client, strength_routine):
    """회원이 적은 버틴 시간이 기록까지 간다 — 라우터에서 버려지지 않는다. (#3364)"""
    routine = strength_routine(sets=3, hold_seconds=60)
    member_headers = _headers(_login(client, "jisu@oncare.com"))

    completed = client.post(
        f"/v1/me/coach/routines/{routine['id']}/complete",
        headers=member_headers,
        json={"sets": 3, "hold_seconds": 45, "intensity": "moderate"},
    )

    assert completed.status_code == 200, completed.text
    assert completed.json()["completed_hold_seconds"] == 45
    assert completed.json()["completed_reps"] is None
    session = _completion_session(client, member_headers, routine["id"])
    assert (session["hold_seconds"], session["reps"]) == (45, None)


def test_strength_completion_still_honours_minutes_the_client_sends(
    client, strength_routine
):
    """분을 적어 보낸 요청은 그 분이 남는다 — 옛 앱의 요청이 달라지지 않는다. (#3364)"""
    routine = strength_routine(sets=4, reps=12)
    member_headers = _headers(_login(client, "jisu@oncare.com"))

    completed = client.post(
        f"/v1/me/coach/routines/{routine['id']}/complete",
        headers=member_headers,
        json={"minutes": 20, "intensity": "moderate"},
    )

    assert completed.status_code == 200, completed.text
    assert completed.json()["completed_minutes"] == 20


def test_cardio_completion_without_minutes_falls_back_to_the_assignment(
    client, db_session
):
    """분을 비운 유산소 완료는 초에서, 초도 없으면 배정된 시간에서 채운다. (#3364)"""
    from app.models.models import ExerciseSession, TrainerRoutine

    trainer_headers = _headers(_login(client, "trainer@oncare.com"))
    member_headers = _headers(_login(client, "jisu@oncare.com"))
    created_ids: list[str] = []
    try:
        for payload, expected in (
            ({"intensity": "light"}, 25),
            ({"duration_seconds": 600, "intensity": "light"}, 10),
        ):
            created = client.post(
                f"/v1/trainer/clients/{MEMBER_ID}/routines",
                headers=trainer_headers,
                json={
                    "name": f"유산소 완료 {uuid4().hex[:6]}",
                    "minutes": 25,
                    "type": "유산소",
                },
            )
            assert created.status_code == 201, created.text
            routine = created.json()
            created_ids.append(routine["id"])

            completed = client.post(
                f"/v1/me/coach/routines/{routine['id']}/complete",
                headers=member_headers,
                json=payload,
            )

            assert completed.status_code == 200, completed.text
            body = completed.json()
            assert body["completed_minutes"] == expected
            # 세트·중량은 근력 기록에만 있다.
            assert body["completed_sets"] is None
            assert body["completed_weight"] is None
    finally:
        db_session.rollback()
        for routine_id in created_ids:
            for row in db_session.query(ExerciseSession).filter_by(
                assigned_routine_id=routine_id
            ):
                db_session.delete(row)
            stored = db_session.get(TrainerRoutine, routine_id)
            if stored is not None:
                db_session.delete(stored)
        db_session.commit()


def test_undoing_a_strength_completion_removes_the_record_and_points(
    client, strength_routine
):
    """완료를 되돌리면 세트 기록과 그 완료로 받은 포인트가 함께 사라진다. (#3364)"""
    routine = strength_routine(sets=4, reps=12, weight=40)
    member_headers = _headers(_login(client, "jisu@oncare.com"))
    balance_before = _points_balance(client, member_headers)

    completed = client.post(
        f"/v1/me/coach/routines/{routine['id']}/complete",
        headers=member_headers,
        json={"sets": 4, "reps": 12, "weight": 40, "intensity": "moderate"},
    )
    assert completed.status_code == 200, completed.text
    earned = completed.json()["points"]["awarded"]

    undone = client.delete(
        f"/v1/me/coach/routines/{routine['id']}/complete", headers=member_headers
    )

    assert undone.status_code == 200, undone.text
    body = undone.json()
    assert body["completed"] is False
    assert body["completed_sets"] is None
    assert body["completed_minutes"] is None
    week = client.get("/v1/exercise/weeks/current", headers=member_headers).json()
    assert not any(
        row["assigned_routine_id"] == routine["id"] for row in week["sessions"]
    )
    # 받은 만큼(하루 한도를 넘었으면 0) 그대로 회수된다.
    assert completed.json()["points"]["balance"] == balance_before + earned
    assert _points_balance(client, member_headers) == balance_before
