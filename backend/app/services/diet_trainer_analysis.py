"""트레이너 웹 `식단 분석` — 원인까지 짚는 서술형 규칙 문장. (#2379)

회원 앱의 식단 조언(`diet_period_advice`·`diet_week_advice`·`diet_all_advice`)과
**같은 기간·같은 판정**을 쓰되, 트레이너가 읽기 좋은 서술로 말한다.

  * 회원 앱은 45자 안의 한 줄 + AI 한 문장이라 문제를 **하나만** 고른다. 트레이너 웹은
    걸린 문제를 **두 가지까지** 말하고, 각각 무엇 **때문에** 그랬는지(원인 음식·끼니)를
    붙이며, 이번 주는 첫 문제를 지난주와 견준다. 다만 프로그램 탭 옆 좁은 칸에도 뜨므로
    모두 합쳐 **4문장**([MAX_SENTENCES])을 넘기지 않는다 — 첫 문제·근거·비교·둘째 문제
    순으로 채우고 넘치면 뒤를 버린다.
  * **AI 를 부르지 않는다.** 그래서 화면 제목도 `AI 분석` 이 아니라 `식단 분석` 이다.
    회원 앱 조언의 AI 문장은 회원에게 하는 말이라 싣지 않는다.
  * 문장은 로케일과 무관한 키·값(`sentences`)으로도 나간다 — 트레이너 웹이 자기
    번역(ARB)으로 그린다. 한국어 평문(`message`)은 아래 `_KO` 틀 하나에서 만든다.

기간:
  * 오늘 — 오늘 기록. 단백질이 모자라면 최근 4주 평균도 본다.
  * 이번 주 — 회원 앱과 같다(월~오늘, 월·화에 이번 주 기록이 2일 미만이고 지난주
    기록이 있으면 지난주).
  * 전체 — 회원 앱과 같은 최근 4주. 그래프의 `전체`(모든 기록)와는 무관하다.
"""
from __future__ import annotations

import json
from collections import Counter
from dataclasses import dataclass, field
from datetime import date, datetime, time, timedelta

from app.core.week import monday_of
from app.services import diet_all_advice as all_advice
from app.services import diet_coach_inputs as inputs
from app.services import diet_week_advice as week_advice

PERIOD_TODAY = "today"
PERIOD_WEEK = "week"
PERIOD_ALL = "all"

#: 오늘 칼로리를 "넘쳤다" 로 볼 배수 — 회원 앱 오늘 조언과 같다.
CALORIE_OVER_RATIO = 1.1
#: 오늘 단백질을 "모자라다" 로 말할 최소 부족분(g) — 회원 앱과 같다.
PROTEIN_GAP_G = 10
#: 최근 4주 평균 단백질이 목표의 이 비율보다 낮으면 "꾸준히 부족" 이다.
PROTEIN_CHRONIC_RATIO = 0.8
#: 이 시각이 지났는데 그 끼니가 없으면 "기록이 아직 없다" 고 말한다(회원 앱과 같다).
MEAL_DEADLINES = {
    "breakfast": time(11, 0),
    "lunch": time(15, 0),
    "dinner": time(21, 0),
}
_MAIN = ("breakfast", "lunch", "dinner")
_NUTRIENT_FIELD = {"sodium": "sodium_mg", "sugar": "sugar_g", "calorie": "calories"}
_ENTRY_FIELD = {"sodium": "sodium_mg", "sugar": "sugar_g", "calorie": "total_calories"}
#: 전체 — 원인 음식은 두 가지까지 이름을 댄다.
TOP_FOODS = 2
#: 이번 주·전체 — 말할 문제 수와 문장 수. 프로그램 탭 옆 좁은 칸에서 3~4줄이다.
MAX_FINDINGS = 2
MAX_SENTENCES = 4

_SLOT_KO = {
    "breakfast": "아침", "lunch": "점심", "dinner": "저녁",
    "snack": "간식", "lateNight": "야식",
}
_NUTRIENT_KO = {"sodium": "나트륨", "sugar": "당류", "calorie": "칼로리", "protein": "단백질"}
#: 주어 조사까지 붙인 말 — 받침에 따라 이/가가 갈린다.
_NUTRIENT_SUBJ = {"sodium": "나트륨이", "sugar": "당류가", "calorie": "칼로리가", "protein": "단백질이"}
_UNIT = {"sodium": "mg", "sugar": "g", "calorie": "kcal", "protein": "g"}
_SCOPE_KO = {"this": "이번 주", "last": "지난주"}
_WEEKDAY_KO = ("월요일", "화요일", "수요일", "목요일", "금요일", "토요일", "일요일")

#: 한국어 틀. 트레이너 웹 한국어 ARB(`clientDietAnalysis…`)가 같은 틀을 옮겨 적는다.
_KO: dict[str, str] = {
    "tr_today_empty": "오늘 식단 기록이 아직 없어요.",
    "tr_today_over": "{slot_ko}에 먹은 {food}({food_value}) 때문에 오늘 {nutrient_subj} "
                     "{value}까지 올라 목표 {target}의 {ratio}배가 됐어요.",
    "tr_today_over_meal": "{slot_ko} 식사({food_value}) 때문에 오늘 {nutrient_subj} "
                          "{value}까지 올라 목표 {target}의 {ratio}배가 됐어요.",
    "tr_today_protein_short": "단백질은 {value}으로 목표보다 {gap} 모자라요.",
    "tr_today_protein_chronic": "단백질은 {value}으로 목표보다 {gap} 모자라고, 최근 4주 "
                                "평균도 하루 {avg}이라 꾸준히 부족한 편이에요.",
    "tr_today_missing": "{slot_ko} 기록이 아직 없어요.",
    "tr_today_good": "오늘 {kcal}, 목표 안에서 고르게 드셨어요.",
    "tr_week_empty": "이번 주 식단 기록이 아직 없어요.",
    "tr_week_skip_breakfast": "{scope_ko} 기록한 {logged}일 중 {days}일 아침을 걸렀어요.",
    "tr_week_skip_breakfast_snack": "{scope_ko} 기록한 {logged}일 중 {days}일 아침을 "
                                    "걸렀고, 그중 {snack_days}일은 간식으로 채웠어요.",
    "tr_week_over": "{scope_ko} 기록한 {logged}일 중 {days}일 {nutrient_subj} 목표를 넘었어요.",
    "tr_week_cause": "{weekday_ko} {slot_ko}에 먹은 {food}({food_value}) 영향이 가장 컸어요.",
    "tr_week_protein_short": "{scope_ko} 기록한 {logged}일 중 {days}일 단백질이 목표의 "
                             "80%에 못 미쳤어요.",
    "tr_week_good": "{scope_ko} 기록한 {days}일 모두 목표 안에서 드셨어요.",
    "tr_week_breakfast_snack_food": "아침 대신 먹은 것은 {food} {count}회가 가장 많았어요.",
    "tr_week_protein_avg": "모자란 날은 하루 평균 {value} 정도였어요.",
    "tr_week_good_avg": "하루 평균 {kcal}, 단백질 {protein}을 드셨어요.",
    "tr_week_vs_last_more": "지난주({prev_logged}일 중 {prev_days}일)보다 늘었어요.",
    "tr_week_vs_last_less": "지난주({prev_logged}일 중 {prev_days}일)보다 줄었어요.",
    "tr_week_vs_last_same": "지난주({prev_logged}일 중 {prev_days}일)와 비슷해요.",
    "tr_all_few": "최근 4주 기록이 {days}일이라, 7일이 넘으면 흐름을 짚어 드릴게요.",
    "tr_all_slot_sodium": "최근 4주 동안 {slot_ko} 나트륨이 {days}회 목표의 절반을 넘었어요.",
    "tr_all_carb_heavy": "최근 4주 섭취 열량 중 탄수화물이 {pct}%로 높은 편이에요.",
    "tr_all_protein_light": "최근 4주 섭취 열량 중 단백질이 {pct}%로 낮은 편이에요.",
    "tr_all_protein_trend_up": "단백질 목표를 채운 날이 앞선 2주 {before}일에서 최근 2주 "
                               "{after}일로 늘었어요.",
    "tr_all_protein_trend_down": "단백질 목표를 채운 날이 앞선 2주 {before}일에서 최근 2주 "
                                 "{after}일로 줄었어요.",
    "tr_all_frequent": "최근 4주 동안 {slot_ko} 메뉴로 {food} {count}회가 가장 많았어요.",
    "tr_all_repeated": "최근 4주 음식 기록에서 {food1}·{food2} 비중이 높아요.",
    "tr_all_good": "최근 4주 동안 {days}일 기록했고, 흐름이 고른 편이에요.",
    "tr_foods_one": "{food1} {count1}회가 대부분이에요.",
    "tr_foods_two": "{food1} {count1}회, {food2} {count2}회가 대부분이에요.",
}

#: 영어 틀 — `Accept-Language: en` 인 트레이너의 `message`. 트레이너 웹 영어 ARB 가
#: 같은 틀을 옮겨 적는다.
_EN: dict[str, str] = {
    "tr_today_empty": "No meals logged today yet.",
    "tr_today_over": "{food} at {slot_en} ({food_value}) pushed today's {nutrient_en} to "
                     "{value}, {ratio}x the {target} goal.",
    "tr_today_over_meal": "{slot_cap} ({food_value}) pushed today's {nutrient_en} to "
                          "{value}, {ratio}x the {target} goal.",
    "tr_today_protein_short": "Protein is at {value}, {gap} short of the goal.",
    "tr_today_protein_chronic": "Protein is at {value}, {gap} short of the goal, and the "
                                "4-week average of {avg} a day stays low.",
    "tr_today_missing": "No {slot_en} logged yet.",
    "tr_today_good": "{kcal} today, evenly within the goals.",
    "tr_week_empty": "No meals logged this week yet.",
    "tr_week_skip_breakfast": "Skipped breakfast on {days} of {logged} logged days {scope_en}.",
    "tr_week_skip_breakfast_snack": "Skipped breakfast on {days} of {logged} logged days "
                                    "{scope_en}, snacking instead on {snack_days}.",
    "tr_week_over": "{nutrient_cap} went over the goal on {days} of {logged} logged days "
                    "{scope_en}.",
    "tr_week_cause": "The biggest was {food} at {weekday_en} {slot_en} ({food_value}).",
    "tr_week_protein_short": "Protein fell below 80% of the goal on {days} of {logged} "
                             "logged days {scope_en}.",
    "tr_week_good": "All {days} logged days {scope_en} stayed within the goals.",
    "tr_week_breakfast_snack_food": "{food} replaced breakfast most often ({count} times).",
    "tr_week_protein_avg": "Those days averaged {value} a day.",
    "tr_week_good_avg": "Averaged {kcal} and {protein} protein a day.",
    "tr_week_vs_last_more": "Up from last week ({prev_days} of {prev_logged} days).",
    "tr_week_vs_last_less": "Down from last week ({prev_days} of {prev_logged} days).",
    "tr_week_vs_last_same": "About the same as last week ({prev_days} of {prev_logged} days).",
    "tr_all_few": "Only {days} days logged in the last 4 weeks. The trend shows after 7.",
    "tr_all_slot_sodium": "In the last 4 weeks, {slot_en} sodium went over half the goal "
                          "{days} times.",
    "tr_all_carb_heavy": "Carbs made up {pct}% of calories in the last 4 weeks.",
    "tr_all_protein_light": "Protein made up only {pct}% of calories in the last 4 weeks.",
    "tr_all_protein_trend_up": "Days meeting the protein goal rose from {before} in the "
                               "prior 2 weeks to {after} in the last 2 weeks.",
    "tr_all_protein_trend_down": "Days meeting the protein goal fell from {before} in the "
                                 "prior 2 weeks to {after} in the last 2 weeks.",
    "tr_all_frequent": "{food} was the most common {slot_en} in the last 4 weeks "
                       "({count} times).",
    "tr_all_repeated": "{food1} and {food2} make up much of the last 4 weeks' log.",
    "tr_all_good": "{days} days logged in the last 4 weeks, with an even trend.",
    "tr_foods_one": "Mostly {food1} ({count1} times).",
    "tr_foods_two": "Mostly {food1} ({count1} times) and {food2} ({count2} times).",
}
_SLOT_EN = {
    "breakfast": "breakfast", "lunch": "lunch", "dinner": "dinner",
    "snack": "snack", "lateNight": "late-night snack",
}
_NUTRIENT_EN = {"sodium": "sodium", "sugar": "sugar", "calorie": "calories", "protein": "protein"}
_SCOPE_EN = {"this": "this week", "last": "last week"}
_WEEKDAY_EN = ("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")

#: 모든 키. 트레이너 웹 번역 테스트가 이 목록을 빠짐없이 그리는지 본다.
KEYS: tuple[str, ...] = tuple(_KO)


@dataclass(frozen=True)
class Sentence:
    key: str
    params: dict[str, str | int] = field(default_factory=dict)

    @property
    def text(self) -> str:
        return self.text_in("ko")

    def text_in(self, locale: str) -> str:
        fields = _ko_fields(self.params, spaced=locale == "en")
        if locale == "en":
            return _EN[self.key].format(**fields)
        return _KO[self.key].format(**fields)


@dataclass(frozen=True)
class Analysis:
    period: str
    from_date: str
    to_date: str
    days_logged: int
    sentences: tuple[Sentence, ...]

    @property
    def message(self) -> str:
        return self.message_in("ko")

    def message_in(self, locale: str) -> str:
        return " ".join(s.text_in(locale) for s in self.sentences)


def _fmt(value: int, nutrient: str, spaced: bool = False) -> str:
    """`4,286mg` / 영어는 `4,286 mg` — 단위를 한국어는 붙이고 영어는 띄운다(#3120)."""
    gap = " " if spaced else ""
    return f"{value:,}{gap}{_UNIT[nutrient]}"


def _ko_fields(params: dict[str, str | int], spaced: bool = False) -> dict[str, str | int]:
    """값 → 틀에 넣을 말. 수치는 천 단위를 끊고 단위를 단다 — [spaced] 면 띄운다(영어)."""
    out: dict[str, str | int] = dict(params)
    nutrient = str(params.get("nutrient", ""))
    for k in ("value", "target", "food_value"):
        if k in params and nutrient in _UNIT:
            out[k] = _fmt(int(params[k]), nutrient, spaced)
    if "slot" in params:
        out["slot_ko"] = _SLOT_KO.get(str(params["slot"]), "간식")
        out["slot_en"] = _SLOT_EN.get(str(params["slot"]), "snack")
        out["slot_cap"] = str(out["slot_en"]).capitalize()
    if nutrient:
        out["nutrient_ko"] = _NUTRIENT_KO.get(nutrient, nutrient)
        out["nutrient_subj"] = _NUTRIENT_SUBJ.get(nutrient, nutrient)
        out["nutrient_en"] = _NUTRIENT_EN.get(nutrient, nutrient)
        out["nutrient_cap"] = out["nutrient_en"].capitalize()
    if "scope" in params:
        out["scope_ko"] = _SCOPE_KO.get(str(params["scope"]), "이번 주")
        out["scope_en"] = _SCOPE_EN.get(str(params["scope"]), "this week")
    if "weekday" in params:
        out["weekday_ko"] = _WEEKDAY_KO[int(params["weekday"])]
        out["weekday_en"] = _WEEKDAY_EN[int(params["weekday"])]
    if "kcal" in params:
        out["kcal"] = _fmt(int(params["kcal"]), "calorie", spaced)
    for k in ("gap", "avg", "protein"):
        if k in params:
            out[k] = _fmt(int(params[k]), "protein", spaced)
    if nutrient == "protein" and "value" in params:
        out["value"] = _fmt(int(params["value"]), "protein", spaced)
    return out


# ── 오늘 ────────────────────────────────────────────────────────────────


def _foods(entry) -> list[dict]:
    try:
        raw = json.loads(entry.foods_json) if entry.foods_json else []
    except ValueError:
        return []
    return [f for f in raw if isinstance(f, dict)] if isinstance(raw, list) else []


def _top_cause(entries, nutrient: str) -> tuple[str, str | None, int]:
    """(끼니, 음식 이름 또는 None, 그 값) — 그 영양을 가장 많이 채운 음식.

    음식별 값이 없는 옛 기록이면 끼니 합계로 끼니만 짚는다(이름은 None).
    """
    food_field = _NUTRIENT_FIELD[nutrient]
    entry_field = _ENTRY_FIELD[nutrient]
    best: tuple[str, str | None, int] = ("", None, -1)
    for e in entries:
        valued = [
            (str(f.get("name", "")).strip(), round(f[food_field]))
            for f in _foods(e)
            if isinstance(f.get(food_field), (int, float)) and str(f.get("name", "")).strip()
        ]
        # 음식별 값이 있는 끼니는 음식끼리, 없는 끼니는 끼니 합계로 겨룬다 — 값 없는
        # 큰 끼니를 두고 값 있는 작은 음식을 원인이라 부르지 않도록.
        if valued:
            name, value = max(valued, key=lambda nv: nv[1])
            candidate: tuple[str, str | None, int] = (e.meal_type, name, value)
        else:
            candidate = (e.meal_type, None, round(getattr(e, entry_field) or 0))
        if candidate[2] > best[2]:
            best = candidate
    return best


def today_sentences(
    entries, targets: inputs.DietTargets, now: datetime, avg_protein_g: int | None
) -> list[Sentence]:
    """오늘 — 넘친 것(원인 음식) → 모자란 단백질 → 빠진 끼니. 없으면 칭찬."""
    if not entries:
        return [Sentence("tr_today_empty")]
    totals = {
        "sodium": round(sum(e.sodium_mg for e in entries)),
        "sugar": round(sum(e.sugar_g for e in entries)),
        "calorie": round(sum(e.total_calories for e in entries)),
    }
    protein = round(sum(e.protein_g for e in entries))
    limits = {
        "sodium": targets.sodium_mg,
        "sugar": targets.sugar_g,
        "calorie": round(targets.calories * CALORIE_OVER_RATIO),
    }
    goals = {"sodium": targets.sodium_mg, "sugar": targets.sugar_g, "calorie": targets.calories}
    out: list[Sentence] = []

    over = [n for n in ("sodium", "sugar", "calorie") if totals[n] > limits[n] and goals[n] > 0]
    if over:
        worst = max(over, key=lambda n: totals[n] / goals[n])
        slot, food, food_value = _top_cause(entries, worst)
        params: dict[str, str | int] = {
            "nutrient": worst, "slot": slot, "food_value": food_value,
            "value": totals[worst], "target": goals[worst],
            "ratio": f"{totals[worst] / goals[worst]:.1f}",
        }
        if food:
            params["food"] = food
            out.append(Sentence("tr_today_over", params))
        else:
            out.append(Sentence("tr_today_over_meal", params))

    gap = targets.protein_g - protein
    if gap >= PROTEIN_GAP_G:
        base = {"nutrient": "protein", "value": protein, "gap": gap}
        if avg_protein_g is not None and avg_protein_g < targets.protein_g * PROTEIN_CHRONIC_RATIO:
            out.append(Sentence("tr_today_protein_chronic", {**base, "avg": avg_protein_g}))
        else:
            out.append(Sentence("tr_today_protein_short", base))

    at = now.timetz().replace(tzinfo=None)
    slots = {e.meal_type for e in entries}
    missing = [s for s in _MAIN if s not in slots and at >= MEAL_DEADLINES[s]]
    if missing:
        out.append(Sentence("tr_today_missing", {"slot": missing[0]}))

    return out or [Sentence("tr_today_good", {"kcal": totals["calorie"]})]


# ── 이번 주 ─────────────────────────────────────────────────────────────


def _week_hits(
    records: dict[date, week_advice.DayRecord],
    targets: inputs.DietTargets,
    *,
    today: date,
    now_time: time,
) -> dict[str, list[week_advice.DayRecord]]:
    """종류별로 걸린 날 — 회원 앱 `week_advice.find` 와 같은 선이다."""
    days = sorted(records.values(), key=lambda r: r.day)
    finished = [
        r for r in days
        if r.day < today or (r.day == today and now_time >= week_advice.BREAKFAST_DEADLINE)
    ]
    closed = [r for r in days if r.day < today]
    return {
        "breakfast": [r for r in finished if "breakfast" not in r.slots],
        "sodium": [r for r in days if r.sodium_mg > targets.sodium_mg],
        "calorie": [
            r for r in days if r.kcal > targets.calories * week_advice.CALORIE_OVER_RATIO
        ],
        "sugar": [r for r in days if r.sugar_g > targets.sugar_g],
        "protein": [
            r for r in closed
            if r.main_meals >= week_advice.PROTEIN_MIN_MEALS
            and r.protein_g < targets.protein_g * week_advice.PROTEIN_SHORT_RATIO
        ],
    }


def _week_kinds(hits: dict[str, list]) -> list[str]:
    """말할 종류 — 아침 습관이 먼저, 그다음 걸린 날이 많은 영양(같으면 과잉이 먼저)."""
    out = ["breakfast"] if len(hits["breakfast"]) >= week_advice.SKIP_BREAKFAST_MIN else []
    order = week_advice._FOCUS_ORDER
    focus = [k for k in order if len(hits[k]) >= week_advice.FOCUS_MIN_DAYS]
    focus.sort(key=lambda k: (-len(hits[k]), order.index(k)))
    return (out + focus)[:MAX_FINDINGS]


def _week_finding(kind: str, hit: list, scope: str, logged: int) -> list[Sentence]:
    """[문제 문장, 근거 문장] — 근거가 없으면 한 문장이다."""
    snacks = set(week_advice._SNACKS)
    if kind == "breakfast":
        snack_days = [r for r in hit if r.slots & snacks]
        if len(snack_days) < week_advice.SKIP_SNACK_MIN:
            return [Sentence("tr_week_skip_breakfast",
                             {"scope": scope, "logged": logged, "days": len(hit)})]
        out = [Sentence("tr_week_skip_breakfast_snack", {
            "scope": scope, "logged": logged, "days": len(hit), "snack_days": len(snack_days),
        })]
        top = Counter(
            n for r in snack_days for m in r.meals if m[0] in snacks for n in m[1]
        ).most_common(1)
        if top:
            out.append(Sentence("tr_week_breakfast_snack_food",
                                {"food": top[0][0], "count": top[0][1]}))
        return out
    if kind == "protein":
        avg = round(sum(r.protein_g for r in hit) / len(hit))
        return [
            Sentence("tr_week_protein_short",
                     {"scope": scope, "logged": logged, "days": len(hit)}),
            Sentence("tr_week_protein_avg", {"nutrient": "protein", "value": avg}),
        ]
    out = [Sentence("tr_week_over", {
        "scope": scope, "logged": logged, "days": len(hit), "nutrient": kind,
    })]
    index = {"calorie": 2, "sodium": 4, "sugar": 5}[kind]
    best = None
    for r in hit:
        for meal in r.meals:
            if best is None or meal[index] > best[1][index]:
                best = (r.day, meal)
    if best is not None and best[1][1]:
        day, meal = best
        out.append(Sentence("tr_week_cause", {
            "weekday": day.weekday(), "slot": meal[0], "food": ", ".join(meal[1]),
            "food_value": meal[index], "nutrient": kind,
        }))
    return out


def _cap(groups: list[list[Sentence]], compare: Sentence | None) -> list[Sentence]:
    """첫 문제 → 비교 → 첫 근거 → 둘째 문제·근거 순으로, [MAX_SENTENCES] 에서 자른다.

    비교는 첫 문제 바로 뒤다 — 근거 뒤에 두면 무엇을 견준 것인지 읽히지 않는다.
    """
    ordered = [groups[0][0]] + ([compare] if compare else []) + list(groups[0][1:])
    for g in groups[1:]:
        ordered += g
    return ordered[:MAX_SENTENCES]


def week_sentences(
    entries, targets: inputs.DietTargets, now: datetime
) -> tuple[date, date, int, list[Sentence]]:
    """이번 주 — 걸린 문제를 두 가지까지, 각각 근거를 붙이고 첫 문제는 지난주와 견준다.

    판정 선은 회원 앱(`week_advice.find`)과 같지만, 회원 앱처럼 첫 문제에서 멈추지 않는다.
    """
    today = now.date()
    at = now.timetz().replace(tzinfo=None)
    records_all = week_advice.day_records(entries)
    scope, start, end = week_advice.week_window(today, set(records_all))
    records = {d: r for d, r in records_all.items() if start <= d <= end}
    if not records:
        return start, end, 0, [Sentence("tr_week_empty")]
    logged = len(records)
    hits = _week_hits(records, targets, today=today, now_time=at)
    kinds = _week_kinds(hits)
    if not kinds:
        days = list(records.values())
        return start, end, logged, [
            Sentence("tr_week_good", {"scope": scope, "days": logged}),
            Sentence("tr_week_good_avg", {
                "kcal": round(sum(r.kcal for r in days) / logged),
                "protein": round(sum(r.protein_g for r in days) / logged),
            }),
        ]
    groups = [_week_finding(k, hits[k], scope, logged) for k in kinds]

    # 지난주 — 이번 주를 볼 때만 견준다(지난주를 돌아볼 때는 그 전 주를 읽지 않는다).
    compare = None
    if scope == "this":
        prev = {d: r for d, r in records_all.items() if start - timedelta(days=7) <= d < start}
        if prev:
            prev_hits = _week_hits(prev, targets, today=today, now_time=at)
            prev_days = len(prev_hits[kinds[0]])
            # 기록한 날 수가 주마다 달라 비율로 견준다.
            now_rate = len(hits[kinds[0]]) / logged
            prev_rate = prev_days / len(prev)
            way = "same" if now_rate == prev_rate else (
                "more" if now_rate > prev_rate else "less"
            )
            compare = Sentence(f"tr_week_vs_last_{way}", {
                "prev_logged": len(prev), "prev_days": prev_days,
            })
    return start, end, logged, _cap(groups, compare)


# ── 전체(최근 4주) ──────────────────────────────────────────────────────


def _foods_sentence(counts: Counter) -> Sentence | None:
    top = counts.most_common(TOP_FOODS)
    if not top:
        return None
    if len(top) == 1:
        return Sentence("tr_foods_one", {"food1": top[0][0], "count1": top[0][1]})
    return Sentence("tr_foods_two", {
        "food1": top[0][0], "count1": top[0][1], "food2": top[1][0], "count2": top[1][1],
    })


def _all_finding(
    f: all_advice.Finding, records, entries, targets: inputs.DietTargets, *, with_foods: bool
) -> list[Sentence]:
    p = f.analysis.params
    key = f.analysis.key
    if key == "all_slot_sodium":
        slot = str(p["slot"])
        limit = targets.sodium_mg * all_advice.SLOT_SODIUM_RATIO
        counts: Counter = Counter(
            name for r in records.values() for m in r.meals
            if m[0] == slot and m[4] > limit for name in m[1]
        )
        extra = _foods_sentence(counts)
        out = [Sentence("tr_all_slot_sodium", {"slot": slot, "days": p["days"]})]
        return out + ([extra] if extra else [])
    if key in ("all_carb_heavy", "all_protein_light"):
        out = [Sentence("tr_" + key, {"pct": p["pct"]})]
        extra = _foods_sentence(Counter(n for e in entries for n in inputs.food_names(e)))
        return out + ([extra] if extra and with_foods else [])
    if key in ("all_protein_trend_up", "all_protein_trend_down"):
        return [Sentence("tr_" + key, {"before": p["before"], "after": p["after"]})]
    if key == "all_frequent_menu":
        return [Sentence("tr_all_frequent", {
            "slot": p["slot"], "food": p["food"], "count": p["count"],
        })]
    return [Sentence("tr_all_repeated", {"food1": p["food1"], "food2": p["food2"]})]


def all_sentences(entries, targets: inputs.DietTargets, today: date) -> tuple[int, list[Sentence]]:
    """전체(최근 4주) — 회원 앱 후보 중 앞의 두 가지까지, 각각 원인 음식을 붙인다.

    트레이너 화면은 지난주에 말한 종류를 건너뛰지 않는다 — 회원 앱처럼 매주 관점을
    바꾸면 트레이너는 같은 회원의 가장 큰 문제를 한 주 걸러 한 번만 보게 된다.
    """
    records = week_advice.day_records(entries)
    days = len(records)
    if days < all_advice.MIN_DAYS:
        return days, [Sentence("tr_all_few", {"days": days})]
    found = all_advice.candidates(entries, records, targets, today)[:MAX_FINDINGS]
    if not found:
        return days, [Sentence("tr_all_good", {"days": days})]
    # 반복 음식이 함께 나오면 편중 뒤의 "자주 먹은 음식" 은 같은 말이라 뺀다.
    repeated = any(f.kind == "repeated" for f in found)
    groups = [
        _all_finding(f, records, entries, targets, with_foods=not repeated) for f in found
    ]
    return days, _cap(groups, None)


# ── 조회 ────────────────────────────────────────────────────────────────


def analysis(db, member_id: str, period: str, *, now: datetime) -> Analysis:
    today = now.date()
    targets = inputs.targets_of(inputs.load_profile(db, member_id))
    if period == PERIOD_TODAY:
        entries = inputs.entries_between(db, member_id, today, today)
        avg = None
        if targets.protein_g - sum(e.protein_g for e in entries) >= PROTEIN_GAP_G:
            start = today - timedelta(days=all_advice.WINDOW_DAYS - 1)
            recent = inputs.digest(inputs.entries_between(db, member_id, start, today))
            avg = recent.avg_protein_g if recent.days_logged else None
        sentences = today_sentences(entries, targets, now, avg)
        return Analysis(period, today.isoformat(), today.isoformat(),
                        1 if entries else 0, tuple(sentences))
    if period == PERIOD_WEEK:
        two_weeks = monday_of(today) - timedelta(days=7)
        entries = inputs.entries_between(db, member_id, two_weeks, today)
        start, end, logged, sentences = week_sentences(entries, targets, now)
        return Analysis(period, start.isoformat(), end.isoformat(), logged, tuple(sentences))
    start = today - timedelta(days=all_advice.WINDOW_DAYS - 1)
    entries = inputs.entries_between(db, member_id, start, today)
    logged, sentences = all_sentences(entries, targets, today)
    return Analysis(period, start.isoformat(), today.isoformat(), logged, tuple(sentences))
