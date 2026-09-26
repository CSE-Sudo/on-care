"""트레이너가 ② 에서 고른 다음 주 목표. (#2232)

이 표가 지키는 규칙은 하나다 — **고른 주가 아니라 지켜야 할 주에 저장한다.**
다음 주 리포트의 `③ 지난 주 목표 달성` 이 자기 주의 목표를 그대로 꺼내
판정하기 때문이다. 회수되지 않는 목표는 공수표라, 고르는 화면만 있고 이
경로가 없으면 기능이 반쪽이다.

DB 필요 (로컬 skip, CI 실행).
"""
from __future__ import annotations

from datetime import date, timedelta

import pytest


def _h(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _trainer_tok(client) -> str:
    return client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    ).json()["access_token"]


def _member_tok(client) -> str:
    return client.post(
        "/v1/auth/login",
        data={"username": "jisu@oncare.com", "password": "oncare123"},
    ).json()["access_token"]


MEMBER = "user-jisu"
GOALS = "/v1/trainer/clients/user-jisu/report/goals"


def _next_week(week: str) -> str:
    return (date.fromisoformat(week) + timedelta(days=7)).isoformat()


# ---- 순수 로직 ----

def test_goals_are_stored_on_the_week_they_apply_to():
    """월요일에 고른 목표가 그 주가 아니라 다음 주 월요일에 붙는다."""
    from app.services.trainer_service import week_start_of

    assert week_start_of(date(2026, 9, 14)) + timedelta(days=7) == date(2026, 9, 21)


def test_any_day_of_the_picking_week_applies_to_the_same_next_week():
    """주 중간에 고쳐도 적용되는 주는 하나다 — 목요일에 고친 목표가 목요일부터
    시작하는 '주' 에 붙으면 회수하는 쪽이 그 주를 찾지 못한다."""
    from app.services.trainer_service import week_start_of

    for offset in range(7):
        day = date(2026, 9, 14) + timedelta(days=offset)
        assert week_start_of(day) + timedelta(days=7) == date(2026, 9, 21)


# ---- 엔드포인트 ----

def test_a_week_with_nothing_picked_is_not_an_error(client):
    """지난 주에 아무것도 고르지 않은 것은 정상이다 — 404 면 ③ 칸이 사라진다."""
    t = _trainer_tok(client)
    r = client.get(GOALS, params={"week_start": "2019-01-07"}, headers=_h(t))
    assert r.status_code == 200, r.text
    assert r.json()["goals"] == []
    assert r.json()["week_start"] == "2019-01-07"


def test_saved_goals_come_back_on_the_following_week(client):
    t = _trainer_tok(client)
    week = "2026-04-06"
    r = client.put(
        GOALS,
        json={"week_start": week, "goals": ["주 2회 하체 추가", "저녁 단백질 30g 이상"]},
        headers=_h(t),
    )
    assert r.status_code == 200, r.text
    # 응답이 **적용된 주**를 말한다 — 앱이 저장 결과를 그대로 믿을 수 있다.
    assert r.json()["week_start"] == _next_week(week)

    got = client.get(
        GOALS, params={"week_start": _next_week(week)}, headers=_h(t)
    ).json()
    assert got["goals"] == ["주 2회 하체 추가", "저녁 단백질 30g 이상"]


def test_the_week_they_were_picked_in_stays_empty(client):
    """고른 주에도 같은 목표가 서면, 같은 목표가 두 주 연속 ③ 에 나온다."""
    t = _trainer_tok(client)
    # 앞뒤 주에 아무도 쓰지 않는 주를 고른다 — 다른 테스트가 남긴 목표가
    # 여기 섞이면 이 테스트는 자기가 저장한 것을 못 본 척하게 된다.
    week = "2026-07-06"
    client.put(GOALS, json={"week_start": week, "goals": ["계단 이용"]}, headers=_h(t))

    assert (
        client.get(GOALS, params={"week_start": week}, headers=_h(t)).json()["goals"]
        == []
    )


def test_a_mid_week_day_applies_to_the_same_next_week(client):
    """목요일에 고쳐도 적용되는 주는 그 주의 다음 주 하나다."""
    t = _trainer_tok(client)
    r = client.put(
        GOALS, json={"week_start": "2026-04-23", "goals": ["물 2L"]}, headers=_h(t)
    )
    assert r.json()["week_start"] == "2026-04-27"


def test_saving_again_replaces_the_whole_list(client):
    """화면이 들고 있는 목록 전체로 바꾼다 — 뺀 목표가 다음 주에 살아 있으면
    트레이너는 목표를 뺄 방법이 없다."""
    t = _trainer_tok(client)
    week = "2026-05-04"
    client.put(GOALS, json={"week_start": week, "goals": ["A", "B", "C"]}, headers=_h(t))
    client.put(GOALS, json={"week_start": week, "goals": ["B"]}, headers=_h(t))

    assert (
        client.get(
            GOALS, params={"week_start": _next_week(week)}, headers=_h(t)
        ).json()["goals"]
        == ["B"]
    )


def test_clearing_every_goal_is_allowed(client):
    """한 주를 목표 없이 보낼 수도 있다 — 억지로 채운 목표는 다음 주에 회수될 때
    아무 의미가 없다."""
    t = _trainer_tok(client)
    week = "2026-05-11"
    client.put(GOALS, json={"week_start": week, "goals": ["A"]}, headers=_h(t))
    r = client.put(GOALS, json={"week_start": week, "goals": []}, headers=_h(t))

    assert r.status_code == 200, r.text
    assert r.json()["goals"] == []


def test_order_is_kept(client):
    """③ 이 1·2·3 번호를 붙여 보여 준다 — 순서가 섞이면 번호가 매주 달라진다."""
    t = _trainer_tok(client)
    week = "2026-05-18"
    goals = ["첫째", "둘째", "셋째", "넷째"]
    client.put(GOALS, json={"week_start": week, "goals": goals}, headers=_h(t))

    assert (
        client.get(
            GOALS, params={"week_start": _next_week(week)}, headers=_h(t)
        ).json()["goals"]
        == goals
    )


def test_blank_and_whitespace_goals_are_dropped(client):
    t = _trainer_tok(client)
    week = "2026-05-25"
    client.put(
        GOALS,
        json={"week_start": week, "goals": ["  진짜 목표  ", "", "   "]},
        headers=_h(t),
    )

    assert (
        client.get(
            GOALS, params={"week_start": _next_week(week)}, headers=_h(t)
        ).json()["goals"]
        == ["진짜 목표"]
    )


def test_the_same_goal_twice_becomes_one_line(client):
    """같은 목표가 두 줄로 서면 다음 주 ③ 이 같은 판정을 두 번 적는다."""
    t = _trainer_tok(client)
    week = "2026-06-01"
    client.put(
        GOALS,
        json={"week_start": week, "goals": ["스트레칭", "스트레칭", "스트레칭 "]},
        headers=_h(t),
    )

    assert (
        client.get(
            GOALS, params={"week_start": _next_week(week)}, headers=_h(t)
        ).json()["goals"]
        == ["스트레칭"]
    )


def test_a_goal_longer_than_the_limit_is_refused(client):
    t = _trainer_tok(client)
    r = client.put(
        GOALS, json={"week_start": "2026-06-08", "goals": ["가" * 121]}, headers=_h(t)
    )
    assert r.status_code == 422


def test_too_many_goals_are_refused(client):
    """스무 줄짜리 목표 목록은 다음 주에 아무도 회수하지 않는다."""
    t = _trainer_tok(client)
    r = client.put(
        GOALS,
        json={"week_start": "2026-06-08", "goals": [f"목표 {i}" for i in range(21)]},
        headers=_h(t),
    )
    assert r.status_code == 422


def test_week_start_defaults_to_this_week(client):
    """날짜를 빼고 보내면 지금 보고 있는 주로 본다 — 적용은 그 다음 주다."""
    from app.core import clock
    from app.services.trainer_service import week_start_of

    t = _trainer_tok(client)
    r = client.put(GOALS, json={"goals": ["기본 주 확인"]}, headers=_h(t))
    assert r.status_code == 200, r.text
    assert r.json()["week_start"] == (
        week_start_of(clock.today()) + timedelta(days=7)
    ).isoformat()


@pytest.mark.parametrize("bad", ["2026-13-01", "오늘", "2026/06/08"])
def test_an_unreadable_week_is_refused(client, bad):
    t = _trainer_tok(client)
    r = client.put(GOALS, json={"week_start": bad, "goals": ["A"]}, headers=_h(t))
    assert r.status_code == 422


def test_a_member_who_is_not_their_client_is_out_of_reach(client):
    t = _trainer_tok(client)
    assert (
        client.get(
            "/v1/trainer/clients/user-not-mine/report/goals", headers=_h(t)
        ).status_code
        == 404
    )
    assert (
        client.put(
            "/v1/trainer/clients/user-not-mine/report/goals",
            json={"goals": ["A"]},
            headers=_h(t),
        ).status_code
        == 404
    )


def test_a_member_token_cannot_set_their_own_goals(client):
    """목표는 트레이너가 정한다 — 회원이 자기 목표를 고쳐 쓰면 ③ 의 판정이
    누구의 약속인지 알 수 없어진다."""
    m = _member_tok(client)
    assert client.get(GOALS, headers=_h(m)).status_code in (401, 403)
    assert (
        client.put(GOALS, json={"goals": ["A"]}, headers=_h(m)).status_code
        in (401, 403)
    )


def test_goals_need_a_signed_in_trainer(client):
    assert client.get(GOALS).status_code == 401
    assert client.put(GOALS, json={"goals": ["A"]}).status_code == 401
