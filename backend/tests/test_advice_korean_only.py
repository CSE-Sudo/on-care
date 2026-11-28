"""식단·운동 기간 조언 문장은 한국어 하나다(#3404).

트레이너웹 회원 상세의 식단·운동 탭과 회원 앱은 서버 조언 문장(`message`)을 그대로
보여 준다. 서버는 `Accept-Language` 를 읽지 않는다 — 헤더가 없든 `ko` 든 `en` 이든
같은 한국어 문장이 나온다.
"""
from __future__ import annotations

import json
import re
from datetime import date, timedelta
from pathlib import Path
from uuid import uuid4

import pytest

from app.core import clock
from app.services import diet_service, exercise_advice, exercise_service, period_window
from app.services.exercise_service import ExerciseDayTotals

_ROOT = Path(__file__).resolve().parents[2]
_CASES = json.loads(
    (_ROOT / "frontend/flutter/test/core/demo/routine_advice_cases.json").read_text(
        encoding="utf-8"
    )
)
_HANGUL = re.compile(r"[가-힣]")
_TODAY = date(2026, 9, 23)  # 수요일
WEEK, ALL, TODAY = (
    period_window.PERIOD_WEEK,
    period_window.PERIOD_ALL,
    period_window.PERIOD_TODAY,
)
#: 어떤 헤더로 불러도 같은 한국어 응답이어야 한다.
LANGS = [None, "ko", "en", "en-US,en;q=0.9,ko;q=0.5", "fr-FR"]


# ---------------------------------------------------------------------------
# 운동 조언 — 틀·키
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "rendering", _CASES["renderings"], ids=lambda r: f"{r['key']}-{sorted(r['params'].items())}"
)
def test_exercise_text_matches_the_shared_cases(rendering):
    """문장은 공유 사례의 한국어와 글자까지 같다."""
    advice = exercise_advice.advice(rendering["key"], **rendering["params"])
    assert advice.text == rendering["message"]


def test_unknown_exercise_key_is_still_rejected():
    with pytest.raises(KeyError):
        exercise_advice.advice("no_such_key")


# ---------------------------------------------------------------------------
# 운동 조언 — 규칙이 고른 문장
# ---------------------------------------------------------------------------


def _ex_days(*specs: tuple[int, dict[str, int]]) -> list[ExerciseDayTotals]:
    return [
        ExerciseDayTotals(
            date=_TODAY - timedelta(days=back),
            minutes=sum(by_type.values()),
            calories=sum(by_type.values()) * 7,
            by_type=by_type,
        )
        for back, by_type in sorted(specs, reverse=True)
    ]


@pytest.mark.parametrize(
    ("days", "period", "message"),
    [
        ([], TODAY, "오늘 운동 기록이 아직 없어요. 10분 걷기부터 시작해 볼까요?"),
        ([], WEEK, "이번 주 운동 기록이 아직 없어요. 10분 걷기부터 시작해 볼까요?"),
        ([], ALL, "기록이 쌓이면 운동량과 유형의 흐름을 짚어 드릴게요."),
        (_ex_days((0, {"cardio": 30})), TODAY,
         "오늘 유산소 위주로 30분, 210kcal 썼어요. 스트레칭으로 마무리해요."),
        (_ex_days((0, {"strength": 40})), WEEK,
         "이번 주는 40분 하루뿐이에요. 한 번 더 나가면 흐름이 이어져요."),
        (_ex_days((0, {"cardio": 30}), (1, {"cardio": 30})), WEEK,
         "이번 주 2일 60분이 유산소에 몰렸어요. 근력도 섞어 볼까요?"),
        (_ex_days((0, {"cardio": 30}), (1, {"strength": 30})), WEEK,
         "이번 주 2일 60분, 유형도 고르게 섞였어요."),
    ],
)
def test_exercise_period_message(days, period, message):
    assert exercise_service.period_coach_message(days, period) == message


# ---------------------------------------------------------------------------
# 식단 조언 — 오늘 코칭 한 마디
# ---------------------------------------------------------------------------


LIMIT = diet_service.SODIUM_LIMIT_MG


@pytest.mark.parametrize(
    ("sodium", "has_entries", "message"),
    [
        (LIMIT + 1, True,
         "오늘 나트륨 섭취가 많았어요. 저녁은 담백한 구이/샐러드로 균형을 맞춰봐요!"),
        (0, False, "아직 오늘 식단 기록이 없어요. 첫 끼니를 기록해 볼까요?"),
        (LIMIT, True, "균형 잡힌 하루였어요. 내일도 이대로 가요!"),
    ],
)
def test_diet_coach_message(sodium, has_entries, message):
    assert diet_service.coach_message(sodium, has_entries) == message


# ---------------------------------------------------------------------------
# API — 트레이너웹 경로와 회원 앱 조언
# ---------------------------------------------------------------------------


def _auth(token: str, lang: str | None = None) -> dict:
    headers = {"Authorization": f"Bearer {token}"}
    if lang is not None:
        headers["Accept-Language"] = lang
    return headers


def _trainer_token(client) -> str:
    return client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    ).json()["access_token"]


def _jisu_token(client) -> str:
    return client.post(
        "/v1/auth/login", data={"username": "jisu@oncare.com", "password": "oncare123"}
    ).json()["access_token"]


@pytest.fixture
def jisu_over_sodium_today(db_session):
    """user-jisu 에 오늘 나트륨이 넘친 끼니 하나를 심고 끝나면 치운다."""
    from app.models import models

    row = models.DietEntry(
        id=f"diet-locale-{uuid4().hex[:10]}",
        user_id="user-jisu",
        date=clock.today().isoformat(),
        meal_type="lunch",
        time_label="12:00",
        foods_json="[]",
        total_calories=900,
        sodium_mg=LIMIT * 3,
        sugar_g=10,
        carbs_g=100,
        protein_g=40,
        fat_g=20,
    )
    db_session.add(row)
    db_session.commit()
    try:
        yield
    finally:
        db_session.delete(row)
        db_session.commit()


@pytest.mark.parametrize("period", ["today", "week", "all"])
@pytest.mark.parametrize("kind", ["diet-advice", "exercise-advice"])
def test_trainer_advice_is_korean_whatever_the_header(client, kind, period):
    token = _trainer_token(client)
    url = f"/v1/trainer/clients/user-jisu/{kind}?period={period}"
    default = client.get(url, headers=_auth(token))
    assert default.status_code == 200, default.text
    assert _HANGUL.search(default.json()["message"])
    for lang in LANGS:
        response = client.get(url, headers=_auth(token, lang))
        assert response.status_code == 200, response.text
        # 헤더가 무엇이든 헤더 없는 응답과 같은 문장·같은 구간이다.
        for field in ("message", "period", "from_date", "to_date", "days_logged"):
            assert response.json()[field] == default.json()[field], (lang, field)


def test_trainer_diet_advice_today_names_the_sodium_in_korean(client, jisu_over_sodium_today):
    token = _trainer_token(client)
    url = "/v1/trainer/clients/user-jisu/diet-advice?period=today"
    default = client.get(url, headers=_auth(token)).json()
    body = client.get(url, headers=_auth(token, "en-US,en;q=0.9,ko;q=0.5")).json()
    # 트레이너 `식단 분석`(#2379) — 넘친 영양과 그 원인(음식 또는 끼니)을 짚는다.
    assert body["sentences"][0]["key"] in ("tr_today_over", "tr_today_over_meal")
    assert body["sentences"][0]["params"]["nutrient"] == "sodium"
    assert _HANGUL.search(body["message"])
    assert body["message"] == default["message"]


@pytest.mark.parametrize("kind", ["diet-advice", "exercise-advice"])
def test_trainer_advice_still_refuses_other_members(client, kind):
    token = _trainer_token(client)
    denied = client.get(
        f"/v1/trainer/clients/not-my-member/{kind}", headers=_auth(token, "en")
    )
    assert denied.status_code in (403, 404), denied.text


@pytest.mark.parametrize("kind", ["diet-advice", "exercise-advice"])
def test_trainer_advice_requires_a_trainer(client, kind):
    member = _jisu_token(client)
    denied = client.get(
        f"/v1/trainer/clients/user-jisu/{kind}", headers=_auth(member, "en")
    )
    assert denied.status_code in (401, 403), denied.text


@pytest.mark.parametrize("period", ["today", "week", "all"])
def test_member_exercise_advice_message_is_korean_whatever_the_header(client, period):
    """회원 앱은 키로 그리지만, 키를 모르는 옛 앱이 읽는 `message` 는 한국어 문장이다."""
    token = _jisu_token(client)
    url = f"/v1/exercise/advice?period={period}"
    default = client.get(url, headers=_auth(token)).json()
    advice = exercise_advice.advice(default["advice_key"], **default["advice_params"])
    assert default["message"] == advice.text
    for lang in LANGS:
        body = client.get(url, headers=_auth(token, lang)).json()
        assert body["advice_key"] == default["advice_key"]
        assert body["message"] == default["message"], lang


def test_member_diet_day_coach_message_is_korean_whatever_the_header(
    client, jisu_over_sodium_today
):
    token = _jisu_token(client)
    for lang in LANGS:
        body = client.get("/v1/diet/days/today", headers=_auth(token, lang)).json()
        assert body["ai_coach_message"].startswith("오늘 나트륨 섭취가 많았어요."), lang
