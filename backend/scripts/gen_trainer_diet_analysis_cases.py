"""트레이너 웹 `식단 분석` 공유 사례 파일을 서버 규칙으로 만든다. (#2379)

서버(`diet_trainer_analysis`)와 트레이너 웹 데모
(`frontend/flutter_trainer/lib/features/clients/domain/diet_analysis_rules.dart`)가
**같은 입력에 같은 문장 키·값**을 내는지, 트레이너 웹 ARB 가 서버 틀과 **같은 문장**을
그리는지 두 쪽 테스트가 이 파일로 본다. 규칙이나 문장을 바꾸면 이 스크립트를 다시
돌려 파일을 고친다(두 테스트가 어긋난 쪽을 알려 준다).

    cd backend && python scripts/gen_trainer_diet_analysis_cases.py
"""
from __future__ import annotations

import json
import sys
from datetime import date, datetime, timedelta
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.core import clock  # noqa: E402
from app.services import diet_coach_inputs as inputs  # noqa: E402
from app.services import diet_trainer_analysis as svc  # noqa: E402

OUT = (
    Path(__file__).resolve().parents[2]
    / "frontend/flutter_trainer/test/features/clients/diet_analysis_cases.json"
)

TARGETS = {"calories": 2000, "protein_g": 100, "sodium_mg": 2000, "sugar_g": 50}
MON = date(2026, 9, 21)
THU = date(2026, 9, 24)


def entry(day: date, meal: str, foods: list[tuple[str, int, int, float]] | None = None, *,
          kcal=500, protein=30, sodium=500, sugar=5, carbs=60, fat=15) -> dict:
    """foods: (이름, 칼로리, 나트륨, 당류). 비우면 음식별 값이 없는 옛 기록이다."""
    return {
        "date": day.isoformat(), "meal_type": meal,
        "foods": [
            {"name": n, "calories": c, "sodium_mg": s, "sugar_g": g}
            for n, c, s, g in (foods or [])
        ],
        "kcal": kcal, "protein_g": protein, "sodium_mg": sodium, "sugar_g": sugar,
        "carbs_g": carbs, "fat_g": fat,
    }


def named(day: date, meal: str, name: str, **kw) -> dict:
    """이름만 있는 음식 하나(값 없음)."""
    e = entry(day, meal, **kw)
    e["foods"] = [{"name": name}]
    return e


def to_entry(e: dict):
    return SimpleNamespace(
        date=e["date"], meal_type=e["meal_type"],
        foods_json=json.dumps(e["foods"], ensure_ascii=False),
        total_calories=e["kcal"], protein_g=e["protein_g"], sodium_mg=e["sodium_mg"],
        sugar_g=e["sugar_g"], carbs_g=e["carbs_g"], fat_g=e["fat_g"],
    )


def sentences_json(sentences) -> list[dict]:
    return [{"key": s.key, "params": s.params} for s in sentences]


def run_today(case: dict) -> dict:
    now = datetime.fromisoformat(case["now"]).replace(tzinfo=clock.SEOUL)
    entries = [to_entry(e) for e in case["entries"]]
    out = svc.today_sentences(
        entries, inputs.DietTargets(**case["targets"]), now, case.get("avg_protein_g"),
    )
    return {"sentences": sentences_json(out)}


def run_week(case: dict) -> dict:
    now = datetime.fromisoformat(case["now"]).replace(tzinfo=clock.SEOUL)
    entries = [to_entry(e) for e in case["entries"]]
    start, end, logged, out = svc.week_sentences(entries, inputs.DietTargets(**case["targets"]), now)
    return {"from": start.isoformat(), "to": end.isoformat(), "logged": logged,
            "sentences": sentences_json(out)}


def run_all(case: dict) -> dict:
    today = date.fromisoformat(case["today"])
    entries = [to_entry(e) for e in case["entries"]]
    logged, out = svc.all_sentences(entries, inputs.DietTargets(**case["targets"]), today)
    return {"logged": logged, "sentences": sentences_json(out)}


RUN = {"today": run_today, "week": run_week, "all": run_all}


def _days(n: int, end: date, make) -> list[dict]:
    out: list[dict] = []
    for i in range(n):
        out += make(end - timedelta(days=i + 1), i)
    return out


def cases() -> list[dict]:
    t = TARGETS
    at = lambda d, h: datetime(d.year, d.month, d.day, h, 0).isoformat()  # noqa: E731
    c: list[dict] = []

    # ── 오늘 ──
    c.append({"name": "today_empty", "period": "today", "now": at(THU, 13),
              "targets": t, "entries": []})
    c.append({"name": "today_sodium_food_and_chronic_protein", "period": "today",
              "now": at(THU, 16), "targets": t, "avg_protein_g": 54, "entries": [
                  entry(THU, "breakfast", [("스크램블 에그", 213, 358, 0.7), ("딸기", 34, 1, 6.1)],
                        kcal=247, protein=16, sodium=359, sugar=7),
                  entry(THU, "lunch", [("짬뽕", 707, 4286, 8.6)],
                        kcal=707, protein=35, sodium=4286, sugar=9),
              ]})
    c.append({"name": "today_meal_without_food_values", "period": "today", "now": at(THU, 13),
              "targets": t, "entries": [
                  entry(THU, "breakfast", [("현미밥", 300, 980, 1)], sodium=980, protein=50),
                  entry(THU, "lunch", None, kcal=900, sodium=6000, protein=50),
              ]})
    # 비율이 정확한 절반(2.25)과 이진수로 절반 아래(1.15)인 경계 — 서버 `:.1f` 와 데모가
    # 같은 문자열을 내는지 본다(#2441 리뷰).
    c.append({"name": "today_ratio_exact_half", "period": "today", "now": at(THU, 10),
              "targets": t, "entries": [
                  entry(THU, "breakfast", [("라면", 500, 4500, 3)], kcal=500, protein=95,
                        sodium=4500),
              ]})
    c.append({"name": "today_ratio_below_half", "period": "today", "now": at(THU, 10),
              "targets": t, "entries": [
                  entry(THU, "breakfast", [("김치찌개", 500, 2300, 3)], kcal=500, protein=95,
                        sodium=2300),
              ]})
    c.append({"name": "today_sugar_over", "period": "today", "now": at(THU, 10),
              "targets": t, "entries": [
                  entry(THU, "breakfast", [("라떼", 250, 150, 30.5), ("케이크", 400, 200, 40)],
                        kcal=650, protein=95, sodium=350, sugar=70),
              ]})
    c.append({"name": "today_calorie_over", "period": "today", "now": at(THU, 22),
              "targets": t, "entries": [
                  entry(THU, "breakfast", [("토스트", 500, 400, 5)], kcal=500, protein=30),
                  entry(THU, "lunch", [("돈가스", 1100, 900, 8)], kcal=1100, protein=35),
                  entry(THU, "dinner", [("치킨", 1000, 1000, 5)], kcal=1000, protein=40),
              ]})
    c.append({"name": "today_short_protein", "period": "today", "now": at(THU, 10),
              "targets": t, "avg_protein_g": 95, "entries": [
                  entry(THU, "breakfast", [("토스트", 400, 400, 5)], kcal=400, protein=60),
              ]})
    c.append({"name": "today_missing_lunch", "period": "today", "now": at(THU, 16),
              "targets": t, "entries": [
                  entry(THU, "breakfast", [("토스트", 400, 400, 5)], kcal=400, protein=95),
              ]})
    c.append({"name": "today_good", "period": "today", "now": at(THU, 13),
              "targets": t, "entries": [
                  entry(THU, "breakfast", [("토스트", 500, 400, 5)], kcal=500, protein=40),
                  entry(THU, "lunch", [("비빔밥", 700, 900, 5)], kcal=700, protein=60),
              ]})

    # ── 이번 주 ──
    c.append({"name": "week_empty", "period": "week", "now": at(THU, 20),
              "targets": t, "entries": []})
    over = []
    for i in range(4):
        d = MON + timedelta(days=i)
        over.append(named(d, "breakfast", "토스트", sodium=300, protein=30, kcal=400))
        sodium = 1500 if i == 3 else (4286 if i == 0 else 2500)
        over.append(named(d, "lunch", "짬뽕" if i == 0 else "라면",
                          sodium=sodium, protein=40, kcal=700))
    c.append({"name": "week_sodium_over", "period": "week", "now": at(THU, 20),
              "targets": t, "entries": over})
    skip = []
    for i in range(4):
        d = MON + timedelta(days=i)
        skip.append(named(d, "lunch", "비빔밥", protein=40, kcal=700))
        if i < 3:
            skip.append(named(d, "snack", "과자", protein=2, kcal=200, sodium=100))
    c.append({"name": "week_skip_breakfast_snack", "period": "week", "now": at(THU, 20),
              "targets": t, "entries": skip})
    good = []
    for i in range(3):
        d = MON + timedelta(days=i)
        for meal in ("breakfast", "lunch", "dinner"):
            good.append(named(d, meal, "현미밥", protein=40, kcal=500, sodium=400))
    c.append({"name": "week_good", "period": "week", "now": at(THU, 20),
              "targets": t, "entries": good})
    protein = []
    for i in range(3):
        d = MON + timedelta(days=i)
        for meal in ("breakfast", "lunch", "dinner"):
            protein.append(named(d, meal, "국수", protein=15, kcal=500, sodium=400))
    c.append({"name": "week_protein_short", "period": "week", "now": at(THU, 20),
              "targets": t, "entries": protein})
    # 화요일, 이번 주 기록 1일 + 지난주 기록 → 지난주를 돌아본다.
    tue = MON + timedelta(days=1)
    last = [named(MON - timedelta(days=7 - i), "breakfast", "토스트", sodium=2500)
            for i in range(3)]
    last.append(named(MON, "lunch", "비빔밥"))
    c.append({"name": "week_last_week", "period": "week", "now": at(tue, 20),
              "targets": t, "entries": last})

    # ── 전체(최근 4주) ──
    today = date(2026, 9, 28)
    c.append({"name": "all_few", "period": "all", "today": today.isoformat(), "targets": t,
              "entries": [named(today - timedelta(days=1), "lunch", "비빔밥")]})

    def slot_sodium(d, i):
        food = "짬뽕" if i < 3 else ("라면" if i < 5 else "김치찌개")
        return [named(d, "lunch", food, sodium=2500, protein=40, carbs=80, fat=20, kcal=700),
                named(d, "dinner", "닭가슴살", sodium=400, protein=50, carbs=30, fat=10, kcal=500)]
    c.append({"name": "all_slot_sodium", "period": "all", "today": today.isoformat(),
              "targets": t, "entries": _days(10, today, slot_sodium)})

    def carb(d, i):
        return [named(d, "lunch", "국수" if i % 2 else "떡볶이", sodium=600, protein=10,
                      carbs=150, fat=5, kcal=700)]
    c.append({"name": "all_carb_heavy", "period": "all", "today": today.isoformat(),
              "targets": t, "entries": _days(8, today, carb)})

    def trend(d, i):
        p = 95 if i < 7 else 40
        return [named(d, "lunch", f"메뉴{i}", sodium=600, protein=p, carbs=60, fat=30, kcal=700)]
    c.append({"name": "all_protein_trend_up", "period": "all", "today": today.isoformat(),
              "targets": t, "entries": _days(20, today, trend)})

    def freq(d, i):
        return [named(d, "lunch", "김밥" if i < 6 else f"메뉴{i}", sodium=600, protein=40,
                      carbs=60, fat=30, kcal=700)]
    c.append({"name": "all_frequent", "period": "all", "today": today.isoformat(),
              "targets": t, "entries": _days(9, today, freq)})

    def good_all(d, i):
        return [named(d, "lunch", f"메뉴{i}", sodium=600, protein=40, carbs=60, fat=30, kcal=700)]
    c.append({"name": "all_good", "period": "all", "today": today.isoformat(),
              "targets": t, "entries": _days(8, today, good_all)})
    return c


def renderings() -> list[dict]:
    """키마다 값 한 벌과 서버가 그린 한국어·영어 문장 — 앱 ARB 가 같게 그리는지 본다."""
    samples = {
        "tr_today_empty": {},
        "tr_today_over": {"nutrient": "sodium", "slot": "lunch", "food": "짬뽕",
                          "food_value": 4286, "value": 4645, "target": 2000, "ratio": "2.3"},
        "tr_today_over_meal": {"nutrient": "calorie", "slot": "dinner", "food_value": 1500,
                               "value": 2600, "target": 2000, "ratio": "1.3"},
        "tr_today_protein_short": {"nutrient": "protein", "value": 60, "gap": 40},
        "tr_today_protein_chronic": {"nutrient": "protein", "value": 51, "gap": 49, "avg": 54},
        "tr_today_missing": {"slot": "breakfast"},
        "tr_today_good": {"kcal": 1200},
        "tr_week_empty": {},
        "tr_week_skip_breakfast": {"scope": "this", "logged": 4, "days": 3},
        "tr_week_skip_breakfast_snack": {"scope": "last", "logged": 5, "days": 3, "snack_days": 2},
        "tr_week_over": {"scope": "this", "logged": 4, "days": 3, "nutrient": "sugar"},
        "tr_week_cause": {"weekday": 0, "slot": "lunch", "food": "짬뽕", "food_value": 4286,
                          "nutrient": "sodium"},
        "tr_week_protein_short": {"scope": "this", "logged": 3, "days": 3},
        "tr_week_good": {"scope": "this", "days": 3},
        "tr_all_few": {"days": 3},
        "tr_all_slot_sodium": {"slot": "dinner", "days": 6},
        "tr_all_carb_heavy": {"pct": 68},
        "tr_all_protein_light": {"pct": 12},
        "tr_all_protein_trend_up": {"before": 2, "after": 6},
        "tr_all_protein_trend_down": {"before": 6, "after": 2},
        "tr_all_frequent": {"slot": "lunch", "food": "김밥", "count": 6},
        "tr_all_repeated": {"food1": "김밥", "food2": "라면"},
        "tr_all_good": {"days": 20},
        "tr_foods_one": {"food1": "짬뽕", "count1": 3},
        "tr_foods_two": {"food1": "짬뽕", "count1": 3, "food2": "라면", "count2": 2},
    }
    assert set(samples) == set(svc.KEYS), set(svc.KEYS) ^ set(samples)
    out = []
    for key in svc.KEYS:
        s = svc.Sentence(key, samples[key])
        out.append({"key": key, "params": s.params, "ko": s.text_in("ko"), "en": s.text_in("en")})
    return out


def build() -> dict:
    all_cases = cases()
    for case in all_cases:
        case["expected"] = RUN[case["period"]](case)
    return {"cases": all_cases, "renderings": renderings()}


if __name__ == "__main__":
    OUT.write_text(
        json.dumps(build(), ensure_ascii=False, indent=1) + "\n", encoding="utf-8", newline="\n"
    )
    print(f"wrote {OUT}")
