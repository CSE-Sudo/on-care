"""
식단 인식 결과의 공통 형식(계약).

Gemini든 YOLO든 이 형식으로 변환됩니다(이식성).
On-Care 특화: 칼로리뿐 아니라 나트륨(sodium_mg)·당류(sugar_g)가 1급 지표.
또한 섭취기준 관점의 식단평(coach_comment)을 포함.
"""
from __future__ import annotations

from typing import Optional
from pydantic import BaseModel, Field


class RecognizedFood(BaseModel):
    name: str = Field(..., description="음식 이름(한국어)")
    calories: Optional[int] = Field(None, description="칼로리 kcal")
    carbs_g: Optional[float] = Field(
        None, ge=0, allow_inf_nan=False, description="탄수화물 g"
    )
    protein_g: Optional[float] = Field(
        None, ge=0, allow_inf_nan=False, description="단백질 g"
    )
    fat_g: Optional[float] = Field(None, ge=0, allow_inf_nan=False, description="지방 g")
    sodium_mg: Optional[int] = Field(None, description="나트륨 mg")
    sugar_g: Optional[float] = Field(
        None, ge=0, allow_inf_nan=False, description="당류 g"
    )
    # 사진에서 추정한 섭취량(g). 공공 DB 값은 100g 기준이라 이 값으로 환산한다.
    # 비전 모델은 "얼마나 있나" 는 잘 보지만 밀도는 모른다 — 밀도는 DB 가 댄다.
    amount_g: Optional[float] = Field(
        None, gt=0, allow_inf_nan=False, description="추정 섭취량 g"
    )
    confidence: Optional[float] = Field(None, ge=0.0, le=1.0)
    # 영양 수치 출처: 공공 DB | 인식기 추정 | 두 값의 혼합. 저장된 기록에는 회원이
    # 수정 화면에서 직접 고친 값(member)도 있다(#2105, `diet_api.EditedFood`).
    source: str = Field("estimate", description="db|estimate|mixed|member")


class DietAnalysis(BaseModel):
    """인식 엔진의 공통 출력."""
    engine: str
    foods: list[RecognizedFood] = Field(default_factory=list)
    total_calories: int = 0
    total_carbs_g: float = 0.0
    total_protein_g: float = 0.0
    total_fat_g: float = 0.0
    total_sodium_mg: int = 0
    total_sugar_g: float = 0.0
    # 나트륨·당류를 중심으로 한 식단평
    coach_comment: str = ""
    latency_ms: Optional[int] = None
    raw_model_output: Optional[str] = None

    def compute_totals(self) -> "DietAnalysis":
        self.total_calories = sum(f.calories or 0 for f in self.foods)
        self.total_carbs_g = sum(f.carbs_g or 0.0 for f in self.foods)
        self.total_protein_g = sum(f.protein_g or 0.0 for f in self.foods)
        self.total_fat_g = sum(f.fat_g or 0.0 for f in self.foods)
        self.total_sodium_mg = sum(f.sodium_mg or 0 for f in self.foods)
        self.total_sugar_g = sum(f.sugar_g or 0.0 for f in self.foods)
        return self
