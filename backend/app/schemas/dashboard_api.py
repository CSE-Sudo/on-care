"""대시보드(홈) 요약 스키마 — 프론트 _dashboardSummary 계약 정렬."""
from __future__ import annotations

from typing import Optional
from pydantic import BaseModel, Field

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
    #: 그대로 쓴다 — 그 두 문장도 요청 언어(`Accept-Language`)를 따르지만, 문장
    #: 틀은 앱 ARB 가 원본이다.
    #:
    #: `sodium_over` · `sodium_over_sources` · `exercise_on_track` ·
    #: `exercise_more` · `exercise_start` 중 하나다.
    ai_advice_key: Optional[str] = None
    #: [ai_advice_key] 문장에 끼울 값. `sodium_over_sources` 면 `foods`(나트륨
    #: 상위 급원 음식 이름, 최대 두 개)가 실린다. 음식 이름은 회원이 적은
    #: 데이터라 번역하지 않고 문장 틀에 그대로 끼운다.
    ai_advice_params: dict[str, list[str]] = Field(default_factory=dict)
