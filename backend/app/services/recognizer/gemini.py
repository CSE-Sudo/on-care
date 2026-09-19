"""
Gemini Vision 식단 인식기.

기존 PoC(gemini_service.py)의 방향 계승:
  - 전문 영양사 역할
  - 회원의 식단 목표 관점 식단평 + 개선 제안(질환을 말하지 않는다)
하지만 PoC 는 자유 텍스트만 반환했고, 우리는 프론트 저장을 위해
  - 음식별 구조화 데이터(칼로리/나트륨/당류)  ← entries 저장용
  - 식단평 텍스트(coach_comment)               ← ai_coach_message/코칭용
둘 다 JSON 으로 받아냅니다.
"""
from __future__ import annotations

import asyncio
import json
import math
import time

from google import genai
from google.genai import types

from app.core.config import get_settings
from app.schemas.diet import DietAnalysis, RecognizedFood
from app.services.recognizer.base import FoodRecognizer

_PROMPT = """당신은 전문 영양사입니다. 업로드된 음식 사진을 분석해 아래 JSON 스키마로만 응답하세요.
설명, 마크다운, 코드블록 없이 순수 JSON만 출력합니다.

{
  "foods": [
    {
      "name": "음식 이름(한국어)",
      "amount_g": 사진에 담긴 양(g),
      "calories": 예상 칼로리 정수(kcal),
      "carbs_g": 예상 탄수화물(g),
      "protein_g": 예상 단백질(g),
      "fat_g": 예상 지방(g),
      "sodium_mg": 예상 나트륨 정수(mg),
      "sugar_g": 예상 당류 정수(g),
      "confidence": 0.0~1.0 인식 확신도
    }
  ],
  "coach_comment": "운동하는 회원의 식단 목표(칼로리·단백질·나트륨·당류) 관점의 식단평. 넘치거나 모자란 영양을 짚고, 장단점과 구체적 개선 제안(예: '국물을 남기세요', '단백질 반찬을 더하세요')을 2~3문장으로 친절하게 한국어로. 질환 이름을 꺼내거나 진단하지 마세요."
}

음식이 여러 개면 foods 에 모두 넣으세요. 모르는 값은 null 로 두세요.
amount_g 는 **사진에 실제로 담긴 양**을 그램으로 추정하세요(그릇 크기·조각 수를
근거로). 공공 영양 DB 가 100g 당 값을 갖고 있어 이 값으로 환산합니다 — 영양
수치보다 이쪽이 더 중요합니다.
나트륨·당류는 회원의 일일 목표와 비교하는 값이니 신중히 추정하세요."""


class GeminiVisionRecognizer(FoodRecognizer):
    name = "gemini"

    def __init__(self) -> None:
        settings = get_settings()
        if not settings.gemini_api_key:
            raise RuntimeError("GEMINI_API_KEY 가 설정되지 않았습니다. .env 를 확인하세요.")
        # 타임아웃(ms). 지연 응답이 작업 스레드를 오래 점유하지 않게 함
        self._client = genai.Client(
            api_key=settings.gemini_api_key,
            http_options=types.HttpOptions(timeout=60_000),
        )
        self._model = settings.gemini_model

    async def recognize(self, image_bytes: bytes, mime_type: str) -> DietAnalysis:
        start = time.perf_counter()
        response = await asyncio.to_thread(
            self._client.models.generate_content,
            model=self._model,
            contents=[
                _PROMPT,
                types.Part.from_bytes(data=image_bytes, mime_type=mime_type),
            ],
            config=types.GenerateContentConfig(
                response_mime_type="application/json",
                temperature=0.2,
            ),
        )
        latency_ms = int((time.perf_counter() - start) * 1000)
        return self._parse(response.text or "", latency_ms)

    def _parse(self, raw: str, latency_ms: int) -> DietAnalysis:
        foods: list[RecognizedFood] = []
        coach_comment = ""
        try:
            data = json.loads(raw)
            coach_comment = str(data.get("coach_comment", "") or "")
            for f in data.get("foods", []):
                foods.append(
                    RecognizedFood(
                        name=str(f.get("name", "알 수 없음")),
                        amount_g=_as_amount_g(f.get("amount_g")),
                        calories=_as_int(f.get("calories")),
                        carbs_g=_as_macro_float(f.get("carbs_g")),
                        protein_g=_as_macro_float(f.get("protein_g")),
                        fat_g=_as_macro_float(f.get("fat_g")),
                        sodium_mg=_as_int(f.get("sodium_mg")),
                        sugar_g=_as_int(f.get("sugar_g")),
                        confidence=_as_float(f.get("confidence")),
                    )
                )
        except (json.JSONDecodeError, AttributeError):
            pass

        return DietAnalysis(
            engine=self.name,
            foods=foods,
            coach_comment=coach_comment,
            latency_ms=latency_ms,
            raw_model_output=raw,
        ).compute_totals()


def _as_int(v) -> int | None:
    if v is None:
        return None
    try:
        return int(round(float(v)))
    except (TypeError, ValueError):
        return None


def _as_float(v) -> float | None:
    if v is None:
        return None
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def _as_amount_g(v) -> float | None:
    """사진에 담긴 양(g). 0·음수·비유한값은 "모름"(None)으로 눕힌다. (#2090)

    `RecognizedFood.amount_g` 는 `gt=0` 이라 0 을 그대로 넘기면 검증 오류로 응답
    파싱 전체가 깨진다. 모델이 0 을 줬다는 건 양을 모른다는 뜻이다 — 보정이
    알려진 1회 섭취량으로 폴백하거나 추정치를 유지한다(`litellm_vision` 과 같은 규칙).
    """
    if v is None:
        return None
    try:
        value = float(v)
    except (TypeError, ValueError):
        return None
    return value if math.isfinite(value) and value > 0 else None


def _as_macro_float(v) -> float | None:
    if v is None:
        return None
    try:
        value = float(v)
    except (TypeError, ValueError):
        return None
    return value if math.isfinite(value) and value >= 0 else None
