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
    #: 홈 `오늘의 AI 통합 조언` 이 고른 문장의 **로케일 독립 식별자**. (#1943)
    #:
    #: 앱은 이 키를 먼저 보고 자기 문장을 그린다. 키가 없으면 위 두 문장을 받은
    #: 그대로 쓰는데, 그것은 서버가 만든 한국어라 **영어 회원이 한국어 조언을
    #: 읽었다.** 데모 서버만 이 키를 내려주고 있었다.
    #:
    #: 나트륨 경고에 음식 이름이 들어가는 경우는 키를 주지 않는다 — 그 이름은
    #: 번역 대상이 아니라 회원이 적은 데이터라, 문장을 통째로 보내는 편이 맞다.
    ai_advice_key: Optional[str] = None
