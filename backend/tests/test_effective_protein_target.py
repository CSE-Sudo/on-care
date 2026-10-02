"""실효 단백질 목표 — 영양 카드·리포트 막대와 식단 분석이 같은 분모를 쓴다. (#2898)

개인 단백질 목표가 없을 때 화면은 100g, 식단 분석·조언은 체중 × 1.2g(없으면 60g)을
써서 같은 날을 서로 다르게 판단했다. 서버가 분석과 같은 규칙으로 계산한 값을
프로필·주간 리포트 응답에 싣고, 두 앱이 그 값을 분모로 쓴다.

앞부분은 DB 없이 돌고, 엔드포인트 검사는 `client` 픽스처를 쓴다.
"""
from __future__ import annotations

from types import SimpleNamespace
from uuid import uuid4

import pytest

from app.services.diet_coach_inputs import (
    DEFAULT_PROTEIN_G,
    PROTEIN_G_PER_KG,
    effective_protein_g,
    targets_of,
)


def _profile(**kw):
    base = dict(
        daily_protein_g=None,
        weight_kg=None,
        daily_calories=None,
        daily_sodium_mg=None,
        daily_sugar_g=None,
    )
    base.update(kw)
    return SimpleNamespace(**base)


# ---- 규칙 (DB 불필요) ----


def test_rule_constants_are_what_the_apps_mirror():
    """두 앱이 옛 응답일 때 같은 규칙을 계산한다 — 상수가 바뀌면 앱도 바꿔야 한다."""
    assert PROTEIN_G_PER_KG == 1.2
    assert DEFAULT_PROTEIN_G == 60


def test_personal_goal_wins():
    assert effective_protein_g(_profile(daily_protein_g=130, weight_kg=70)) == 130


def test_weight_is_used_when_there_is_no_goal():
    assert effective_protein_g(_profile(weight_kg=72)) == 86  # 86.4
    assert effective_protein_g(_profile(weight_kg=55.5)) == 67  # 66.6


def test_default_when_neither_is_known():
    assert effective_protein_g(_profile()) == 60
    assert effective_protein_g(None) == 60


def test_zero_goal_is_treated_as_unset():
    """분석 쪽이 원래 0 을 '없음'으로 읽었다 — 그 규칙을 그대로 둔다."""
    assert effective_protein_g(_profile(daily_protein_g=0, weight_kg=50)) == 60


@pytest.mark.parametrize(
    "profile",
    [None, _profile(), _profile(weight_kg=80), _profile(daily_protein_g=110)],
)
def test_diet_analysis_uses_the_same_number(profile):
    """분석·조언이 읽는 `targets_of` 와 응답 값이 갈라지지 않는다."""
    assert targets_of(profile).protein_g == effective_protein_g(profile)


# ---- 엔드포인트 (DB 필요) ----


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _new_member(client) -> str:
    email = f"protein-{uuid4().hex[:8]}@oncare.com"
    password = "protein-pw-1234"
    r = client.post(
        "/v1/auth/register",
        json={"email": email, "password": password, "name": "단백질 목표"},
    )
    assert r.status_code == 201, r.text
    return client.post(
        "/v1/auth/login", data={"username": email, "password": password}
    ).json()["access_token"]


def _trainer(client) -> str:
    return client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    ).json()["access_token"]


def test_member_profile_carries_the_effective_target(client):
    token = _new_member(client)
    me = client.get("/v1/users/me/profile", headers=_auth(token)).json()
    # 목표·체중이 없는 새 회원 — 개인 목표 칸은 비어 있고 실효값은 60g.
    assert me["daily_protein_g"] is None
    assert me["effective_daily_protein_g"] == 60

    r = client.put("/v1/users/me", json={"weight_kg": 72}, headers=_auth(token))
    assert r.status_code == 200, r.text
    assert r.json()["effective_daily_protein_g"] == 86
    assert r.json()["daily_protein_g"] is None

    r = client.put(
        "/v1/users/me/health-goals",
        json={"daily_protein_g": 130},
        headers=_auth(token),
    )
    assert r.status_code == 200, r.text
    assert r.json()["effective_daily_protein_g"] == 130

    # 목표를 지우면 다시 체중 기준이다.
    r = client.put(
        "/v1/users/me/health-goals",
        json={"daily_protein_g": None},
        headers=_auth(token),
    )
    assert r.status_code == 200, r.text
    assert r.json()["effective_daily_protein_g"] == 86


def test_trainer_health_profile_and_report_carry_the_effective_target(client):
    token = _trainer(client)
    url = "/v1/trainer/clients/user-jisu/health-profile"
    before = client.get(url, headers=_auth(token)).json()
    try:
        r = client.put(
            url,
            json={"daily_protein_g": None, "weight_kg": 70},
            headers=_auth(token),
        )
        assert r.status_code == 200, r.text
        assert r.json()["daily_protein_g"] is None
        assert r.json()["effective_daily_protein_g"] == 84

        report = client.get(
            "/v1/trainer/clients/user-jisu/report",
            params={"week_start": "2026-08-03"},
            headers=_auth(token),
        ).json()
        # 개인 목표 칸은 그대로 비어 있고(판정은 기본값과 회원 목표를 가른다),
        # 막대 분모는 분석과 같은 실효값이다.
        assert report["protein_target"] is None
        assert report["effective_protein_target"] == 84

        r = client.put(url, json={"daily_protein_g": 125}, headers=_auth(token))
        assert r.json()["effective_daily_protein_g"] == 125
        report = client.get(
            "/v1/trainer/clients/user-jisu/report",
            params={"week_start": "2026-08-03"},
            headers=_auth(token),
        ).json()
        assert report["protein_target"] == 125
        assert report["effective_protein_target"] == 125
    finally:
        client.put(
            url,
            json={
                "daily_protein_g": before["daily_protein_g"],
                "weight_kg": before["weight_kg"],
            },
            headers=_auth(token),
        )
