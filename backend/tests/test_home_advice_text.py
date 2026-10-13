"""홈 나트륨 경고·하루 식단 코치 문장과 날짜. (#2644, #3404)

- 홈 `오늘의 AI 통합 조언` — 음식 이름이 든 나트륨 경고는 `sodium_over_sources`
  키와 음식 이름 인자로 내려간다. 문장(`sodium_warning`)은 한국어다.
- 식단 탭 지난 날짜의 AI 피드백(`ai_coach_message`) — 지난 날짜면 그날 문장이고,
  기준은 회원 나트륨 목표다.
- 서버는 `Accept-Language` 를 읽지 않는다 — `en` 을 보내도 같은 한국어 문장이다.
"""
from __future__ import annotations

import json
from datetime import timedelta
from uuid import uuid4

import pytest
from sqlalchemy import delete

from app.api.v1.dashboard import (
    _advice_key, _advice_params, _build_sodium_warning, _exercise_feedback,
)
from app.core import clock
from app.services import diet_service

EN = {"Accept-Language": "en"}


# ---------------------------------------------------------------------------
# 규칙 — 홈 나트륨 경고
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("total", "sources", "goal", "message"),
    [
        (2100, [], 2000, "오늘 나트륨이 2,100mg으로 목표(2,000mg)를 넘었어요."),
        (1600, [], 1500, "오늘 나트륨이 1,600mg으로 목표(1,500mg)를 넘었어요."),
        (2100, ["라면"], 2000, "라면 섭취로 나트륨이 높아요."),
        (2100, ["김밥", "라면"], 2000, "김밥·라면 섭취로 나트륨이 높아요."),
        (2100, ["김치찌개", "배추김치", "라면"], 2000,
         "김치찌개·배추김치 섭취로 나트륨이 높아요."),
    ],
)
def test_sodium_warning(total, sources, goal, message):
    assert _build_sodium_warning(total, sources, goal) == message


def test_sodium_warning_is_none_within_the_goal():
    assert _build_sodium_warning(2000, ["라면"], 2000) is None
    assert _build_sodium_warning(1400, [], 1500) is None


def test_sodium_warning_with_foods_gets_its_own_key_and_the_names():
    key = _advice_key(
        sodium_warning="라면·김밥 섭취로 나트륨이 높아요.",
        sodium_source_names=["라면", "김밥", "샐러드"],
        exercise_advice_key="exercise_more",
    )
    assert key == "sodium_over_sources"
    # 문장이 짚는 두 개만 싣는다 — 앱 문장과 서버 문장이 같은 음식을 말한다.
    assert _advice_params(
        advice_key=key, sodium_source_names=["라면", "김밥", "샐러드"],
    ) == {"foods": ["라면", "김밥"]}


@pytest.mark.parametrize(
    "key",
    [
        "sodium_over", "exercise_on_track", "exercise_more",
        "exercise_cardio_start", "exercise_start",
    ],
)
def test_other_advice_keys_carry_no_params(key):
    assert _advice_params(advice_key=key, sodium_source_names=["라면"]) == {}


# 분 수는 이번 주 유산소 분, 기준은 회원의 주간 유산소 목표다(#3350). 여기서는
# 목표가 없는 회원의 기본값(150분)으로 문장만 본다.
@pytest.mark.parametrize(
    ("minutes", "any_exercise", "key", "message"),
    [
        (150, True, "exercise_on_track",
         "이번 주 유산소 150분 운동했어요. 목표 달성 중이에요!"),
        (40, True, "exercise_more",
         "이번 주 유산소 40분 운동했어요. 조금만 더 힘내요!"),
        (0, False, "exercise_start",
         "이번 주 운동을 시작해 보세요. 가벼운 걷기부터 좋아요."),
    ],
)
def test_exercise_feedback(minutes, any_exercise, key, message):
    assert _exercise_feedback(minutes, 150, any_exercise=any_exercise) == (message, key)


# ---------------------------------------------------------------------------
# 규칙 — 하루 식단 코치 문장
# ---------------------------------------------------------------------------

LIMIT = diet_service.SODIUM_LIMIT_MG


@pytest.mark.parametrize(
    ("sodium", "has_entries", "message"),
    [
        (LIMIT + 1, True,
         "그날은 나트륨 섭취가 많았어요. 다음 날은 국물·양념을 줄여 균형을 맞춰 봐요."),
        (0, False, "이날은 식단 기록이 없어요."),
        (LIMIT, True, "나트륨을 목표 안에서 지킨 균형 잡힌 하루였어요."),
    ],
)
def test_past_day_coach_message_talks_about_that_day(sodium, has_entries, message):
    assert diet_service.coach_message(sodium, has_entries, is_past=True) == message


@pytest.mark.parametrize("sodium", [0, LIMIT, LIMIT + 1, LIMIT * 3])
def test_past_day_coach_message_never_says_today(sodium):
    message = diet_service.coach_message(sodium, True, is_past=True)
    assert "오늘" not in message
    assert "저녁" not in message


def test_today_coach_message_is_unchanged_by_default():
    """오늘 문장은 그대로다 — 기본값이 오늘이다."""
    assert diet_service.coach_message(LIMIT + 1, True).startswith("오늘 나트륨")


@pytest.mark.parametrize("is_past", [False, True])
def test_coach_message_uses_the_member_sodium_goal(is_past):
    # 목표 1,500mg 인 회원에게 1,800mg 은 넘친 하루다 — 고정 상한(2,000)이면
    # 균형 잡힌 하루라고 말했다.
    over = diet_service.coach_message(
        1800, True, is_past=is_past, sodium_limit_mg=1500,
    )
    fixed = diet_service.coach_message(1800, True, is_past=is_past)
    assert "많았어요" in over
    assert "균형 잡힌" in fixed


def test_coach_message_falls_back_to_the_default_limit():
    assert diet_service.coach_message(
        LIMIT + 1, True, sodium_limit_mg=None,
    ) == diet_service.coach_message(LIMIT + 1, True)


# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------


@pytest.fixture
def demo_meals(db_session):
    """데모 회원(토큰 없이 부르면 이 회원이다)에게 끼니를 심고 끝나면 치운다."""
    from app.db.init_db import DEMO_USER_ID
    from app.models.models import DietEntry

    created: list[str] = []

    def add(date: str, foods: list[dict], sodium_mg: int) -> None:
        entry_id = f"home-locale-{uuid4().hex[:10]}"
        db_session.add(DietEntry(
            id=entry_id, user_id=DEMO_USER_ID, date=date, meal_type="lunch",
            time_label="12:00", foods_json=json.dumps(foods, ensure_ascii=False),
            total_calories=800, carbs_g=90, protein_g=30, fat_g=20,
            sodium_mg=sodium_mg, sugar_g=5,
        ))
        db_session.commit()
        created.append(entry_id)

    def clear(date: str) -> None:
        db_session.execute(delete(DietEntry).where(
            DietEntry.user_id == DEMO_USER_ID, DietEntry.date == date,
        ))
        db_session.commit()

    add.clear = clear  # type: ignore[attr-defined]
    try:
        yield add
    finally:
        db_session.execute(delete(DietEntry).where(DietEntry.id.in_(created)))
        db_session.commit()


@pytest.fixture
def demo_sodium_goal(db_session):
    """데모 회원의 나트륨 목표를 잠시 바꾼다."""
    from app.db.init_db import DEMO_USER_ID
    from app.models.models import User

    profile = db_session.get(User, DEMO_USER_ID).health_profile
    original = profile.daily_sodium_mg

    def set_goal(value: int | None) -> None:
        profile.daily_sodium_mg = value
        db_session.commit()

    try:
        yield set_goal
    finally:
        profile.daily_sodium_mg = original
        db_session.commit()


def test_home_sodium_warning_with_foods_is_keyed_and_korean(
    client, demo_meals, demo_sodium_goal,
):
    today = clock.today().isoformat()
    demo_meals.clear(today)
    demo_sodium_goal(2000)
    demo_meals(today, [
        {"name": "라면", "sodium_mg": 1800},
        {"name": "김밥", "sodium_mg": 900},
        {"name": "단무지", "sodium_mg": 100},
    ], 2800)

    default = client.get("/v1/dashboard/summary").json()
    en = client.get("/v1/dashboard/summary", headers=EN).json()

    for body in (default, en):
        assert body["ai_advice_key"] == "sodium_over_sources"
        assert body["ai_advice_params"] == {"foods": ["라면", "김밥"]}
        assert body["sodium_warning"] == "라면·김밥 섭취로 나트륨이 높아요."
    assert en["exercise_feedback"] == default["exercise_feedback"]


def test_home_summary_without_warning_has_empty_params(client, demo_meals):
    today = clock.today().isoformat()
    demo_meals.clear(today)
    body = client.get("/v1/dashboard/summary").json()
    assert body["sodium_warning"] is None
    assert body["ai_advice_key"] in (
        "exercise_on_track", "exercise_more", "exercise_cardio_start", "exercise_start",
    )
    assert body["ai_advice_params"] == {}


def test_past_diet_day_message_is_about_that_day(client, demo_meals):
    past = (clock.today() - timedelta(days=3)).isoformat()
    demo_meals.clear(past)
    demo_meals(past, [{"name": "짬뽕", "sodium_mg": 4000}], LIMIT * 2)

    for headers in (None, EN):
        message = client.get(f"/v1/diet/days/{past}", headers=headers).json()[
            "ai_coach_message"
        ]
        assert message.startswith("그날은 나트륨 섭취가 많았어요.")
        assert "오늘" not in message


def test_today_diet_day_message_still_talks_about_today(client, demo_meals):
    today = clock.today().isoformat()
    demo_meals.clear(today)
    demo_meals(today, [{"name": "짬뽕", "sodium_mg": 4000}], LIMIT * 2)
    body = client.get("/v1/diet/days/today").json()
    assert body["ai_coach_message"].startswith("오늘 나트륨 섭취가 많았어요.")


def test_diet_day_message_uses_the_member_sodium_goal(
    client, demo_meals, demo_sodium_goal,
):
    past = (clock.today() - timedelta(days=4)).isoformat()
    demo_meals.clear(past)
    demo_meals(past, [{"name": "김치찌개", "sodium_mg": 1800}], 1800)

    demo_sodium_goal(1500)
    strict = client.get(f"/v1/diet/days/{past}").json()["ai_coach_message"]
    demo_sodium_goal(None)
    default = client.get(f"/v1/diet/days/{past}").json()["ai_coach_message"]

    assert strict.startswith("그날은 나트륨 섭취가 많았어요.")
    assert default == "나트륨을 목표 안에서 지킨 균형 잡힌 하루였어요."
