"""홈 나트륨 경고·하루 식단 코치 문장의 언어와 날짜. (#2644)

영어 화면의 회원이 두 자리에서 한국어를 읽었다.

- 홈 `오늘의 AI 통합 조언` — 음식 이름이 든 나트륨 경고는 키 없이 한국어 문장만
  내려가 앱이 그대로 그렸다. 이제 `sodium_over_sources` 키와 음식 이름 인자로
  내려가고, 문장 자체도 요청 언어를 따른다.
- 식단 탭 지난 날짜의 AI 피드백(`ai_coach_message`) — 날짜와 무관하게 "오늘 …
  저녁은" 이었고 기준도 고정 상한이었다. 이제 지난 날짜면 그날 문장이고, 기준은
  회원 나트륨 목표다.
"""
from __future__ import annotations

import json
import re
from datetime import timedelta
from uuid import uuid4

import pytest
from sqlalchemy import delete

from app.api.v1.dashboard import (
    _advice_key, _advice_params, _build_sodium_warning, _exercise_feedback,
)
from app.core import clock
from app.core.locale import _request_locale_ctx
from app.services import diet_service

_HANGUL = re.compile(r"[가-힣]")


def _no_hangul(text: str) -> bool:
    return _HANGUL.search(text) is None


# ---------------------------------------------------------------------------
# 규칙 — 홈 나트륨 경고
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("total", "sources", "goal", "ko", "en"),
    [
        (2100, [], 2000,
         "오늘 나트륨이 2,100mg으로 권장량(2,000mg)을 넘었어요.",
         "Sodium is at 2,100 mg today, over your target (2,000 mg)."),
        (1600, [], 1500,
         "오늘 나트륨이 1,600mg으로 권장량(1,500mg)을 넘었어요.",
         "Sodium is at 1,600 mg today, over your target (1,500 mg)."),
        (2100, ["라면"], 2000,
         "라면 섭취로 나트륨이 높아요.",
         "Sodium is high from 라면."),
        (2100, ["김밥", "라면"], 2000,
         "김밥·라면 섭취로 나트륨이 높아요.",
         "Sodium is high from 김밥 and 라면."),
        (2100, ["김치찌개", "배추김치", "라면"], 2000,
         "김치찌개·배추김치 섭취로 나트륨이 높아요.",
         "Sodium is high from 김치찌개 and 배추김치."),
    ],
)
def test_sodium_warning_in_both_languages(total, sources, goal, ko, en):
    assert _build_sodium_warning(total, sources, goal) == ko
    assert _build_sodium_warning(total, sources, goal, locale="ko") == ko
    assert _build_sodium_warning(total, sources, goal, locale="en") == en


def test_sodium_warning_follows_the_request_locale():
    token = _request_locale_ctx.set("en")
    try:
        assert _build_sodium_warning(2100, ["라면"], 2000) == "Sodium is high from 라면."
    finally:
        _request_locale_ctx.reset(token)


@pytest.mark.parametrize("locale", ["ko", "en"])
def test_sodium_warning_is_none_within_the_goal(locale):
    assert _build_sodium_warning(2000, ["라면"], 2000, locale=locale) is None
    assert _build_sodium_warning(1400, [], 1500, locale=locale) is None


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
    "key", ["sodium_over", "exercise_on_track", "exercise_more", "exercise_start"],
)
def test_other_advice_keys_carry_no_params(key):
    assert _advice_params(advice_key=key, sodium_source_names=["라면"]) == {}


@pytest.mark.parametrize(
    ("minutes", "key", "ko", "en"),
    [
        (150, "exercise_on_track",
         "이번 주 150분 운동했어요. 목표 달성 중이에요!",
         "You worked out 150 minutes this week. You are on track!"),
        (40, "exercise_more",
         "이번 주 40분 운동했어요. 조금만 더 힘내요!",
         "You worked out 40 minutes this week. A little more to go!"),
        (0, "exercise_start",
         "이번 주 운동을 시작해 보세요. 가벼운 걷기부터 좋아요.",
         "Start moving this week — an easy walk is a good beginning."),
    ],
)
def test_exercise_feedback_in_both_languages(minutes, key, ko, en):
    assert _exercise_feedback(minutes, "ko") == (ko, key)
    assert _exercise_feedback(minutes, "en") == (en, key)


# ---------------------------------------------------------------------------
# 규칙 — 하루 식단 코치 문장
# ---------------------------------------------------------------------------

LIMIT = diet_service.SODIUM_LIMIT_MG


@pytest.mark.parametrize(
    ("sodium", "has_entries", "ko", "en"),
    [
        (LIMIT + 1, True,
         "그날은 나트륨 섭취가 많았어요. 다음 날은 국물·양념을 줄여 균형을 맞춰 봐요.",
         "Sodium ran high that day. Go easy on soups and sauces the next day to balance it out."),
        (0, False,
         "이날은 식단 기록이 없어요.",
         "No meals were logged that day."),
        (LIMIT, True,
         "나트륨을 목표 안에서 지킨 균형 잡힌 하루였어요.",
         "A well-balanced day with sodium within your target."),
    ],
)
def test_past_day_coach_message_talks_about_that_day(sodium, has_entries, ko, en):
    assert diet_service.coach_message(sodium, has_entries, "ko", is_past=True) == ko
    assert diet_service.coach_message(sodium, has_entries, "en", is_past=True) == en


@pytest.mark.parametrize("locale", ["ko", "en"])
@pytest.mark.parametrize("sodium", [0, LIMIT, LIMIT + 1, LIMIT * 3])
def test_past_day_coach_message_never_says_today(locale, sodium):
    message = diet_service.coach_message(sodium, True, locale, is_past=True)
    assert "오늘" not in message
    assert "저녁" not in message
    assert "today" not in message.lower()
    assert "dinner" not in message.lower()


def test_today_coach_message_is_unchanged_by_default():
    """오늘 문장은 그대로다 — 기본값이 오늘이다."""
    assert diet_service.coach_message(LIMIT + 1, True, "ko").startswith("오늘 나트륨")
    assert diet_service.coach_message(LIMIT + 1, True, "en").startswith(
        "You had a lot of sodium today."
    )


@pytest.mark.parametrize("is_past", [False, True])
def test_coach_message_uses_the_member_sodium_goal(is_past):
    # 목표 1,500mg 인 회원에게 1,800mg 은 넘친 하루다 — 고정 상한(2,000)이면
    # 균형 잡힌 하루라고 말했다.
    over = diet_service.coach_message(
        1800, True, "ko", is_past=is_past, sodium_limit_mg=1500,
    )
    fixed = diet_service.coach_message(1800, True, "ko", is_past=is_past)
    assert "많았어요" in over
    assert "균형 잡힌" in fixed


def test_coach_message_falls_back_to_the_default_limit():
    assert diet_service.coach_message(
        LIMIT + 1, True, "ko", sodium_limit_mg=None,
    ) == diet_service.coach_message(LIMIT + 1, True, "ko")


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


def test_home_sodium_warning_with_foods_is_keyed_in_both_languages(
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

    en = client.get("/v1/dashboard/summary", headers={"Accept-Language": "en"}).json()
    ko = client.get("/v1/dashboard/summary", headers={"Accept-Language": "ko"}).json()

    for body in (en, ko):
        assert body["ai_advice_key"] == "sodium_over_sources"
        assert body["ai_advice_params"] == {"foods": ["라면", "김밥"]}
    assert ko["sodium_warning"] == "라면·김밥 섭취로 나트륨이 높아요."
    assert en["sodium_warning"] == "Sodium is high from 라면 and 김밥."
    # 음식 이름을 빼면 영어 문장에 한글이 없다.
    assert _no_hangul(en["sodium_warning"].replace("라면", "").replace("김밥", ""))
    assert _no_hangul(en["exercise_feedback"])


def test_home_summary_without_warning_has_empty_params(client, demo_meals):
    today = clock.today().isoformat()
    demo_meals.clear(today)
    body = client.get("/v1/dashboard/summary").json()
    assert body["sodium_warning"] is None
    assert body["ai_advice_key"] in ("exercise_on_track", "exercise_more", "exercise_start")
    assert body["ai_advice_params"] == {}


def test_past_diet_day_message_is_about_that_day(client, demo_meals):
    past = (clock.today() - timedelta(days=3)).isoformat()
    demo_meals.clear(past)
    demo_meals(past, [{"name": "짬뽕", "sodium_mg": 4000}], LIMIT * 2)

    ko = client.get(f"/v1/diet/days/{past}").json()["ai_coach_message"]
    en = client.get(
        f"/v1/diet/days/{past}", headers={"Accept-Language": "en"},
    ).json()["ai_coach_message"]

    assert ko.startswith("그날은 나트륨 섭취가 많았어요.")
    assert en.startswith("Sodium ran high that day.")
    assert "오늘" not in ko
    assert _no_hangul(en)


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
