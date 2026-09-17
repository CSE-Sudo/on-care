"""대시보드(홈) 요약 스키마 — 프론트 _dashboardSummary 계약 정렬."""
from __future__ import annotations

from typing import Optional
from pydantic import BaseModel

from app.schemas.diet_api import Macros


class DashboardIndicator(BaseModel):
    label: str            # 칼로리 | 나트륨 | 당류
    # 당류가 소수(17.8g)라 current 는 float. 칼로리·나트륨은 정수 값이 그대로
    # 실려 나가고, 목표치(max)는 세 지표 모두 정수라 int 를 유지한다.
    current: float
    max: int
    unit: str
    over_budget: bool = False


class DashboardNutritionDay(BaseModel):
    """홈 식단 카드의 주간 추이 차트 한 점 — 하루치 영양 집계."""
    date: str        # YYYY-MM-DD
    label: str       # 요일 라벨(월/화/…) — 프론트 x축용
    calories: int
    sodium_mg: int
    sugar_g: float


class DashboardSummary(BaseModel):
    indicators: list[DashboardIndicator]
    macros: Macros
    diet_entries: int
    exercise_minutes: int
    exercise_calories: int
    exercise_count: int
    # 운동 소모 목표(kcal) — 홈 운동 카드 진행률용. 개인화 전까지 서버 기본값.
    exercise_burn_goal: int = 500
    # 식단 카드 주간 추이(최근 7일 일별 영양) + 지난 주 같은 요일(비교선)
    nutrition_week: list[DashboardNutritionDay] = []
    nutrition_week_prev: list[DashboardNutritionDay] = []
    week_score: int
    week_score_delta: int
    sodium_warning: Optional[str]
    exercise_feedback: str
