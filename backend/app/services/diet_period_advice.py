"""식단 AI 맞춤 조언 — 규칙 한 줄 + 다음 할 일 한 문장. (#2251)

회의 결정 3번: **수치는 규칙이 정확히 계산**하고, 원인 메뉴·구체적 대안은 AI 가 짚는다.
대원칙은 "AI 는 트레이너 조언과 상충하지 않는다" 다.

오늘:
  * 규칙 한 줄 — 오늘 합계를 목표와 견준다. 앞선 끼니가 비어 있으면 "적지 않은 끼니가
    있나요?" 로 기록부터 받는다. 이때는 메뉴를 고르지 않고 **추천 메뉴 리스트도 열지
    않는다** — 리스트가 없으면 그 자리에서 AI 를 부르게 되는데, 빠진 기록을 두고 고른
    메뉴는 곧 바뀐다.
  * 다음 식사 한 문장 — 4주 추천 메뉴 리스트(`diet_menu_plan`)에서 오늘 가장 큰
    부족·초과를 메우는 태그의 메뉴를 고른다. **이 조회에서는 AI 를 부르지 않는다**
    (리스트가 없을 때 만드는 한 번만 부른다). 끼니를 기록할 때마다 다시 계산한다.
  * 추천 이유가 충족되면 다른 메뉴로 바뀐다 — 그 태그의 부족·초과가 풀리면 다음
    태그의 메뉴를 고른다.
  * 최근 3일 안에 추천한 메뉴는 뒤로 미룬다. 같은 날 안에서는 이 기준이 바뀌지 않아
    기록이 그대로면 같은 메뉴가 나온다.
"""
from __future__ import annotations

import json
import uuid
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core import clock
from app.data import diet_menu_catalog as catalog
from app.models.models import DietAdviceState
from app.services import diet_coach_inputs as inputs
from app.services import diet_menu_plan
from app.services.diet_advice_copy import Line, line

PERIOD_TODAY = "today"

MAIN_SLOTS = (catalog.SLOT_BREAKFAST, catalog.SLOT_LUNCH, catalog.SLOT_DINNER)
#: 이 시각이 지났는데 그 끼니가 없으면 "적지 않은 끼니" 로 본다. 다음 식사도 이
#: 시각 전의 끼니 가운데서 고른다.
MEAL_DEADLINES = {
    catalog.SLOT_BREAKFAST: time(11, 0),
    catalog.SLOT_LUNCH: time(15, 0),
    catalog.SLOT_DINNER: time(21, 0),
}

#: 단백질이 이만큼 모자라면 말하고, 채울 메뉴를 고른다.
PROTEIN_GAP_G = 10
#: 칼로리가 목표의 이 배수를 넘으면 초과로 말한다.
CALORIE_OVER_RATIO = 1.1
#: 다음 식사를 고를 때 "이미 많다" 로 보는 선. 하루가 끝나기 전이라 한도보다 낮게 잡는다.
SODIUM_HIGH_RATIO = 0.6
CALORIE_HIGH_RATIO = 0.9
SUGAR_HIGH_RATIO = 0.7
#: 저녁까지 먹고도 칼로리가 이보다 적으면 간식으로 채우자고 한다.
CALORIE_LOW_RATIO = 0.7
#: 최근 며칠 안에 추천한 메뉴를 뒤로 미룰지.
RECENT_PICK_DAYS = 3

#: 급한 태그가 없을 때의 순서. `든든한` 은 칼로리가 모자랄 때만 고른다.
_DEFAULT_TAGS = [t for t in catalog.TAGS if t != catalog.TAG_CALORIE_HIGH]


@dataclass(frozen=True)
class DietAdvice:
    period: str
    from_date: str
    to_date: str
    days_logged: int
    analysis: Line
    action: Line | None
    #: 다음 할 일 문장의 출처 — `plan`(추천 메뉴 리스트)·`rules`·`llm`. 없으면 None.
    action_source: str | None


@dataclass(frozen=True)
class TodayTotals:
    kcal: int
    protein_g: float
    sodium_mg: int
    sugar_g: float
    slots: frozenset[str]
    has_entries: bool


def today_totals(entries) -> TodayTotals:
    return TodayTotals(
        kcal=round(sum(e.total_calories for e in entries)),
        protein_g=sum(e.protein_g for e in entries),
        sodium_mg=round(sum(e.sodium_mg for e in entries)),
        sugar_g=sum(e.sugar_g for e in entries),
        slots=frozenset(e.meal_type for e in entries),
        has_entries=bool(entries),
    )


def missing_meal(slots: frozenset[str], at: time) -> bool:
    """시각이 지났는데 비어 있는 끼니가 있는가."""
    return any(s not in slots and at >= MEAL_DEADLINES[s] for s in MAIN_SLOTS)


def next_slot(slots: frozenset[str], at: time) -> str | None:
    """다음에 먹을 끼니. 이미 적은 끼니보다 뒤이고, 시각이 지나지 않은 첫 끼니다.

    없으면(저녁까지 적었거나 밤이 늦었다) None — 간식을 볼 차례다.
    """
    logged = [i for i, s in enumerate(MAIN_SLOTS) if s in slots]
    after = max(logged) if logged else -1
    for i, slot in enumerate(MAIN_SLOTS):
        if i > after and at < MEAL_DEADLINES[slot]:
            return slot
    return None


def needs_today(t: TodayTotals, targets: inputs.DietTargets) -> list[str]:
    """오늘 합계가 가리키는 태그를 급한 순서로.

    아직 아무것도 적지 않았으면 급한 것이 없다 — 먹기 전부터 "단백질이 모자라다" 고
    보면 아침마다 같은 이유의 메뉴만 나온다.
    """
    needs: list[str] = []
    if not t.has_entries:
        return needs
    if t.sodium_mg >= targets.sodium_mg * SODIUM_HIGH_RATIO:
        needs.append(catalog.TAG_SODIUM_LOW)
    if targets.protein_g - t.protein_g >= PROTEIN_GAP_G:
        needs.append(catalog.TAG_PROTEIN_HIGH)
    if t.kcal >= targets.calories * CALORIE_HIGH_RATIO:
        needs.append(catalog.TAG_CALORIE_LOW)
    if t.sugar_g >= targets.sugar_g * SUGAR_HIGH_RATIO:
        needs.append(catalog.TAG_SUGAR_LOW)
    return needs


def snack_needs(t: TodayTotals, targets: inputs.DietTargets) -> list[str]:
    """저녁 뒤 간식으로 채울 것. 줄여야 하는 것(나트륨·당류)은 간식으로 채우지 않는다."""
    needs: list[str] = []
    if targets.protein_g - t.protein_g >= PROTEIN_GAP_G:
        needs.append(catalog.TAG_PROTEIN_HIGH)
    if t.kcal <= targets.calories * CALORIE_LOW_RATIO:
        needs.append(catalog.TAG_CALORIE_HIGH)
    return needs


def satisfied_today(t: TodayTotals, targets: inputs.DietTargets) -> set[str]:
    """오늘 이미 채운 이유. 급한 것이 없을 때도 이 태그의 메뉴는 고르지 않는다 —
    "추천 이유가 충족되면 다른 메뉴로" 바뀌어야 한다."""
    done: set[str] = set()
    if t.has_entries and targets.protein_g - t.protein_g < PROTEIN_GAP_G:
        done.add(catalog.TAG_PROTEIN_HIGH)
    return done


def pick_menu(
    menus: list[diet_menu_plan.PlanMenu],
    needs: list[str],
    recent: set[str],
    satisfied: set[str] = frozenset(),
) -> diet_menu_plan.PlanMenu | None:
    """급한 태그부터, 최근에 추천하지 않은 메뉴를 고른다.

    급한 태그의 메뉴가 모두 최근에 추천한 것이면, 다른 태그로 넘어가기보다 그 태그의
    메뉴를 다시 쓴다 — 이유가 맞는 메뉴가 새 메뉴보다 중요하다. 오늘 이미 채운
    이유([satisfied])의 메뉴는 다른 메뉴가 있는 한 고르지 않는다.
    """
    order = needs + [t for t in _DEFAULT_TAGS if t not in needs and t not in satisfied]
    if catalog.TAG_CALORIE_LOW in needs and catalog.TAG_CALORIE_HIGH in order:
        order.remove(catalog.TAG_CALORIE_HIGH)
    for tag in order:
        of_tag = [m for m in menus if m.tag == tag]
        fresh = [m for m in of_tag if diet_menu_plan.norm_name(m.name) not in recent]
        if fresh:
            return fresh[0]
        if of_tag and tag in needs:
            return of_tag[0]
    return menus[0] if menus else None


def analysis_today(t: TodayTotals, targets: inputs.DietTargets, at: time) -> Line:
    if not t.has_entries:
        return line("today_empty")
    if missing_meal(t.slots, at):
        return line("today_missing_meal")
    if t.sodium_mg > targets.sodium_mg:
        return line("today_sodium_over", sodium_mg=t.sodium_mg)
    if t.kcal > targets.calories * CALORIE_OVER_RATIO:
        return line("today_calorie_over", kcal=t.kcal)
    gap = round(targets.protein_g - t.protein_g)
    if gap >= PROTEIN_GAP_G:
        return line("today_protein_left", protein_g=gap)
    return line("today_balanced", kcal=t.kcal)


# ── 추천한 메뉴 기억 ─────────────────────────────────────────────────────


def _recent_picks(db: Session, user_id: str, today: date) -> set[str]:
    since = (today - timedelta(days=RECENT_PICK_DAYS)).isoformat()
    rows = db.scalars(
        select(DietAdviceState)
        .where(DietAdviceState.user_id == user_id)
        .where(DietAdviceState.period == PERIOD_TODAY)
        .where(DietAdviceState.key_date >= since)
        .where(DietAdviceState.key_date < today.isoformat())
    ).all()
    names: set[str] = set()
    for row in rows:
        try:
            picks = json.loads(row.payload_json or "{}").get("picks", [])
        except (ValueError, AttributeError):
            continue
        names.update(diet_menu_plan.norm_name(str(p)) for p in picks)
    return names


def _remember_pick(db: Session, user_id: str, today: date, lang: str, name: str) -> None:
    key = today.isoformat()
    row = db.scalar(
        select(DietAdviceState)
        .where(DietAdviceState.user_id == user_id)
        .where(DietAdviceState.period == PERIOD_TODAY)
        .where(DietAdviceState.key_date == key)
        .where(DietAdviceState.lang == lang)
    )
    if row is None:
        db.add(DietAdviceState(
            id=f"dadv-{uuid.uuid4().hex[:16]}", user_id=user_id, period=PERIOD_TODAY,
            key_date=key, lang=lang, payload_json=json.dumps({"picks": [name]}, ensure_ascii=False),
        ))
        try:
            db.commit()
        except IntegrityError:
            # 같은 회원의 두 요청이 동시에 처음 기록했다 — 한쪽이 남았으면 충분하다.
            db.rollback()
        return
    payload = json.loads(row.payload_json or "{}")
    picks = payload.get("picks", [])
    if name in picks:
        return
    payload["picks"] = [*picks, name]
    row.payload_json = json.dumps(payload, ensure_ascii=False)
    db.commit()


# ── 오늘 ────────────────────────────────────────────────────────────────


def today_advice(
    db: Session,
    user_id: str,
    *,
    lang: str = "ko",
    use_llm: bool = True,
    now: datetime | None = None,
) -> DietAdvice:
    now = now or clock.now()
    today = now.date()
    at = now.timetz().replace(tzinfo=None)

    entries = inputs.entries_between(db, user_id, today, today)
    totals = today_totals(entries)
    targets = inputs.targets_of(inputs.load_profile(db, user_id))
    analysis = analysis_today(totals, targets, at)

    slot = next_slot(totals.slots, at)
    if slot is not None:
        needs = needs_today(totals, targets)
    elif totals.has_entries:
        needs = snack_needs(totals, targets)
        slot = catalog.SLOT_SNACK if needs else None
    else:
        needs = []

    action: Line | None = None
    source: str | None = None
    if analysis.key == "today_missing_meal":
        action = line("today_log_first")
        source = "rules"
    elif slot is not None:
        plan = diet_menu_plan.get_plan(db, user_id, lang=lang, use_llm=use_llm, now=now)
        menu = pick_menu(
            plan.for_slot(slot), needs, _recent_picks(db, user_id, today),
            satisfied_today(totals, targets),
        )
        if menu is not None:
            _remember_pick(db, user_id, today, plan.lang, menu.name)
            if slot == catalog.SLOT_SNACK:
                # 키워드는 문장에 싣지 않지만 값으로는 준다 — 앱이 따로 보여 줄 수 있다.
                action = line("next_snack", menu=menu.name, keyword=menu.keyword)
            else:
                action = line("next_meal", slot=slot, menu=menu.name, keyword=menu.keyword)
            source = "plan"
    elif totals.has_entries:
        action = line("today_done")
        source = "rules"

    return DietAdvice(
        period=PERIOD_TODAY,
        from_date=today.isoformat(),
        to_date=today.isoformat(),
        days_logged=1 if totals.has_entries else 0,
        analysis=analysis,
        action=action,
        action_source=source,
    )


# ── 만든 조언 보관(이번 주·전체) ─────────────────────────────────────────


def load_state(
    db: Session, user_id: str, period: str, key_date: str, lang: str
) -> DietAdviceState | None:
    return db.scalar(
        select(DietAdviceState)
        .where(DietAdviceState.user_id == user_id)
        .where(DietAdviceState.period == period)
        .where(DietAdviceState.key_date == key_date)
        .where(DietAdviceState.lang == lang)
    )


def _line_payload(ln: Line | None) -> dict | None:
    if ln is None:
        return None
    return {"key": ln.key, "params": ln.params, "raw": ln.raw}


def _line_from(data: dict | None) -> Line | None:
    if not data:
        return None
    return Line(key=data.get("key"), params=data.get("params") or {}, raw=data.get("raw") or "")


def advice_payload(advice: DietAdvice) -> dict:
    return {
        "from_date": advice.from_date,
        "to_date": advice.to_date,
        "days_logged": advice.days_logged,
        "analysis": _line_payload(advice.analysis),
        "action": _line_payload(advice.action),
        "action_source": advice.action_source,
    }


def advice_from_state(period: str, row: DietAdviceState) -> DietAdvice | None:
    try:
        data = json.loads(row.payload_json or "{}")
        analysis = _line_from(data["analysis"])
    except (ValueError, KeyError, TypeError):
        return None
    if analysis is None:
        return None
    return DietAdvice(
        period=period,
        from_date=data.get("from_date", ""),
        to_date=data.get("to_date", ""),
        days_logged=int(data.get("days_logged", 0)),
        analysis=analysis,
        action=_line_from(data.get("action")),
        action_source=data.get("action_source"),
    )


def cached_advice(
    db: Session, user_id: str, period: str, key_date: str, lang: str, now: datetime
) -> DietAdvice | None:
    """보관한 조언. 없거나, AI 실패로 둔 대체 문장의 재시도 시각이 지났으면 None."""
    row = load_state(db, user_id, period, key_date, lang)
    if row is None:
        return None
    if row.retry_after is not None:
        retry = row.retry_after if row.retry_after.tzinfo else row.retry_after.replace(tzinfo=clock.SEOUL)
        if retry <= now:
            return None
    return advice_from_state(period, row)


def store_advice(
    db: Session,
    user_id: str,
    period: str,
    key_date: str,
    lang: str,
    advice: DietAdvice,
    *,
    retry_after: datetime | None,
) -> None:
    """만든 조언을 둔다. 같은 날(주)의 것이 있으면 갈아 끼운다."""
    payload = json.dumps(advice_payload(advice), ensure_ascii=False)
    row = load_state(db, user_id, period, key_date, lang)
    if row is None:
        db.add(DietAdviceState(
            id=f"dadv-{uuid.uuid4().hex[:16]}", user_id=user_id, period=period,
            key_date=key_date, lang=lang, payload_json=payload, retry_after=retry_after,
        ))
    else:
        row.payload_json = payload
        row.retry_after = retry_after
    try:
        db.commit()
    except IntegrityError:
        # 같은 회원의 두 요청이 동시에 처음 만들었다 — 먼저 들어간 것이 남으면 충분하다.
        db.rollback()
