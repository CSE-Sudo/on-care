"""운동 이름 기반 소모 칼로리 — 참조표·체중·폴백. (#1312)

이 스위트가 지키는 것은 넷이다.

1. 운동 이름이 종목 참조표에 붙으면 값이 **이름과 체중**을 따라간다.
2. 붙지 않으면 유형 평균으로 떨어지고, 그렇다고 **말한다**(`source`).
3. 저장된 기록의 칼로리는 서버가 계산한다 — 앱이 보낸 값을 믿지 않아야 회원
   앱·트레이너 앱·서버가 같은 값을 본다.
4. 참조표가 비어 있거나 체중을 몰라도 **저장은 실패하지 않는다.**
"""
from __future__ import annotations

from datetime import timedelta
from uuid import uuid4

import pytest

from app.core import clock
from app.services import exercise_types
from app.services.exercise_catalog import energy, matcher
from app.services.exercise_service import WEEKDAY_LABELS
from tests.exercise_helpers import post_exercise


def _day(label: str) -> str:
    today = clock.today()
    monday = today - timedelta(days=today.weekday())
    return (monday + timedelta(days=WEEKDAY_LABELS.index(label))).isoformat()


def _login(client) -> dict:
    email = f"cal-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register",
        json={"email": email, "password": "test-pw-1234", "name": "u"},
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "test-pw-1234"}
    ).json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


def _with_weight(client, headers: dict, weight_kg: float) -> dict:
    client.post(
        "/v1/users/me/onboarding",
        json={"name": "체중있는회원", "weight_kg": weight_kg},
        headers=headers,
    )
    return headers


# ── 매칭기 (DB 불필요) ────────────────────────────────────────────────────


class _Row:
    """참조표 한 행 흉내 — 매칭기는 이 세 속성만 본다."""

    def __init__(self, name: str, aliases: tuple[str, ...] = ()) -> None:
        self.name = name
        self.name_norm = matcher.normalize(name)
        self.aliases_norm = "|".join(matcher.normalize(a) for a in aliases)


@pytest.mark.parametrize(
    ("query", "expected"),
    [
        ("러닝머신", "러닝머신"),
        # 표기가 달라도 같은 종목이다 — 별칭은 대표 이름과 같은 자격으로 본다.
        ("런닝머신", "러닝머신"),
        # 양을 이름 칸에 함께 적는 일이 잦다 — 숫자는 정규화가 지운다.
        ("줄넘기 300개", "줄넘기"),
        ("스쿼트 3세트", "스쿼트"),
        # 수행 방식은 종목이 아니다. 강도는 강도 칩이 따로 받는다.
        ("가볍게 스쿼트", "스쿼트"),
        # 표 이름이 질의 안에 있으면 가장 구체적인 것.
        ("아침 러닝머신 유산소", "러닝머신"),
        # 질의가 표 이름의 조각이면 **유일할 때만**.
        ("랫풀", "랫풀다운"),
    ],
)
def test_matcher_folds_free_input_to_one_activity(query: str, expected: str):
    rows = [
        _Row("러닝머신", ("런닝머신", "트레드밀")),
        _Row("줄넘기", ("2단뛰기",)),
        _Row("스쿼트"),
        _Row("랫풀다운",),
    ]
    matched = matcher.match_in_rows(rows, query)
    assert matched is not None and matched.name == expected


@pytest.mark.parametrize("query", ["", "PT 하체날", "오늘 운동", "프레스"])
def test_matcher_prefers_fallback_over_wrong_activity(query: str):
    """애매하면 붙이지 않는다 — 틀린 종목으로 계산한 값은 어림값보다 나쁘다."""
    rows = [
        _Row("벤치프레스"),
        _Row("숄더프레스"),
        _Row("러닝머신"),
    ]
    assert matcher.match_in_rows(rows, query) is None


# ── 계산 (DB 불필요) ──────────────────────────────────────────────────────


class _Catalog:
    def __init__(self, met: float, type_: str = exercise_types.CARDIO) -> None:
        self.name = "러닝머신"
        self.met = met
        self.type = type_


def test_calories_follow_body_weight():
    """같은 운동이라도 체중이 다르면 값이 다르다 — 고정 분당 kcal 이 못 하던 일."""
    row = _Catalog(met=8.3)
    light = energy.estimate(row, "cardio", 30, "moderate", 50.0)
    heavy = energy.estimate(row, "cardio", 30, "moderate", 90.0)

    assert light.calories < heavy.calories
    assert light.source == energy.SOURCE_DB
    assert light.matched_name == "러닝머신"


def test_calories_fall_back_without_name_or_weight():
    """근거가 없으면 어림값이고, `source` 가 그렇다고 말한다."""
    unmatched = energy.estimate(None, "cardio", 30, "moderate", 70.0)
    weightless = energy.estimate(_Catalog(met=8.3), "cardio", 30, "moderate", None)

    for result in (unmatched, weightless):
        assert result.source == energy.SOURCE_ESTIMATE
        assert result.matched_name == ""
    # 폴백은 #1312 이전의 표 그대로다 — 여기가 움직이면 옛 기록의 값이 통째로
    # 따라 움직인다.
    assert unmatched.calories == round(9.0 * 30 * 1.0)


def test_ai_resolution_is_marked_mixed_and_needs_confidence():
    """이름 해석만 AI 가 해도 숫자는 참조표에서 나온다 — `mixed` 다."""
    row = _Catalog(met=8.3)
    confident = energy.estimate(
        row, "cardio", 30, "moderate", 70.0, resolver="ai", confidence=0.9
    )
    unsure = energy.estimate(
        row, "cardio", 30, "moderate", 70.0, resolver="ai", confidence=0.3
    )

    assert confident.source == energy.SOURCE_MIXED
    assert confident.calories == energy.from_catalog(row, 30, "moderate", 70.0).calories
    # 확신이 낮으면 채택하지 않는다 — 매칭기의 폴백 원칙과 같다.
    assert unsure.source == energy.SOURCE_ESTIMATE


# ── API (DB 필요) ─────────────────────────────────────────────────────────


def test_preview_rejects_empty_name(client):
    """이름 없이 확정된 숫자를 내주지 않는 것이 이 계산의 요점이다."""
    h = _login(client)
    r = client.post(
        "/v1/exercise/calories",
        json={"type": "cardio", "name": "   ", "minutes": 30},
        headers=h,
    )
    assert r.status_code == 400, r.text


def test_preview_uses_catalog_and_weight(client):
    h = _with_weight(client, _login(client), 90.0)
    heavy = client.post(
        "/v1/exercise/calories",
        json={"type": "cardio", "name": "런닝머신", "minutes": 30},
        headers=h,
    ).json()

    assert heavy["source"] == "db"
    # 회원이 적은 말과 종목 이름이 다를 수 있다 — 무엇으로 계산했는지 돌려준다.
    assert heavy["matched_name"] == "러닝머신"

    lighter = _with_weight(client, _login(client), 50.0)
    light = client.post(
        "/v1/exercise/calories",
        json={"type": "cardio", "name": "런닝머신", "minutes": 30},
        headers=lighter,
    ).json()
    assert light["calories"] < heavy["calories"]


def test_preview_falls_back_for_unmatched_name(client):
    """종목으로 접히지 않는 자유 입력은 유형 평균이고, 그렇다고 표시된다."""
    h = _with_weight(client, _login(client), 70.0)
    r = client.post(
        "/v1/exercise/calories",
        json={"type": "cardio", "name": "PT 하체날", "minutes": 30},
        headers=h,
    ).json()

    assert r["source"] == "estimate"
    assert r["matched_name"] == ""
    assert r["calories"] == round(9.0 * 30)


def test_saved_calories_come_from_the_server_not_the_client(client):
    """앱이 보낸 값을 믿지 않는다 — 세 화면이 같은 값을 보려면 계산이 하나여야 한다."""
    h = _with_weight(client, _login(client), 70.0)
    preview = client.post(
        "/v1/exercise/calories",
        json={"type": "cardio", "name": "러닝머신", "minutes": 30},
        headers=h,
    ).json()

    created = post_exercise(
        client,
        json={
            "type": "cardio",
            "name": "러닝머신",
            "minutes": 30,
            # 앱이 엉뚱한 값을 보내도 기록에는 서버 계산이 남는다.
            "calories": 99999,
            "date": _day("월"),
        },
        headers=h,
    )
    assert created.status_code == 201, created.text
    body = created.json()
    assert body["calories"] == preview["calories"]
    assert body["calorie_source"] == "db"

    # 주간 집계도 같은 값을 본다.
    week = client.get("/v1/exercise/weeks/current", headers=h).json()
    saved = next(s for s in week["sessions"] if s["id"] == body["id"])
    assert saved["calories"] == preview["calories"]
    assert saved["calorie_source"] == "db"


def test_save_succeeds_without_weight_or_matching_name(client):
    """외부 의존도 체중도 없는 환경에서 저장이 막히면 안 된다."""
    h = _login(client)  # 온보딩을 하지 않아 체중이 없다
    r = post_exercise(
        client,
        json={
            "type": "strength",
            "name": "오늘 하체 몰아치기",
            "minutes": 36,
            "calories": 0,
            "date": _day("화"),
        },
        headers=h,
    )
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["calorie_source"] == "estimate"
    assert body["calories"] == round(6.0 * 36)


def test_edit_recomputes_calories(client):
    """시간을 고치면 칼로리도 따라 고쳐진다 — 앱이 다시 계산해 보내지 않아도."""
    h = _with_weight(client, _login(client), 70.0)
    created = post_exercise(
        client,
        json={
            "type": "cardio",
            "name": "러닝머신",
            "minutes": 30,
            "calories": 0,
            "date": _day("수"),
        },
        headers=h,
    ).json()

    updated = client.put(
        f"/v1/exercise/sessions/{created['id']}",
        json={
            "type": "cardio",
            "name": "러닝머신",
            "minutes": 60,
            "calories": 0,
            "date": _day("수"),
        },
        headers=h,
    )
    assert updated.status_code == 200, updated.text
    # 두 배 시간이면 두 배 칼로리다. 1kcal 여유는 반올림 자리 — 두 번 반올림한
    # 값(30분 두 개)과 한 번 반올림한 값(60분)이 정확히 같을 수는 없다.
    assert abs(updated.json()["calories"] - created["calories"] * 2) <= 1
