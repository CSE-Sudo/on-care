"""트레이너 웹 `식단 분석` — 원인까지 짚는 서술형 규칙 문장. (#2379)

DB 없이 규칙만 본다. 보는 것:

1. 오늘 — 넘친 영양은 가장 많이 채운 음식과 목표 대비 배수로, 모자란 단백질은
   부족분과 4주 평균으로, 지난 끼니 마감이 지났는데 없으면 그 끼니를 말한다.
2. 이번 주·전체는 회원 앱과 같은 판정 선으로 문제를 두 가지까지 말하고 원인을
   붙인다. 이번 주는 첫 문제를 지난주와 견주고, 모두 합쳐 4문장을 넘지 않는다.
3. 모든 키에 한국어·영어 틀이 있고, 값이 틀을 빠짐없이 채운다.
"""
from __future__ import annotations

import json
import string
from datetime import date, datetime, timedelta
from types import SimpleNamespace

import pytest

from app.core import clock
from app.services import diet_coach_inputs as inputs
from app.services import diet_trainer_analysis as svc

TARGETS = inputs.DietTargets(calories=2000, protein_g=100, sodium_mg=2000, sugar_g=50)


def _entry(day: date, slot: str, foods: list[dict], **totals):
    base = {"total_calories": 0, "protein_g": 0, "sodium_mg": 0, "sugar_g": 0,
            "carbs_g": 0, "fat_g": 0}
    base.update(totals)
    return SimpleNamespace(
        date=day.isoformat(), meal_type=slot,
        foods_json=json.dumps(foods, ensure_ascii=False), **base,
    )


def _at(day: date, hour: int) -> datetime:
    return datetime(day.year, day.month, day.day, hour, 0, tzinfo=clock.SEOUL)


# ── 오늘 ────────────────────────────────────────────────────────────────


def test_today_names_the_food_behind_the_overflow_and_the_ratio():
    day = date(2026, 9, 28)
    entries = [
        _entry(day, "breakfast", [{"name": "스크램블 에그", "sodium_mg": 358}],
               sodium_mg=359, protein_g=16, total_calories=247),
        _entry(day, "lunch", [{"name": "짬뽕", "sodium_mg": 4286}],
               sodium_mg=4286, protein_g=35, total_calories=707),
    ]
    out = svc.today_sentences(entries, TARGETS, _at(day, 16), avg_protein_g=54)
    assert [s.key for s in out] == ["tr_today_over", "tr_today_protein_chronic"]
    assert out[0].text == (
        "점심에 먹은 짬뽕(4,286mg) 때문에 오늘 나트륨이 4,645mg까지 올라 목표 2,000mg의 "
        "2.3배가 됐어요."
    )
    assert out[1].text == (
        "단백질은 51g으로 목표보다 49g 모자라고, 최근 4주 평균도 하루 54g이라 꾸준히 "
        "부족한 편이에요."
    )


def test_today_without_food_values_points_at_the_meal():
    day = date(2026, 9, 28)
    entries = [_entry(day, "lunch", [], sodium_mg=6000, protein_g=95, total_calories=900)]
    out = svc.today_sentences(entries, TARGETS, _at(day, 13), avg_protein_g=None)
    # 13시 — 아침 마감(11시)이 지나 빠진 아침도 함께 말한다.
    assert [s.key for s in out] == ["tr_today_over_meal", "tr_today_missing"]
    assert out[0].text.startswith("점심 식사(6,000mg) 때문에 오늘 나트륨이")


def test_today_meal_without_food_values_beats_a_smaller_valued_food():
    # 음식별 값이 있는 작은 음식(980mg)을 두고, 값이 없는 큰 끼니(6,000mg)를
    # 원인에서 빼면 안 된다.
    day = date(2026, 9, 28)
    entries = [
        _entry(day, "breakfast", [{"name": "현미밥", "sodium_mg": 980}],
               sodium_mg=980, protein_g=50, total_calories=500),
        _entry(day, "lunch", [], sodium_mg=6000, protein_g=50, total_calories=900),
    ]
    out = svc.today_sentences(entries, TARGETS, _at(day, 13), avg_protein_g=None)
    assert out[0].key == "tr_today_over_meal"
    assert out[0].params["slot"] == "lunch" and out[0].params["food_value"] == 6000


def test_today_short_protein_without_a_chronic_average_stays_short():
    day = date(2026, 9, 28)
    entries = [_entry(day, "breakfast", [], protein_g=60, total_calories=500)]
    out = svc.today_sentences(entries, TARGETS, _at(day, 10), avg_protein_g=95)
    assert [s.key for s in out] == ["tr_today_protein_short"]


def test_today_names_a_meal_whose_deadline_has_passed():
    day = date(2026, 9, 28)
    entries = [_entry(day, "breakfast", [], protein_g=95, total_calories=500)]
    # 14시는 점심 마감(15시) 전이다 — 아직 빠졌다고 하지 않는다.
    assert [s.key for s in svc.today_sentences(entries, TARGETS, _at(day, 14), None)] == [
        "tr_today_good"
    ]
    out = svc.today_sentences(entries, TARGETS, _at(day, 16), None)
    assert out[-1].key == "tr_today_missing" and out[-1].params["slot"] == "lunch"


def test_today_good_and_empty():
    day = date(2026, 9, 28)
    entries = [
        _entry(day, "breakfast", [], protein_g=40, total_calories=500),
        _entry(day, "lunch", [], protein_g=60, total_calories=700),
    ]
    assert [s.key for s in svc.today_sentences(entries, TARGETS, _at(day, 13), None)] == [
        "tr_today_good"
    ]
    assert [s.key for s in svc.today_sentences([], TARGETS, _at(day, 13), None)] == [
        "tr_today_empty"
    ]


# ── 이번 주 ─────────────────────────────────────────────────────────────


def test_week_over_names_the_biggest_meal():
    # 목요일 — 이번 주 월~목, 사흘이 나트륨을 넘었다.
    today = date(2026, 10, 1)
    monday = today - timedelta(days=today.weekday())
    entries = []
    for i in range(4):
        d = monday + timedelta(days=i)
        entries.append(_entry(d, "breakfast", [{"name": "토스트"}],
                              sodium_mg=300, protein_g=30, total_calories=400))
        sodium = 1500 if i == 3 else (4286 if i == 0 else 2500)
        entries.append(_entry(d, "lunch", [{"name": "짬뽕" if i == 0 else "라면"}],
                              sodium_mg=sodium, protein_g=40, total_calories=700))
    start, end, logged, out = svc.week_sentences(entries, TARGETS, _at(today, 20))
    assert (start, end, logged) == (monday, today, 4)
    # 나트륨·단백질이 모두 사흘 — 같으면 과잉이 먼저고, 둘째 문제도 근거와 함께 말한다.
    assert [s.key for s in out] == [
        "tr_week_over", "tr_week_cause", "tr_week_protein_short", "tr_week_protein_avg",
    ]
    assert out[0].text == "이번 주 기록한 4일 중 3일 나트륨이 목표를 넘었어요."
    assert out[1].text == "월요일 점심에 먹은 짬뽕(4,286mg) 영향이 가장 컸어요."
    assert out[2].text == "이번 주 기록한 4일 중 3일 단백질이 목표의 80%에 못 미쳤어요."
    assert out[3].text == "모자란 날은 하루 평균 70g 정도였어요."


def test_week_compares_the_first_finding_with_last_week_and_caps_at_four():
    # 목요일 — 지난주 기록이 있으면 첫 문제를 지난주와 견주고, 넘치는 근거는 버린다.
    today = date(2026, 10, 1)
    monday = today - timedelta(days=today.weekday())
    entries = []
    for i in range(-7, 4):
        d = monday + timedelta(days=i)
        sodium = 2500 if (i >= 0 and i != 3) or i in (-7, -6) else 900
        entries.append(_entry(d, "breakfast", [{"name": "토스트"}],
                              sodium_mg=300, protein_g=30, total_calories=400))
        entries.append(_entry(d, "lunch", [{"name": "라면"}],
                              sodium_mg=sodium, protein_g=40, total_calories=700))
    _, _, _, out = svc.week_sentences(entries, TARGETS, _at(today, 20))
    assert [s.key for s in out] == [
        "tr_week_over", "tr_week_cause", "tr_week_vs_last", "tr_week_protein_short",
    ]
    assert out[2].text == "지난주에는 기록한 7일 중 2일이었어요."
    assert len(out) == svc.MAX_SENTENCES


def test_week_breakfast_snack_names_what_replaced_breakfast():
    today = date(2026, 10, 1)
    monday = today - timedelta(days=today.weekday())
    entries = []
    for i in range(4):
        d = monday + timedelta(days=i)
        entries.append(_entry(d, "snack", [{"name": "빵" if i else "과자"}],
                              protein_g=40, total_calories=300))
        entries.append(_entry(d, "lunch", [{"name": "샐러드"}],
                              protein_g=50, total_calories=600))
    _, _, _, out = svc.week_sentences(entries, TARGETS, _at(today, 20))
    assert [s.key for s in out[:2]] == [
        "tr_week_skip_breakfast_snack", "tr_week_breakfast_snack_food",
    ]
    assert out[1].text == "아침 대신 먹은 것은 빵 3번이 가장 많았어요."


def test_week_good_adds_the_daily_average():
    today = date(2026, 10, 1)
    monday = today - timedelta(days=today.weekday())
    entries = [
        _entry(monday + timedelta(days=i), slot, [], protein_g=50, total_calories=900)
        for i in range(3) for slot in ("breakfast", "lunch")
    ]
    _, _, _, out = svc.week_sentences(entries, TARGETS, _at(today, 20))
    assert [s.key for s in out] == ["tr_week_good", "tr_week_good_avg"]
    assert out[1].text == "하루 평균 1,800kcal, 단백질 100g을 드셨어요."


def test_week_empty():
    today = date(2026, 10, 1)
    _, _, logged, out = svc.week_sentences([], TARGETS, _at(today, 20))
    assert logged == 0 and [s.key for s in out] == ["tr_week_empty"]


# ── 전체 ────────────────────────────────────────────────────────────────


def test_all_slot_sodium_names_the_foods():
    today = date(2026, 9, 28)
    entries = []
    for i in range(10):
        d = today - timedelta(days=i + 1)
        food = "짬뽕" if i < 3 else ("라면" if i < 5 else "김치찌개")
        entries.append(_entry(d, "lunch", [{"name": food}],
                              sodium_mg=2500, protein_g=40, carbs_g=80, fat_g=20,
                              total_calories=700))
        entries.append(_entry(d, "dinner", [{"name": "닭가슴살"}],
                              sodium_mg=400, protein_g=50, carbs_g=30, fat_g=10,
                              total_calories=500))
    logged, out = svc.all_sentences(entries, TARGETS, today)
    assert logged == 10
    # 회원 앱은 하나만 말하지만, 트레이너 웹은 다음 후보(자주 먹은 메뉴)까지 말한다.
    assert [s.key for s in out] == ["tr_all_slot_sodium", "tr_foods_two", "tr_all_frequent"]
    assert out[0].text == "최근 4주 동안 점심 나트륨이 10번 목표의 절반을 넘었어요."
    assert out[1].text == "김치찌개 5번, 짬뽕 3번이 대부분이에요."
    assert out[2].text == "최근 4주 동안 저녁 메뉴로 닭가슴살 10번이 가장 많았어요."


def test_all_few_records():
    today = date(2026, 9, 28)
    entries = [_entry(today - timedelta(days=1), "lunch", [], total_calories=500)]
    logged, out = svc.all_sentences(entries, TARGETS, today)
    assert [s.key for s in out] == ["tr_all_few"] and out[0].params["days"] == 1


# ── 틀 ─────────────────────────────────────────────────────────────────


def _fields(template: str) -> set[str]:
    return {f for _, f, _, _ in string.Formatter().parse(template) if f}


@pytest.mark.parametrize("key", svc.KEYS)
def test_every_key_has_korean_and_english_with_the_same_values(key):
    assert key in svc._EN
    # 두 언어가 같은 값(수치·이름)을 쓴다 — 말이 다르면 번역이 뜻을 바꾼 것이다.
    raw = {"food", "food1", "food2", "count", "count1", "count2", "days", "logged",
           "snack_days", "pct", "before", "after", "ratio", "prev_logged", "prev_days"}
    assert _fields(svc._KO[key]) & raw == _fields(svc._EN[key]) & raw


def test_english_message_has_no_hangul_except_food_names():
    s = svc.Sentence("tr_week_over", {"scope": "last", "logged": 5, "days": 2,
                                      "nutrient": "sugar"})
    assert s.text_in("en") == "Sugar went over the goal on 2 of 5 logged days last week."
