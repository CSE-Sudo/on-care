"""
식단 API 응답 스키마 — 프론트 계약(_dietToday) 정렬.

GET /diet/days/today 응답:
  { entries[], total_calories, total_sodium_mg, total_sugar_g, macros, ai_coach_message }
entries[]: { id, meal_type, time_label, foods[], total_calories, carbs_g, protein_g,
             fat_g, sodium_mg, sugar_g, photo_asset? }
"""
from __future__ import annotations

import re
from datetime import date as _date
from typing import Any, Literal
from pydantic import BaseModel, Field, field_validator

from app.core import clock
from app.schemas.points_api import PointsOut

#: 계약 날짜 표기. `2026-08-01` 만 받는다.
_YMD = re.compile(r"\d{4}-\d{2}-\d{2}")

from app.schemas.partial_update import PartialUpdate

from app.schemas.diet import DietAnalysis, RecognizedFood


class Macros(BaseModel):
    carbs_g: float = 0.0
    protein_g: float = 0.0
    fat_g: float = 0.0
    carbs_pct: int = 0
    protein_pct: int = 0
    fat_pct: int = 0


def calculate_macros(carbs_g: float, protein_g: float, fat_g: float) -> Macros:
    """Build 4/4/9 percentages with largest remainders; ties favor fat, then protein."""
    energies = (carbs_g * 4, protein_g * 4, fat_g * 9)
    total_energy = sum(energies)
    if total_energy == 0:
        percentages = [0, 0, 0]
    else:
        raw_percentages = [energy / total_energy * 100 for energy in energies]
        percentages = [int(value) for value in raw_percentages]
        remaining = 100 - sum(percentages)
        ranked = sorted(
            range(len(percentages)),
            key=lambda index: (raw_percentages[index] - percentages[index], index),
            reverse=True,
        )
        for index in ranked[:remaining]:
            percentages[index] += 1
    return Macros(
        carbs_g=carbs_g,
        protein_g=protein_g,
        fat_g=fat_g,
        carbs_pct=percentages[0],
        protein_pct=percentages[1],
        fat_pct=percentages[2],
    )


class DietEntryOut(BaseModel):
    id: str
    meal_type: str
    time_label: str
    foods: list[dict[str, Any]]  # [{name, calories}]
    total_calories: int
    carbs_g: float
    protein_g: float
    fat_g: float
    sodium_mg: int
    sugar_g: float
    # Local/demo seeds may point at a bundled Flutter asset. Real API entries
    # do not own a client asset path, so they return null.
    photo_asset: str | None = None
    # 회원이 올린 끼니 사진의 조회 경로(API base 기준 상대 경로). 사진이 없으면
    # null — 사진 저장(#699) 이전 기록과 인식만 하고 사진을 못 남긴 기록이 있다.
    photo_url: str | None = None


class DietEntryUpdate(PartialUpdate):
    """PUT /diet/entries/{id} — 끼니 정보와 영양소 부분 수정.

    모든 항목이 DB NOT NULL 이라 null 로 바꿀 수 있는 값이 아니다(#495).
    """
    #: 기록 날짜(`YYYY-MM-DD`). 사진 분석은 저장 시각의 날짜로 남기는데, 지난
    #: 식사의 사진을 나중에 올리는 일이 있어 실제로 먹은 날로 옮길 수 있어야
    #: 한다(#1241).
    date: str | None = None
    meal_type: str | None = None
    time_label: str | None = None
    #: 고친 음식 목록(#1892). 오면 저장된 음식을 이 값으로 갈아 끼우고, 끼니
    #: 합계도 이 목록에서 다시 낸다 — 함께 온 합계 값보다 음식이 우선이다.
    #: 원본을 하나로 두지 않으면 음식을 고칠 때마다 합계와 내역이 갈린다.
    #:
    #: 빈 목록은 받지 않는다. 음식이 하나도 없는 끼니는 수정이 아니라 삭제이고
    #: (앱도 그때 삭제할지 묻는다), 실수로 빈 배열이 오면 그 기록의 영양이
    #: 소리 없이 0 이 된다.
    foods: list[RecognizedFood] | None = Field(None, min_length=1)
    total_calories: int | None = Field(None, ge=0)
    carbs_g: float | None = Field(None, ge=0, allow_inf_nan=False)
    protein_g: float | None = Field(None, ge=0, allow_inf_nan=False)
    fat_g: float | None = Field(None, ge=0, allow_inf_nan=False)
    sodium_mg: int | None = Field(None, ge=0)
    sugar_g: float | None = Field(None, ge=0, allow_inf_nan=False)

    @field_validator("date")
    @classmethod
    def _valid_past_or_today(cls, value: str | None) -> str | None:
        """달력에 있는 날짜여야 하고, 아직 오지 않은 날은 받지 않는다.

        먹지 않은 식사를 기록할 수는 없다. 앞날을 허용하면 오늘까지를 세는
        평균·연속 기록이 미래 값을 함께 세어 화면마다 다른 수를 말한다.
        """
        if value is None:
            return None
        # `fromisoformat` 은 `20260801` 같은 축약형도 받는다. 계약은 한 가지
        # 표기뿐이라 형태부터 걸러 낸다 — 두 표기가 섞이면 화면과 로그에서
        # 같은 날짜가 다른 문자열로 남는다.
        if not _YMD.fullmatch(value):
            raise ValueError("date 는 YYYY-MM-DD 형식이어야 합니다.")
        try:
            parsed = _date.fromisoformat(value)
        except ValueError as e:
            raise ValueError("date 는 YYYY-MM-DD 형식이어야 합니다.") from e
        if parsed > clock.today():
            raise ValueError("date 는 오늘보다 뒤일 수 없습니다.")
        return parsed.isoformat()


class DietAdviceResponse(BaseModel):
    """기간에 맞는 식단 조언. (#1017)

    기간 경계도 함께 돌려준다 — 화면이 "무슨 구간을 두고 한 말인가" 를 보여 줄 수
    있어야 하고, 앱과 서버가 서로 다른 주를 셌는지도 이 값으로 드러난다.
    """

    period: str
    from_date: str
    to_date: str
    days_logged: int
    message: str


class DietTodayResponse(BaseModel):
    entries: list[DietEntryOut]
    total_calories: int
    total_sodium_mg: int
    total_sugar_g: float
    macros: Macros
    ai_coach_message: str


class DietAnalyzeResponse(BaseModel):
    """POST /diet/analyze 응답: 저장된 entry id + 분석 결과 (+ 사진 경로)."""
    entry_id: str
    analysis: DietAnalysis
    # 저장된 기록의 시각(`HH:MM`). `entries[]` 가 내려주는 것과 같은 값이며,
    # 저장한 시계 스냅샷에서 뽑은 서버 값이다(`save_analyzed_entry`). 앱이 제
    # 시계로 다시 계산하면 끼니 카드가 보여 주는 시각과 어긋날 수 있어 여기서
    # 내려준다(#1897).
    time_label: str = ""
    # 방금 올린 사진의 조회 경로. 저장하지 못했으면 null 이며, 그때도 끼니 기록
    # 자체는 저장된다(사진은 기록의 부속이지 조건이 아니다).
    photo_url: str | None = None
    # 이 끼니로 받은 포인트와 잔액(#1786). 한도를 넘었으면 `awarded` 가 0 이다.
    # 멱등키로 되돌아온 재시도는 처음 저장할 때 받은 값을 그대로 싣는다.
    points: PointsOut | None = None


class DietRecommendationItem(BaseModel):
    """홈 추천 카드 1장.

    문자열(요리명·태그)을 내려주지 않는 게 핵심이다. 앱이 `key` 로 번들 이미지와
    로케일 문구를 찾아 그리므로, 서버는 "무엇을 어떤 순서로"만 정한다.
    `reason_text` 는 LLM 이 쓴 개인화 문구이며 없을 수 있다(그때 앱은 `reason_key`
    의 l10n 기본 문구를 쓴다) — 영어 로케일에서 한국어가 새는 걸 막는 장치다.
    """
    key: str
    reason_key: str
    reason_text: str | None = None


class DietRecommendationsResponse(BaseModel):
    """GET /diet/recommendations 응답.

    `basis` 는 추천의 근거를 사람이 읽는 한 줄로 요약한 것(예: "최근 3일 평균 나트륨
    2,400mg"). 개인화가 실제로 일어났는지 화면에서 확인할 수 있게 노출한다.
    `personalized=False` 면 근거 데이터가 없어 기본 순서로 내려준 것이다.
    `source` 는 관측용: llm | rules | fallback.
    """
    items: list[DietRecommendationItem]
    basis: str | None = None
    personalized: bool = False
    source: Literal["llm", "rules", "fallback"] = "rules"

    # 근거를 앱이 직접 문장으로 만들 수 있도록 수치도 함께 준다. `basis` 는 서버가
    # 조립한 한국어 문장이라 영어 로케일에 그대로 쓸 수 없다(요리명·이유를 key 로
    # 주고받는 것과 같은 이유). 화면 문구는 앱이 l10n 으로 만든다.
    days_with_data: int = 0
    avg_sodium_mg: int = 0
    sodium_limit_mg: int = 0
