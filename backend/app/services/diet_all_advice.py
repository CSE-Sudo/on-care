"""식단 `전체` AI 맞춤 조언 — 최근 4주 식습관, 주 한 번. (#2254)

회의 결정 3번: `전체` 는 **최근 4주** 데이터로 전체적인 식습관을 짚는다. #2079 는
`전체` 조언이 84일을 읽는다고 적었지만 식단 조언은 회의 결정대로 4주를 읽고, 문구에
"최근 4주"(또는 "4주간")를 밝힌다. 그래프 기간과는 무관하다.

규칙 한 줄 — 아래 중 하나. 45자 안이라 한 번에 하나만 말하고, **지난주에 말한 종류는
한 번 건너뛰어** 매주 다른 관점이 되게 한다(말할 것이 그것뿐이면 다시 말한다):
  1. 반복 패턴 — 끼니별 나트륨이 자주 높았다("최근 4주 저녁 나트륨이 6번 높았어요").
  2. 편중 — 탄수화물 비중이 높거나 단백질 비중이 낮다.
  3. 추세 — 단백질 목표 달성일, 최근 2주와 그 전 2주.
  4. 자주 먹은 메뉴 — 끼니별로 가장 자주 먹은 음식과 횟수.
  5. 반복 음식 — 두 가지 음식의 비중이 높아 다양성이 낮다.
  말할 것이 없으면 칭찬(AI 없음). 4주 기록이 7일 미만이면 AI 를 부르지 않고 안내만 한다.

AI 한 문장은 다음 4주의 행동 목표나 구체적 대안이다(`diet_ai_sentence`). 음식군
편중(채소·생선 …)을 이름으로 읽는 일도 AI 가 한다.

**한 주(월~일)에 한 번 만든다.** 그 주 월요일을 열쇠로 둔다.
"""
from __future__ import annotations

import json
from collections import Counter
from dataclasses import dataclass
from datetime import date, datetime, timedelta

from sqlalchemy.orm import Session

from app.core import clock
from app.services import diet_ai_sentence
from app.services import diet_coach_inputs as inputs
from app.services.diet_advice_copy import SLOT_LABELS_KO, Line, ai_line, line
from app.services.diet_period_advice import (
    DietAdvice,
    cached_advice,
    load_state,
    store_advice,
)
from app.services.diet_week_advice import WEEKDAY_KO, DayRecord, day_records

PERIOD_ALL = "all"
WINDOW_DAYS = 28
#: 이보다 기록이 적으면 4주 흐름을 말하지 않는다.
MIN_DAYS = 7
RETRY_AFTER = timedelta(hours=1)

#: 한 끼 나트륨이 하루 한도의 이 비율을 넘으면 "높은 끼니" 로 센다.
SLOT_SODIUM_RATIO = 0.5
#: 끼니별 높은 나트륨을 "자주" 로 볼 최소 횟수와, 그 끼니 기록 중 비율.
SLOT_SODIUM_MIN = 4
SLOT_SODIUM_SHARE = 0.3
#: 탄단지 에너지 비율의 선(2025 한국인 영양소 섭취기준의 에너지 적정 비율 범위 끝).
CARB_HEAVY_PCT = 65
PROTEIN_LIGHT_PCT = 15
#: 단백질 목표를 "달성" 으로 볼 비율과, 추세로 말할 최소 차이·반기(2주)별 최소 기록일.
PROTEIN_MET_RATIO = 0.9
TREND_MIN_DIFF = 2
TREND_MIN_DAYS = 3
#: 자주 먹은 메뉴로 말할 최소 횟수와 이름 길이(카드 45자).
FREQUENT_MIN = 5
FREQUENT_NAME_MAX = 6
#: 두 음식이 전체 음식 기록의 이 비율 이상이면 "반복 음식".
REPEATED_SHARE = 0.25
REPEATED_MIN_ITEMS = 20
RECORD_LINES = 8

_TIPS = {
    "all_slot_sodium": "tip_sodium",
    "all_carb_heavy": "tip_carb",
    "all_protein_light": "tip_protein",
    "all_protein_trend_up": "tip_keep",
    "all_protein_trend_down": "tip_protein",
    "all_frequent_menu": "tip_swap",
    "all_repeated_foods": "tip_variety",
}
_KIND_OF_KEY = {
    "all_slot_sodium": "slot_sodium",
    "all_carb_heavy": "macro",
    "all_protein_light": "macro",
    "all_protein_trend_up": "trend",
    "all_protein_trend_down": "trend",
    "all_frequent_menu": "frequent",
    "all_repeated_foods": "repeated",
}
_TASK = "다음 4주 동안 지킬 행동 목표나 구체적인 대안 한 문장"


@dataclass(frozen=True)
class Finding:
    kind: str
    analysis: Line
    description: str
    records: tuple[str, ...]


def _meal_line(day: date, slot: str, names: list[str], kcal: int, protein: int, sodium: int) -> str:
    label = SLOT_LABELS_KO.get(slot, "간식")
    return (
        f"{day.month}/{day.day}({WEEKDAY_KO[day.weekday()]}) {label}: "
        f"{', '.join(names) or '이름 없음'} (칼로리 {kcal}kcal, 단백질 {protein}g, 나트륨 {sodium}mg)"
    )


def slot_sodium(records: dict[date, DayRecord], targets: inputs.DietTargets) -> Finding | None:
    best = None
    for slot in ("breakfast", "lunch", "dinner"):
        meals = [
            (day, m) for day, r in records.items() for m in r.meals if m[0] == slot
        ]
        slot_days = {day for day, _ in meals}
        high = [(day, m) for day, m in meals if m[4] > targets.sodium_mg * SLOT_SODIUM_RATIO]
        high_days = {day for day, _ in high}
        if len(high_days) < SLOT_SODIUM_MIN or len(high_days) < len(slot_days) * SLOT_SODIUM_SHARE:
            continue
        if best is None or len(high_days) > best[1]:
            best = (slot, len(high_days), high)
    if best is None:
        return None
    slot, days, high = best
    high.sort(key=lambda dm: -dm[1][4])
    return Finding(
        "slot_sodium",
        line("all_slot_sodium", slot=slot, days=days),
        f"최근 4주 {SLOT_LABELS_KO[slot]}에 한 끼 나트륨이 "
        f"{round(targets.sodium_mg * SLOT_SODIUM_RATIO)}mg 을 넘은 날이 {days}일이다.",
        tuple(_meal_line(d, m[0], m[1], m[2], m[3], m[4]) for d, m in high[:RECORD_LINES]),
    )


def macro(entries) -> Finding | None:
    carbs = sum(e.carbs_g for e in entries)
    protein = sum(e.protein_g for e in entries)
    fat = sum(e.fat_g for e in entries)
    energy = carbs * 4 + protein * 4 + fat * 9
    if energy <= 0:
        return None
    carb_pct = round(carbs * 4 * 100 / energy)
    protein_pct = round(protein * 4 * 100 / energy)
    top_foods = Counter(n for e in entries for n in inputs.food_names(e)).most_common(RECORD_LINES)
    foods = tuple(f"{name} {n}회" for name, n in top_foods)
    if carb_pct >= CARB_HEAVY_PCT:
        return Finding(
            "macro", line("all_carb_heavy", pct=carb_pct),
            f"최근 4주 섭취 에너지 중 탄수화물이 {carb_pct}%, 단백질이 {protein_pct}% 다. "
            "아래는 자주 먹은 음식이다.",
            foods,
        )
    if protein_pct <= PROTEIN_LIGHT_PCT:
        return Finding(
            "macro", line("all_protein_light", pct=protein_pct),
            f"최근 4주 섭취 에너지 중 단백질이 {protein_pct}% 로 낮다. 아래는 자주 먹은 음식이다.",
            foods,
        )
    return None


def trend(records: dict[date, DayRecord], targets: inputs.DietTargets, today: date) -> Finding | None:
    split = today - timedelta(days=13)
    recent = [r for d, r in records.items() if d >= split and d < today]
    before = [r for d, r in records.items() if d < split]
    if len(recent) < TREND_MIN_DAYS or len(before) < TREND_MIN_DAYS:
        return None

    def met(rs: list[DayRecord]) -> int:
        return sum(1 for r in rs if r.protein_g >= targets.protein_g * PROTEIN_MET_RATIO)

    a, b = met(before), met(recent)
    if abs(b - a) < TREND_MIN_DIFF:
        return None
    key = "all_protein_trend_up" if b > a else "all_protein_trend_down"
    return Finding(
        "trend", line(key, before=a, after=b),
        f"단백질 목표({targets.protein_g}g)의 90% 이상을 먹은 날이 그 전 2주 {a}일에서 "
        f"최근 2주 {b}일로 {'늘었다' if b > a else '줄었다'}.",
        (),
    )


def frequent(records: dict[date, DayRecord]) -> Finding | None:
    best = None
    for slot in ("breakfast", "lunch", "dinner"):
        counts = Counter(
            name for r in records.values() for m in r.meals if m[0] == slot for name in m[1]
        )
        for name, n in counts.most_common():
            if len(name) > FREQUENT_NAME_MAX:
                continue
            if n >= FREQUENT_MIN and (best is None or n > best[2]):
                best = (slot, name, n)
            break
    if best is None:
        return None
    slot, name, n = best
    samples = [
        _meal_line(d, m[0], m[1], m[2], m[3], m[4])
        for d, r in sorted(records.items()) for m in r.meals if m[0] == slot and name in m[1]
    ]
    return Finding(
        "frequent", line("all_frequent_menu", slot=slot, food=name, count=n),
        f"최근 4주 {SLOT_LABELS_KO[slot]}에 {name}을(를) {n}회 먹었다. 좋아하는 메뉴는 두고 "
        "곁들임·양을 바꾸는 대안을 권한다.",
        tuple(samples[:RECORD_LINES]),
    )


def repeated(records: dict[date, DayRecord]) -> Finding | None:
    counts = Counter(name for r in records.values() for m in r.meals for name in m[1])
    total = sum(counts.values())
    if total < REPEATED_MIN_ITEMS or len(counts) < 2:
        return None
    (a, na), (b, nb) = counts.most_common(2)
    if (na + nb) / total < REPEATED_SHARE or max(len(a), len(b)) > FREQUENT_NAME_MAX:
        return None
    return Finding(
        "repeated", line("all_repeated_foods", food1=a, food2=b),
        f"최근 4주 음식 기록 {total}개 중 {a} {na}개, {b} {nb}개로 두 음식의 비중이 높아 "
        "식단 다양성이 낮다.",
        tuple(f"{name} {n}회" for name, n in counts.most_common(RECORD_LINES)),
    )


def _last_kind(db: Session, user_id: str, monday: date, lang: str) -> str | None:
    row = load_state(db, user_id, PERIOD_ALL, (monday - timedelta(days=7)).isoformat(), lang)
    if row is None:
        return None
    try:
        key = json.loads(row.payload_json or "{}")["analysis"]["key"]
    except (ValueError, KeyError, TypeError):
        return None
    return _KIND_OF_KEY.get(key)


def choose(candidates: list[Finding], last_kind: str | None) -> Finding | None:
    """앞 순서부터, 지난주에 말한 종류는 한 번 건너뛴다."""
    fresh = [f for f in candidates if f.kind != last_kind]
    return (fresh or candidates or [None])[0]


def decide_all(
    entries, targets: inputs.DietTargets, today: date, last_kind: str | None
) -> tuple[dict[date, DayRecord], Line, Finding | None]:
    """전체 조언에서 DB 없이 정해지는 것 — (날짜별 기록, 규칙 한 줄, 고른 것).

    [entries] 는 최근 28일이다. 고른 것이 None 이면 AI 를 부르지 않는다(기록이 모자라거나
    칭찬). 데모(`period_advice.dart`)가 같은 규칙을 옮긴다.
    """
    records = day_records(entries)
    if len(records) < MIN_DAYS:
        return records, line("all_few_records", days=len(records)), None
    candidates = [
        f for f in (
            slot_sodium(records, targets),
            macro(entries),
            trend(records, targets, today),
            frequent(records),
            repeated(records),
        ) if f is not None
    ]
    finding = choose(candidates, last_kind)
    if finding is None:
        return records, line("all_good", days=len(records)), None
    return records, finding.analysis, finding


def fallback_action(analysis: Line) -> Line:
    """AI 문장이 없을 때의 다음 할 일."""
    if analysis.key == "all_few_records":
        return line("all_few_hint")
    return line(_TIPS.get(analysis.key or "", "tip_keep"))


def all_advice(
    db: Session,
    user_id: str,
    *,
    lang: str = "ko",
    use_llm: bool = True,
    now: datetime | None = None,
) -> DietAdvice:
    now = now or clock.now()
    today = now.date()
    monday = today - timedelta(days=today.weekday())
    key = monday.isoformat()
    start = today - timedelta(days=WINDOW_DAYS - 1)

    cached = cached_advice(db, user_id, PERIOD_ALL, key, lang, now)
    if cached is not None:
        return cached

    entries = inputs.entries_between(db, user_id, start, today)
    profile = inputs.load_profile(db, user_id)
    targets = inputs.targets_of(profile)
    records, analysis, finding = decide_all(
        entries, targets, today, _last_kind(db, user_id, monday, lang)
    )
    base = dict(period=PERIOD_ALL, from_date=start.isoformat(), to_date=today.isoformat(),
                days_logged=len(records))
    if analysis.key == "all_few_records":
        # 기록이 쌓이는 중이다 — 두지 않는다. 7일이 되는 날 바로 짚어야 한다.
        return DietAdvice(
            **base, analysis=analysis, action=fallback_action(analysis), action_source="rules",
        )

    retry_after = None
    action, source = fallback_action(analysis), "rules"
    if finding is not None:
        text = None
        if use_llm:
            text = diet_ai_sentence.generate(
                lang=lang,
                analysis_text=finding.analysis.text,
                finding=finding.description,
                records=list(finding.records),
                notes=inputs.trainer_notes(db, user_id),
                goal=(profile.conditions if profile else "") or "",
                metric="diet_all_advice",
                task=_TASK,
            )
        if text:
            action, source = ai_line(text), "llm"
        elif use_llm:
            retry_after = now + RETRY_AFTER

    advice = DietAdvice(**base, analysis=analysis, action=action, action_source=source)
    store_advice(db, user_id, PERIOD_ALL, key, lang, advice, retry_after=retry_after)
    return advice
