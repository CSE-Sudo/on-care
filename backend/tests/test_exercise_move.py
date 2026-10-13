"""운동 기록 묶음 날짜 이동 — POST /exercise/sessions/move. (#3365)

회원이 하루의 기록을 다른 날로 옮긴다. 기록마다 수정 요청을 보내면 중간에 하나가
실패했을 때 하루치가 두 날로 갈린 채 남는다 — 그래서 한 트랜잭션이고, 전부
옮겨지거나 하나도 옮겨지지 않는다. 기록마다의 규칙(소유·파생 기록·앞날)은 단건
수정(`PUT /exercise/sessions/{id}`)과 같다.

"오늘" 을 목요일(2026-09-17, KST)로 고정한다. DB 필요(로컬 skip, CI 실행).
"""
from __future__ import annotations

from datetime import datetime
from uuid import uuid4

import pytest
from sqlalchemy import select

from app.core import clock
from app.models.models import ExerciseSession
from app.schemas.exercise_limits import MAX_EXERCISE_SESSIONS_PER_MOVE
from tests.exercise_helpers import EXERCISE_SESSIONS_PATH, post_exercise

MOVE_PATH = "/v1/exercise/sessions/move"

THURSDAY = datetime(2026, 9, 17, 10, 0, tzinfo=clock.SEOUL)
TODAY = "2026-09-17"
#: 지난주 화요일 — 다른 주로 옮기는 것까지 본다.
LAST_TUESDAY = "2026-09-08"


@pytest.fixture(autouse=True)
def thursday(monkeypatch):
    monkeypatch.setattr(clock, "now", lambda: THURSDAY)


def _new_member(client) -> tuple[str, dict[str, str]]:
    email = f"exm-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register",
        json={"email": email, "password": "test-pw-1234", "name": "u"},
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "test-pw-1234"}
    ).json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    return client.get("/v1/users/me", headers=headers).json()["id"], headers


def _add(client, headers, name: str, day: str = TODAY) -> dict:
    r = post_exercise(
        client,
        json={"type": "cardio", "name": name, "minutes": 30, "date": day},
        headers=headers,
    )
    assert r.status_code == 201, r.text
    return r.json()


def _dates(client, headers, week_start: str) -> dict[str, str]:
    """그 주의 기록 이름 → 날짜."""
    week = client.get(
        "/v1/exercise/weeks/current",
        params={"week_start": week_start},
        headers=headers,
    )
    assert week.status_code == 200, week.text
    return {s["name"]: s["date"] for s in week.json()["sessions"]}


def _derived(db_session, member_id: str, source: str) -> str:
    """PT·배정 루틴에서 생긴 기록 한 건을 오늘에 넣는다."""
    row_id = f"ex-derived-{uuid4().hex[:8]}"
    db_session.add(
        ExerciseSession(
            id=row_id,
            user_id=member_id,
            week_start="2026-09-14",
            day_label="목",
            type="strength",
            name="벤치프레스",
            minutes=12,
            calories=72,
            source=source,
        )
    )
    db_session.commit()
    return row_id


def test_moves_every_record_to_the_chosen_day(client):
    _member, headers = _new_member(client)
    run = _add(client, headers, "러닝머신")
    bike = _add(client, headers, "사이클")

    r = client.post(
        MOVE_PATH,
        json={"session_ids": [run["id"], bike["id"]], "date": LAST_TUESDAY},
        headers=headers,
    )

    assert r.status_code == 200, r.text
    body = r.json()
    # 응답은 요청과 같은 순서다.
    assert [s["id"] for s in body["sessions"]] == [run["id"], bike["id"]]
    assert {s["date"] for s in body["sessions"]} == {LAST_TUESDAY}
    assert {s["day_label"] for s in body["sessions"]} == {"화"}
    assert _dates(client, headers, "2026-09-14") == {}
    assert _dates(client, headers, "2026-09-07") == {
        "러닝머신": LAST_TUESDAY,
        "사이클": LAST_TUESDAY,
    }


def test_move_changes_nothing_but_the_date(client, db_session):
    """날짜 말고는 그대로다 — 칼로리도 다시 계산하지 않는다."""
    _member, headers = _new_member(client)
    saved = _add(client, headers, "러닝머신")

    r = client.post(
        MOVE_PATH,
        json={"session_ids": [saved["id"]], "date": LAST_TUESDAY},
        headers=headers,
    )

    assert r.status_code == 200, r.text
    (moved,) = r.json()["sessions"]
    for field in ("type", "name", "minutes", "calories", "intensity", "source"):
        assert moved[field] == saved[field], field
    # 세 날짜 필드가 같은 날을 가리킨다(#1264).
    db_session.expire_all()
    row = db_session.scalar(
        select(ExerciseSession).where(ExerciseSession.id == saved["id"])
    )
    assert (row.week_start, row.day_label) == ("2026-09-07", "화")
    assert clock.to_seoul(row.completed_at).date().isoformat() == LAST_TUESDAY


def test_repeating_the_same_move_gives_the_same_result(client):
    """응답을 잃은 뒤의 재시도가 기록을 한 번 더 옮기지 않는다."""
    _member, headers = _new_member(client)
    saved = _add(client, headers, "러닝머신")
    payload = {"session_ids": [saved["id"]], "date": LAST_TUESDAY}

    first = client.post(MOVE_PATH, json=payload, headers=headers)
    again = client.post(MOVE_PATH, json=payload, headers=headers)

    assert first.status_code == again.status_code == 200
    assert first.json() == again.json()
    assert _dates(client, headers, "2026-09-07") == {"러닝머신": LAST_TUESDAY}


def test_a_repeated_id_is_moved_once(client):
    _member, headers = _new_member(client)
    saved = _add(client, headers, "러닝머신")

    r = client.post(
        MOVE_PATH,
        json={"session_ids": [saved["id"], saved["id"]], "date": LAST_TUESDAY},
        headers=headers,
    )

    assert r.status_code == 200, r.text
    assert [s["id"] for s in r.json()["sessions"]] == [saved["id"]]


def test_an_unknown_id_moves_nothing(client):
    """하나라도 찾지 못하면 404 이고, 찾은 기록도 그대로다."""
    _member, headers = _new_member(client)
    saved = _add(client, headers, "러닝머신")

    r = client.post(
        MOVE_PATH,
        json={"session_ids": [saved["id"], "ex-없는기록"], "date": LAST_TUESDAY},
        headers=headers,
    )

    assert r.status_code == 404, r.text
    assert _dates(client, headers, "2026-09-14") == {"러닝머신": TODAY}
    assert _dates(client, headers, "2026-09-07") == {}


def test_another_members_record_moves_nothing(client):
    """남의 기록은 없는 기록과 같다 — 404 이고 두 회원 모두 그대로다."""
    _other, other_headers = _new_member(client)
    theirs = _add(client, other_headers, "수영")
    _member, headers = _new_member(client)
    mine = _add(client, headers, "러닝머신")

    r = client.post(
        MOVE_PATH,
        json={"session_ids": [mine["id"], theirs["id"]], "date": LAST_TUESDAY},
        headers=headers,
    )

    assert r.status_code == 404, r.text
    assert _dates(client, headers, "2026-09-14") == {"러닝머신": TODAY}
    assert _dates(client, other_headers, "2026-09-14") == {"수영": TODAY}


@pytest.mark.parametrize("source", ["trainer_pt", "assigned_routine"])
def test_a_derived_record_moves_nothing(client, db_session, source):
    """PT·배정 완료로 생긴 기록이 섞여 있으면 단건 수정처럼 409 이고, 전부 그대로다."""
    member_id, headers = _new_member(client)
    mine = _add(client, headers, "러닝머신")
    derived_id = _derived(db_session, member_id, source)
    try:
        r = client.post(
            MOVE_PATH,
            json={"session_ids": [mine["id"], derived_id], "date": LAST_TUESDAY},
            headers=headers,
        )

        assert r.status_code == 409, r.text
        assert _dates(client, headers, "2026-09-07") == {}
        assert _dates(client, headers, "2026-09-14") == {
            "러닝머신": TODAY,
            "벤치프레스": TODAY,
        }
    finally:
        db_session.expire_all()
        row = db_session.get(ExerciseSession, derived_id)
        if row is not None:
            db_session.delete(row)
            db_session.commit()


def test_a_future_date_moves_nothing(client):
    """앞날로는 옮기지 못한다 — 단건 수정과 같은 422(#3042)."""
    _member, headers = _new_member(client)
    saved = _add(client, headers, "러닝머신")

    r = client.post(
        MOVE_PATH,
        json={"session_ids": [saved["id"]], "date": "2026-09-18"},
        headers=headers,
    )

    assert r.status_code == 422, r.text
    assert _dates(client, headers, "2026-09-14") == {"러닝머신": TODAY}


@pytest.mark.parametrize(
    "payload",
    [
        {"session_ids": [], "date": LAST_TUESDAY},
        {"session_ids": ["ex-a"]},
        {"session_ids": ["ex-a"], "date": "2026-13-40"},
        {
            "session_ids": [f"ex-{i}" for i in range(MAX_EXERCISE_SESSIONS_PER_MOVE + 1)],
            "date": LAST_TUESDAY,
        },
    ],
    ids=["empty", "no-date", "bad-date", "too-many"],
)
def test_malformed_requests_are_rejected(client, payload):
    _member, headers = _new_member(client)

    r = client.post(MOVE_PATH, json=payload, headers=headers)

    assert r.status_code == 422, r.text


def test_move_requires_login(client):
    r = client.post(MOVE_PATH, json={"session_ids": ["ex-a"], "date": LAST_TUESDAY})

    assert r.status_code == 401, r.text


def test_move_path_does_not_shadow_adding_records(client):
    """추가(`POST /exercise/sessions`)는 그대로다 — 경로가 겹치지 않는다."""
    _member, headers = _new_member(client)

    r = client.post(
        EXERCISE_SESSIONS_PATH,
        json={"sessions": [{"type": "cardio", "name": "걷기", "minutes": 10}]},
        headers=headers,
    )

    assert r.status_code == 201, r.text
