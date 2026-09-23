"""기록 그래프와 그래프 색 — 날짜별 기록, KST 경계, 색 교환·고르기. (#2075, #2076)

칸의 진하기는 그날 무엇을 남겼는가 세 단계다(없음 / 하나만 / 둘 다). 보호권으로
이어 붙인 날은 실제 기록이 아니므로 `has_*` 가 둘 다 false 이고 `protected` 만
true 다 — 앱이 그 칸에 방패를 얹어 구분한다.

"오늘" 을 목요일(2026-09-17, KST)로 고정한다. 보호권 테스트와 같은 날이다 —
실행 요일과 상관없이 날짜에 매인 규칙을 재려는 것이다.

DB 필요(로컬 skip, CI 실행).
"""
from __future__ import annotations

from datetime import datetime
from uuid import uuid4

import pytest
from sqlalchemy import select

from app.core import clock
from app.models.models import DietEntry, HealthProfile
from app.services import graph_color_service

THURSDAY = datetime(2026, 9, 17, 10, 0, tzinfo=clock.SEOUL)
TODAY = "2026-09-17"
YESTERDAY = "2026-09-16"
TUESDAY = "2026-09-15"
MONDAY = "2026-09-14"


@pytest.fixture
def thursday(monkeypatch):
    monkeypatch.setattr(clock, "now", lambda: THURSDAY)


# ---- 도우미 ----


def _new_member(client, db_session, points: int = 0) -> tuple[str, dict[str, str]]:
    email = f"grs-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register", json={"email": email, "password": "pw!", "name": "u"}
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "pw!"}
    ).json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    member_id = client.get("/v1/users/me", headers=headers).json()["id"]
    db_session.expire_all()
    profile = db_session.scalar(
        select(HealthProfile).where(HealthProfile.user_id == member_id)
    )
    if profile is None:
        db_session.add(HealthProfile(user_id=member_id, activity_points=points))
    else:
        profile.activity_points = points
    db_session.commit()
    return member_id, headers


def _calendar(client, headers, **params) -> dict:
    r = client.get("/v1/me/activity-calendar", params=params or None, headers=headers)
    assert r.status_code == 200, r.text
    return r.json()


def _day(body: dict, date: str) -> dict:
    return next(d for d in body["days"] if d["date"] == date)


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


def _add_diet(db_session, member_id: str, day: str) -> None:
    db_session.add(
        DietEntry(
            id=f"diet-grs-{uuid4().hex[:10]}",
            user_id=member_id,
            date=day,
            meal_type="lunch",
            time_label="12:00",
            total_calories=500,
        )
    )
    db_session.commit()


def _exchange_color(client, headers, color: str | None, request_id: str | None = None):
    body: dict[str, str] = {"item": "graph_color"}
    if color is not None:
        body["option"] = color
    if request_id is not None:
        body["client_request_id"] = request_id
    return client.post("/v1/me/points/exchange", json=body, headers=headers)


def _shop_ids(client, headers) -> list[str]:
    r = client.get("/v1/me/points/shop", headers=headers)
    assert r.status_code == 200, r.text
    return [i["id"] for i in r.json()["items"]]


# ---- 기록 그래프 ----


def test_calendar_defaults_to_the_last_year(client, db_session, thursday):
    _, h = _new_member(client, db_session)

    body = _calendar(client, h)

    # 오늘로 끝나는 53주. 오늘 이후 날짜는 싣지 않는다 — 아직 오지 않은 날을 빈
    # 칸으로 그리면 끊긴 날처럼 보인다.
    assert body["to_date"] == TODAY
    assert body["from_date"] == "2025-09-12"
    assert len(body["days"]) == 371
    assert body["days"][-1]["date"] == TODAY
    # 구간은 하루도 빠짐없이 채운다 — 기록이 없는 날도 빈 칸으로 온다.
    assert all(d["date"] for d in body["days"])


def test_day_marks_diet_and_exercise_separately(
    client, db_session, thursday
):
    member_id, h = _new_member(client, db_session)
    _add_diet(db_session, member_id, MONDAY)
    _add_exercise(client, h, TUESDAY)
    _add_diet(db_session, member_id, TODAY)
    _add_exercise(client, h, TODAY)

    body = _calendar(client, h, **{"from": MONDAY, "to": TODAY})

    # 세 단계: 아무것도 없음 / 하나만 / 둘 다.
    assert (_day(body, MONDAY)["has_diet"], _day(body, MONDAY)["has_exercise"]) == (
        True,
        False,
    )
    assert (_day(body, TUESDAY)["has_diet"], _day(body, TUESDAY)["has_exercise"]) == (
        False,
        True,
    )
    assert (_day(body, TODAY)["has_diet"], _day(body, TODAY)["has_exercise"]) == (
        True,
        True,
    )
    assert (
        _day(body, YESTERDAY)["has_diet"],
        _day(body, YESTERDAY)["has_exercise"],
    ) == (False, False)


def test_protected_day_is_marked_without_a_record(client, db_session, thursday):
    _, h = _new_member(client, db_session, points=300)
    assert (
        client.post(
            "/v1/me/points/exchange", json={"item": "streak_shield"}, headers=h
        ).status_code
        == 201
    )
    assert (
        client.post(
            "/v1/me/streak-shields/use", json={"date": YESTERDAY}, headers=h
        ).status_code
        == 200
    )

    body = _calendar(client, h, **{"from": MONDAY, "to": TODAY})
    protected = _day(body, YESTERDAY)

    # 보호한 날은 실제 기록이 아니다 — 두 has_* 는 false 이고 연속에만 든다.
    assert protected["protected"] is True
    assert (protected["has_diet"], protected["has_exercise"]) == (False, False)
    assert body["record_streak_days"] == 1
    # 창은 보유 수와 상관없이 내려 온다 — 보호권이 없으면 앱이 교환과 사용을 잇는다.
    # 어느 칸이 비었는지는 days[] 가 말한다.
    assert body["shields_held"] == 0
    assert (body["protectable_from"], body["protectable_to"]) == (
        "2026-08-18",
        YESTERDAY,
    )


def test_record_streak_counts_yesterday_when_today_is_empty(
    client, db_session, thursday
):
    member_id, h = _new_member(client, db_session)
    for day in (MONDAY, TUESDAY, YESTERDAY):
        _add_diet(db_session, member_id, day)

    body = _calendar(client, h)

    # 오늘이 비어도 어제까지 쌓은 연속이 0 으로 보이지 않는다.
    assert body["record_streak_days"] == 3


def test_calendar_range_is_clamped_to_today_and_max_days(client, db_session, thursday):
    _, h = _new_member(client, db_session)

    ahead = _calendar(client, h, **{"from": TODAY, "to": "2026-12-31"})
    assert ahead["to_date"] == TODAY
    assert [d["date"] for d in ahead["days"]] == [TODAY]

    long = _calendar(client, h, **{"from": "2020-01-01", "to": TODAY})
    assert len(long["days"]) == 371
    assert long["to_date"] == TODAY


# ---- 그래프 색 ----


def test_calendar_starts_on_the_base_color(client, db_session, thursday):
    _, h = _new_member(client, db_session)

    color = _calendar(client, h)["color"]

    assert color["current"] == "blue"
    assert color["unlocked"] == ["blue"]
    assert color["palette"] == ["blue", "green", "purple", "orange", "pink"]
    assert color["cost"] == 150


def test_exchange_opens_one_color_and_selects_it(client, db_session, thursday):
    _, h = _new_member(client, db_session, points=400)

    r = _exchange_color(client, h, "purple")

    assert r.status_code == 201, r.text
    body = r.json()
    assert body["coupon"] is None and body["shield"] is None
    assert (body["spent"], body["balance"]) == (150, 250)
    # 열자마자 그 색이 된다 — 샀는데 아무 일도 없는 화면이 되지 않게.
    assert body["graph_color"]["current"] == "purple"
    assert body["graph_color"]["unlocked"] == ["blue", "purple"]
    assert _calendar(client, h)["color"]["current"] == "purple"


def test_same_color_cannot_be_bought_twice(client, db_session, thursday):
    _, h = _new_member(client, db_session, points=400)
    assert _exchange_color(client, h, "green").status_code == 201

    again = _exchange_color(client, h, "green")

    assert again.status_code == 409
    assert _calendar(client, h)["color"]["unlocked"] == ["blue", "green"]


def test_unknown_or_base_color_is_not_for_sale(client, db_session, thursday):
    _, h = _new_member(client, db_session, points=400)

    # 기본 색은 이미 누구나 쓰므로 살 것이 아니다.
    assert _exchange_color(client, h, "blue").status_code == 404
    assert _exchange_color(client, h, "rainbow").status_code == 404
    assert _exchange_color(client, h, None).status_code == 404
    assert _calendar(client, h)["color"]["unlocked"] == ["blue"]


def test_exchange_without_enough_points_is_blocked(client, db_session, thursday):
    _, h = _new_member(client, db_session, points=100)

    r = _exchange_color(client, h, "orange")

    assert r.status_code == 409
    assert _calendar(client, h)["color"]["unlocked"] == ["blue"]


def test_retry_with_the_same_request_id_opens_one_color(client, db_session, thursday):
    _, h = _new_member(client, db_session, points=400)

    first = _exchange_color(client, h, "pink", request_id="req-1")
    second = _exchange_color(client, h, "pink", request_id="req-1")

    assert (first.status_code, second.status_code) == (201, 201)
    assert second.json()["balance"] == 250
    assert _calendar(client, h)["color"]["unlocked"] == ["blue", "pink"]


def test_picking_a_color_costs_nothing_and_survives(client, db_session, thursday):
    _, h = _new_member(client, db_session, points=400)
    _exchange_color(client, h, "green")

    back = client.put("/v1/me/graph-color", json={"color": "blue"}, headers=h)
    assert back.status_code == 200, back.text
    assert back.json()["current"] == "blue"
    assert _calendar(client, h)["color"]["current"] == "blue"

    again = client.put("/v1/me/graph-color", json={"color": "green"}, headers=h)
    assert again.status_code == 200
    # 이미 연 색 사이는 포인트 없이 오간다.
    assert _calendar(client, h)["color"]["current"] == "green"
    assert client.get("/v1/users/me/health", headers=h).json()["activity_points"] == 250


def test_locked_or_unknown_color_cannot_be_picked(client, db_session, thursday):
    _, h = _new_member(client, db_session)

    assert (
        client.put("/v1/me/graph-color", json={"color": "orange"}, headers=h).status_code
        == 409
    )
    assert (
        client.put(
            "/v1/me/graph-color", json={"color": "rainbow"}, headers=h
        ).status_code
        == 404
    )


def test_shop_drops_the_item_once_every_color_is_open(client, db_session, thursday):
    _, h = _new_member(client, db_session, points=1000)
    assert "graph_color" in _shop_ids(client, h)

    for color in graph_color_service.BUYABLE_COLORS:
        assert _exchange_color(client, h, color).status_code == 201

    # 더 살 게 없는 카드를 막힌 채 남겨 두지 않는다. 색 바꾸기는 기록 그래프에서 한다.
    assert "graph_color" not in _shop_ids(client, h)
    assert _calendar(client, h)["color"]["unlocked"] == [
        "blue",
        "green",
        "purple",
        "orange",
        "pink",
    ]
