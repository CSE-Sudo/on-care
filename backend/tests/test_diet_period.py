"""기간 식단 조회와 기록 시작일 — GET /diet/days?from=&to=, /me/records/span. (#2236)

`전체` 그래프가 **모든 기록**을 그리기로 했다(#2079). 하루에 한 번씩 부르던
길로는 해가 바뀐 회원에게 수백 번의 왕복이 되므로, 기간을 한 번에 받는다.

"오늘" 을 목요일(2026-09-17, KST)로 고정한다 — 실행 요일과 무관하게 날짜에
매인 규칙을 재려는 것이다.

DB 필요(로컬 skip, CI 실행).
"""
from __future__ import annotations

from datetime import datetime
from uuid import uuid4

import pytest
from sqlalchemy import select

from app.core import clock
from app.models.models import DietEntry, HealthProfile

THURSDAY = datetime(2026, 9, 17, 10, 0, tzinfo=clock.SEOUL)
TODAY = "2026-09-17"


@pytest.fixture
def thursday(monkeypatch):
    monkeypatch.setattr(clock, "now", lambda: THURSDAY)


def _new_member(client, db_session) -> tuple[str, dict[str, str]]:
    email = f"dp-{uuid4().hex[:8]}@oncare.com"
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


def _add_diet(
    db_session,
    member_id: str,
    day: str,
    *,
    calories: int = 500,
    sodium_mg: int = 400,
    sugar_g: float = 5.0,
    carbs_g: float = 40.0,
    protein_g: float = 20.0,
    fat_g: float = 10.0,
) -> None:
    db_session.add(
        DietEntry(
            id=f"diet-dp-{uuid4().hex[:10]}",
            user_id=member_id,
            date=day,
            meal_type="lunch",
            time_label="12:00",
            total_calories=calories,
            sodium_mg=sodium_mg,
            sugar_g=sugar_g,
            carbs_g=carbs_g,
            protein_g=protein_g,
            fat_g=fat_g,
        )
    )
    db_session.commit()


def _period(client, headers, **params) -> dict:
    r = client.get("/v1/diet/days", params=params or None, headers=headers)
    assert r.status_code == 200, r.text
    return r.json()


def _day(body: dict, date: str) -> dict:
    return next(d for d in body["days"] if d["date"] == date)


@pytest.mark.usefixtures("thursday")
def test_period_fills_every_day_and_sums_meals(client, db_session):
    """구간의 모든 날이 오고, 같은 날의 끼니는 합쳐진다."""
    member_id, headers = _new_member(client, db_session)
    _add_diet(db_session, member_id, "2026-09-15", calories=400, carbs_g=30)
    _add_diet(db_session, member_id, "2026-09-15", calories=600, carbs_g=50)

    body = _period(client, headers, **{"from": "2026-09-14", "to": TODAY})

    assert body["from_date"] == "2026-09-14"
    assert body["to_date"] == TODAY
    # 월~목 나흘, 기록 없는 날도 빈 칸으로.
    assert [d["date"] for d in body["days"]] == [
        "2026-09-14",
        "2026-09-15",
        "2026-09-16",
        "2026-09-17",
    ]
    assert _day(body, "2026-09-15")["total_calories"] == 1000
    assert _day(body, "2026-09-15")["carbs_g"] == pytest.approx(80.0)
    assert _day(body, "2026-09-14")["total_calories"] == 0


@pytest.mark.usefixtures("thursday")
def test_period_without_from_starts_at_the_first_record(client, db_session):
    """`from` 을 생략하면 첫 기록일부터다 — 화면이 어디까지 거슬러 갈지 몰라도 된다."""
    member_id, headers = _new_member(client, db_session)
    _add_diet(db_session, member_id, "2026-09-10")
    _add_diet(db_session, member_id, "2026-09-16")

    body = _period(client, headers)

    assert body["from_date"] == "2026-09-10"
    assert body["to_date"] == TODAY
    assert len(body["days"]) == 8


@pytest.mark.usefixtures("thursday")
def test_period_does_not_run_past_today(client, db_session):
    """아직 오지 않은 날은 칸이 아니다 — 기록 그래프와 같은 규칙이다."""
    member_id, headers = _new_member(client, db_session)
    _add_diet(db_session, member_id, TODAY)

    body = _period(client, headers, **{"from": TODAY, "to": "2026-12-31"})

    assert body["to_date"] == TODAY
    assert len(body["days"]) == 1


@pytest.mark.usefixtures("thursday")
def test_period_of_a_member_with_no_records(client, db_session):
    """기록이 하나도 없으면 오늘 하루짜리 빈 칸 하나다."""
    _member_id, headers = _new_member(client, db_session)

    body = _period(client, headers)

    assert body["from_date"] == body["to_date"] == TODAY
    assert [d["total_calories"] for d in body["days"]] == [0]


def test_period_rejects_a_bad_date(client, db_session):
    """형식이 틀린 날짜는 조용히 흘려보내지 않는다."""
    _member_id, headers = _new_member(client, db_session)

    r = client.get("/v1/diet/days", params={"from": "2026-13-40"}, headers=headers)

    assert r.status_code == 422


@pytest.mark.usefixtures("thursday")
def test_record_span_reports_first_diet_and_exercise_days(client, db_session):
    """`전체` 가 어디서부터 그릴지 — 식단과 운동이 각자 제 첫 기록일을 가진다."""
    member_id, headers = _new_member(client, db_session)
    _add_diet(db_session, member_id, "2026-09-02")
    r = client.post(
        "/v1/exercise/sessions",
        json={
            "type": "cardio",
            "name": "걷기",
            "minutes": 30,
            "calories": 0,
            "date": "2026-09-09",
        },
        headers=headers,
    )
    assert r.status_code == 201, r.text

    body = client.get("/v1/me/records/span", headers=headers).json()

    assert body["diet_first_date"] == "2026-09-02"
    assert body["exercise_first_date"] == "2026-09-09"


def test_record_span_is_null_without_records(client, db_session):
    """기록이 없으면 null 이다 — 0 이나 오늘로 지어내지 않는다."""
    _member_id, headers = _new_member(client, db_session)

    body = client.get("/v1/me/records/span", headers=headers).json()

    assert body["diet_first_date"] is None
    assert body["exercise_first_date"] is None
