"""
대시보드(홈) 라우터 — 프론트 계약 정렬.

  GET /dashboard/summary -> 홈 화면용 종합 집계

식단/운동/일정 데이터를 모아 한 번에 반환합니다.
권장 기준치(나트륨 2000mg, 당류 50g, 칼로리 2000kcal)는 고혈압·당뇨 관점 기본값.
"""
from __future__ import annotations

import json
from collections.abc import Iterable
from datetime import datetime, timedelta
from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import CurrentUser
from app.core import clock
from app.db.session import get_db
from app.models.models import DietEntry, ExerciseSession
from app.schemas.dashboard_api import (
    DashboardIndicator, DashboardNutritionDay,
    DashboardSummary,
)
from app.schemas.diet_api import calculate_macros

router = APIRouter(tags=["dashboard"])

# 일일 권장 기준치. 나트륨은 WHO 권고, 당류는 2025 한국인 영양소 섭취기준의
# 첨가당 권고(총에너지의 10% 이내 = 2,000kcal 기준 50g)를 따른다(#1652).
_MAX_CALORIES = 2000
_MAX_SODIUM_MG = 2000
_MAX_SUGAR_G = 50

# 요일 라벨(월=0 … 일=6) — 홈 주간 추이 차트 x축용
_DAY_LABELS = ["월", "화", "수", "목", "금", "토", "일"]


def _score_for(sodium_ok: bool, exercise_minutes: int) -> int:
    """식단 균형(나트륨) + 운동량 기반 간이 주간 점수(0~100)."""
    score = 50
    if sodium_ok:
        score += 20
    if exercise_minutes >= 150:
        score += 30
    elif exercise_minutes > 0:
        score += 15
    return min(score, 100)


def _avg_sodium_of_logged(days: list[DashboardNutritionDay]) -> float | None:
    """기록된(칼로리>0) 날짜들의 평균 나트륨(mg). 기록이 없으면 None.

    주간 점수를 이번 주·지난 주 모두 "기록된 날짜들의 평균 나트륨"으로 계산해
    하루치와 주간 평균을 비교하는 왜곡을 막는다.
    """
    logged = [d for d in days if d.calories > 0]
    if not logged:
        return None
    return sum(d.sodium_mg for d in logged) / len(logged)


def _nutrition_week(
    db: Session, uid: str, monday: datetime,
) -> list[DashboardNutritionDay]:
    """월요일 [monday]부터 일요일까지 7일의 일별 영양 집계(월→일).

    차트 x축이 고정 월~일이므로 달력 주(캘린더 위크) 기준으로 집계해 요일이
    정확히 정렬되게 한다. 오늘 이후(미래) 요일은 기록이 없어 0으로 남는다.
    """
    dates = [
        (monday + timedelta(days=i)).strftime("%Y-%m-%d") for i in range(7)
    ]
    rows = db.scalars(
        select(DietEntry).where(DietEntry.user_id == uid).where(DietEntry.date.in_(dates))
    ).all()
    # [cal, na, sugar]
    acc: dict[str, list[float]] = {d: [0, 0, 0] for d in dates}
    for r in rows:
        a = acc.get(r.date)
        if a is not None:
            a[0] += r.total_calories
            a[1] += r.sodium_mg
            a[2] += r.sugar_g
    return [
        DashboardNutritionDay(
            date=d, label=_DAY_LABELS[i],
            calories=acc[d][0], sodium_mg=acc[d][1], sugar_g=acc[d][2],
        )
        for i, d in enumerate(dates)
    ]


def _build_sodium_warning(
    total_sodium_mg: int,
    source_names: list[str],
    sodium_goal_mg: int = _MAX_SODIUM_MG,
) -> str | None:
    if total_sodium_mg <= sodium_goal_mg:
        return None
    if not source_names:
        return (
            f"오늘 나트륨이 {total_sodium_mg}mg 으로 "
            f"권장량({sodium_goal_mg}mg)을 넘었어요."
        )

    top_source_names = "·".join(source_names[:2])
    return f"{top_source_names} 섭취로 나트륨이 높아요."


def _advice_key(
    *,
    sodium_warning: str | None,
    sodium_source_names: list[str],
    exercise_advice_key: str,
) -> str | None:
    """홈 조언으로 고른 문장의 로케일 독립 식별자. (#1943)

    앱이 고르는 순서와 **같은 순서**로 고른다(`ai_advice_text.dart`) — 나트륨
    경고가 있으면 그것이고, 없으면 운동 되먹임이다. 순서가 갈리면 키가 가리키는
    문장과 화면이 어긋난다.

    음식 이름이 들어간 나트륨 경고는 키를 주지 않는다. 그 이름은 회원이 적은
    데이터라 번역 대상이 아니고, 문장을 통째로 보내는 편이 맞다.
    """
    if sodium_warning is not None:
        return None if sodium_source_names else "sodium_over"
    return exercise_advice_key


def _rank_sodium_sources(foods_json_values: Iterable[str]) -> list[str]:
    sodium_by_food_name: dict[str, int] = {}
    for foods_json in foods_json_values:
        try:
            foods = json.loads(foods_json)
        except (TypeError, json.JSONDecodeError):
            continue
        for food in foods if isinstance(foods, list) else []:
            if not isinstance(food, dict):
                continue
            name = str(food.get("name") or "").strip()
            sodium = food.get("sodium_mg")
            if name and isinstance(sodium, (int, float)) and sodium > 0:
                sodium_by_food_name[name] = (
                    sodium_by_food_name.get(name, 0) + int(sodium)
                )

    sodium_sources = sorted(
        sodium_by_food_name.items(),
        key=lambda item: (-item[1], item[0]),
    )
    return [name for name, _ in sodium_sources]


@router.get("/dashboard/summary", response_model=DashboardSummary)
def dashboard_summary(
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> DashboardSummary:
    uid = current_user.id
    health_profile = current_user.health_profile
    calorie_goal = (
        health_profile.daily_calories
        if health_profile and health_profile.daily_calories is not None
        else _MAX_CALORIES
    )
    sodium_goal = (
        health_profile.daily_sodium_mg
        if health_profile and health_profile.daily_sodium_mg is not None
        else _MAX_SODIUM_MG
    )
    sugar_goal = (
        health_profile.daily_sugar_g
        if health_profile and health_profile.daily_sugar_g is not None
        else _MAX_SUGAR_G
    )
    today_dt = clock.now()
    today = today_dt.strftime("%Y-%m-%d")

    # --- 오늘 식단 집계 ---
    diet_rows = db.scalars(
        select(DietEntry).where(DietEntry.user_id == uid).where(DietEntry.date == today)
    ).all()
    total_cal = sum(r.total_calories for r in diet_rows)
    total_na = sum(r.sodium_mg for r in diet_rows)
    total_sugar = sum(r.sugar_g for r in diet_rows)
    total_carbs = sum(r.carbs_g for r in diet_rows)
    total_protein = sum(r.protein_g for r in diet_rows)
    total_fat = sum(r.fat_g for r in diet_rows)
    macros = calculate_macros(total_carbs, total_protein, total_fat)

    indicators = [
        DashboardIndicator(label="칼로리", current=total_cal, max=calorie_goal,
                           unit="kcal", over_budget=total_cal > calorie_goal),
        DashboardIndicator(label="나트륨", current=total_na, max=sodium_goal,
                           unit="mg", over_budget=total_na > sodium_goal),
        DashboardIndicator(label="당류", current=total_sugar, max=sugar_goal,
                           unit="g", over_budget=total_sugar > sugar_goal),
    ]
    source_names = _rank_sodium_sources(row.foods_json for row in diet_rows)
    sodium_warning = _build_sodium_warning(total_na, source_names, sodium_goal)

    # --- 식단 주간 추이(이번 주 월~일 + 지난 주 월~일 비교선) ---
    this_monday = today_dt - timedelta(days=today_dt.weekday())
    nutrition_week = _nutrition_week(db, uid, this_monday)
    nutrition_week_prev = _nutrition_week(db, uid, this_monday - timedelta(days=7))

    # --- 이번 주 운동 집계 ---
    # 위 식단·주간 추이와 같은 스냅샷에서 뽑는다 — 여기서 시계를 다시 읽으면
    # KST 자정을 걸친 요청에서 한 응답 안의 기준 주가 갈린다.
    week = this_monday.strftime("%Y-%m-%d")
    ex_rows = db.scalars(
        select(ExerciseSession).where(ExerciseSession.user_id == uid)
        .where(ExerciseSession.week_start == week)
    ).all()
    exercise_minutes = sum(r.minutes for r in ex_rows)
    exercise_calories = sum(r.calories for r in ex_rows)
    exercise_count = len(ex_rows)
    if exercise_minutes >= 150:
        exercise_feedback = f"이번 주 {exercise_minutes}분 운동했어요. 목표 달성 중이에요!"
        exercise_advice_key = "exercise_on_track"
    elif exercise_minutes > 0:
        exercise_feedback = f"이번 주 {exercise_minutes}분 운동했어요. 조금만 더 힘내요!"
        exercise_advice_key = "exercise_more"
    else:
        exercise_feedback = "이번 주 운동을 시작해 보세요. 가벼운 걷기부터 좋아요."
        exercise_advice_key = "exercise_start"

    # --- 주간 점수 + 지난주 대비 변화량(동일 공식으로 실제 차이 집계) ---
    # 이번 주 점수도 지난주와 같은 방식(기록된 날짜들의 평균 나트륨)으로 계산한다.
    # 하루치(total_na)를 주간 평균과 비교하면 왜곡되고, 오늘 아직 식사를 기록하지
    # 않았을 때 total_na==0 이라 주간 식습관과 무관하게 나트륨 조건을 통과하는
    # 문제가 있었다. 이번 주 기록이 아직 없으면 오늘 하루치로 폴백한다.
    this_avg_sodium = _avg_sodium_of_logged(nutrition_week)
    if this_avg_sodium is None:
        this_avg_sodium = total_na
    score = _score_for(this_avg_sodium <= sodium_goal, exercise_minutes)
    last_week = (today_dt - timedelta(days=today_dt.weekday() + 7)).strftime("%Y-%m-%d")
    last_ex_minutes = sum(
        r.minutes for r in db.scalars(
            select(ExerciseSession).where(ExerciseSession.user_id == uid)
            .where(ExerciseSession.week_start == last_week)
        ).all()
    )
    last_avg_sodium = _avg_sodium_of_logged(nutrition_week_prev) or 0
    last_week_score = _score_for(last_avg_sodium <= sodium_goal, last_ex_minutes)
    week_score_delta = score - last_week_score

    return DashboardSummary(
        indicators=indicators,
        macros=macros,
        diet_entries=len(diet_rows),
        exercise_minutes=exercise_minutes,
        exercise_calories=exercise_calories,
        exercise_count=exercise_count,
        nutrition_week=nutrition_week,
        nutrition_week_prev=nutrition_week_prev,
        week_score=score,
        week_score_delta=week_score_delta,
        sodium_warning=sodium_warning,
        exercise_feedback=exercise_feedback,
        ai_advice_key=_advice_key(
            sodium_warning=sodium_warning,
            sodium_source_names=source_names,
            exercise_advice_key=exercise_advice_key,
        ),
    )
