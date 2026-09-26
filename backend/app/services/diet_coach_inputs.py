"""식단 AI 맞춤 조언이 읽는 재료 — 목표, 트레이너 메시지, 최근 기록 요약. (#2250)

추천 메뉴 리스트(`diet_menu_plan`)와 기간별 조언이 **같은 재료**를 읽어야 한다.
목표를 한쪽은 개인 수치로, 다른 쪽은 기본값으로 보면 리스트는 단백질을 채우라는데
조언은 칼로리를 줄이라는 식으로 서로 다른 말을 한다.
"""
from __future__ import annotations

import hashlib
import json
from collections import Counter
from dataclasses import dataclass
from datetime import date, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core import clock
from app.models.models import ChatMessage, DietEntry, HealthProfile
from app.services import health_focus

#: 개인 목표가 없을 때의 기본값. 나트륨은 WHO 권고, 당류는 2025 한국인 영양소
#: 섭취기준의 첨가당 권고(총에너지 10% 이내)다 — 홈 추천 식단과 같은 값이다.
DEFAULT_CALORIES = 2000
DEFAULT_SODIUM_MG = 2000
DEFAULT_SUGAR_G = 50
#: 단백질은 체중이 있으면 체중 × 1.2g, 없으면 60g. 근력 운동을 하는 PT 회원에게
#: 일반 성인 권장(0.8g/kg)은 낮고, 개인 목표 칸은 비어 있는 경우가 많다.
PROTEIN_G_PER_KG = 1.2
DEFAULT_PROTEIN_G = 60

#: 트레이너 메시지를 거슬러 읽는 날 수와 개수. 오래된 지시는 이미 바뀌었을 수 있고,
#: 많이 넣으면 프롬프트가 대화 기록으로 채워진다.
TRAINER_NOTE_DAYS = 14
TRAINER_NOTE_LIMIT = 5
TRAINER_NOTE_MAX_CHARS = 200


@dataclass(frozen=True)
class DietTargets:
    calories: int
    protein_g: int
    sodium_mg: int
    sugar_g: int


def load_profile(db: Session, user_id: str) -> HealthProfile | None:
    return db.scalar(select(HealthProfile).where(HealthProfile.user_id == user_id))


def targets_of(profile: HealthProfile | None) -> DietTargets:
    """개인 목표를 먼저, 없으면 기본값."""
    if profile is not None and profile.daily_protein_g:
        protein = profile.daily_protein_g
    elif profile is not None and profile.weight_kg:
        protein = round(profile.weight_kg * PROTEIN_G_PER_KG)
    else:
        protein = DEFAULT_PROTEIN_G
    return DietTargets(
        calories=(profile.daily_calories if profile else None) or DEFAULT_CALORIES,
        protein_g=protein,
        sodium_mg=(profile.daily_sodium_mg if profile else None) or DEFAULT_SODIUM_MG,
        sugar_g=(profile.daily_sugar_g if profile else None) or DEFAULT_SUGAR_G,
    )


def goal_fingerprint(profile: HealthProfile | None) -> str:
    """목표가 바뀌었는지 가려내는 지문 — 건강 목표 칩과 수치 목표.

    칩은 순서를 보지 않는다(`health_goal_change.focus_changed` 와 같다). 체중은
    목표가 아니라 넣지 않는다 — 몸무게를 잴 때마다 리스트가 바뀌면 안 된다.
    """
    if profile is None:
        raw: dict = {}
    else:
        raw = {
            "focus": sorted(health_focus.focus_in(profile.conditions)),
            "goals": (profile.goals or "").strip(),
            "calories": profile.daily_calories,
            "protein": profile.daily_protein_g,
            "sodium": profile.daily_sodium_mg,
            "sugar": profile.daily_sugar_g,
        }
    blob = json.dumps(raw, ensure_ascii=False, sort_keys=True)
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()[:32]


def trainer_notes(db: Session, member_id: str) -> list[str]:
    """담당 트레이너가 최근 회원에게 보낸 메시지(새것부터).

    **회원이 이미 받은 것만** 읽는다 — 트레이너의 비공개 메모는 넣지 않는다. 조언이
    메모에서 나온 말을 하면 회원은 보지 못한 지시를 AI 에게서 듣게 된다.
    """
    from app.services.trainer_service import get_member_trainer_id

    trainer_id = get_member_trainer_id(db, member_id)
    if trainer_id is None:
        return []
    since = clock.now() - timedelta(days=TRAINER_NOTE_DAYS)
    rows = db.scalars(
        select(ChatMessage)
        .where(ChatMessage.member_id == member_id)
        .where(ChatMessage.trainer_id == trainer_id)
        .where(ChatMessage.sender == "trainer")
        .where(ChatMessage.created_at >= since)
        .order_by(ChatMessage.created_at.desc())
        .limit(TRAINER_NOTE_LIMIT)
    ).all()
    notes = []
    for row in rows:
        body = " ".join((row.body or "").split())
        if body:
            notes.append(body[:TRAINER_NOTE_MAX_CHARS])
    return notes


@dataclass(frozen=True)
class DietDigest:
    """기간의 식단 요약. 기록이 있는 날만 센다(안 먹은 날과 안 적은 날은 다르다)."""

    days_logged: int
    avg_calories: int
    avg_protein_g: int
    avg_sodium_mg: int
    avg_sugar_g: int
    #: 끼니별로 기록이 있는 날 수.
    slot_days: dict[str, int]
    #: 자주 먹은 음식 (이름, 횟수), 많은 순.
    top_foods: list[tuple[str, int]]


def food_names(entry: DietEntry) -> list[str]:
    try:
        foods = json.loads(entry.foods_json) if entry.foods_json else []
    except ValueError:
        return []
    names = []
    for food in foods if isinstance(foods, list) else []:
        name = str(food.get("name", "")).strip() if isinstance(food, dict) else ""
        if name:
            names.append(name)
    return names


def entries_between(db: Session, user_id: str, start: date, end: date) -> list[DietEntry]:
    return list(
        db.scalars(
            select(DietEntry)
            .where(DietEntry.user_id == user_id)
            .where(DietEntry.date >= start.isoformat())
            .where(DietEntry.date <= end.isoformat())
        ).all()
    )


def digest(entries: list[DietEntry], top_n: int = 15) -> DietDigest:
    per_day: dict[str, list[float]] = {}
    slot_days: dict[str, set[str]] = {}
    foods: Counter[str] = Counter()
    for e in entries:
        day = per_day.setdefault(e.date, [0.0, 0.0, 0.0, 0.0])
        day[0] += e.total_calories
        day[1] += e.protein_g
        day[2] += e.sodium_mg
        day[3] += e.sugar_g
        slot_days.setdefault(e.meal_type, set()).add(e.date)
        foods.update(food_names(e))
    n = len(per_day)

    def avg(i: int) -> int:
        return round(sum(v[i] for v in per_day.values()) / n) if n else 0

    return DietDigest(
        days_logged=n,
        avg_calories=avg(0),
        avg_protein_g=avg(1),
        avg_sodium_mg=avg(2),
        avg_sugar_g=avg(3),
        slot_days={slot: len(days) for slot, days in slot_days.items()},
        top_foods=foods.most_common(top_n),
    )
