"""트레이너 웹 실서버 리포트가 읽는 `GET …/report/goals` 의 약속. (#2287)

트레이너 웹의 실서버 저장소는 리포트를 열 때 **보고 있는 주** 를 그대로
`week_start` 로 묻고, 응답의 `goals` 를 그 주의 `지난 주 목표 달성` 재료로 쓴다.
저장(`PUT`)이 한 주를 더해 남기므로, 앱은 주 경계를 따로 계산하지 않는다.

이 파일이 지키는 것:
 * 응답 모양 — 앱이 읽는 두 키(`week_start`·`goals`)와 그 타입.
 * 앱이 보낸 주로 저장하고 다음 주로 물으면 그대로 돌아온다(앱의 왕복 경로).
 * 주 중간 날짜로 물어도 그 주의 월요일로 맞춰 답한다.
 * 아직 오지 않은 주·읽을 수 없는 주는 거부한다(앱은 이때 빈 칸으로 넘어간다).
 * 저장된 값이 깨졌어도 500 이 아니라 빈 목록이다.
 * 다른 회원의 목표가 섞이지 않는다.

DB 필요 (로컬 skip, CI 실행).
"""
from __future__ import annotations

import json
import uuid
from datetime import date, datetime, timedelta, timezone

import pytest
from sqlalchemy import select


def _h(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _trainer_tok(client) -> str:
    return client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    ).json()["access_token"]


MEMBER = "user-jisu"
GOALS = f"/v1/trainer/clients/{MEMBER}/report/goals"


def _next_week(week: str) -> str:
    return (date.fromisoformat(week) + timedelta(days=7)).isoformat()


def _put_row(db, week: str, goals_json: str) -> None:
    """앱을 거치지 않고 그 주의 행을 직접 남긴다 — 깨진 값을 흉내 내려고."""
    from app.models.models import TrainerReportGoal, User

    trainer = db.scalar(select(User).where(User.email == "trainer@oncare.com"))
    row = db.scalar(
        select(TrainerReportGoal).where(
            TrainerReportGoal.member_id == MEMBER,
            TrainerReportGoal.week_start == week,
        )
    )
    now = datetime.now(timezone.utc)
    if row is None:
        db.add(
            TrainerReportGoal(
                id=f"rg-{uuid.uuid4().hex[:12]}",
                trainer_id=trainer.id,
                member_id=MEMBER,
                week_start=week,
                goals_json=goals_json,
                created_at=now,
                updated_at=now,
            )
        )
    else:
        row.goals_json = goals_json
        row.updated_at = now
    db.commit()


# ---- 응답 모양 ----

def test_the_response_carries_exactly_what_the_app_reads(client):
    t = _trainer_tok(client)
    r = client.get(GOALS, params={"week_start": "2019-02-04"}, headers=_h(t))

    assert r.status_code == 200, r.text
    body = r.json()
    assert set(body) == {"week_start", "goals"}
    assert isinstance(body["week_start"], str)
    assert isinstance(body["goals"], list)


def test_goals_are_plain_strings_in_the_order_they_were_picked(client):
    t = _trainer_tok(client)
    week = "2026-03-02"
    picked = ["주 3회 기록", "저녁 단백질 챙기기", "하체 루틴 2회"]
    client.put(GOALS, json={"week_start": week, "goals": picked}, headers=_h(t))

    goals = client.get(
        GOALS, params={"week_start": _next_week(week)}, headers=_h(t)
    ).json()["goals"]

    assert goals == picked
    assert all(isinstance(g, str) for g in goals)


# ---- 앱의 왕복 경로 ----

def test_what_the_app_saves_while_viewing_a_week_comes_back_on_the_next_one(client):
    """앱은 보고 있는 주로 저장하고, 다음 주 리포트를 열 때 그 주로 묻는다."""
    t = _trainer_tok(client)
    viewing = "2026-03-09"
    saved = client.put(
        GOALS, json={"week_start": viewing, "goals": ["물 2L"]}, headers=_h(t)
    ).json()

    got = client.get(
        GOALS, params={"week_start": _next_week(viewing)}, headers=_h(t)
    ).json()

    assert got == saved
    assert got == {"week_start": _next_week(viewing), "goals": ["물 2L"]}


@pytest.mark.parametrize("offset", range(7))
def test_any_day_of_the_week_reads_the_same_monday(client, offset):
    """리포트 딥링크가 주 중간 날짜를 실어 와도 같은 목표를 읽는다."""
    t = _trainer_tok(client)
    picked_in = "2026-03-16"
    applies = _next_week(picked_in)
    client.put(GOALS, json={"week_start": picked_in, "goals": ["계단 이용"]}, headers=_h(t))

    day = (date.fromisoformat(applies) + timedelta(days=offset)).isoformat()
    got = client.get(GOALS, params={"week_start": day}, headers=_h(t)).json()

    assert got["week_start"] == applies
    assert got["goals"] == ["계단 이용"]


def test_the_default_week_is_this_week(client):
    from app.core import clock
    from app.services.trainer.reports import week_start_of

    t = _trainer_tok(client)
    r = client.get(GOALS, headers=_h(t))

    assert r.status_code == 200, r.text
    assert r.json()["week_start"] == week_start_of(clock.today()).isoformat()


# ---- 거부 ----

def test_a_week_that_has_not_come_yet_is_refused(client):
    """저장은 다음 주에 남지만, 그 주를 미리 읽는 길은 없다 — 리포트도 그 주를
    열 수 없다."""
    from app.core import clock
    from app.services.trainer.reports import week_start_of

    t = _trainer_tok(client)
    upcoming = (week_start_of(clock.today()) + timedelta(days=7)).isoformat()
    r = client.get(GOALS, params={"week_start": upcoming}, headers=_h(t))

    assert r.status_code == 422


@pytest.mark.parametrize("bad", ["2026-13-01", "지난주", "2026/03/02", "20260302"])
def test_an_unreadable_week_is_refused(client, bad):
    t = _trainer_tok(client)
    r = client.get(GOALS, params={"week_start": bad}, headers=_h(t))
    assert r.status_code == 422


# ---- 저장된 값이 이상할 때 ----

@pytest.mark.parametrize(
    "stored",
    ["{not json", '{"goals": ["A"]}', '"A"', "null", "3"],
)
def test_a_broken_stored_value_reads_as_no_goals(client, db_session, stored):
    """깨진 값으로 500 을 내면 앱은 칸을 비우고 넘어가지만, 목표를 지어내는
    것보다는 빈 목록이 정직하다."""
    t = _trainer_tok(client)
    week = "2026-02-02"
    _put_row(db_session, week, stored)

    r = client.get(GOALS, params={"week_start": week}, headers=_h(t))

    assert r.status_code == 200, r.text
    assert r.json() == {"week_start": week, "goals": []}


def test_non_string_and_blank_entries_are_left_out(client, db_session):
    t = _trainer_tok(client)
    week = "2026-02-09"
    _put_row(db_session, week, json.dumps(["주 2회 하체", "", "   ", 3, None, {"a": 1}, "물 2L"]))

    got = client.get(GOALS, params={"week_start": week}, headers=_h(t)).json()

    assert got["goals"] == ["주 2회 하체", "물 2L"]


# ---- 다른 회원·다른 주 ----

def test_another_week_does_not_leak_in(client):
    t = _trainer_tok(client)
    client.put(GOALS, json={"week_start": "2026-02-16", "goals": ["A주 목표"]}, headers=_h(t))
    client.put(GOALS, json={"week_start": "2026-02-23", "goals": ["B주 목표"]}, headers=_h(t))

    assert client.get(
        GOALS, params={"week_start": "2026-02-23"}, headers=_h(t)
    ).json()["goals"] == ["A주 목표"]
    assert client.get(
        GOALS, params={"week_start": "2026-03-02"}, headers=_h(t)
    ).json()["goals"] == ["B주 목표"]
