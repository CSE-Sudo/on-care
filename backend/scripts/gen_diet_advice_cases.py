"""식단 AI 맞춤 조언 공유 사례 파일을 서버 규칙으로 만든다. (#2255)

서버(`diet_period_advice`·`diet_week_advice`·`diet_all_advice`)와 데모
(`frontend/flutter/lib/core/demo/diet_advice.dart`)가 **같은 입력에 같은 규칙 한 줄과
다음 할 일**을 내는지 두 쪽 테스트가 이 파일로 본다. 규칙이나 문장을 바꾸면 이
스크립트를 다시 돌려 파일을 고친다(두 테스트가 어긋난 쪽을 알려 준다).

    cd backend && python scripts/gen_diet_advice_cases.py

데모에는 AI 가 없으므로 이번 주·전체의 다음 할 일은 **AI 가 실패했을 때의 규칙
문장**이다.
"""
from __future__ import annotations

import json
import sys
from dataclasses import asdict
from datetime import date, datetime, timedelta
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.core import clock  # noqa: E402
from app.services import diet_advice_copy as copy  # noqa: E402
from app.services import diet_all_advice as all_svc  # noqa: E402
from app.services import diet_coach_inputs as inputs  # noqa: E402
from app.services import diet_menu_plan  # noqa: E402
from app.services import diet_period_advice as today_svc  # noqa: E402
from app.services import diet_week_advice as week_svc  # noqa: E402

OUT = Path(__file__).resolve().parents[2] / "frontend/flutter/test/core/demo/diet_advice_cases.json"

TARGETS = {"calories": 2000, "protein_g": 90, "sodium_mg": 2000, "sugar_g": 50}
THU = date(2026, 9, 24)
MON = date(2026, 9, 21)


def entry(day: date, meal: str, name: str = "밥", *, kcal=500, protein=25, sodium=500,
          sugar=5, carbs=60, fat=15) -> dict:
    return {
        "date": day.isoformat(), "meal_type": meal, "foods": [name], "kcal": kcal,
        "protein_g": protein, "sodium_mg": sodium, "sugar_g": sugar, "carbs_g": carbs, "fat_g": fat,
    }


def to_entry(e: dict):
    return SimpleNamespace(
        date=e["date"], meal_type=e["meal_type"],
        foods_json=json.dumps([{"name": n} for n in e["foods"]], ensure_ascii=False),
        total_calories=e["kcal"], protein_g=e["protein_g"], sodium_mg=e["sodium_mg"],
        sugar_g=e["sugar_g"], carbs_g=e["carbs_g"], fat_g=e["fat_g"],
    )


def line_json(ln: copy.Line | None) -> dict | None:
    if ln is None:
        return None
    return {"key": ln.key, "params": ln.params, "text": ln.text}


def targets_of(t: dict) -> inputs.DietTargets:
    return inputs.DietTargets(**t)


DEMO_PLAN = {
    lang: [asdict(m) for m in diet_menu_plan.rules_plan(lang=lang, needs=[], excluded=set())]
    for lang in ("ko", "en")
}


def run_today(case: dict) -> dict:
    now = datetime.fromisoformat(case["now"]).replace(tzinfo=clock.SEOUL)
    today = now.date()
    entries = [to_entry(e) for e in case["entries"] if e["date"] == today.isoformat()]
    totals = today_svc.today_totals(entries)
    decision = today_svc.decide_today(totals, targets_of(case["targets"]), now.time())
    action = decision.action
    if decision.slot is not None:
        plan = [diet_menu_plan.PlanMenu(**m) for m in DEMO_PLAN[case.get("lang", "ko")]]
        menus = [m for m in plan if m.slot == decision.slot]
        recent = {diet_menu_plan.norm_name(n) for n in case.get("recent", [])}
        menu = today_svc.pick_menu(menus, decision.needs, recent, decision.satisfied)
        action = today_svc.menu_line(decision.slot, menu) if menu else None
    return {"analysis": line_json(decision.analysis), "action": line_json(action)}


def run_week(case: dict) -> dict:
    now = datetime.fromisoformat(case["now"]).replace(tzinfo=clock.SEOUL)
    scope, start, end, _records, finding = week_svc.decide_week(
        [to_entry(e) for e in case["entries"]], targets_of(case["targets"]), now,
    )
    if finding is None:
        analysis, action = copy.line("week_empty"), copy.line("week_empty_hint")
    else:
        analysis, action = finding.analysis, week_svc.fallback_action(finding)
    return {
        "from_date": start.isoformat(), "to_date": end.isoformat(),
        "analysis": line_json(analysis), "action": line_json(action),
    }


def run_all(case: dict) -> dict:
    now = datetime.fromisoformat(case["now"]).replace(tzinfo=clock.SEOUL)
    today = now.date()
    start = today - timedelta(days=all_svc.WINDOW_DAYS - 1)
    entries = [to_entry(e) for e in case["entries"] if start.isoformat() <= e["date"] <= today.isoformat()]
    _records, analysis, _finding = all_svc.decide_all(
        entries, targets_of(case["targets"]), today, case.get("last_kind"),
    )
    return {
        "from_date": start.isoformat(), "to_date": today.isoformat(),
        "analysis": line_json(analysis), "action": line_json(all_svc.fallback_action(analysis)),
    }


RUN = {"today": run_today, "week": run_week, "all": run_all}


def cases() -> list[dict]:
    out: list[dict] = []

    def add(name, period, now, entries, **extra):
        out.append({"name": name, "period": period, "now": now, "targets": extra.pop("targets", TARGETS),
                    "entries": entries, **extra})

    # ── 오늘 ──
    add("today_empty_morning", "today", "2026-09-24T08:00", [])
    add("today_empty_noon", "today", "2026-09-24T12:30", [])
    add("today_empty_night", "today", "2026-09-24T22:00", [])
    add("today_missing_breakfast", "today", "2026-09-24T13:00", [entry(THU, "lunch")])
    add("today_sodium_over", "today", "2026-09-24T13:00",
        [entry(THU, "breakfast", sodium=900), entry(THU, "lunch", "짬뽕", sodium=1500)])
    add("today_calorie_over", "today", "2026-09-24T16:00",
        [entry(THU, "breakfast", kcal=900, protein=50), entry(THU, "lunch", kcal=1400, protein=45)])
    add("today_protein_left", "today", "2026-09-24T13:00",
        [entry(THU, "breakfast", protein=15), entry(THU, "lunch", protein=20)])
    add("today_balanced", "today", "2026-09-24T19:00",
        [entry(THU, "breakfast", protein=30), entry(THU, "lunch", protein=30), entry(THU, "dinner", protein=30)])
    add("today_after_dinner_snack", "today", "2026-09-24T20:00",
        [entry(THU, m, kcal=400, protein=15) for m in ("breakfast", "lunch", "dinner")])
    add("today_after_dinner_done", "today", "2026-09-24T20:00",
        [entry(THU, m, kcal=600, protein=31) for m in ("breakfast", "lunch", "dinner")])
    add("today_protein_met_other_tag", "today", "2026-09-24T13:00",
        [entry(THU, "breakfast", protein=45), entry(THU, "lunch", protein=45)])
    add("today_recent_pushed_back", "today", "2026-09-24T08:00", [], recent=[DEMO_PLAN["ko"][0]["name"]])
    add("today_english", "today", "2026-09-24T13:00",
        [entry(THU, "breakfast", protein=15), entry(THU, "lunch", protein=20)], lang="en")
    add("today_personal_targets", "today", "2026-09-24T13:00",
        [entry(THU, "breakfast", sodium=700), entry(THU, "lunch", sodium=700)],
        targets={"calories": 1800, "protein_g": 60, "sodium_mg": 1300, "sugar_g": 40})

    # ── 이번 주 ──
    salty = [entry(MON + timedelta(days=i), m, "짬뽕" if m == "dinner" else "밥",
                   sodium=2500 if m == "dinner" else 500) for i in range(3) for m in ("breakfast", "lunch", "dinner")]
    add("week_empty", "week", "2026-09-24T19:00", [])
    add("week_focus_sodium", "week", "2026-09-24T19:00", salty)
    add("week_skip_breakfast_snack", "week", "2026-09-24T19:00",
        [entry(MON + timedelta(days=i), m) for i in range(3) for m in ("lunch", "dinner", "snack")])
    add("week_skip_breakfast", "week", "2026-09-24T19:00",
        [entry(MON + timedelta(days=i), m) for i in range(3) for m in ("lunch", "dinner")])
    add("week_today_before_eleven", "week", "2026-09-23T10:00",
        [entry(MON + timedelta(days=i), "lunch") for i in range(3)])
    add("week_focus_protein", "week", "2026-09-24T19:00",
        [entry(MON + timedelta(days=i), m, protein=20) for i in range(3) for m in ("breakfast", "lunch")])
    add("week_focus_calorie", "week", "2026-09-24T19:00",
        [entry(MON + timedelta(days=i), m, kcal=800, protein=30) for i in range(2) for m in ("breakfast", "lunch", "dinner")])
    add("week_focus_sugar_one_day", "week", "2026-09-24T19:00",
        [entry(MON + timedelta(days=i), m, protein=30, sugar=30 if i == 0 else 5)
         for i in range(3) for m in ("breakfast", "lunch", "dinner")])
    add("week_good", "week", "2026-09-24T19:00",
        [entry(MON + timedelta(days=i), m, protein=30) for i in range(3) for m in ("breakfast", "lunch", "dinner")])
    add("week_monday_looks_back", "week", "2026-09-21T09:00",
        [entry(MON - timedelta(days=7 - i), "dinner", "짬뽕", sodium=2500) for i in range(3)])
    add("week_tuesday_two_days_this_week", "week", "2026-09-22T19:00",
        [entry(MON - timedelta(days=5), "dinner", sodium=2500)]
        + [entry(MON + timedelta(days=i), m, protein=30) for i in range(2) for m in ("breakfast", "lunch", "dinner")])

    # ── 전체 ──
    def dinners(n, sodium=1800, lunch="김치찌개"):
        rows = []
        for i in range(n):
            day = THU - timedelta(days=i + 1)
            rows += [entry(day, "lunch", lunch), entry(day, "dinner", f"찌개{i}", sodium=sodium)]
        return rows

    add("all_few_records", "all", "2026-09-24T19:00", dinners(6))
    add("all_slot_sodium", "all", "2026-09-24T19:00", dinners(10))
    add("all_skips_last_kind", "all", "2026-09-24T19:00", dinners(10), last_kind="slot_sodium")
    add("all_old_records_ignored", "all", "2026-09-24T19:00",
        dinners(10, sodium=400, lunch="점심") + [entry(THU - timedelta(days=40), "dinner", "옛 찌개", sodium=5000)])
    add("all_carb_heavy", "all", "2026-09-24T19:00",
        [entry(THU - timedelta(days=i + 1), "lunch", f"면{i}", carbs=120, protein=15, fat=5) for i in range(8)])
    add("all_protein_light", "all", "2026-09-24T19:00",
        [entry(THU - timedelta(days=i + 1), "lunch", f"전{i}", carbs=50, protein=10, fat=30) for i in range(8)])
    trend_rows = []
    for i in range(1, 28):
        day = THU - timedelta(days=i)
        trend_rows.append(entry(day, "lunch", f"식사{i}", protein=95 if i <= 8 else 50, carbs=60, fat=20))
    add("all_protein_trend_up", "all", "2026-09-24T19:00", trend_rows)
    add("all_repeated_foods", "all", "2026-09-24T19:00",
        [entry(THU - timedelta(days=i + 1), m, "닭가슴살" if m == "lunch" else ("계란" if m == "dinner" else f"아침{i}"))
         for i in range(8) for m in ("breakfast", "lunch", "dinner")], last_kind="frequent")
    add("all_good", "all", "2026-09-24T19:00",
        [entry(THU - timedelta(days=i + 1), m, f"{m}{i}", protein=30) for i in range(8) for m in ("breakfast", "lunch", "dinner")])
    return out


def renderings() -> list[dict]:
    """키마다 한 벌 — 앱의 한국어 ARB 가 서버 틀과 글자까지 같은지 본다."""
    samples = {
        "today_sodium_over": {"sodium_mg": 2400},
        "today_calorie_over": {"kcal": 2350},
        "today_protein_left": {"protein_g": 32},
        "today_balanced": {"kcal": 1850},
        "next_meal": {"slot": "dinner", "menu": "구운 고등어 정식", "keyword": "고단백"},
        "next_snack": {"menu": "그릭요거트", "keyword": "고단백"},
        "all_few_records": {"days": 5},
        "all_slot_sodium": {"slot": "lunch", "days": 6},
        "all_carb_heavy": {"pct": 70},
        "all_protein_light": {"pct": 12},
        "all_protein_trend_up": {"before": 3, "after": 8},
        "all_protein_trend_down": {"before": 8, "after": 3},
        "all_frequent_menu": {"slot": "lunch", "food": "김치찌개", "count": 14},
        "all_repeated_foods": {"food1": "닭가슴살", "food2": "계란"},
        "all_good": {"days": 20},
    }
    week_keys = {
        "week_skip_breakfast": {"days": 4},
        "week_skip_breakfast_snack": {"days": 4, "snack_days": 3},
        "week_focus_sodium": {"days": 3},
        "week_focus_calorie": {"days": 2},
        "week_focus_sugar": {"days": 1},
        "week_focus_protein": {"days": 5},
        "week_good": {"days": 6},
    }
    rows = []
    for key in copy.KEYS:
        if key in week_keys:
            for scope in ("this", "last"):
                params = {"scope": scope, **week_keys[key]}
                rows.append({"key": key, "params": params, "text": copy.line(key, **params).text})
        else:
            params = samples.get(key, {})
            rows.append({"key": key, "params": params, "text": copy.line(key, **params).text})
    return rows


def main() -> None:
    built = []
    for case in cases():
        built.append({**case, "expected": RUN[case["period"]](case)})
    doc = {
        "_comment": (
            "식단 AI 맞춤 조언 공유 사례(#2255). backend/scripts/gen_diet_advice_cases.py 가 서버 "
            "규칙으로 만든다 — 손으로 고치지 말고 스크립트를 다시 돌린다. 서버(test_diet_advice_cases.py)"
            "와 데모(diet_advice_test.dart)가 같은 입력에 같은 결과를 내는지, 앱 한국어 ARB 가 서버 "
            "문장 틀과 같은지(renderings) 본다."
        ),
        "demo_plan": DEMO_PLAN,
        "cases": built,
        "renderings": renderings(),
    }
    OUT.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"{len(built)} cases, {len(doc['renderings'])} renderings → {OUT}")


if __name__ == "__main__":
    main()
