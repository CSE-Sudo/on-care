"""운동 여러 개 한 번에 추가 — DB 필요(로컬 skip, CI 실행). (#2544)

`POST /exercise/sessions` 는 기록 1~N개를 한 트랜잭션으로 저장한다. 몇 개만
저장된 채 실패하면 다시 시도한 회원이 중복 기록을 만든다 — 그래서 전부 되거나
전부 안 된다.
"""
from __future__ import annotations

from uuid import uuid4

from app.core import clock
from app.schemas.exercise_limits import MAX_EXERCISE_SESSIONS_PER_REQUEST
from tests.exercise_helpers import EXERCISE_SESSIONS_PATH


def _login(client) -> dict:
    email = f"exb-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register",
        json={"email": email, "password": "test-pw-1234", "name": "u"},
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "test-pw-1234"}
    ).json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


def _cardio(name: str, seconds: int = 1800) -> dict:
    return {
        "type": "cardio",
        "name": name,
        "duration_seconds": seconds,
        "date": clock.today().isoformat(),
    }


def _squat() -> dict:
    return {
        "type": "strength",
        "name": "스쿼트",
        "minutes": 12,
        "sets": 3,
        "reps": 10,
        "weight": 20,
        "date": clock.today().isoformat(),
    }


def _week_names(client, headers) -> list[str]:
    week = client.get("/v1/exercise/weeks/current", headers=headers)
    assert week.status_code == 200, week.text
    return sorted(s["name"] for s in week.json()["sessions"])


def test_saves_every_session_in_request_order(client):
    h = _login(client)
    r = client.post(
        EXERCISE_SESSIONS_PATH,
        json={"sessions": [_cardio("러닝머신"), _squat(), _cardio("사이클", 600)]},
        headers=h,
    )
    assert r.status_code == 201, r.text
    body = r.json()
    assert [s["name"] for s in body["sessions"]] == ["러닝머신", "스쿼트", "사이클"]
    assert all(s["id"] for s in body["sessions"])
    assert body["sessions"][1]["sets"] == 3
    assert body["sessions"][2]["duration_seconds"] == 600
    assert _week_names(client, h) == sorted(["러닝머신", "스쿼트", "사이클"])


def test_one_bad_session_saves_nothing(client):
    """항목 하나가 잘못되면 전체가 422 이고, 앞의 항목도 남지 않는다."""
    h = _login(client)
    bad = {**_cardio("줄넘기"), "duration_seconds": 0}
    r = client.post(
        EXERCISE_SESSIONS_PATH,
        json={"sessions": [_cardio("러닝머신"), bad]},
        headers=h,
    )
    assert r.status_code == 422, r.text
    assert _week_names(client, h) == []


def test_empty_list_is_rejected(client):
    h = _login(client)
    r = client.post(EXERCISE_SESSIONS_PATH, json={"sessions": []}, headers=h)
    assert r.status_code == 422, r.text


def test_too_many_sessions_are_rejected(client):
    h = _login(client)
    many = [_cardio(f"운동{i}", 60) for i in range(MAX_EXERCISE_SESSIONS_PER_REQUEST + 1)]
    r = client.post(EXERCISE_SESSIONS_PATH, json={"sessions": many}, headers=h)
    assert r.status_code == 422, r.text
    assert _week_names(client, h) == []


def test_single_session_body_is_no_longer_accepted(client):
    """추가 경로는 한 벌이다 — 목록으로 감싸지 않은 한 건은 받지 않는다."""
    h = _login(client)
    r = client.post(EXERCISE_SESSIONS_PATH, json=_cardio("러닝머신"), headers=h)
    assert r.status_code == 422, r.text


def test_points_follow_the_daily_cap_across_one_request(client):
    """다섯 개를 한 번에 저장해도 하루 한도(3회)만큼만 적립되고 합계로 온다."""
    h = _login(client)
    r = client.post(
        EXERCISE_SESSIONS_PATH,
        json={"sessions": [_cardio(f"운동{i}", 600) for i in range(5)]},
        headers=h,
    )
    assert r.status_code == 201, r.text
    points = r.json()["points"]
    assert points["awarded"] == 60
    assert points["balance"] == 60

    health = client.get("/v1/users/me/health", headers=h)
    assert health.json()["activity_points"] == 60
