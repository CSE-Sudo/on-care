"""요일 값이 깨진 옛 운동 기록이 그 주 운동 탭을 막지 않는다. (#3368)

`exercise_sessions.day_label` 에는 제약이 없다. 월~일이 아닌 값이 하나만 있어도
요일 정렬이 터져 그 주 조회가 통째로 500 이었다. 그런 행은 건너뛰고 로그만 남긴다 —
어느 요일인지 모르는 기록을 합계에만 넣으면 요일별 값과 합계가 어긋난다.

순수 로직은 DB 없이 돌고, 엔드포인트는 DB 가 있어야 한다(로컬 skip, CI 실행).
"""
from __future__ import annotations

import logging
from datetime import datetime
from types import SimpleNamespace

import pytest

from app.core import clock
from app.services.exercise_service import build_current_week

#: 2026-10-07(수) 12:00 KST.
_NOW = datetime(2026, 10, 7, 12, 0, tzinfo=clock.SEOUL)
_WEEK = "2026-10-05"


@pytest.fixture(autouse=True)
def _wednesday(monkeypatch):
    monkeypatch.setattr(clock, "now", lambda: _NOW)


def _row(day_label, *, id_: str = "", minutes: int = 30, type_: str = "cardio"):
    return SimpleNamespace(
        id=id_ or f"ex-{day_label}", week_start=_WEEK, day_label=day_label,
        type=type_, name="걷기", minutes=minutes, calories=100, completed_at=None,
    )


# ---- 순수 로직 ----

@pytest.mark.parametrize("broken", ["", "Mon", "월요일", "8", " 월", None])
def test_a_broken_day_label_does_not_break_the_week(broken):
    data = build_current_week([_row("월"), _row(broken, id_="ex-broken"), _row("수")])

    assert [s["id"] for s in data["sessions"]] == ["ex-수", "ex-월"]


def test_skipped_rows_stay_out_of_the_totals_too():
    """요일별 값의 합과 합계가 같아야 한다 — 한쪽에만 들어가면 화면이 어긋난다."""
    data = build_current_week(
        [_row("월", minutes=30), _row("?", id_="ex-broken", minutes=45)]
    )

    assert data["total_minutes"] == 30
    assert data["total_calories"] == 100
    assert sum(data["daily_minutes"]) == data["total_minutes"]
    assert sum(data["daily_calories"]) == data["total_calories"]
    assert len(data["daily_minutes"]) == 7


def test_broken_strength_row_adds_no_sets():
    data = build_current_week([_row("?", type_="strength", minutes=30)])

    assert data["strength_sets"] == [0] * 7
    assert data["strength_minutes"] == [0] * 7


def test_a_week_of_only_broken_rows_is_an_empty_week():
    data = build_current_week([_row("?"), _row("")])

    assert data["sessions"] == []
    assert data["total_minutes"] == 0
    assert data["daily_minutes"] == [0] * 7
    assert data["streak_days"] == 0


def test_skipping_leaves_a_log_line_naming_the_row(caplog):
    with caplog.at_level(logging.WARNING, logger="app.services.exercise_service"):
        build_current_week([_row("?", id_="ex-old-1")])

    assert any("ex-old-1" in record.getMessage() for record in caplog.records)


def test_healthy_rows_leave_no_log_line(caplog):
    with caplog.at_level(logging.WARNING, logger="app.services.exercise_service"):
        build_current_week([_row("월"), _row("일")])

    assert caplog.records == []


# ---- 엔드포인트 ----

def _h(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _member_tok(client) -> str:
    return client.post(
        "/v1/auth/login",
        data={"username": "jisu@oncare.com", "password": "oncare123"},
    ).json()["access_token"]


#: 데모 시드가 닿지 않는 먼 과거의 월요일.
_OLD_WEEK = "2019-03-04"


@pytest.fixture
def broken_row(db_session):
    from app.models.models import ExerciseSession

    row = ExerciseSession(
        id="ex-broken-day-label-3368",
        user_id="user-jisu",
        week_start=_OLD_WEEK,
        day_label="?",
        type="cardio",
        name="걷기",
        minutes=40,
        calories=120,
    )
    db_session.add(row)
    db_session.commit()
    yield row
    db_session.rollback()
    db_session.query(ExerciseSession).filter(
        ExerciseSession.id == "ex-broken-day-label-3368"
    ).delete(synchronize_session=False)
    db_session.commit()


def test_member_week_opens_with_a_broken_row_in_it(client, broken_row):
    r = client.get(
        "/v1/exercise/weeks/current",
        params={"week_start": _OLD_WEEK},
        headers=_h(_member_tok(client)),
    )

    assert r.status_code == 200, r.text
    body = r.json()
    assert broken_row.id not in {s["id"] for s in body["sessions"]}
    assert body["total_minutes"] == sum(body["daily_minutes"])


def test_member_period_opens_with_a_broken_row_in_it(client, broken_row):
    r = client.get(
        "/v1/exercise/weeks",
        params={"from": _OLD_WEEK, "to": _OLD_WEEK},
        headers=_h(_member_tok(client)),
    )

    assert r.status_code == 200, r.text
