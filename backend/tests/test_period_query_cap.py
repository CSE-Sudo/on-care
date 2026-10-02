"""기간 집계 구간 상한 — GET /diet/days, /exercise/weeks 와 트레이너 미러. (#2833)

응답은 구간의 모든 날(주)을 0 으로 채운 배열이라, `from=0001-01-01` 이나 날짜가
잘못 들어간 아주 오래된 기록 하나가 수십만 칸을 만들어 워커를 묶었다. 구간은 끝에서
거슬러 1100일(160주)까지로 자르고, 응답의 시작일이 실제로 적용된 값을 알린다.

"오늘" 을 목요일(2026-09-17, KST)로 고정한다. 앞부분 하한 계산은 DB 없이,
뒷부분(`client` 픽스처)은 CI 의 Postgres 에서 돈다.
"""
from __future__ import annotations

from datetime import date, datetime, timedelta
from uuid import uuid4

import pytest

from app.core import clock
from app.services import diet_service, exercise_service

THURSDAY = datetime(2026, 9, 17, 10, 0, tzinfo=clock.SEOUL)
TODAY = date(2026, 9, 17)
THIS_MONDAY = date(2026, 9, 14)
DAY_FLOOR = TODAY - timedelta(days=diet_service.MAX_PERIOD_DAYS - 1)
WEEK_FLOOR = THIS_MONDAY - timedelta(weeks=exercise_service.MAX_PERIOD_WEEKS - 1)


@pytest.fixture
def thursday(monkeypatch):
    monkeypatch.setattr(clock, "now", lambda: THURSDAY)


# ---- 하한 계산 (DB 불필요) ----


def test_caps_are_about_three_years():
    assert diet_service.MAX_PERIOD_DAYS == 1100
    assert exercise_service.MAX_PERIOD_WEEKS == 160


def test_day_floor_keeps_exactly_max_days():
    floor = diet_service.period_floor(TODAY)
    assert floor == DAY_FLOOR
    assert (TODAY - floor).days + 1 == diet_service.MAX_PERIOD_DAYS


def test_day_floor_near_the_start_of_the_calendar_does_not_underflow():
    assert diet_service.period_floor(date(1, 1, 5)) == date.min
    assert diet_service.period_floor(date.min) == date.min


def test_week_floor_keeps_exactly_max_weeks_and_is_a_monday():
    floor = exercise_service.period_floor_monday(THIS_MONDAY)
    assert floor == WEEK_FLOOR
    assert floor.weekday() == 0
    assert (THIS_MONDAY - floor).days // 7 + 1 == exercise_service.MAX_PERIOD_WEEKS


def test_week_floor_near_the_start_of_the_calendar_does_not_underflow():
    assert exercise_service.period_floor_monday(date(1, 1, 8)) == date.min
    assert date.min.weekday() == 0


# ---- 회원 경로 (DB) ----


def _member(db_session) -> tuple[str, dict[str, str]]:
    from app.core.security import create_access_token
    from app.models.models import User

    member_id = f"period-cap-{uuid4().hex[:10]}"
    db_session.add(
        User(id=member_id, email=f"{member_id}@oncare.com", name="u", role="member")
    )
    db_session.commit()
    return member_id, {"Authorization": f"Bearer {create_access_token(member_id)}"}


def _add_diet(db_session, member_id: str, day: date, calories: int = 500) -> None:
    from app.models.models import DietEntry

    db_session.add(
        DietEntry(
            id=f"diet-cap-{uuid4().hex[:10]}",
            user_id=member_id,
            date=day.isoformat(),
            meal_type="lunch",
            time_label="12:00",
            total_calories=calories,
        )
    )
    db_session.commit()


def _add_exercise(db_session, member_id: str, day: date, minutes: int = 30) -> None:
    from app.models.models import ExerciseSession

    monday = day - timedelta(days=day.weekday())
    db_session.add(
        ExerciseSession(
            id=f"ex-cap-{uuid4().hex[:10]}",
            user_id=member_id,
            week_start=monday.isoformat(),
            day_label="월화수목금토일"[day.weekday()],
            type="cardio",
            name="걷기",
            minutes=minutes,
        )
    )
    db_session.commit()


def _diet(client, headers, path: str = "/v1/diet/days", **params) -> dict:
    r = client.get(path, params=params or None, headers=headers)
    assert r.status_code == 200, r.text
    return r.json()


def _weeks(client, headers, path: str = "/v1/exercise/weeks", **params) -> dict:
    r = client.get(path, params=params or None, headers=headers)
    assert r.status_code == 200, r.text
    return r.json()


@pytest.mark.usefixtures("thursday")
@pytest.mark.parametrize("start", ["0001-01-01", "1900-01-01", "2020-01-01"])
def test_diet_far_from_is_cut_to_the_cap(client, db_session, start):
    _, headers = _member(db_session)
    body = _diet(client, headers, **{"from": start})
    assert body["from_date"] == DAY_FLOOR.isoformat()
    assert body["to_date"] == TODAY.isoformat()
    assert len(body["days"]) == diet_service.MAX_PERIOD_DAYS
    assert body["days"][0]["date"] == DAY_FLOOR.isoformat()


@pytest.mark.usefixtures("thursday")
def test_diet_without_from_and_an_ancient_record_is_cut(client, db_session):
    """날짜가 잘못 들어간 옛 기록 하나가 `전체` 를 폭주시키지 않는다."""
    member_id, headers = _member(db_session)
    _add_diet(db_session, member_id, date(1970, 1, 1))
    _add_diet(db_session, member_id, TODAY - timedelta(days=3), calories=700)
    body = _diet(client, headers)
    assert body["from_date"] == DAY_FLOOR.isoformat()
    assert len(body["days"]) == diet_service.MAX_PERIOD_DAYS
    assert body["days"][-4]["total_calories"] == 700


@pytest.mark.usefixtures("thursday")
def test_diet_range_inside_the_cap_is_unchanged(client, db_session):
    member_id, headers = _member(db_session)
    start = TODAY - timedelta(days=364)
    _add_diet(db_session, member_id, start, calories=321)
    body = _diet(client, headers, **{"from": start.isoformat()})
    assert body["from_date"] == start.isoformat()
    assert len(body["days"]) == 365
    assert body["days"][0]["total_calories"] == 321

    first_only = _diet(client, headers)
    assert first_only["from_date"] == start.isoformat()


@pytest.mark.usefixtures("thursday")
def test_diet_cap_counts_back_from_the_requested_end(client, db_session):
    """옛 구간도 볼 수 있다 — 상한은 구간의 길이다."""
    _, headers = _member(db_session)
    end = date(2020, 6, 30)
    body = _diet(client, headers, **{"from": "0001-01-01", "to": end.isoformat()})
    assert body["to_date"] == end.isoformat()
    assert body["from_date"] == diet_service.period_floor(end).isoformat()
    assert len(body["days"]) == diet_service.MAX_PERIOD_DAYS


@pytest.mark.usefixtures("thursday")
def test_diet_reversed_and_extreme_inputs_stay_normalized(client, db_session):
    _, headers = _member(db_session)
    reversed_ = _diet(client, headers, **{"from": "2026-09-10", "to": "2026-09-01"})
    assert reversed_["from_date"] == reversed_["to_date"] == "2026-09-01"
    assert len(reversed_["days"]) == 1

    future = _diet(client, headers, **{"from": "9999-12-31", "to": "9999-12-31"})
    assert future["from_date"] == future["to_date"] == TODAY.isoformat()

    assert client.get("/v1/diet/days", params={"from": "0000-01-01"}, headers=headers).status_code == 422
    assert client.get("/v1/diet/days", params={"from": "10000-01-01"}, headers=headers).status_code == 422


@pytest.mark.usefixtures("thursday")
@pytest.mark.parametrize("start", ["0001-01-01", "1900-01-03", "2020-01-01"])
def test_exercise_far_from_is_cut_to_the_cap(client, db_session, start):
    _, headers = _member(db_session)
    body = _weeks(client, headers, **{"from": start})
    assert body["from_week"] == WEEK_FLOOR.isoformat()
    assert body["to_week"] == THIS_MONDAY.isoformat()
    assert len(body["weeks"]) == exercise_service.MAX_PERIOD_WEEKS


@pytest.mark.usefixtures("thursday")
def test_exercise_without_from_and_an_ancient_record_is_cut(client, db_session):
    member_id, headers = _member(db_session)
    _add_exercise(db_session, member_id, date(1970, 1, 5))
    body = _weeks(client, headers)
    assert body["from_week"] == WEEK_FLOOR.isoformat()
    assert len(body["weeks"]) == exercise_service.MAX_PERIOD_WEEKS


@pytest.mark.usefixtures("thursday")
def test_exercise_range_inside_the_cap_is_unchanged(client, db_session):
    member_id, headers = _member(db_session)
    start = THIS_MONDAY - timedelta(weeks=51)
    _add_exercise(db_session, member_id, start, minutes=45)
    body = _weeks(client, headers)
    assert body["from_week"] == start.isoformat()
    assert len(body["weeks"]) == 52
    assert body["weeks"][0]["total_minutes"] == 45


@pytest.mark.usefixtures("thursday")
def test_exercise_reversed_input_stays_one_week(client, db_session):
    _, headers = _member(db_session)
    body = _weeks(client, headers, **{"from": "2026-09-10", "to": "2026-08-31"})
    assert body["from_week"] == body["to_week"] == "2026-08-31"
    assert len(body["weeks"]) == 1


# ---- 트레이너 미러 (DB) ----


@pytest.fixture
def trainer_pair(db_session):
    from app.core.security import create_access_token
    from app.models.models import TrainerClient, User

    suffix = uuid4().hex[:10]
    trainer_id = f"period-cap-trainer-{suffix}"
    member_id = f"period-cap-member-{suffix}"
    db_session.add_all(
        [
            User(id=trainer_id, email=f"{trainer_id}@oncare.com", name="t", role="trainer"),
            User(id=member_id, email=f"{member_id}@oncare.com", name="m", role="member"),
        ]
    )
    db_session.flush()
    db_session.add(
        TrainerClient(
            id=f"tc-{uuid4().hex[:12]}",
            trainer_id=trainer_id,
            member_id=member_id,
            active=True,
        )
    )
    db_session.commit()
    return member_id, {"Authorization": f"Bearer {create_access_token(trainer_id)}"}


@pytest.mark.usefixtures("thursday")
def test_trainer_diet_period_uses_the_same_cap(client, db_session, trainer_pair):
    member_id, headers = trainer_pair
    _add_diet(db_session, member_id, date(1970, 1, 1))
    path = f"/v1/trainer/clients/{member_id}/diet/days"
    for params in ({}, {"from": "0001-01-01"}):
        body = _diet(client, headers, path, **params)
        assert body["from_date"] == DAY_FLOOR.isoformat()
        assert len(body["days"]) == diet_service.MAX_PERIOD_DAYS


@pytest.mark.usefixtures("thursday")
def test_trainer_exercise_period_uses_the_same_cap(client, db_session, trainer_pair):
    member_id, headers = trainer_pair
    _add_exercise(db_session, member_id, date(1970, 1, 5))
    path = f"/v1/trainer/clients/{member_id}/exercise/weeks"
    for params in ({}, {"from": "0001-01-01"}):
        body = _weeks(client, headers, path, **params)
        assert body["from_week"] == WEEK_FLOOR.isoformat()
        assert len(body["weeks"]) == exercise_service.MAX_PERIOD_WEEKS
