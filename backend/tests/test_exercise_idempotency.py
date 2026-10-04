"""운동 기록 추가의 재시도 멱등성 — DB 필요(로컬 skip, CI 실행). (#3095)

`POST /exercise/sessions` 는 저장 뒤 개인 RAG 적재까지 마친 다음 응답했다. 그
사이 앱이 수신 제한에 걸리면 저장은 됐는데 앱은 실패로 보고, 회원이 다시 누르면
같은 기록과 포인트가 한 벌 더 생겼다. `client_request_id` 로 같은 저장 시도를
알아보고 처음 결과를 돌려주며, 적재는 응답 뒤(BackgroundTasks)로 옮겼다.

TestClient 는 응답을 돌려주기 전에 백그라운드 작업까지 마치므로, 요청이 끝난
시점에 적재 횟수를 셀 수 있다.
"""
from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
from uuid import uuid4

from sqlalchemy import select

from app.api.v1 import exercise as exercise_router
from app.core import clock
from app.db import session as db_session_module
from app.models.models import ExerciseSession
from tests.exercise_helpers import EXERCISE_SESSIONS_PATH


def _login(client) -> tuple[dict, str]:
    email = f"exi-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register",
        json={"email": email, "password": "test-pw-1234", "name": "u"},
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "test-pw-1234"}
    ).json()["access_token"]
    me = client.get("/v1/users/me", headers={"Authorization": f"Bearer {token}"})
    return {"Authorization": f"Bearer {token}"}, me.json()["id"]


def _sessions() -> list[dict]:
    today = clock.today().isoformat()
    return [
        {"type": "cardio", "name": "러닝머신", "duration_seconds": 1800, "date": today},
        {
            "type": "strength", "name": "스쿼트", "minutes": 12, "sets": 3,
            "reps": 10, "weight": 20, "date": today,
        },
    ]


def _post(client, headers, sessions, key):
    body: dict = {"sessions": sessions}
    if key is not None:
        body["client_request_id"] = key
    return client.post(EXERCISE_SESSIONS_PATH, json=body, headers=headers)


def _rows(db_session, user_id: str) -> list[ExerciseSession]:
    db_session.expire_all()
    return list(
        db_session.scalars(
            select(ExerciseSession).where(ExerciseSession.user_id == user_id)
        )
    )


def _count_ingests(monkeypatch) -> list[str]:
    calls: list[str] = []
    monkeypatch.setattr(
        exercise_router.personal_ingest,
        "record_exercise",
        lambda db, user_id, **kw: calls.append(kw["source_ref"]),
    )
    return calls


def test_same_key_retry_returns_first_result_without_new_rows(
    client, db_session, monkeypatch
):
    ingests = _count_ingests(monkeypatch)
    h, user_id = _login(client)
    key = uuid4().hex

    first = _post(client, h, _sessions(), key)
    assert first.status_code == 201, first.text
    assert first.json()["points"]["awarded"] > 0

    retry = _post(client, h, _sessions(), key)
    assert retry.status_code == 201, retry.text
    assert [s["id"] for s in retry.json()["sessions"]] == [
        s["id"] for s in first.json()["sessions"]
    ]
    # 처음 받은 적립을 그대로 보여 주고, 잔액은 늘지 않는다.
    assert retry.json()["points"] == first.json()["points"]
    assert len(_rows(db_session, user_id)) == 2
    assert len(ingests) == 2


def test_same_key_with_other_sessions_is_409_and_changes_nothing(
    client, db_session, monkeypatch
):
    ingests = _count_ingests(monkeypatch)
    h, user_id = _login(client)
    key = uuid4().hex
    first = _post(client, h, _sessions(), key)
    assert first.status_code == 201, first.text
    balance = first.json()["points"]["balance"]

    edited = _sessions()
    edited[1]["sets"] = 4
    for changed in (edited, _sessions()[:1], [*_sessions(), _sessions()[0]]):
        r = _post(client, h, changed, key)
        assert r.status_code == 409, r.text

    assert len(_rows(db_session, user_id)) == 2
    assert len(ingests) == 2
    again = _post(client, h, _sessions(), key)
    assert again.json()["points"]["balance"] == balance


def test_concurrent_same_key_saves_one_set(client, db_session, monkeypatch):
    _count_ingests(monkeypatch)
    h, user_id = _login(client)
    key = uuid4().hex
    barrier = Barrier(2)

    def send():
        barrier.wait()
        return _post(client, h, _sessions(), key)

    with ThreadPoolExecutor(max_workers=2) as pool:
        responses = [
            future.result(timeout=15)
            for future in [pool.submit(send), pool.submit(send)]
        ]

    assert [r.status_code for r in responses] == [201, 201]
    ids = [tuple(s["id"] for s in r.json()["sessions"]) for r in responses]
    assert ids[0] == ids[1]
    assert len(_rows(db_session, user_id)) == 2


def test_without_key_every_request_saves(client, db_session, monkeypatch):
    _count_ingests(monkeypatch)
    h, user_id = _login(client)
    assert _post(client, h, _sessions(), None).status_code == 201
    assert _post(client, h, _sessions(), None).status_code == 201
    rows = _rows(db_session, user_id)
    assert len(rows) == 4
    assert all(row.client_request_id is None for row in rows)


def test_same_key_after_every_record_was_deleted_saves_again(
    client, db_session, monkeypatch
):
    """그 키의 기록이 모두 지워졌으면 비교할 것이 없어 새로 저장한다."""
    _count_ingests(monkeypatch)
    h, user_id = _login(client)
    key = uuid4().hex
    first = _post(client, h, _sessions(), key)
    for s in first.json()["sessions"]:
        r = client.delete(f"/v1/exercise/sessions/{s['id']}", headers=h)
        assert r.status_code in (200, 204), r.text

    again = _post(client, h, _sessions(), key)
    assert again.status_code == 201, again.text
    assert {s["id"] for s in again.json()["sessions"]}.isdisjoint(
        s["id"] for s in first.json()["sessions"]
    )
    assert len(_rows(db_session, user_id)) == 2


def test_same_key_after_one_record_was_deleted_is_409(
    client, db_session, monkeypatch
):
    _count_ingests(monkeypatch)
    h, user_id = _login(client)
    key = uuid4().hex
    first = _post(client, h, _sessions(), key)
    gone = first.json()["sessions"][0]["id"]
    assert client.delete(f"/v1/exercise/sessions/{gone}", headers=h).status_code in (
        200, 204,
    )

    assert _post(client, h, _sessions(), key).status_code == 409
    assert len(_rows(db_session, user_id)) == 1


def test_ingest_runs_after_commit_on_its_own_session_of_the_same_db(
    client, db_session, monkeypatch
):
    """적재는 요청 세션이 아닌 자기 세션으로, 기록이 저장된 그 DB 에서 돈다."""
    seen: list[tuple[object, bool]] = []

    def record(db, user_id, **kw):
        # 커밋이 끝난 뒤라 같은 DB 의 새 세션에서 그 기록이 보여야 한다.
        found = db.get(ExerciseSession, kw["source_ref"]) is not None
        seen.append((db.get_bind(), found))

    monkeypatch.setattr(exercise_router.personal_ingest, "record_exercise", record)
    h, _ = _login(client)
    r = _post(client, h, _sessions(), uuid4().hex)
    assert r.status_code == 201, r.text
    assert len(seen) == 2
    assert all(bind is db_session_module.engine for bind, _ in seen)
    assert all(found for _, found in seen)


def test_ingest_failure_keeps_the_saved_response(client, db_session, monkeypatch):
    """적재가 실패해도 저장 응답·기록·포인트는 그대로이고, 다음 항목도 적재를 시도한다."""
    attempts: list[str] = []

    def broken(db, user_id, **kw):
        attempts.append(kw["source_ref"])
        raise RuntimeError("embedding timeout")

    monkeypatch.setattr(exercise_router.personal_ingest, "record_exercise", broken)
    h, user_id = _login(client)
    key = uuid4().hex
    r = _post(client, h, _sessions(), key)
    assert r.status_code == 201, r.text
    assert r.json()["points"]["awarded"] > 0
    assert len(_rows(db_session, user_id)) == 2
    assert len(attempts) == 2

    # 재시도 재생은 적재를 다시 돌리지 않는다.
    again = _post(client, h, _sessions(), key)
    assert again.status_code == 201, again.text
    assert len(attempts) == 2
