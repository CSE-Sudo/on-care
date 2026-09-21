"""다중 세션 프로그램 — 저장·배정·일정 등록. (#709) DB 필요.

편집기는 오래전부터 한 프로그램에 세션을 여러 개 만들 수 있었지만 저장은 하나에서
멈춰 있었다. 여기서 단언하는 것은 **세션 이름·순서와 세션별 운동 구성이 끝까지
살아남는가**, 그리고 **세션이 하나뿐인 기존 흐름이 그대로인가** 다.
"""
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
def trainer_token(client) -> str:
    return _login(client, "trainer@oncare.com")


@pytest.fixture()
def cleanup_drafts(client, db_session):
    created: list[str] = []
    yield created
    from app.models.models import TrainerProgramDraft

    for draft_id in created:
        draft = db_session.get(TrainerProgramDraft, draft_id)
        if draft is not None:
            db_session.delete(draft)
    db_session.commit()


@pytest.fixture()
def cleanup_routines(client, db_session):
    """배정 테스트가 만든 루틴만 지운다 — 시드 루틴은 건드리지 않는다."""
    created: list[str] = []
    yield created
    from app.models.models import TrainerRoutine

    for routine_id in created:
        routine = db_session.get(TrainerRoutine, routine_id)
        if routine is not None:
            db_session.delete(routine)
    db_session.commit()


def _exercise(name: str, **overrides) -> dict:
    base = {
        "id": f"exercise-{uuid4().hex[:6]}",
        "name": name,
        "type": "근력",
        "date": None,
        "duration": None,
        "sets": 4,
        "reps": 12,
        "hold_seconds": None,
        "weight": 60.0,
        "intensity": "moderate",
        "memo": "",
        "source": "trainer",
    }
    base.update(overrides)
    return base


def _two_sessions() -> list[dict]:
    return [
        {
            "id": "session-1",
            "name": "세션 A · 하체",
            "exercises": [_exercise("레그프레스"), _exercise("스쿼트")],
        },
        {
            "id": "session-2",
            "name": "세션 B · 유산소",
            "exercises": [
                _exercise(
                    "인터벌 러닝",
                    type="유산소",
                    duration=20,
                    sets=None,
                    reps=None,
                    weight=None,
                    source="ai",
                )
            ],
        },
    ]


def test_a_multi_session_draft_keeps_its_order_and_composition(
    client, trainer_token, cleanup_drafts
):
    """세션 이름·순서와 세션 안의 운동 순서가 저장·재조회를 지나도 그대로다."""
    sessions = _two_sessions()
    created = client.post(
        "/v1/trainer/programs",
        headers=_headers(trainer_token),
        json={"name": f"주 2회 분할 {uuid4().hex[:6]}", "sessions": sessions},
    )
    assert created.status_code == 201, created.text
    cleanup_drafts.append(created.json()["id"])
    assert created.json()["sessions"] == sessions

    detail = client.get(
        f"/v1/trainer/programs/{created.json()['id']}",
        headers=_headers(trainer_token),
    )
    assert detail.status_code == 200, detail.text
    assert detail.json()["sessions"] == sessions
    assert [s["name"] for s in detail.json()["sessions"]] == [
        "세션 A · 하체",
        "세션 B · 유산소",
    ]
    assert [
        e["name"] for e in detail.json()["sessions"][0]["exercises"]
    ] == ["레그프레스", "스쿼트"]

    summary = next(
        item
        for item in client.get(
            "/v1/trainer/programs", headers=_headers(trainer_token)
        ).json()
        if item["id"] == created.json()["id"]
    )
    assert summary["session_count"] == 2
    assert summary["exercise_count"] == 3


def test_editing_a_multi_session_draft_replaces_the_whole_structure(
    client, trainer_token, cleanup_drafts
):
    created = client.post(
        "/v1/trainer/programs",
        headers=_headers(trainer_token),
        json={"name": f"수정 대상 {uuid4().hex[:6]}", "sessions": _two_sessions()},
    ).json()
    cleanup_drafts.append(created["id"])

    reordered = list(reversed(_two_sessions()))
    updated = client.put(
        f"/v1/trainer/programs/{created['id']}",
        headers=_headers(trainer_token),
        json={"sessions": reordered},
    )
    assert updated.status_code == 200, updated.text
    assert [s["name"] for s in updated.json()["sessions"]] == [
        "세션 B · 유산소",
        "세션 A · 하체",
    ]

    reread = client.get(
        f"/v1/trainer/programs/{created['id']}", headers=_headers(trainer_token)
    ).json()
    assert [s["name"] for s in reread["sessions"]] == [
        "세션 B · 유산소",
        "세션 A · 하체",
    ]


def test_assigning_a_multi_session_program_creates_one_routine_per_session(
    client, trainer_token, cleanup_routines
):
    """세션당 루틴 한 건. 회원이 세션 구분과 운동 구성을 그대로 본다."""
    name = f"주 2회 분할 {uuid4().hex[:6]}"
    assigned = client.post(
        f"/v1/trainer/clients/{MEMBER_ID}/program",
        headers=_headers(trainer_token),
        json={"name": name, "sessions": _two_sessions()},
    )
    assert assigned.status_code == 201, assigned.text
    routines = assigned.json()
    for routine in routines:
        cleanup_routines.append(routine["id"])

    assert len(routines) == 2
    assert [r["session_name"] for r in routines] == ["세션 A · 하체", "세션 B · 유산소"]
    assert [r["session_order"] for r in routines] == [0, 1]
    assert {r["program_name"] for r in routines} == {name}
    # 세션별 운동 구성이 그대로 실린다 — 예전에는 이름만 reason 에 이어 붙었다.
    assert [e["name"] for e in routines[0]["exercises"]] == ["레그프레스", "스쿼트"]
    assert routines[0]["exercises"][0]["weight"] == 60.0
    # 분·유형·출처는 세션 단위로 요약된다. 근력은 시간을 적지 않으므로 세트에서
    # 환산한다 — 4세트 × 2개 × 세트당 3분 (#1276).
    assert routines[0]["minutes"] == 24
    assert routines[0]["source"] == "trainer"
    assert routines[1]["source"] == "ai"
    assert routines[1]["type"] == "유산소"

    # 회원이 읽는 목록에서도 순서와 세션 구분이 유지된다.
    member_token = _login(client, "jisu@oncare.com")
    member_view = client.get(
        "/v1/me/coach/routines", headers=_headers(member_token)
    ).json()
    mine = [r for r in member_view if r["program_name"] == name]
    assert [r["session_name"] for r in mine] == ["세션 A · 하체", "세션 B · 유산소"]
    assert [e["name"] for e in mine[0]["exercises"]] == ["레그프레스", "스쿼트"]


def test_a_single_session_program_looks_like_the_old_flat_assignment(
    client, trainer_token, cleanup_routines
):
    """세션이 하나면 예전과 같은 모양이다 — 회원 화면에 없던 라벨이 생기지 않는다."""
    name = f"단일 세션 {uuid4().hex[:6]}"
    routines = client.post(
        f"/v1/trainer/clients/{MEMBER_ID}/program",
        headers=_headers(trainer_token),
        json={
            "name": name,
            "sessions": [
                {
                    "id": "session-1",
                    "name": "세션 A",
                    "exercises": [_exercise("레그프레스")],
                }
            ],
        },
    ).json()
    for routine in routines:
        cleanup_routines.append(routine["id"])

    assert len(routines) == 1
    assert routines[0]["name"] == name
    assert routines[0]["session_name"] == ""
    assert routines[0]["program_name"] == ""


def test_retrying_the_same_program_does_not_assign_it_twice(
    client, trainer_token, cleanup_routines, db_session
):
    """같은 멱등키로 재시도하면 먼저 배정된 세션들이 그대로 돌아온다.

    루틴만이 아니라 **알림도** 한 번이어야 한다 — 멱등 조회보다 먼저 알림을
    보내면 재시도마다 회원 알림함에 같은 배정이 쌓인다.
    """
    from sqlalchemy import func, select

    from app.models.models import Notification

    def _routine_notifications() -> int:
        db_session.expire_all()
        return db_session.scalar(
            select(func.count())
            .select_from(Notification)
            .where(Notification.user_id == MEMBER_ID)
        ) or 0

    before = _routine_notifications()
    request_id = f"req-{uuid4().hex[:10]}"
    payload = {
        "name": f"재시도 {uuid4().hex[:6]}",
        "sessions": _two_sessions(),
        "client_request_id": request_id,
    }
    first = client.post(
        f"/v1/trainer/clients/{MEMBER_ID}/program",
        headers=_headers(trainer_token),
        json=payload,
    ).json()
    for routine in first:
        cleanup_routines.append(routine["id"])

    second = client.post(
        f"/v1/trainer/clients/{MEMBER_ID}/program",
        headers=_headers(trainer_token),
        json=payload,
    )
    assert second.status_code == 201, second.text
    assert [r["id"] for r in second.json()] == [r["id"] for r in first]

    # 회원의 루틴 목록에도 두 벌이 아니라 한 벌만 남는다.
    listed = client.get(
        f"/v1/trainer/clients/{MEMBER_ID}/routines", headers=_headers(trainer_token)
    ).json()
    assert len([r for r in listed if r["id"] in {x["id"] for x in first}]) == 2
    # 세션이 둘이어도 알림은 프로그램당 하나이고, 재시도가 더 만들지 않는다.
    assert _routine_notifications() - before == 1


def test_a_program_without_exercises_is_rejected(client, trainer_token):
    empty = client.post(
        f"/v1/trainer/clients/{MEMBER_ID}/program",
        headers=_headers(trainer_token),
        json={
            "name": "빈 프로그램",
            "sessions": [{"id": "session-1", "name": "세션 A", "exercises": []}],
        },
    )
    assert empty.status_code == 400

    no_sessions = client.post(
        f"/v1/trainer/clients/{MEMBER_ID}/program",
        headers=_headers(trainer_token),
        json={"name": "세션 없음", "sessions": []},
    )
    assert no_sessions.status_code == 422


def test_a_multi_session_program_can_be_registered_on_the_schedule(
    client, trainer_token, db_session
):
    """일정에 등록한 프로그램이 세션 구분을 유지한 채 다시 조회된다."""
    from app.core import clock

    date = clock.today().isoformat()
    program = [
        {
            "name": "레그프레스",
            "type": "근력",
            "sets": 4,
            "weight": 60.0,
            "session": "세션 A · 하체",
        },
        {
            "name": "인터벌 러닝",
            "type": "유산소",
            "duration": 20,
            "session": "세션 B · 유산소",
        },
    ]
    registered = client.post(
        "/v1/trainer/schedule",
        headers=_headers(trainer_token),
        json={
            "date": date,
            "time": "11:00",
            "client_name": "이지수",
            "member_id": MEMBER_ID,
            "type": "1:1 PT",
            "duration_minutes": 60,
            "program": program,
        },
    )
    assert registered.status_code == 201, registered.text
    session_id = registered.json()["id"]
    try:
        assert [
            item["session"] for item in registered.json()["program"]
        ] == ["세션 A · 하체", "세션 B · 유산소"]

        # 다시 조회해도 세션 구분이 남는다.
        listed = client.get(
            f"/v1/trainer/schedule?date={date}", headers=_headers(trainer_token)
        ).json()
        stored = next(item for item in listed if item["id"] == session_id)
        assert [item["session"] for item in stored["program"]] == [
            "세션 A · 하체",
            "세션 B · 유산소",
        ]
        assert stored["program"][0]["weight"] == 60.0
    finally:
        client.delete(
            f"/v1/trainer/schedule/{session_id}", headers=_headers(trainer_token)
        )


def test_a_schedule_row_without_session_keys_still_reads(client, trainer_token):
    """세션 키가 없던 예전 일정도 그대로 읽힌다(빈 세션 이름)."""
    from app.core import clock

    date = clock.today().isoformat()
    registered = client.post(
        "/v1/trainer/schedule",
        headers=_headers(trainer_token),
        json={
            "date": date,
            "time": "12:00",
            "client_name": "이지수",
            "member_id": MEMBER_ID,
            "type": "1:1 PT",
            "duration_minutes": 60,
            "program": [{"name": "레그프레스", "type": "근력", "sets": 4}],
        },
    )
    assert registered.status_code == 201, registered.text
    session_id = registered.json()["id"]
    try:
        assert registered.json()["program"][0]["session"] == ""
        # 저장 직후 응답과 다시 읽은 값이 갈릴 수 있으므로 조회 경로도 본다.
        listed = client.get(
            f"/v1/trainer/schedule?date={date}", headers=_headers(trainer_token)
        ).json()
        stored = next(item for item in listed if item["id"] == session_id)
        assert stored["program"][0]["session"] == ""
        assert stored["program"][0]["name"] == "레그프레스"
    finally:
        client.delete(
            f"/v1/trainer/schedule/{session_id}", headers=_headers(trainer_token)
        )


def test_another_trainer_cannot_assign_a_program(client, db_session, trainer_token):
    from app.core.security import create_access_token
    from app.models.models import User

    other_trainer_id = f"trainer-{uuid4().hex[:10]}"
    other_trainer = User(
        id=other_trainer_id,
        email=f"{other_trainer_id}@oncare.com",
        name="다른 트레이너",
        hashed_password="unused",
        role="trainer",
    )
    db_session.add(other_trainer)
    db_session.commit()
    try:
        denied = client.post(
            f"/v1/trainer/clients/{MEMBER_ID}/program",
            headers=_headers(create_access_token(other_trainer_id)),
            json={"name": "몰래 배정", "sessions": _two_sessions()},
        )
        assert denied.status_code == 404
    finally:
        db_session.delete(other_trainer)
        db_session.commit()


def _sized_sessions(session_count: int, exercise_count: int) -> list[dict]:
    """[session_count] 개 세션에 운동 [exercise_count] 개를 고르게 나눈다."""
    sessions = [
        {"id": f"session-{index}", "name": f"세션 {index}", "exercises": []}
        for index in range(session_count)
    ]
    for index in range(exercise_count):
        sessions[index % session_count]["exercises"].append(
            {"id": f"ex-{index}", "name": f"운동 {index}", "sets": 3}
        )
    return sessions


@pytest.mark.parametrize(
    ("session_count", "exercise_count", "accepted"),
    [(12, 30, True), (13, 30, False), (12, 31, False)],
)
def test_program_size_limits_are_the_same_for_draft_assign_and_schedule(
    session_count, exercise_count, accepted
):
    """초안·배정·일정 추가가 같은 크기(12세션·전체 30운동)를 받는다. (#1583)

    배정만 받고 일정 등록이 422 가 되는 크기 불일치가 없어야 한다.
    """
    from pydantic import ValidationError

    from app.core import clock
    from app.schemas.trainer_api import (
        ProgramAssignRequest,
        ProgramScheduleRequest,
        TrainerProgramDraftCreate,
        TrainerProgramDraftUpdate,
    )

    sessions = _sized_sessions(session_count, exercise_count)
    payloads = {
        TrainerProgramDraftCreate: {"name": "크기", "sessions": sessions},
        TrainerProgramDraftUpdate: {"sessions": sessions},
        ProgramAssignRequest: {"name": "크기", "sessions": sessions},
        ProgramScheduleRequest: {
            "name": "크기",
            "sessions": sessions,
            "date": clock.today().isoformat(),
            "time": "10:00",
            "duration_minutes": 60,
        },
    }
    for model, payload in payloads.items():
        if accepted:
            model.model_validate(payload)
        else:
            with pytest.raises(ValidationError):
                model.model_validate(payload)
