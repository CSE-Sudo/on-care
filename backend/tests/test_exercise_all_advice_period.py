"""`전체` 운동 조언의 기간 — `전체` 그래프와 같은 첫 기록 주부터다. (#3365)

예전에는 최근 84일만 읽어, 12주 넘게 쓴 회원에게 조언의 "○주 동안" 과 그래프가
다른 기간을 말했다. 이제 조언(`GET /exercise/advice?period=all`)과 그래프
(`GET /exercise/weeks`)가 시작 주를 같은 함수로 정한다.

"오늘" 을 목요일(2026-09-17, KST)로 고정한다. 앞의 것들은 DB 없이, API 를 부르는
것들은 CI 의 Postgres 에서 돈다.
"""
from __future__ import annotations

from datetime import date, datetime
from uuid import uuid4

import pytest

from app.core import clock
from app.services import exercise_service, exercise_types, period_window
from app.services.exercise_service import ExerciseDayTotals
from app.services.trainer import member_mirror
from tests.exercise_helpers import post_exercise

THURSDAY = datetime(2026, 9, 17, 10, 0, tzinfo=clock.SEOUL)
TODAY = "2026-09-17"
THIS_MONDAY = "2026-09-14"


@pytest.fixture
def thursday(monkeypatch):
    monkeypatch.setattr(clock, "now", lambda: THURSDAY)


@pytest.fixture
def no_routines(monkeypatch):
    """추천 개인운동이 없는 회원으로 본다 — 직접 기록 기준 조언을 확인한다.

    담당이 없는 회원에게는 조언을 읽을 때 오늘의 AI 추천이 만들어지고, 그러면
    조언이 추천 목록 기준 문장으로 바뀐다(#2162).
    """
    monkeypatch.setattr(member_mirror, "advice_routine_days", lambda *_args: [])


def _day(when: str, minutes: int = 30) -> ExerciseDayTotals:
    return ExerciseDayTotals(
        date=date.fromisoformat(when),
        minutes=minutes,
        calories=minutes * 9,
        by_type={exercise_types.CARDIO: minutes},
    )


@pytest.mark.parametrize(
    ("start", "end", "weeks"),
    [
        (THIS_MONDAY, TODAY, 1),
        ("2026-09-07", TODAY, 2),
        ("2026-06-29", TODAY, 12),
        ("2026-03-02", TODAY, 29),
        # 월요일이 아닌 날짜도 그 주로 센다.
        ("2026-09-13", "2026-09-14", 2),
        (TODAY, TODAY, 1),
    ],
)
def test_period_weeks_counts_the_calendar_weeks_spanned(start, end, weeks):
    assert exercise_service.period_weeks(start, end) == weeks


def test_steady_advice_says_the_weeks_it_was_given():
    """문장의 "○주 동안" 은 읽은 구간의 주 수다 — 12 로 박혀 있지 않다."""
    days = [_day("2026-03-03"), _day("2026-06-09"), _day(TODAY)]

    advice = exercise_service.period_advice(days, period_window.PERIOD_ALL, weeks=29)

    assert advice.key == "record_all_steady"
    assert advice.params["weeks"] == 29
    assert "29주 동안" in advice.text


def test_steady_advice_without_weeks_spans_the_recorded_days():
    """주 수를 넘기지 않으면 첫 기록일부터 마지막 기록일까지다."""
    days = [_day("2026-09-08"), _day(TODAY)]

    advice = exercise_service.period_advice(days, period_window.PERIOD_ALL)

    assert advice.params["weeks"] == 2


def test_weeks_do_not_change_the_other_periods():
    days = [_day("2026-09-15"), _day(TODAY)]

    week = exercise_service.period_advice(days, period_window.PERIOD_WEEK, weeks=1)
    today = exercise_service.period_advice(days, period_window.PERIOD_TODAY, weeks=1)

    assert "weeks" not in week.params
    assert "weeks" not in today.params


def test_shared_all_window_is_unchanged():
    """다른 곳이 쓰는 공용 `전체` 창(84일)은 그대로다."""
    start, end = period_window.period_bounds(
        period_window.PERIOD_ALL, date.fromisoformat(TODAY)
    )

    assert period_window.ALL_PERIOD_DAYS == 84
    assert (start, end) == ("2026-06-26", TODAY)


# --- API (DB 필요) ------------------------------------------------------------


def _new_member(client) -> dict[str, str]:
    email = f"exa-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register",
        json={"email": email, "password": "test-pw-1234", "name": "u"},
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "test-pw-1234"}
    ).json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


def _add(client, headers, day: str, minutes: int = 30) -> None:
    r = post_exercise(
        client,
        json={"type": "cardio", "name": "걷기", "minutes": minutes, "date": day},
        headers=headers,
    )
    assert r.status_code == 201, r.text


def _advice(client, headers, period: str = "all") -> dict:
    r = client.get(f"/v1/exercise/advice?period={period}", headers=headers)
    assert r.status_code == 200, r.text
    return r.json()


def _graph(client, headers) -> dict:
    r = client.get("/v1/exercise/weeks", headers=headers)
    assert r.status_code == 200, r.text
    return r.json()


@pytest.mark.usefixtures("thursday", "no_routines")
def test_all_advice_reaches_back_past_twelve_weeks(client):
    """12주보다 오래된 기록도 `전체` 조언이 센다 — 그래프와 같은 주부터다."""
    headers = _new_member(client)
    _add(client, headers, "2026-03-04")  # 28주 전 수요일
    _add(client, headers, "2026-06-10")
    _add(client, headers, TODAY)

    advice = _advice(client, headers)
    graph = _graph(client, headers)

    assert advice["from_date"] == graph["from_week"] == "2026-03-02"
    assert advice["to_date"] == TODAY
    assert advice["days_logged"] == 3
    assert advice["advice_key"] == "record_all_steady"
    assert advice["advice_params"]["weeks"] == len(graph["weeks"]) == 29
    assert "29주 동안" in advice["message"]


@pytest.mark.usefixtures("thursday", "no_routines")
def test_all_advice_of_a_new_member_spans_only_their_weeks(client):
    """막 시작한 회원에게 "12주 동안" 이라고 하지 않는다."""
    headers = _new_member(client)
    _add(client, headers, "2026-09-09")
    _add(client, headers, TODAY)

    advice = _advice(client, headers)
    graph = _graph(client, headers)

    assert advice["from_date"] == graph["from_week"] == "2026-09-07"
    assert advice["advice_params"]["weeks"] == len(graph["weeks"]) == 2


@pytest.mark.usefixtures("thursday", "no_routines")
def test_all_advice_without_records_starts_this_week(client):
    """기록이 없으면 그래프의 한 칸과 같은 이번 주다. 조언은 지어내지 않는다."""
    headers = _new_member(client)

    advice = _advice(client, headers)

    assert advice["from_date"] == _graph(client, headers)["from_week"] == THIS_MONDAY
    assert advice["days_logged"] == 0
    assert advice["advice_key"] == "record_empty_all"


@pytest.mark.usefixtures("thursday")
def test_week_and_today_bounds_are_unchanged(client):
    headers = _new_member(client)
    _add(client, headers, "2026-03-04")
    _add(client, headers, TODAY)

    week = _advice(client, headers, "week")
    today = _advice(client, headers, "today")

    assert (week["from_date"], week["to_date"]) == (THIS_MONDAY, TODAY)
    assert (today["from_date"], today["to_date"]) == (TODAY, TODAY)
    assert week["days_logged"] == today["days_logged"] == 1
