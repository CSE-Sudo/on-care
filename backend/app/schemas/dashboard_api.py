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
    #: 이번 주 **유산소** 분 — 운동 조언이 주간 유산소 목표와 견주는 값이고, 조언
    #: 문장에 적히는 분 수다(#3350). `exercise_minutes` 는 유형을 가리지 않은 합계다.
    exercise_cardio_minutes: int = 0
    # 식단 카드 주간 추이(이번 주 월~일 일별 영양). 홈 카드는 칼로리를 그린다.
    nutrition_week: list[DashboardNutritionDay] = []
    sodium_warning: Optional[str]
    exercise_feedback: str
    #: 홈 `오늘의 AI 통합 조언` 이 고른 문장의 **로케일 독립 식별자**. (#1943)
    #:
    #: 앱은 이 키를 먼저 보고 자기 문장을 그린다. 키가 없으면 위 두 문장을 받은
    #: 그대로 쓴다. 문장 틀은 앱 ARB 가 원본이다.
    #:
    #: `sodium_over` · `sodium_over_sources` · `exercise_on_track` ·
    #: `exercise_more` · `exercise_cardio_start` · `exercise_start` 중 하나다.
    ai_advice_key: Optional[str] = None
    #: [ai_advice_key] 문장에 끼울 값. `sodium_over_sources` 면 `foods`(나트륨
    #: 상위 급원 음식 이름, 최대 두 개)가 실린다. 음식 이름은 회원이 적은
    #: 데이터라 번역하지 않고 문장 틀에 그대로 끼운다.
    ai_advice_params: dict[str, list[str]] = Field(default_factory=dict)
