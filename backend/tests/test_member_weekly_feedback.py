"""회원이 한 주를 끝내며 남기는 세 문항. (#2232)

수치만 보면 같은 한 주가 `게으름` 으로도 `과부하·일정 문제` 로도 읽힌다.
그 둘은 다음 주 처방이 정반대라, 갈림길은 회원 본인에게 물어야만 정해진다.
이 파일이 지키는 것은 그 물음이 **한 주에 하나의 답으로만 남는다**는 것과,
답이 없는 주가 오류가 아니라 정상 상태라는 것이다.

순수 로직(주 계산·값 검증)은 DB 없이 돌고, 엔드포인트는 DB 가 있어야 한다
(로컬 skip, CI 실행).
"""
from __future__ import annotations

from datetime import date, timedelta

import pytest
from fastapi import HTTPException

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


def _last_week() -> str:
    from app.services.trainer_service import week_start_of

    return (week_start_of(clock.today()) - timedelta(days=7)).isoformat()


# ---- 순수 로직: 어느 주를 가리키나 ----

def test_default_week_is_last_week_not_this_one():
    """기본값이 지난 주인 까닭 — 끝나지도 않은 주의 `한 주 컨디션` 은 물을 수 없다."""
    from app.api.v1.member_coach import _feedback_week
    from app.services.trainer_service import week_start_of

    assert _feedback_week(None) == week_start_of(clock.today()) - timedelta(days=7)


def test_default_week_is_a_monday():
    from app.api.v1.member_coach import _feedback_week

    assert _feedback_week(None).weekday() == 0


def test_any_day_in_a_week_lands_on_that_weeks_monday():
    """앱이 일요일에 물으면 일요일 날짜를 보낼 수도 있다 — 같은 주면 같은 답이다."""
    from app.api.v1.member_coach import _feedback_week

    monday = date(2026, 9, 14)
    for offset in range(7):
        assert _feedback_week((monday + timedelta(days=offset)).isoformat()) == monday


def test_bad_week_start_is_rejected_not_silently_defaulted():
    """못 읽는 날짜를 조용히 이번 주로 접으면, 엉뚱한 주에 답이 쌓인다."""
    from app.api.v1.member_coach import _feedback_week

    with pytest.raises(HTTPException) as err:
        _feedback_week("2026-13-40")
    assert err.value.status_code == 422


@pytest.mark.parametrize("bad", ["  ", "2026/09/14", "9월 14일", "오늘", "2026-13-01"])
def test_week_strings_in_other_shapes_are_rejected(bad):
    """받는 표기는 `YYYY-MM-DD` 하나다 — 관대하게 읽어 주면 어느 주에 들어갔는지
    아무도 모르게 된다."""
    from app.api.v1.member_coach import _feedback_week

    with pytest.raises(HTTPException):
        _feedback_week(bad)


def test_empty_week_start_means_the_same_as_not_sending_one():
    """앱의 빈 입력칸이 오류가 되지는 않는다 — 값을 안 준 것과 같게 본다."""
    from app.api.v1.member_coach import _feedback_week

    assert _feedback_week("") == _feedback_week(None)


# ---- 순수 로직: 고를 수 있는 값 ----

def test_allowed_values_match_the_database_constraint():
    """서비스와 DB 가 같은 목록을 봐야 한다 — 한쪽만 늘리면 저장이 DB 에서 막힌다."""
    from app.models.models import MemberWeeklyFeedback
    from app.services.trainer_service import (
        _WEEKLY_FEEDBACK_CONDITIONS,
        _WEEKLY_FEEDBACK_INTENSITIES,
    )

    sql = " ".join(
        str(c.sqltext) for c in MemberWeeklyFeedback.__table__.constraints
        if hasattr(c, "sqltext")
    )
    for value in _WEEKLY_FEEDBACK_CONDITIONS + _WEEKLY_FEEDBACK_INTENSITIES:
        assert f"'{value}'" in sql, f"{value} 가 DB 제약에 없다"


def test_condition_scale_runs_from_best_to_worst():
    """화면이 이 순서를 그대로 줄로 세운다 — 섞이면 `좋음` 이 `나쁨` 왼쪽이 아니게 된다."""
    from app.services.trainer_service import _WEEKLY_FEEDBACK_CONDITIONS

    assert _WEEKLY_FEEDBACK_CONDITIONS == ("great", "good", "ok", "tired", "bad")


def test_intensity_scale_runs_from_too_easy_to_too_hard():
    """양쪽 끝이 모두 있어야 한다. `힘들었나` 만 물으면 너무 쉬웠던 주가 `괜찮음`
    으로 접혀, 다음 주에도 같은 무게가 나간다."""
    from app.services.trainer_service import _WEEKLY_FEEDBACK_INTENSITIES

    assert _WEEKLY_FEEDBACK_INTENSITIES == ("too_easy", "right", "hard", "too_hard")


def test_intensity_scale_has_a_middle():
    """가운데 값이 없으면 `딱 맞았다` 를 말할 수 없어, 모든 주가 문제로 보인다."""
    from app.services.trainer_service import _WEEKLY_FEEDBACK_INTENSITIES

    assert "right" in _WEEKLY_FEEDBACK_INTENSITIES


# ---- 엔드포인트: 회원 쪽 ----

def test_unanswered_week_is_not_an_error(client):
    t = _member_tok(client)
    r = client.get(
        "/v1/me/coach/weekly-feedback",
        params={"week_start": "2020-01-06"},
        headers=_h(t),
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["submitted"] is False
    assert body["week_start"] == "2020-01-06"
    assert body["condition"] == ""


def test_saving_then_reading_returns_the_same_answer(client):
    t = _member_tok(client)
    week = "2026-01-05"
    r = client.put(
        "/v1/me/coach/weekly-feedback",
        json={
            "week_start": week,
            "condition": "tired",
            "intensity": "too_hard",
            "pain_area": "왼쪽 어깨",
            "pain_on": "2026-01-08",
            "note": "야근이 겹쳤어요",
        },
        headers=_h(t),
    )
    assert r.status_code == 200, r.text
    assert r.json()["submitted"] is True

    got = client.get(
        "/v1/me/coach/weekly-feedback", params={"week_start": week}, headers=_h(t)
    ).json()
    assert got["condition"] == "tired"
    assert got["intensity"] == "too_hard"
    assert got["pain_area"] == "왼쪽 어깨"
    assert got["note"] == "야근이 겹쳤어요"
    assert got["submitted_at"] is not None


def test_sending_twice_overwrites_instead_of_stacking(client):
    """한 주에 대한 회원의 말은 마지막 것 하나다."""
    t = _member_tok(client)
    week = "2026-01-12"
    for condition in ("bad", "good"):
        r = client.put(
            "/v1/me/coach/weekly-feedback",
            json={"week_start": week, "condition": condition, "intensity": "right"},
            headers=_h(t),
        )
        assert r.status_code == 200, r.text

    assert (
        client.get(
            "/v1/me/coach/weekly-feedback", params={"week_start": week}, headers=_h(t)
        ).json()["condition"]
        == "good"
    )


def test_a_mid_week_date_saves_onto_that_weeks_monday(client):
    """일요일에 물어 일요일 날짜로 보내도, 그 주 월요일 한 칸에 들어간다."""
    t = _member_tok(client)
    client.put(
        "/v1/me/coach/weekly-feedback",
        json={"week_start": "2026-01-25", "condition": "ok", "intensity": "right"},
        headers=_h(t),
    )

    got = client.get(
        "/v1/me/coach/weekly-feedback",
        params={"week_start": "2026-01-19"},
        headers=_h(t),
    ).json()
    assert got["submitted"] is True
    assert got["week_start"] == "2026-01-19"


def test_week_start_defaults_to_last_week_on_both_sides(client):
    """앱이 날짜를 빼고 보내도, 저장과 읽기가 같은 주를 가리킨다."""
    t = _member_tok(client)
    r = client.put(
        "/v1/me/coach/weekly-feedback",
        json={"condition": "great", "intensity": "too_easy"},
        headers=_h(t),
    )
    assert r.status_code == 200, r.text
    assert r.json()["week_start"] == _last_week()

    got = client.get("/v1/me/coach/weekly-feedback", headers=_h(t)).json()
    assert got["submitted"] is True
    assert got["condition"] == "great"


@pytest.mark.parametrize("bad", ["fine", "GREAT", "", "최고"])
def test_unknown_condition_is_refused(client, bad):
    t = _member_tok(client)
    r = client.put(
        "/v1/me/coach/weekly-feedback",
        json={"week_start": "2026-02-02", "condition": bad, "intensity": "right"},
        headers=_h(t),
    )
    assert r.status_code == 422, r.text


@pytest.mark.parametrize("bad", ["easy", "RIGHT", "", "조금 힘듦"])
def test_unknown_intensity_is_refused(client, bad):
    t = _member_tok(client)
    r = client.put(
        "/v1/me/coach/weekly-feedback",
        json={"week_start": "2026-02-02", "condition": "ok", "intensity": bad},
        headers=_h(t),
    )
    assert r.status_code == 422, r.text


def test_refused_answer_leaves_no_row_behind(client):
    """거절된 답이 반쯤 저장되면, 다음 주에 트레이너가 빈 칸을 답으로 읽는다."""
    t = _member_tok(client)
    week = "2026-02-09"
    client.put(
        "/v1/me/coach/weekly-feedback",
        json={"week_start": week, "condition": "nope", "intensity": "right"},
        headers=_h(t),
    )

    assert (
        client.get(
            "/v1/me/coach/weekly-feedback", params={"week_start": week}, headers=_h(t)
        ).json()["submitted"]
        is False
    )


def test_pain_day_is_dropped_when_no_pain_area_was_given(client):
    """아픈 곳을 안 적었는데 날짜만 남으면, 화면이 `(빈칸) 이 아팠다` 를 그린다."""
    t = _member_tok(client)
    week = "2026-02-16"
    r = client.put(
        "/v1/me/coach/weekly-feedback",
        json={
            "week_start": week,
            "condition": "good",
            "intensity": "right",
            "pain_area": "   ",
            "pain_on": "2026-02-18",
        },
        headers=_h(t),
    )
    assert r.status_code == 200, r.text
    assert r.json()["pain_area"] == ""
    assert r.json()["pain_on"] == ""


def test_surrounding_spaces_do_not_become_part_of_the_answer(client):
    t = _member_tok(client)
    week = "2026-02-23"
    r = client.put(
        "/v1/me/coach/weekly-feedback",
        json={
            "week_start": week,
            "condition": "good",
            "intensity": "hard",
            "pain_area": "  오른쪽 무릎  ",
            "note": "  계단에서 무리했어요  ",
        },
        headers=_h(t),
    )
    assert r.json()["pain_area"] == "오른쪽 무릎"
    assert r.json()["note"] == "계단에서 무리했어요"


def test_note_longer_than_the_limit_is_refused(client):
    """한 줄 답이 길어지면 매주 돌아오지 않는다 — 길이는 화면이 아니라 여기서 막는다."""
    t = _member_tok(client)
    r = client.put(
        "/v1/me/coach/weekly-feedback",
        json={
            "week_start": "2026-03-02",
            "condition": "ok",
            "intensity": "right",
            "note": "가" * 501,
        },
        headers=_h(t),
    )
    assert r.status_code == 422


def test_pain_area_longer_than_the_limit_is_refused(client):
    t = _member_tok(client)
    r = client.put(
        "/v1/me/coach/weekly-feedback",
        json={
            "week_start": "2026-03-02",
            "condition": "ok",
            "intensity": "right",
            "pain_area": "가" * 41,
        },
        headers=_h(t),
    )
    assert r.status_code == 422


def test_reading_without_a_token_falls_back_to_the_demo_member(client):
    """읽기는 다른 회원 화면과 같은 규칙을 따른다 — 로그인 없이 도는 데모에서
    이 칸만 빈 채로 서면, 데모가 기능을 못 보여 준다."""
    r = client.get("/v1/me/coach/weekly-feedback")
    assert r.status_code == 200, r.text
    assert "submitted" in r.json()


def test_writing_without_a_token_is_refused(client):
    """쓰기는 다르다 — 누가 낸 답인지 모르는 채로 남으면 트레이너가 엉뚱한
    회원의 한 주를 읽는다."""
    r = client.put(
        "/v1/me/coach/weekly-feedback",
        json={"condition": "good", "intensity": "right"},
    )
    assert r.status_code == 401


def test_trainer_account_cannot_answer_as_a_member(client):
    """트레이너가 자기 계정으로 회원 답을 낼 수는 없다 — 받는 사람이 자기 자신이 된다."""
    t = _trainer_tok(client)
    r = client.put(
        "/v1/me/coach/weekly-feedback",
        json={"condition": "good", "intensity": "right"},
        headers=_h(t),
    )
    assert r.status_code in (403, 404)


# ---- 엔드포인트: 트레이너 쪽 ----

def test_trainer_reads_the_answer_their_client_sent(client):
    """리포트 ② 칸이 읽는 값이다."""
    m = _member_tok(client)
    week = "2026-03-09"
    client.put(
        "/v1/me/coach/weekly-feedback",
        json={
            "week_start": week,
            "condition": "tired",
            "intensity": "too_hard",
            "note": "3일차부터 힘들었어요",
        },
        headers=_h(m),
    )

    t = _trainer_tok(client)
    r = client.get(
        "/v1/trainer/clients/user-jisu/report/member-feedback",
        params={"week_start": week},
        headers=_h(t),
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["submitted"] is True
    assert body["condition"] == "tired"
    assert body["note"] == "3일차부터 힘들었어요"


def test_trainer_sees_not_submitted_instead_of_an_error(client):
    """답이 없는 주에 404 를 주면 리포트의 ② 칸이 통째로 사라진다."""
    t = _trainer_tok(client)
    r = client.get(
        "/v1/trainer/clients/user-jisu/report/member-feedback",
        params={"week_start": "2019-01-07"},
        headers=_h(t),
    )
    assert r.status_code == 200, r.text
    assert r.json()["submitted"] is False


def test_trainer_cannot_read_a_member_who_is_not_their_client(client):
    t = _trainer_tok(client)
    r = client.get(
        "/v1/trainer/clients/user-not-mine/report/member-feedback",
        headers=_h(t),
    )
    assert r.status_code == 404


def test_member_token_cannot_reach_the_trainer_endpoint(client):
    m = _member_tok(client)
    r = client.get(
        "/v1/trainer/clients/user-jisu/report/member-feedback", headers=_h(m)
    )
    assert r.status_code in (401, 403)
