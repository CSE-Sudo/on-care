"""회원이 자기 주간 리포트를 읽는 엔드포인트. (#2652)

회원 앱 결과지와 트레이너 웹 결과지가 같은 한 주를 두고 다른 수치를 말하면,
회원은 트레이너가 무엇을 보고 코칭하는지 알 수 없다. 이 파일이 지키는 것은
두 가지다 — 회원이 받는 값이 트레이너가 같은 회원을 두고 받는 값과 **같다**는 것,
그리고 트레이너 몫인 자동 초안(`message`)은 회원에게 **가지 않는다**는 것.

순수 로직(주 계산)은 DB 없이 돌고, 엔드포인트는 DB 가 있어야 한다
(로컬 skip, CI 실행).
"""
from __future__ import annotations

from datetime import date, timedelta
from uuid import uuid4

import pytest
from fastapi import HTTPException

from app.core import clock


def _h(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _login(client, email: str, password: str = "oncare123") -> str:
    return client.post(
        "/v1/auth/login", data={"username": email, "password": password}
    ).json()["access_token"]


def _this_monday() -> date:
    from app.services.trainer.reports import week_start_of

    return week_start_of(clock.today())


# ---- 순수 로직: 어느 주를 가리키나 ----

def test_default_week_is_this_week():
    """트레이너 리포트와 같은 기본값 — 결과지는 지금 지나는 주부터 연다."""
    from app.api.v1.member_coach import _my_report_week

    assert _my_report_week(None) == _this_monday()


def test_empty_week_start_means_the_same_as_not_sending_one():
    from app.api.v1.member_coach import _my_report_week

    assert _my_report_week("") == _my_report_week(None)


def test_any_day_in_a_week_lands_on_that_weeks_monday():
    from app.api.v1.member_coach import _my_report_week

    monday = date(2026, 9, 14)
    for offset in range(7):
        assert _my_report_week((monday + timedelta(days=offset)).isoformat()) == monday


def test_past_weeks_are_allowed():
    """지난 주들은 결과지의 `4주 평균 대비` 가 읽는다 — 막으면 비교가 비어 버린다."""
    from app.api.v1.member_coach import _my_report_week

    four_back = _this_monday() - timedelta(weeks=4)
    assert _my_report_week(four_back.isoformat()) == four_back


def test_future_week_is_rejected():
    """아직 오지 않은 주는 전부 0 인 한 장이 된다 — 트레이너 쪽과 같이 거부한다."""
    from app.api.v1.member_coach import _my_report_week

    with pytest.raises(HTTPException) as err:
        _my_report_week((_this_monday() + timedelta(days=7)).isoformat())
    assert err.value.status_code == 422


def test_this_weeks_sunday_is_still_this_week():
    """주 끝의 날짜를 보내도 미래 주가 아니다."""
    from app.api.v1.member_coach import _my_report_week

    sunday = _this_monday() + timedelta(days=6)
    assert _my_report_week(sunday.isoformat()) == _this_monday()


@pytest.mark.parametrize("bad", ["  ", "2026/09/14", "9월 14일", "오늘", "2026-13-01"])
def test_week_strings_in_other_shapes_are_rejected(bad):
    from app.api.v1.member_coach import _my_report_week

    with pytest.raises(HTTPException) as err:
        _my_report_week(bad)
    assert err.value.status_code == 422


# ---- 엔드포인트 ----

def test_member_reads_own_week(client):
    t = _login(client, "jisu@oncare.com")
    r = client.get("/v1/me/coach/weekly-report", headers=_h(t))
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["member_id"] == "user-jisu"
    assert body["week_start"] == _this_monday().isoformat()
    assert len(body["week_completion"]) == 7
    assert len(body["days"]) == 7
    assert len(body["calories_week"]) == 7


def test_member_never_receives_the_trainer_draft(client):
    """자동 초안은 트레이너가 손보고 보낼 글이다 — 회원에게 먼저 닿으면 안 된다."""
    t = _login(client, "jisu@oncare.com")
    body = client.get("/v1/me/coach/weekly-report", headers=_h(t)).json()
    assert body["message"] == ""


@pytest.mark.parametrize("weeks_back", [0, 1, 4])
def test_member_sees_the_same_numbers_as_the_trainer(client, weeks_back):
    """같은 회원·같은 주면 두 앱의 결과지가 같은 값을 읽는다."""
    week = (_this_monday() - timedelta(weeks=weeks_back)).isoformat()
    mt = _login(client, "jisu@oncare.com")
    tt = _login(client, "trainer@oncare.com")

    mine = client.get(
        "/v1/me/coach/weekly-report", params={"week_start": week}, headers=_h(mt)
    )
    theirs = client.get(
        "/v1/trainer/clients/user-jisu/report",
        params={"week_start": week},
        headers=_h(tt),
    )
    assert mine.status_code == 200, mine.text
    assert theirs.status_code == 200, theirs.text

    a, b = mine.json(), theirs.json()
    a.pop("message")
    b.pop("message")
    assert a == b


def test_mid_week_date_returns_that_weeks_monday(client):
    t = _login(client, "jisu@oncare.com")
    monday = _this_monday() - timedelta(weeks=1)
    r = client.get(
        "/v1/me/coach/weekly-report",
        params={"week_start": (monday + timedelta(days=3)).isoformat()},
        headers=_h(t),
    )
    assert r.status_code == 200, r.text
    assert r.json()["week_start"] == monday.isoformat()
    assert r.json()["week_end"] == (monday + timedelta(days=6)).isoformat()


def test_future_week_is_422(client):
    t = _login(client, "jisu@oncare.com")
    r = client.get(
        "/v1/me/coach/weekly-report",
        params={"week_start": (_this_monday() + timedelta(days=7)).isoformat()},
        headers=_h(t),
    )
    assert r.status_code == 422


def test_bad_date_is_422(client):
    t = _login(client, "jisu@oncare.com")
    r = client.get(
        "/v1/me/coach/weekly-report",
        params={"week_start": "2026-13-40"},
        headers=_h(t),
    )
    assert r.status_code == 422


def test_member_without_trainer_still_gets_a_sheet(client):
    """포인트로 교환한 리포트(#2022)는 담당 트레이너 없이도 열린다 — 수업 칸만 0 이다."""
    email = f"m-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register",
        json={"email": email, "password": "test-pw-1234", "name": "u"},
    )
    t = _login(client, email, "test-pw-1234")
    r = client.get("/v1/me/coach/weekly-report", headers=_h(t))
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["sessions_booked"] == 0
    assert body["sessions_done"] == 0
    assert body["completion_avg"] is None
    assert body["message"] == ""


def test_another_members_week_cannot_be_named(client):
    """경로에 회원 id 가 없다 — 토큰의 주인만 자기 주를 읽는다."""
    t = _login(client, "jisu@oncare.com")
    r = client.get(
        "/v1/me/coach/weekly-report",
        params={"member_id": "user-minsu"},
        headers=_h(t),
    )
    assert r.status_code == 200
    assert r.json()["member_id"] == "user-jisu"


def test_trainer_token_is_rejected(client):
    tt = _login(client, "trainer@oncare.com")
    r = client.get("/v1/me/coach/weekly-report", headers=_h(tt))
    assert r.status_code == 403

