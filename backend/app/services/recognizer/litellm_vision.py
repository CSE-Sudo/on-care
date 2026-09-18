"""
LiteLLM(Claude) 경유 식단 인식기.

Claude 비전 모델에 음식 사진을 주고 JSON 으로 분석받습니다.
LiteLLM 이 OpenAI 호환이므로, OpenAI SDK 의 vision 형식(base64 image_url)을 사용합니다.
결과는 Gemini 인식기와 동일한 DietAnalysis 로 변환 → 프론트 계약 동일.

Gemini 인식기와 같은 방향(전문 영양사 + 회원의 식단 목표 관점 + 나트륨·당류).
"""
from __future__ import annotations

import base64
import json
import math
import re
import time

from app.core.config import get_settings
from app.schemas.diet import DietAnalysis, RecognizedFood
from app.services.recognizer.base import FoodRecognizer

_PROMPT = """당신은 전문 영양사입니다. 이 음식 사진을 분석해 아래 JSON 스키마로만 응답하세요.
설명, 마크다운, 코드블록 없이 순수 JSON만 출력합니다.

{
  "foods": [
    {"name":"음식명(한국어)","amount_g":추정섭취량g,"calories":정수kcal,"carbs_g":탄수화물g,"protein_g":단백질g,"fat_g":지방g,"sodium_mg":정수mg,"sugar_g":정수g,"confidence":0.0~1.0}
  ],
  "coach_comment": "운동하는 회원의 식단 목표(칼로리·단백질·나트륨·당류) 관점 식단평. 넘치거나 모자란 영양을 짚고 개선 제안을 2~3문장 한국어로. 질환 이름을 꺼내거나 진단하지 마세요."
}
음식이 여러 개면 foods 에 모두. 모르는 값은 null.

amount_g 는 **사진에 실제로 담긴 양**을 그램으로 추정하세요(그릇 크기·조각 수를
근거로). 공공 영양 DB 가 100g 당 값을 갖고 있어 이 값으로 환산합니다 — 영양
수치보다 이쪽이 더 중요합니다. 나트륨·당류도 함께 신중히 추정하세요."""


class LiteLLMVisionRecognizer(FoodRecognizer):
    name = "claude"  # LiteLLM 뒤의 Claude 비전 모델

    def __init__(self) -> None:
        s = get_settings()
        if not s.litellm_api_key:
            raise RuntimeError("LITELLM_API_KEY(Virtual Key) 가 설정되지 않았습니다.")
        from openai import OpenAI
        # 타임아웃을 둬서 지연 응답이 작업 스레드를 오래 점유하지 않게 함
        self._client = OpenAI(
            api_key=s.litellm_api_key, base_url=f"{s.litellm_base_url}/v1", timeout=60.0
        )
        self._model = s.litellm_vision_model

    async def recognize(self, image_bytes: bytes, mime_type: str) -> DietAnalysis:
        import asyncio
        start = time.perf_counter()
        b64 = base64.b64encode(image_bytes).decode()
        data_url = f"data:{mime_type};base64,{b64}"

        resp = await asyncio.to_thread(
            self._client.chat.completions.create,
            model=self._model,
            messages=[{
                "role": "user",
                "content": [
                    {"type": "text", "text": _PROMPT},
                    {"type": "image_url", "image_url": {"url": data_url}},
                ],
            }],
            temperature=0.2,
        )
        latency_ms = int((time.perf_counter() - start) * 1000)
        raw = resp.choices[0].message.content or ""
        return self._parse(raw, latency_ms)

    def _parse(self, raw: str, latency_ms: int) -> DietAnalysis:
        # Claude 가 코드블록(```json ... ```)으로 감쌀 수 있어 앞부분 펜스만 정확히 제거
        text = raw.strip()
        # 선행 ```lang 펜스와 후행 ``` 만 제거 (본문의 'json' 은 건드리지 않음)
        text = re.sub(r"^```[a-zA-Z]*\s*", "", text)
        text = re.sub(r"\s*```$", "", text).strip()
        foods: list[RecognizedFood] = []
        coach = ""
        try:
            data = json.loads(text)
            coach = str(data.get("coach_comment", "") or "")
            for f in data.get("foods", []):
                foods.append(RecognizedFood(
                    name=str(f.get("name", "알 수 없음")),
                    calories=_i(f.get("calories")), sodium_mg=_i(f.get("sodium_mg")),
                    carbs_g=_macro_f(f.get("carbs_g")),
                    protein_g=_macro_f(f.get("protein_g")),
                    fat_g=_macro_f(f.get("fat_g")), sugar_g=_i(f.get("sugar_g")),
                    # 보정이 100g 기준 값을 이 양으로 환산한다 — 안 넘기면
                    # 프롬프트가 요구해도 항상 None 이라 폴백만 탄다.
                    amount_g=_amount_g(f.get("amount_g")),
                    confidence=_f(f.get("confidence")),
                ))
        except (json.JSONDecodeError, AttributeError):
            pass
        return DietAnalysis(
            engine=self.name, foods=foods, coach_comment=coach,
            latency_ms=latency_ms, raw_model_output=raw,
        ).compute_totals()


def _i(v):
    if v is None:
        return None
    try:
        return int(round(float(v)))
    except (TypeError, ValueError):
        return None


def _f(v):
    if v is None:
        return None
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def _amount_g(v):
    """추정 섭취량(g). 0·음수·비유한값은 "모름"으로 눕힌다.

    `RecognizedFood.amount_g` 는 `gt=0` 이라 0 을 그대로 넘기면 검증 오류로
    응답 파싱 전체가 깨진다. 모델이 0 을 줬다는 건 양을 모른다는 뜻이므로
    None 이 맞다(보정이 폴백을 타거나 추정치를 유지한다).
    """
    if v is None:
        return None
    try:
        value = float(v)
    except (TypeError, ValueError):
        return None
    return value if math.isfinite(value) and value > 0 else None


def _macro_f(v):
    if v is None:
        return None
    try:
        value = float(v)
    except (TypeError, ValueError):
        return None
    return value if math.isfinite(value) and value >= 0 else None
