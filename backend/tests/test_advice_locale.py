"""식단·운동 기간 조언의 영어 문장(#2299).

트레이너웹 회원 상세의 식단·운동 탭은 서버 조언 문장(`message`)을 그대로 보여 준다.
영어 화면에서도 한국어로만 나오던 문장을 요청 언어(`Accept-Language`)로 고른다.

- **한국어는 글자까지 그대로다.** 헤더가 없거나 `ko` 면 지금까지와 같은 문장이다.
- 운동 영어 문장은 회원 앱 `app_en.arb`(`exerciseAdvice…`)와 **같은 문장**이다 —
  같은 회원의 같은 기간을 회원과 트레이너가 다른 말로 읽지 않게. 이 파일이 ARB 를
  직접 읽어 `plural`·`select` 를 풀고 서버 문장과 견준다.
- 영어 문장에는 한글이 남지 않는다(트레이너가 적은 운동 이름은 예외 — 값 그대로다).
"""
from __future__ import annotations

import json
import re
from datetime import date, timedelta
from pathlib import Path
from uuid import uuid4

import pytest

from app.core import clock
from app.core.locale import _request_locale_ctx
from app.services import diet_service, exercise_advice, exercise_service, period_window
from app.services.diet_service import DietDayTotals
from app.services.exercise_service import ExerciseDayTotals

_ROOT = Path(__file__).resolve().parents[2]
_EN_ARB = json.loads(
    (_ROOT / "frontend/flutter/lib/l10n/app_en.arb").read_text(encoding="utf-8")
)
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


def _no_hangul(text: str) -> bool:
    return _HANGUL.search(text) is None


@pytest.fixture
def english():
    """요청 언어가 영어인 상태 — 미들웨어가 채우는 컨텍스트를 그대로 흉내 낸다."""
    token = _request_locale_ctx.set("en")
    try:
        yield
    finally:
        _request_locale_ctx.reset(token)


# ---------------------------------------------------------------------------
# ARB 의 ICU 문장을 푸는 작은 해석기 — `{x}`, `{x, select, …}`, `{x, plural, =1{…} other{…}}`
# ---------------------------------------------------------------------------


def _matching_brace(text: str, start: int) -> int:
    depth = 0
    for i in range(start, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return i
    raise ValueError(f"괄호가 닫히지 않았다: {text}")


def _options(body: str) -> dict[str, str]:
    options: dict[str, str] = {}
    i = 0
    while i < len(body):
        if body[i].isspace():
            i += 1
            continue
        open_at = body.index("{", i)
        close_at = _matching_brace(body, open_at)
        options[body[i:open_at].strip()] = body[open_at + 1 : close_at]
        i = close_at + 1
    return options


def render_icu(template: str, params: dict) -> str:
    out: list[str] = []
    i = 0
    while i < len(template):
        if template[i] != "{":
            out.append(template[i])
            i += 1
            continue
        close_at = _matching_brace(template, i)
        inner = template[i + 1 : close_at]
        parts = inner.split(",", 2)
        name = parts[0].strip()
        if len(parts) == 1:
            out.append(str(params[name]))
        else:
            kind = parts[1].strip()
            options = _options(parts[2])
            value = params[name]
            if kind == "plural":
                chosen = options.get(f"={value}", options["other"])
            else:
                chosen = options.get(str(value), options["other"])
            out.append(render_icu(chosen, params))
        i = close_at + 1
    return "".join(out)


def _arb_key(key: str) -> str:
    return "exerciseAdvice" + "".join(part.capitalize() for part in key.split("_"))


def test_icu_renderer_handles_nesting():
    tpl = "{n, plural, =1{one {x}} other{{n} of {k, select, a{A} other{O}}}}!"
    assert render_icu(tpl, {"n": 1, "x": "X", "k": "a"}) == "one X!"
    assert render_icu(tpl, {"n": 3, "x": "X", "k": "a"}) == "3 of A!"
    assert render_icu(tpl, {"n": 3, "x": "X", "k": "zz"}) == "3 of O!"


# ---------------------------------------------------------------------------
# 운동 조언 — 틀·키
# ---------------------------------------------------------------------------


def test_every_exercise_key_has_an_english_template():
    assert set(exercise_advice._EN) == set(exercise_advice._KO)


@pytest.mark.parametrize("key", exercise_advice.KEYS)
def test_every_exercise_key_exists_in_the_member_app_english_arb(key):
    assert _arb_key(key) in _EN_ARB, key


@pytest.mark.parametrize(
    "rendering", _CASES["renderings"], ids=lambda r: f"{r['key']}-{sorted(r['params'].items())}"
)
def test_exercise_english_matches_the_member_app_arb(rendering):
    """서버 영어 문장 == 회원 앱이 같은 키·값으로 그리는 영어 문장."""
    advice = exercise_advice.advice(rendering["key"], **rendering["params"])
    expected = render_icu(_EN_ARB[_arb_key(rendering["key"])], rendering["params"])
    assert advice.text_en == expected
    assert advice.text_for("en") == expected


@pytest.mark.parametrize(
    "rendering", _CASES["renderings"], ids=lambda r: f"{r['key']}-{sorted(r['params'].items())}"
)
def test_exercise_korean_is_unchanged(rendering):
    """한국어 문장은 공유 사례의 한국어와 글자까지 같다 — 기본값·`ko` 모두."""
    advice = exercise_advice.advice(rendering["key"], **rendering["params"])
    assert advice.text == rendering["message"]
    assert advice.text_for("ko") == rendering["message"]
    assert advice.text_for() == rendering["message"]


@pytest.mark.parametrize(
    "rendering", _CASES["renderings"], ids=lambda r: f"{r['key']}-{sorted(r['params'].items())}"
)
def test_exercise_english_has_no_korean_left(rendering):
    text = exercise_advice.advice(rendering["key"], **rendering["params"]).text_en
    for value in rendering["params"].values():
        # 트레이너가 적은 운동 이름은 값 그대로 들어간다.
        if isinstance(value, str):
            text = text.replace(value, "")
    assert _no_hangul(text), text
    assert "{" not in text and "}" not in text


@pytest.mark.parametrize(
    ("count", "done", "left"),
    [
        (1, "You finished your personal exercise today. Great job!",
         "1 personal exercise left. Go down the list in order."),
        (2, "You finished all 2 personal exercises today. Great job!",
         "2 personal exercises left. Go down the list in order."),
        (0, "You finished all 0 personal exercises today. Great job!",
         "0 personal exercises left. Go down the list in order."),
    ],
)
def test_exercise_english_plurals(count, done, left):
    assert exercise_advice.advice("routine_today_all_done", count=count).text_en == done
    assert exercise_advice.advice("routine_today_left", count=count).text_en == left


def test_exercise_english_days_and_weeks_plurals():
    one = exercise_advice.advice("record_all_steady", days=1, minutes=30, weeks=1)
    many = exercise_advice.advice("record_all_steady", days=5, minutes=150, weeks=12)
    assert one.text_en == "1 day and 30 min over 1 week — nice and steady."
    assert many.text_en == "5 days and 150 min over 12 weeks — nice and steady."


@pytest.mark.parametrize(
    ("code", "label"),
    [
        ("cardio", "cardio"),
        ("strength", "strength"),
        ("stretching", "stretching"),
        ("other", "other exercise"),
        # 옛 값도 표준 코드로 접어 부른다.
        ("walking", "cardio"),
        ("yoga", "stretching"),
    ],
)
def test_exercise_english_type_labels(code, label):
    text = exercise_advice.advice("record_today", type=code, minutes=20, calories=100).text_en
    assert text == f"Today: 20 min and 100 kcal, mostly {label}. Wrap up with a stretch."


@pytest.mark.parametrize(
    ("part", "middle", "start"),
    [
        ("lower", "lower-body", "Lower-body"),
        ("upper", "upper-body", "Upper-body"),
        ("core", "core", "Core"),
        ("full", "full-body", "Full-body"),
    ],
)
def test_exercise_english_body_parts(part, middle, start):
    assert (
        exercise_advice.advice("routine_all_done_today_part", part=part).text_en
        == f"You did the {middle} workouts you often skip today. Keep it going!"
    )
    assert exercise_advice.advice("routine_all_missed_part", part=part).text_en.startswith(
        f"{start} personal exercises"
    )


@pytest.mark.parametrize(
    ("rest", "lead", "keep"),
    [
        ("remaining", "For the rest of the week", "Keep it going for the rest of the week."),
        ("next_week", "Next week", "Keep it going next week."),
    ],
)
def test_exercise_english_rest_of_week(rest, lead, keep):
    only = exercise_advice.advice(
        "routine_week_only", top="cardio", missing="strength", rest=rest
    )
    assert only.text_en == (
        f"This week you only did cardio workouts. {lead}, start with strength."
    )
    counts = exercise_advice.advice(
        "routine_week_counts_keep", assigned=5, completed=3, rest=rest
    )
    assert counts.text_en.endswith(keep)


def test_exercise_english_keeps_non_korean_names_without_particles():
    """영어 문장은 조사가 없다 — 한글 이름이든 영문 이름이든 그대로 넣는다."""
    ko_name = exercise_advice.advice("routine_all_missed_name", name="스쿼트")
    en_name = exercise_advice.advice("routine_all_missed_name_plain", name="Squat")
    assert ko_name.text_en == "스쿼트 gets skipped often. Try doing it first next time?"
    assert en_name.text_en == "Squat gets skipped often. Try doing it first next time?"
    assert "을" not in ko_name.text_en and "(를)" not in en_name.text_en


def test_text_for_follows_the_request_locale(english):
    advice = exercise_advice.advice("record_all_up")
    assert advice.text_for() == advice.text_en
    # 명시한 언어가 요청 언어보다 우선한다.
    assert advice.text_for("ko") == advice.text


def test_text_for_defaults_to_korean_outside_a_request():
    advice = exercise_advice.advice("record_all_up")
    assert advice.text_for() == advice.text


def test_unknown_exercise_key_is_still_rejected():
    with pytest.raises(KeyError):
        exercise_advice.advice("no_such_key")


# ---------------------------------------------------------------------------
# 운동 조언 — 규칙이 고른 조언이 두 언어로 같은 키
# ---------------------------------------------------------------------------


def _records(raw: list[dict]) -> list[ExerciseDayTotals]:
    return [
        ExerciseDayTotals(
            date=date.fromisoformat(r["date"]),
            minutes=r["minutes"],
            calories=r["calories"],
            by_type=dict(r["by_type"]),
        )
        for r in raw
    ]


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
    ("days", "period", "ko", "en"),
    [
        ([], TODAY, "오늘 운동 기록이 아직 없어요. 10분 걷기부터 시작해 볼까요?",
         "No workout logged today yet. How about a 10-minute walk to start?"),
        ([], WEEK, "이번 주 운동 기록이 아직 없어요. 10분 걷기부터 시작해 볼까요?",
         "No workouts logged this week yet. How about a 10-minute walk to start?"),
        ([], ALL, "기록이 쌓이면 운동량과 유형의 흐름을 짚어 드릴게요.",
         "Once you log more, we'll show how your workout volume and types are trending."),
        (_ex_days((0, {"cardio": 30})), TODAY,
         "오늘 유산소 위주로 30분, 210kcal 썼어요. 스트레칭으로 마무리해요.",
         "Today: 30 min and 210 kcal, mostly cardio. Wrap up with a stretch."),
        (_ex_days((0, {"strength": 40})), WEEK,
         "이번 주는 40분 하루뿐이에요. 한 번 더 나가면 흐름이 이어져요.",
         "Just one day this week (40 min). One more workout keeps the flow going."),
        (_ex_days((0, {"cardio": 30}), (1, {"cardio": 30})), WEEK,
         "이번 주 2일 60분이 유산소에 몰렸어요. 근력도 섞어 볼까요?",
         "This week's 2 days and 60 min leaned on cardio. Mix in some strength?"),
        (_ex_days((0, {"cardio": 30}), (1, {"strength": 30})), WEEK,
         "이번 주 2일 60분, 유형도 고르게 섞였어요.",
         "2 days and 60 min this week, with a good mix of types."),
    ],
)
def test_exercise_period_message_in_both_languages(days, period, ko, en):
    assert exercise_service.period_coach_message(days, period) == ko
    assert exercise_service.period_coach_message(days, period, locale="ko") == ko
    assert exercise_service.period_coach_message(days, period, locale="en") == en


def test_exercise_period_message_uses_the_request_locale(english):
    assert (
        exercise_service.period_coach_message([], ALL)
        == "Once you log more, we'll show how your workout volume and types are trending."
    )


@pytest.mark.parametrize("case", _CASES["cases"], ids=[c["name"] for c in _CASES["cases"]])
def test_shared_cases_in_english_match_the_arb(case):
    """공유 사례의 조언을 영어로 — 회원 앱이 같은 키로 그리는 문장과 같다."""
    from tests.test_period_advice_copy import _routine_days

    result = exercise_service.period_advice(
        _records(case["records"]), case["period"], _routine_days(case["days"])
    )
    assert result.text == case["expected"]["message"]
    assert result.text_for("en") == render_icu(
        _EN_ARB[_arb_key(result.key)], result.params
    )


# ---------------------------------------------------------------------------
# 식단 조언 — 기간 조언(트레이너웹)과 오늘 코칭 한 마디
# ---------------------------------------------------------------------------


def _diet_days(*sodium_by_back: tuple[int, int]) -> list[DietDayTotals]:
    days = []
    for back, sodium in sorted(sodium_by_back, reverse=True):
        day = _TODAY - timedelta(days=back)
        days.append(
            DietDayTotals(
                date=day,
                calories=1800,
                sodium_mg=sodium,
                sugar_g=30,
            )
        )
    return days


LIMIT = diet_service.SODIUM_LIMIT_MG
WEEKS = period_window.ALL_PERIOD_DAYS // 7


def _weekend(back_from_today: int) -> bool:
    return (_TODAY - timedelta(days=back_from_today)).weekday() >= 5


DIET_CASES = [
    pytest.param([], TODAY,
                 "오늘 식단 기록이 아직 없어요. 첫 끼니를 기록해 볼까요?",
                 "No meals logged today yet. Want to log your first meal?", id="today-empty"),
    pytest.param([], WEEK,
                 "이번 주 식단 기록이 아직 없어요. 한 끼만 남겨도 흐름이 보여요.",
                 "No meals logged this week yet. Even one meal shows the trend.", id="week-empty"),
    pytest.param([], ALL,
                 "기록이 쌓이면 나트륨·칼로리 흐름을 짚어 드릴게요.",
                 "Once you log more, we'll show how your sodium and calories are trending.",
                 id="all-empty"),
    pytest.param(_diet_days((0, LIMIT + 400)), TODAY,
                 f"오늘 나트륨 {LIMIT + 400:,}mg으로 권장량을 넘겼어요. 남은 끼니는 담백하게.",
                 f"Sodium is at {LIMIT + 400:,} mg today, over the limit. Keep the rest of your meals light.",
                 id="today-over"),
    pytest.param(_diet_days((0, LIMIT)), TODAY,
                 f"오늘 나트륨 {LIMIT:,}mg으로 권장량 안이에요. 이대로 마무리해요.",
                 f"Sodium is at {LIMIT:,} mg today, within the limit. Finish the day like this.",
                 id="today-at-limit"),
    pytest.param(_diet_days((0, 1200)), TODAY,
                 "오늘 나트륨 1,200mg으로 권장량 안이에요. 이대로 마무리해요.",
                 "Sodium is at 1,200 mg today, within the limit. Finish the day like this.",
                 id="today-under"),
    pytest.param(_diet_days((0, 3000), (1, 3000), (2, 3000)), WEEK,
                 "이번 주 3일이나 나트륨을 넘겼어요. 국물은 건더기 위주로 드세요.",
                 "Sodium went over on 3 days this week. With soups, eat the solids and leave the broth.",
                 id="week-three-over"),
    pytest.param(_diet_days((0, 3000), (1, 1000)), WEEK,
                 "이번 주 1일만 권장량을 넘었어요. 나머지 날의 균형은 좋았어요.",
                 "Only 1 day went over the sodium limit this week. The other days were well balanced.",
                 id="week-one-over"),
    pytest.param(_diet_days((0, 3000), (1, 3000), (2, 1000)), WEEK,
                 "이번 주 2일만 권장량을 넘었어요. 나머지 날의 균형은 좋았어요.",
                 "Only 2 days went over the sodium limit this week. The other days were well balanced.",
                 id="week-two-over"),
    pytest.param(_diet_days((0, 1000), (1, 1000)), WEEK,
                 "이번 주 2일 모두 나트륨을 권장량 안에서 지켰어요!",
                 "You kept sodium within the limit on all 2 days this week!",
                 id="week-all-under"),
    pytest.param(_diet_days((0, 1000)), WEEK,
                 "이번 주 1일 모두 나트륨을 권장량 안에서 지켰어요!",
                 "You kept sodium within the limit on the 1 day you logged this week!",
                 id="week-one-day-under"),
    pytest.param(_diet_days(*((b, 3000) for b in range(40, 30, -1)), *((b, 1000) for b in range(10))),
                 ALL,
                 "최근 4주 나트륨이 그 전보다 낮아졌어요. 지금 방식이 잘 맞아요.",
                 "Sodium over the last 4 weeks is lower than before. This approach suits you.",
                 id="all-down"),
    pytest.param(_diet_days(*((b, 1000) for b in range(40, 30, -1)), *((b, 3000) for b in range(10))),
                 ALL,
                 "최근 4주 나트륨이 다시 올라가고 있어요. 한 주만 되짚어 볼까요?",
                 "Sodium is creeping back up over the last 4 weeks. Want to look back over one week?",
                 id="all-up"),
    pytest.param(_diet_days(*((b, 3000 if _weekend(b) else 1000) for b in range(14))), ALL,
                 f"최근 {WEEKS}주 주말마다 나트륨이 올라요. 주말 한 끼만 담백하게 바꿔요.",
                 f"Over the last {WEEKS} weeks, sodium rises every weekend. Make one weekend meal lighter.",
                 id="all-weekend"),
    pytest.param(_diet_days((0, 3000), (1, 3000), (2, 1000), (3, 1000), (4, 1000)), ALL,
                 f"최근 {WEEKS}주 중 40%가 나트륨 권장량을 넘었어요. 국물부터 남겨 봐요.",
                 f"40% of days in the last {WEEKS} weeks went over the sodium limit. Start by leaving the broth.",
                 id="all-ratio"),
    pytest.param(_diet_days((0, 1000), (1, 1000), (2, 3000)), ALL,
                 f"최근 {WEEKS}주 기록한 3일 대부분이 권장량 안이에요. 지금 흐름이 좋아요.",
                 f"Most of your 3 logged days in the last {WEEKS} weeks stayed within the sodium limit. Nice trend.",
                 id="all-mostly-under"),
    pytest.param(_diet_days((0, 1000)), ALL,
                 f"최근 {WEEKS}주 기록한 1일 대부분이 권장량 안이에요. 지금 흐름이 좋아요.",
                 f"Your 1 logged day in the last {WEEKS} weeks stayed within the sodium limit. Nice trend.",
                 id="all-one-day"),
]


@pytest.mark.parametrize(("days", "period", "ko", "en"), DIET_CASES)
def test_diet_period_message_in_both_languages(days, period, ko, en):
    assert diet_service.period_coach_message(days, period) == ko
    assert diet_service.period_coach_message(days, period, locale="ko") == ko
    assert diet_service.period_coach_message(days, period, locale="en") == en
    assert _no_hangul(en)


@pytest.mark.parametrize(("days", "period", "ko", "en"), DIET_CASES)
def test_diet_period_message_follows_the_request_locale(english, days, period, ko, en):
    assert diet_service.period_coach_message(days, period) == en
    assert diet_service.period_coach_message(days, period, locale="ko") == ko


def test_diet_english_messages_are_distinct_per_rule():
    """규칙마다 다른 영어 문장이다 — 번역하다 두 규칙을 한 문장으로 뭉개지 않았다."""
    english = {c.values[3] for c in DIET_CASES}
    korean = {c.values[2] for c in DIET_CASES}
    assert len(english) == len(korean)


@pytest.mark.parametrize(
    ("sodium", "has_entries", "ko", "en"),
    [
        (LIMIT + 1, True,
         "오늘 나트륨 섭취가 많았어요. 저녁은 담백한 구이/샐러드로 균형을 맞춰봐요!",
         "You had a lot of sodium today. Balance it out with a light grilled dish or salad for dinner!"),
        (0, False,
         "아직 오늘 식단 기록이 없어요. 첫 끼니를 기록해 볼까요?",
         "No meals logged today yet. Want to log your first meal?"),
        (LIMIT, True,
         "균형 잡힌 하루였어요. 내일도 이대로 가요!",
         "A well-balanced day. Keep it up tomorrow!"),
    ],
)
def test_diet_coach_message_in_both_languages(sodium, has_entries, ko, en):
    assert diet_service.coach_message(sodium, has_entries) == ko
    assert diet_service.coach_message(sodium, has_entries, locale="en") == en
    token = _request_locale_ctx.set("en")
    try:
        assert diet_service.coach_message(sodium, has_entries) == en
    finally:
        _request_locale_ctx.reset(token)


# ---------------------------------------------------------------------------
# API — 트레이너웹 경로와 회원 앱 운동 조언
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


def _without_foods(body: dict) -> str:
    """영어 문장에서 음식 이름을 뺀다 — 음식 이름은 회원이 기록한 말 그대로라
    번역하지 않는다(#2379)."""
    message = body["message"]
    for sentence in body.get("sentences") or []:
        for key, value in sentence["params"].items():
            if key.startswith("food") and isinstance(value, str) and not key.startswith("food_value"):
                message = message.replace(value, "")
    return message


@pytest.mark.parametrize("period", ["today", "week", "all"])
@pytest.mark.parametrize("kind", ["diet-advice", "exercise-advice"])
def test_trainer_advice_is_english_when_asked(client, kind, period):
    token = _trainer_token(client)
    url = f"/v1/trainer/clients/user-jisu/{kind}?period={period}"
    en = client.get(url, headers=_auth(token, "en"))
    ko = client.get(url, headers=_auth(token, "ko"))
    default = client.get(url, headers=_auth(token))
    for response in (en, ko, default):
        assert response.status_code == 200, response.text
    assert _no_hangul(_without_foods(en.json())) or kind == "exercise-advice", en.json()
    assert en.json()["message"] != ko.json()["message"]
    # 헤더가 없으면 지금까지처럼 한국어다.
    assert default.json()["message"] == ko.json()["message"]
    assert _HANGUL.search(ko.json()["message"])
    # 언어가 바뀌어도 규칙이 고른 것(구간·기록 수·키)은 같다.
    for field in ("period", "from_date", "to_date", "days_logged"):
        assert en.json()[field] == ko.json()[field]
    if kind == "exercise-advice":
        assert en.json()["advice_key"] == ko.json()["advice_key"]
        assert en.json()["advice_params"] == ko.json()["advice_params"]


def test_trainer_diet_advice_today_english_names_the_sodium(client, jisu_over_sodium_today):
    token = _trainer_token(client)
    body = client.get(
        "/v1/trainer/clients/user-jisu/diet-advice?period=today",
        headers=_auth(token, "en-US,en;q=0.9,ko;q=0.5"),
    ).json()
    # 트레이너 `식단 분석`(#2379) — 넘친 영양과 그 원인(음식 또는 끼니)을 짚는다.
    assert "pushed today's sodium to" in body["message"]
    assert body["sentences"][0]["key"] in ("tr_today_over", "tr_today_over_meal")
    assert body["sentences"][0]["params"]["nutrient"] == "sodium"
    assert _no_hangul(_without_foods(body))
    assert _no_hangul(body["message"])


def test_trainer_advice_english_respects_q_weights(client):
    token = _trainer_token(client)
    url = "/v1/trainer/clients/user-jisu/diet-advice?period=all"
    prefers_ko = client.get(url, headers=_auth(token, "en;q=0.3, ko;q=0.9")).json()
    unsupported = client.get(url, headers=_auth(token, "fr-FR")).json()
    ko = client.get(url, headers=_auth(token, "ko")).json()
    assert prefers_ko["message"] == ko["message"]
    assert unsupported["message"] == ko["message"]


@pytest.mark.parametrize("kind", ["diet-advice", "exercise-advice"])
def test_trainer_advice_still_refuses_other_members_in_english(client, kind):
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
def test_member_exercise_advice_message_follows_the_language(client, period):
    """회원 앱은 키로 그리지만, 키를 모르는 옛 앱이 읽는 `message` 도 언어를 따른다."""
    token = _jisu_token(client)
    url = f"/v1/exercise/advice?period={period}"
    en = client.get(url, headers=_auth(token, "en")).json()
    ko = client.get(url, headers=_auth(token)).json()
    assert en["advice_key"] == ko["advice_key"]
    advice = exercise_advice.advice(en["advice_key"], **en["advice_params"])
    assert en["message"] == advice.text_en
    assert ko["message"] == advice.text


def test_member_diet_day_coach_message_follows_the_language(client, jisu_over_sodium_today):
    token = _jisu_token(client)
    en = client.get("/v1/diet/days/today", headers=_auth(token, "en")).json()
    ko = client.get("/v1/diet/days/today", headers=_auth(token)).json()
    assert en["ai_coach_message"].startswith("You had a lot of sodium today.")
    assert ko["ai_coach_message"].startswith("오늘 나트륨 섭취가 많았어요.")
