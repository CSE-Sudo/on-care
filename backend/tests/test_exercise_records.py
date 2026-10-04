"""직접 기록한 운동의 개인 기록 태그. (#2971)

운동 기록 상세의 운동 줄에 붙는 태그 하나 — 평가가 아니라 사실만 알린다.

1. 이름으로 처음 적은 운동은 `first` 다.
2. 근력은 같은 운동의 지난 어떤 중량보다 무거울 때만 `max_weight` 다.
3. 근력 외는 같은 운동의 지난 어떤 시간보다 길 때만 `longest` 다.
4. 같은 운동은 이름의 공백·대소문자를 무시하고 묶는다.
5. 이번 주를 볼 때도 지난 주 기록과 견준다.
"""
from __future__ import annotations

from datetime import timedelta
from uuid import uuid4

from app.core import clock
from app.services import exercise_records
from tests.exercise_helpers import post_exercise

WEEK_PATH = "/v1/exercise/weeks/current"


def _day(days_ago: int) -> str:
    return (clock.today() - timedelta(days=days_ago)).isoformat()


def _login(client) -> dict:
    email = f"records-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register",
        json={"email": email, "password": "test-pw-1234", "name": "u"},
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "test-pw-1234"}
    ).json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


def _bench(weight: float, days_ago: int, name: str = "벤치프레스") -> dict:
    return {
        "type": "strength",
        "name": name,
        "minutes": 12,
        "sets": 4,
        "reps": 10,
        "weight": weight,
        "intensity": "moderate",
        "date": _day(days_ago),
    }


def _run(minutes: int, days_ago: int, name: str = "아침 러닝") -> dict:
    return {
        "type": "cardio",
        "name": name,
        "minutes": minutes,
        "duration_seconds": minutes * 60,
        "intensity": "moderate",
        "date": _day(days_ago),
    }


def _save(client, headers, body) -> str:
    res = post_exercise(client, body, headers=headers)
    assert res.status_code in (200, 201), res.text
    return res.json()["id"]


def _record_of(client, headers, session_id: str):
    week = client.get(WEEK_PATH, headers=headers).json()
    for s in week["sessions"]:
        if s["id"] == session_id:
            return s["record"]
    raise AssertionError(f"{session_id} 가 이번 주 목록에 없다")


def test_the_first_record_of_a_name_is_first(client):
    headers = _login(client)
    sid = _save(client, headers, _bench(40, 0))
    assert _record_of(client, headers, sid) == exercise_records.FIRST


def test_a_heavier_lift_than_ever_before_is_max_weight(client):
    headers = _login(client)
    _save(client, headers, _bench(40, 3))
    _save(client, headers, _bench(45, 2))
    sid = _save(client, headers, _bench(50, 0))
    assert _record_of(client, headers, sid) == exercise_records.MAX_WEIGHT


def test_a_lift_that_ties_or_falls_short_has_no_tag(client):
    headers = _login(client)
    _save(client, headers, _bench(50, 2))
    tie = _save(client, headers, _bench(50, 1))
    lighter = _save(client, headers, _bench(45, 0))
    # 어제·오늘이 지난주로 갈리는 월요일에도 오늘 기록은 이번 주에 있다.
    assert _record_of(client, headers, lighter) is None
    if clock.today().weekday() >= 1:
        assert _record_of(client, headers, tie) is None


def test_a_longer_run_than_ever_before_is_longest(client):
    headers = _login(client)
    _save(client, headers, _run(30, 2))
    sid = _save(client, headers, _run(40, 0))
    assert _record_of(client, headers, sid) == exercise_records.LONGEST


def test_names_are_grouped_ignoring_spaces_and_case(client):
    headers = _login(client)
    _save(client, headers, _bench(60, 2, name="벤치 프레스"))
    sid = _save(client, headers, _bench(55, 0, name="벤치프레스"))
    # 띄어쓰기만 다른 같은 운동이라 `처음` 이 아니고, 더 가벼워 태그가 없다.
    assert _record_of(client, headers, sid) is None


def test_last_weeks_records_count_as_history(client):
    headers = _login(client)
    _save(client, headers, _run(50, 8))
    sid = _save(client, headers, _run(40, 0))
    # 지난주에 더 오래 뛰었으니 이번 기록은 처음도 최장도 아니다.
    assert _record_of(client, headers, sid) is None


def test_exercise_key_ignores_spaces_and_case():
    assert exercise_records.exercise_key(" Bench  Press ") == "benchpress"
    assert exercise_records.exercise_key("") == ""
    assert exercise_records.exercise_key(None) == ""
