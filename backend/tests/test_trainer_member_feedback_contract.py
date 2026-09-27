"""트레이너 웹이 읽는 회원 주간 피드백 응답의 모양. (#2286)

트레이너 웹 실서버 저장소는 `GET /trainer/clients/{id}/report/member-feedback`
응답의 키를 이름으로 읽는다(`submitted`·`condition`·`intensity`·`pain_area`·
`pain_on`·`note`·`week_start`). 키 이름이 한쪽에서만 바뀌면 리포트 ① 칸이
오류 없이 조용히 "아직 받지 못함" 으로 돌아가므로, 그 계약을 여기서 묶는다.

순수 스키마 검사는 DB 없이 돌고, 엔드포인트는 DB 가 있어야 한다
(로컬 skip, CI 실행).
"""
from __future__ import annotations

from datetime import date, timedelta

from app.core import clock


def _h(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _member_tok(client) -> str:
    return client.post(
        "/v1/auth/login",
        data={"username": "jisu@oncare.com", "password": "oncare123"},
    ).json()["access_token"]


def _trainer_tok(client) -> str:
    return client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    ).json()["access_token"]


_PATH = "/v1/trainer/clients/user-jisu/report/member-feedback"


# ---- 순수 스키마: 웹이 읽는 키 ----

def test_response_keys_are_the_ones_the_trainer_web_reads():
    from app.schemas.trainer_api import MemberWeeklyFeedbackOut

    assert set(MemberWeeklyFeedbackOut.model_fields) == {
        "week_start",
        "submitted",
        "condition",
        "intensity",
        "pain_area",
        "pain_on",
        "note",
        "submitted_at",
    }


def test_not_submitted_defaults_are_empty_strings_not_nulls():
    """웹은 문자열이 아닌 값을 빈 값으로 읽지만, 서버가 기본값을 빈 문자열로
    주면 두 쪽의 `답 없음` 해석이 어긋날 일이 없다."""
    from app.schemas.trainer_api import MemberWeeklyFeedbackOut

    body = MemberWeeklyFeedbackOut(week_start="2026-09-14").model_dump()
    assert body["submitted"] is False
    for key in ("condition", "intensity", "pain_area", "pain_on", "note"):
        assert body[key] == "", key
    assert body["submitted_at"] is None


# ---- 엔드포인트 ----

def test_trainer_reads_pain_area_and_day(client):
    """통증은 부위와 날짜가 함께 온다 — 카드가 `오른 무릎 (9월 17일)` 로 적는다."""
    m = _member_tok(client)
    week = "2026-03-16"
    r = client.put(
        "/v1/me/coach/weekly-feedback",
        json={
            "week_start": week,
            "condition": "ok",
            "intensity": "hard",
            "pain_area": "오른 무릎",
            "pain_on": "2026-03-19",
        },
        headers=_h(m),
    )
    assert r.status_code == 200, r.text

    t = _trainer_tok(client)
    r = client.get(_PATH, params={"week_start": week}, headers=_h(t))
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["submitted"] is True
    assert body["condition"] == "ok"
    assert body["intensity"] == "hard"
    assert body["pain_area"] == "오른 무릎"
    assert body["pain_on"] == "2026-03-19"
    assert body["week_start"] == week


def test_mid_week_date_answers_with_that_weeks_monday(client):
    """웹은 응답의 `week_start` 를 믿는다 — 주 중간 날짜로 물어도 월요일로 온다."""
    m = _member_tok(client)
    monday = date(2026, 3, 23)
    client.put(
        "/v1/me/coach/weekly-feedback",
        json={
            "week_start": monday.isoformat(),
            "condition": "good",
            "intensity": "right",
        },
        headers=_h(m),
    )

    t = _trainer_tok(client)
    r = client.get(
        _PATH,
        params={"week_start": (monday + timedelta(days=3)).isoformat()},
        headers=_h(t),
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["week_start"] == monday.isoformat()
    assert body["submitted"] is True
    assert body["condition"] == "good"


def test_pain_day_without_area_is_not_returned(client):
    """부위 없이 온 날짜는 저장하지 않는다 — 웹도 같은 규칙으로 버린다."""
    m = _member_tok(client)
    week = "2026-03-30"
    client.put(
        "/v1/me/coach/weekly-feedback",
        json={
            "week_start": week,
            "condition": "great",
            "intensity": "right",
            "pain_area": "  ",
            "pain_on": "2026-04-01",
        },
        headers=_h(m),
    )

    t = _trainer_tok(client)
    body = client.get(_PATH, params={"week_start": week}, headers=_h(t)).json()
    assert body["pain_area"] == ""
    assert body["pain_on"] == ""


def test_not_submitted_week_answers_with_defaults(client):
    """답이 없는 주도 모든 키가 온다 — 웹은 `submitted` 만 보고 칸을 비운다."""
    t = _trainer_tok(client)
    r = client.get(_PATH, params={"week_start": "2019-01-09"}, headers=_h(t))
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["submitted"] is False
    assert body["week_start"] == "2019-01-07"
    assert body["condition"] == ""
    assert body["intensity"] == ""


def test_future_week_is_rejected(client):
    """오지 않은 주는 리포트 본문과 같은 규칙으로 막힌다."""
    from app.services.trainer_service import week_start_of

    t = _trainer_tok(client)
    next_week = week_start_of(clock.today()) + timedelta(days=7)
    r = client.get(
        _PATH, params={"week_start": next_week.isoformat()}, headers=_h(t)
    )
    assert r.status_code == 422


def test_malformed_week_is_rejected(client):
    t = _trainer_tok(client)
    r = client.get(_PATH, params={"week_start": "2026/03/16"}, headers=_h(t))
    assert r.status_code == 422
