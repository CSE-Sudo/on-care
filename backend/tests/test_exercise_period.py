"""기간 운동 조회 — GET /exercise/weeks?from=&to=. (#2247)

`전체` 가 모든 기록을 그리면서(#2079) 주마다 부르면 해가 바뀐 회원에게 쉰 번이
넘는 왕복이 된다. 한 번에 받아 주 단위로 나눈다.

주마다의 집계는 한 주 조회(`build_current_week`)와 **같은 함수**다 — 한 주만 볼
때와 여러 주를 볼 때의 숫자가 갈리면 안 된다.

"오늘" 을 목요일(2026-09-17, KST)로 고정한다. DB 필요(로컬 skip, CI 실행).
"""
from __future__ import annotations

from datetime import datetime
from uuid import uuid4

import pytest
from sqlalchemy import select

from app.core import clock
from app.models.models import HealthProfile

THURSDAY = datetime(2026, 9, 17, 10, 0, tzinfo=clock.SEOUL)
THIS_MONDAY = "2026-09-14"


@pytest.fixture
def thursday(monkeypatch):
    monkeypatch.setattr(clock, "now", lambda: THURSDAY)


def _new_member(client, db_session) -> tuple[str, dict[str, str]]:
    email = f"ep-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register", json={"email": email, "password": "pw!", "name": "u"}
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "pw!"}
    ).json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    member_id = client.get("/v1/users/me", headers=headers).json()["id"]
    db_session.expire_all()
    if db_session.scalar(
        select(HealthProfile).where(HealthProfile.user_id == member_id)
    ) is None:
        db_session.add(HealthProfile(user_id=member_id))
        db_session.commit()
    return member_id, headers


def _add_exercise(client, headers, day: str, minutes: int = 30) -> None:
    r = client.post(
        "/v1/exercise/sessions",
        json={
            "type": "cardio",
            "name": "걷기",
            "minutes": minutes,
            "calories": 0,
            "date": day,
        },
        headers=headers,
    )
    assert r.status_code == 201, r.text


def _period(client, headers, **params) -> dict:
    r = client.get("/v1/exercise/weeks", params=params or None, headers=headers)
    assert r.status_code == 200, r.text
    return r.json()


@pytest.mark.usefixtures("thursday")
def test_period_fills_every_week_between_the_bounds(client, db_session):
    """구간이 걸친 주가 하나도 빠지지 않는다 — 기록이 없는 주도 0 으로 온다."""
    _member_id, headers = _new_member(client, db_session)
    _add_exercise(client, headers, "2026-09-01")  # 2주 전 화요일
    _add_exercise(client, headers, "2026-09-16")  # 이번 주 수요일

    body = _period(client, headers, **{"from": "2026-08-31", "to": "2026-09-17"})

    assert body["from_week"] == "2026-08-31"
    assert body["to_week"] == THIS_MONDAY
    assert [w["week_start"] for w in body["weeks"]] == [
        "2026-08-31",
        "2026-09-07",
        THIS_MONDAY,
    ]
    # 기록이 없는 가운데 주도 빈 칸으로 온다.
    assert sum(body["weeks"][1]["daily_minutes"]) == 0
    # 화요일(index 1)에 30분.
    assert body["weeks"][0]["daily_minutes"][1] == 30


@pytest.mark.usefixtures("thursday")
def test_period_without_from_starts_at_the_first_recorded_week(client, db_session):
    """`from` 을 생략하면 첫 기록이 있는 주부터다."""
    _member_id, headers = _new_member(client, db_session)
    _add_exercise(client, headers, "2026-08-19")

    body = _period(client, headers)

    assert body["from_week"] == "2026-08-17"
    assert body["to_week"] == THIS_MONDAY
    assert len(body["weeks"]) == 5


@pytest.mark.usefixtures("thursday")
def test_period_snaps_to_mondays_and_stops_at_this_week(client, db_session):
    """월요일이 아닌 날짜는 그 주의 월요일로, 앞날은 이번 주로 당긴다."""
    _member_id, headers = _new_member(client, db_session)

    body = _period(client, headers, **{"from": "2026-09-09", "to": "2026-12-31"})

    assert body["from_week"] == "2026-09-07"
    assert body["to_week"] == THIS_MONDAY


@pytest.mark.usefixtures("thursday")
def test_period_of_a_member_without_records(client, db_session):
    """기록이 없으면 이번 주 한 칸이다."""
    _member_id, headers = _new_member(client, db_session)

    body = _period(client, headers)

    assert body["from_week"] == body["to_week"] == THIS_MONDAY
    assert len(body["weeks"]) == 1
    assert sum(body["weeks"][0]["daily_minutes"]) == 0


@pytest.mark.usefixtures("thursday")
def test_period_matches_the_single_week_answer(client, db_session):
    """같은 주를 한 주 조회로 물어도 같은 숫자다 — 집계 함수가 하나다."""
    _member_id, headers = _new_member(client, db_session)
    _add_exercise(client, headers, "2026-09-16", minutes=45)

    week = client.get(
        "/v1/exercise/weeks/current",
        params={"week_start": THIS_MONDAY},
        headers=headers,
    ).json()
    body = _period(client, headers, **{"from": THIS_MONDAY})

    same = body["weeks"][0]
    for key in (
        "day_labels",
        "daily_minutes",
        "daily_calories",
        "cardio_minutes",
        "strength_minutes",
        "strength_sets",
        "stretching_minutes",
        "other_minutes",
        "total_minutes",
        "total_calories",
        "streak_days",
        "weekly_goal_minutes",
        "weekly_goal_calories",
    ):
        assert same[key] == week[key], key
    # 세션 목록과 코칭 문구는 싣지 않는다 — 그래프가 쓰지 않는다.
    assert "sessions" not in same
    assert "ai_coach_message" not in same


def test_period_rejects_a_bad_date(client, db_session):
    """형식이 틀린 날짜는 조용히 흘려보내지 않는다."""
    _member_id, headers = _new_member(client, db_session)

    r = client.get(
        "/v1/exercise/weeks", params={"from": "2026-13-40"}, headers=headers
    )

    assert r.status_code == 422
