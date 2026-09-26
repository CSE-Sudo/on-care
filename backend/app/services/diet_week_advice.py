"""식단 `이번 주` AI 맞춤 조언 — 규칙 한 줄 + AI 한 문장, 하루 한 번. (#2253)

규칙 한 줄(45자 안이라 한 번에 하나만 말한다):
  1. **끼니 습관**이 뚜렷하면 그것 — 기록한 날 중 아침을 3번 이상 건너뛰었다. 그날
     간식이 2일 이상 있었으면 둘을 함께 말한다.
  2. 아니면 **집중 목표** — 가장 많이 넘긴(모자란) 영양소와 그 날 수.
  3. 넘긴 날이 하루도 없으면 칭찬 — 하루라도 넘겼으면 "모두 목표 안" 이라고 하지 않는다.

AI 한 문장은 규칙이 고른 한 가지와 그 주의 끼니 기록을 보고 원인 메뉴를 짚거나
구체적인 대안을 준다(`diet_ai_sentence`). 칭찬에는 AI 를 부르지 않는다 — 고칠 것이
없으면 짚을 원인도 없다.

기간 경계는 운동 조언(#2162)과 같다: 월·화이고 이번 주에 끼니를 기록한 날이 이틀
미만이며 지난주 기록이 있으면 지난주(월~일)를 돌아본다.

**하루에 한 번 만든다.** 그날 처음 연 조언을 그날 내내 둔다(다음 날 새로 만든다). 기록이
없어 안내만 하는 문구는 두지 않는다 — 곧 첫 기록이 생긴다. AI 가 실패해 대체 문장을
두었으면 1시간 뒤 다시 만든다.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date, datetime, time, timedelta

from sqlalchemy.orm import Session

from app.core import clock
from app.services import diet_ai_sentence
from app.services import diet_coach_inputs as inputs
from app.services.diet_advice_copy import SLOT_LABELS_KO, Line, ai_line, line
from app.services.diet_period_advice import DietAdvice, cached_advice, store_advice

PERIOD_WEEK = "week"

#: 아침을 이만큼 건너뛰면 끼니 습관으로 말한다.
SKIP_BREAKFAST_MIN = 3
#: 아침을 거른 날 중 간식이 이만큼 있었으면 함께 말한다.
SKIP_SNACK_MIN = 2
#: 집중 목표로 말할 최소 날 수. 하루라도 넘겼으면 칭찬 대신 그것을 말한다.
FOCUS_MIN_DAYS = 1
#: 그날의 아침이 끝났다고 보는 시각(오늘 조언과 같은 경계).
BREAKFAST_DEADLINE = time(11, 0)
#: 단백질 부족을 셀 때 하루로 치는 최소 끼니 수. 한 끼만 적은 날은 부족해 보여도
#: 먹지 않은 것이 아니라 적지 않은 것일 수 있다.
PROTEIN_MIN_MEALS = 2
CALORIE_OVER_RATIO = 1.1
PROTEIN_SHORT_RATIO = 0.8
RETRY_AFTER = timedelta(hours=1)
#: AI 에게 보여 줄 끼니 기록 줄 수.
RECORD_LINES = 6

_MAIN = ("breakfast", "lunch", "dinner")
_SNACKS = ("snack", "lateNight")
WEEKDAY_KO = "월화수목금토일"
_FOCUS_TIPS = {
    "sodium": "tip_sodium",
    "calorie": "tip_calorie",
    "sugar": "tip_sugar",
    "protein": "tip_protein",
}
#: 같은 날 수면 이 순서로 고른다 — 과잉 섭취가 부족보다 먼저다.
_FOCUS_ORDER = ("sodium", "calorie", "sugar", "protein")


@dataclass
class DayRecord:
    day: date
    kcal: float = 0
    protein_g: float = 0
    sodium_mg: float = 0
    sugar_g: float = 0
    slots: set[str] = field(default_factory=set)
    #: (끼니, 음식 이름들, 칼로리, 단백질, 나트륨, 당류)
    meals: list[tuple[str, list[str], int, int, int, int]] = field(default_factory=list)

    @property
    def main_meals(self) -> int:
        return len(self.slots & set(_MAIN))


def week_window(today: date, recorded: set[date]) -> tuple[str, date, date]:
    """(scope, 시작, 끝). 운동 조언의 월·화 회고와 같은 규칙이다."""
    monday = today - timedelta(days=today.weekday())
    this_week_days = sum(1 for d in recorded if monday <= d <= today)
    last_monday = monday - timedelta(days=7)
    has_last = any(last_monday <= d < monday for d in recorded)
    if today.weekday() <= 1 and this_week_days < 2 and has_last:
        return "last", last_monday, monday - timedelta(days=1)
    return "this", monday, today


def day_records(entries) -> dict[date, DayRecord]:
    days: dict[date, DayRecord] = {}
    for e in entries:
        try:
            when = date.fromisoformat(e.date)
        except ValueError:
            continue
        rec = days.setdefault(when, DayRecord(day=when))
        rec.kcal += e.total_calories
        rec.protein_g += e.protein_g
        rec.sodium_mg += e.sodium_mg
        rec.sugar_g += e.sugar_g
        rec.slots.add(e.meal_type)
        rec.meals.append((
            e.meal_type, inputs.food_names(e), round(e.total_calories),
            round(e.protein_g), round(e.sodium_mg), round(e.sugar_g),
        ))
    return days


@dataclass(frozen=True)
class Finding:
    kind: str  # breakfast|sodium|calorie|sugar|protein|good
    analysis: Line
    #: 프롬프트에 주는 한국어 설명.
    description: str
    #: 원인을 짚을 날들.
    days: tuple[date, ...]


def find(
    records: dict[date, DayRecord],
    targets: inputs.DietTargets,
    scope: str,
    *,
    today: date,
    now_time: time,
) -> Finding:
    """규칙 한 줄 — 끼니 습관 → 집중 목표 → 칭찬."""
    days = sorted(records.values(), key=lambda r: r.day)
    # 아직 끝나지 않은 오늘은 "건너뛴 아침"·"부족" 을 세지 않는다.
    finished = [
        r for r in days
        if r.day < today or (r.day == today and now_time >= BREAKFAST_DEADLINE)
    ]
    closed = [r for r in days if r.day < today]
    scope_ko = "이번 주" if scope == "this" else "지난주"

    skipped = [r for r in finished if "breakfast" not in r.slots]
    if len(skipped) >= SKIP_BREAKFAST_MIN:
        with_snack = [r for r in skipped if r.slots & set(_SNACKS)]
        if len(with_snack) >= SKIP_SNACK_MIN:
            return Finding(
                "breakfast",
                line("week_skip_breakfast_snack", scope=scope, days=len(skipped),
                     snack_days=len(with_snack)),
                f"{scope_ko} 기록한 날 중 아침을 {len(skipped)}번 건너뛰었고, "
                f"그중 {len(with_snack)}일은 간식을 먹었다.",
                tuple(r.day for r in with_snack),
            )
        return Finding(
            "breakfast",
            line("week_skip_breakfast", scope=scope, days=len(skipped)),
            f"{scope_ko} 기록한 날 중 아침을 {len(skipped)}번 건너뛰었다.",
            tuple(r.day for r in skipped),
        )

    counted: dict[str, list[DayRecord]] = {
        "sodium": [r for r in days if r.sodium_mg > targets.sodium_mg],
        "calorie": [r for r in days if r.kcal > targets.calories * CALORIE_OVER_RATIO],
        "sugar": [r for r in days if r.sugar_g > targets.sugar_g],
        "protein": [
            r for r in closed
            if r.main_meals >= PROTEIN_MIN_MEALS
            and r.protein_g < targets.protein_g * PROTEIN_SHORT_RATIO
        ],
    }
    kind = max(_FOCUS_ORDER, key=lambda k: (len(counted[k]), -_FOCUS_ORDER.index(k)))
    hits = counted[kind]
    if len(hits) >= FOCUS_MIN_DAYS:
        described = {
            "sodium": f"나트륨 권장량({targets.sodium_mg}mg)을 넘긴 날",
            "calorie": f"칼로리 목표({targets.calories}kcal)의 1.1배를 넘긴 날",
            "sugar": f"당류 권장량({targets.sugar_g}g)을 넘긴 날",
            "protein": f"단백질이 목표({targets.protein_g}g)의 80%에 못 미친 날",
        }[kind]
        return Finding(
            kind,
            line(f"week_focus_{kind}", scope=scope, days=len(hits)),
            f"{scope_ko} {described}이 {len(hits)}일이다.",
            tuple(r.day for r in hits),
        )

    return Finding(
        "good",
        line("week_good", scope=scope, days=len(days)),
        f"{scope_ko} 기록한 {len(days)}일 모두 목표 안이다.",
        (),
    )


def decide_week(
    entries, targets: inputs.DietTargets, now: datetime
) -> tuple[str, date, date, dict[date, DayRecord], Finding | None]:
    """이번 주 조언에서 DB 없이 정해지는 것 — (scope, 시작, 끝, 날짜별 기록, 규칙 한 줄).

    [entries] 는 지난주 월요일부터 오늘까지다. 기록이 없으면 규칙 한 줄이 None 이다.
    데모(`period_advice.dart`)가 같은 규칙을 옮긴다.
    """
    today = now.date()
    records_all = day_records(entries)
    scope, start, end = week_window(today, set(records_all))
    records = {d: r for d, r in records_all.items() if start <= d <= end}
    if not records:
        return scope, start, end, records, None
    at = now.timetz().replace(tzinfo=None)
    return scope, start, end, records, find(records, targets, scope, today=today, now_time=at)


def fallback_action(finding: Finding) -> Line:
    """AI 문장이 없을 때의 다음 할 일. 칭찬은 늘 이것이다."""
    if finding.kind == "good":
        return line("tip_keep")
    return line("tip_breakfast" if finding.kind == "breakfast" else _FOCUS_TIPS[finding.kind])


def record_lines(finding: Finding, records: dict[date, DayRecord]) -> list[str]:
    """AI 에게 보여 줄 원인 후보 끼니. 그 영양이 큰 끼니부터."""
    index = {"sodium": 4, "calorie": 2, "sugar": 5, "protein": 3}.get(finding.kind)
    rows: list[tuple[float, str]] = []
    for day in finding.days:
        rec = records.get(day)
        if rec is None:
            continue
        for slot, names, kcal, protein, sodium, sugar in rec.meals:
            if finding.kind == "breakfast" and slot not in _SNACKS:
                continue
            label = SLOT_LABELS_KO.get(slot, "간식")
            text = (
                f"{WEEKDAY_KO[day.weekday()]} {label}: {', '.join(names) or '이름 없음'} "
                f"(칼로리 {kcal}kcal, 단백질 {protein}g, 나트륨 {sodium}mg, 당류 {sugar}g)"
            )
            values = (0, 0, kcal, protein, sodium, sugar)
            weight = values[index] if index else 0
            if finding.kind == "protein":
                weight = -weight  # 단백질이 적은 끼니부터
            rows.append((weight, text))
    rows.sort(key=lambda r: -r[0])
    return [text for _, text in rows[:RECORD_LINES]]


def week_advice(
    db: Session,
    user_id: str,
    *,
    lang: str = "ko",
    use_llm: bool = True,
    now: datetime | None = None,
) -> DietAdvice:
    now = now or clock.now()
    today = now.date()
    key = today.isoformat()

    cached = cached_advice(db, user_id, PERIOD_WEEK, key, lang, now)
    if cached is not None:
        return cached

    two_weeks = today - timedelta(days=today.weekday() + 7)
    entries = inputs.entries_between(db, user_id, two_weeks, today)
    profile = inputs.load_profile(db, user_id)
    targets = inputs.targets_of(profile)
    scope, start, end, records, finding = decide_week(entries, targets, now)

    if finding is None:
        # 기록이 없으면 안내만 한다. 두지 않는다 — 곧 첫 기록이 생긴다.
        return DietAdvice(
            period=PERIOD_WEEK, from_date=start.isoformat(), to_date=end.isoformat(),
            days_logged=0, analysis=line("week_empty"), action=line("week_empty_hint"),
            action_source="rules",
        )

    action: Line
    source = "rules"
    retry_after = None
    if finding.kind == "good":
        action = line("tip_keep")
    else:
        text = None
        if use_llm:
            text = diet_ai_sentence.generate(
                lang=lang,
                analysis_text=finding.analysis.text,
                finding=finding.description,
                records=record_lines(finding, records),
                notes=inputs.trainer_notes(db, user_id),
                goal=(profile.conditions if profile else "") or "",
                metric="diet_week_advice",
            )
        if text:
            action = ai_line(text)
            source = "llm"
        else:
            action = fallback_action(finding)
            retry_after = now + RETRY_AFTER if use_llm else None

    advice = DietAdvice(
        period=PERIOD_WEEK, from_date=start.isoformat(), to_date=end.isoformat(),
        days_logged=len(records), analysis=finding.analysis, action=action,
        action_source=source,
    )
    store_advice(db, user_id, PERIOD_WEEK, key, lang, advice, retry_after=retry_after)
    return advice
