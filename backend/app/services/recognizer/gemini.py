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
import time

from google import genai
from google.genai import types

from app.core.config import get_settings
from app.schemas.diet import DietAnalysis
from app.services import ai_call_quota
from app.services.coach.llm import gemini_truncated
from app.services.coach.llm_base import output_cap
from app.services.recognizer.base import RECOGNIZER_MAX_OUTPUT_TOKENS, FoodRecognizer
from app.services.recognizer.parse import parse_payload
from app.services.recognizer.prompt import RECOGNITION_PROMPT

#: 인식 프롬프트는 엔진과 무관하게 하나다(#1642).
_PROMPT = RECOGNITION_PROMPT


class GeminiVisionRecognizer(FoodRecognizer):
    name = "gemini"

    def __init__(self) -> None:
        settings = get_settings()
        if not settings.gemini_api_key:
            raise RuntimeError("GEMINI_API_KEY 가 설정되지 않았습니다. .env 를 확인하세요.")
        # 타임아웃(ms). 지연 응답이 작업 스레드를 오래 점유하지 않게 함. 값은 설정에서
        # 읽는다 — 운영 중 조정하려고 배포할 일이 없게(#2912).
        self._client = genai.Client(
            api_key=settings.gemini_api_key,
            http_options=types.HttpOptions(
                timeout=int(settings.recognizer_timeout_seconds * 1000)
            ),
        )
        self._model = settings.gemini_model

    async def recognize(self, image_bytes: bytes, mime_type: str) -> DietAnalysis:
        prompt = _PROMPT
        # 서버 전체 하루 상한(#3032). 사진 분석은 규칙형 대안이 없어, 넘으면 라우터가
        # 503 `ai_capacity` 로 답하고 회원의 하루 몫을 돌려준다.
        await asyncio.to_thread(ai_call_quota.acquire, ai_call_quota.FEATURE_DIET_PHOTO)
        start = time.perf_counter()
        response = await asyncio.to_thread(
            self._client.models.generate_content,
            model=self._model,
            contents=[
                prompt,
                types.Part.from_bytes(data=image_bytes, mime_type=mime_type),
            ],
            config=types.GenerateContentConfig(
                response_mime_type="application/json",
                temperature=0.2,
                # 출력 토큰 상한(#3032).
                max_output_tokens=output_cap(RECOGNIZER_MAX_OUTPUT_TOKENS),
            ),
        )
        latency_ms = int((time.perf_counter() - start) * 1000)
        if gemini_truncated(response):
            # 끊긴 JSON 은 음식 일부만 저장될 수 있다 — 인식 실패(502)로 돌린다.
            raise RuntimeError("식단 인식 응답이 출력 상한에 걸려 끊김")
        return self._parse(response.text or "", latency_ms)

    def _parse(self, raw: str, latency_ms: int) -> DietAnalysis:
        # 값 검사·상한은 두 인식기가 같은 규칙을 쓴다(#3090, `parse.py`).
        try:
            foods, coach_comment = parse_payload(json.loads(raw))
        except json.JSONDecodeError:
            foods, coach_comment = [], ""

        return DietAnalysis(
            engine=self.name,
            foods=foods,
            coach_comment=coach_comment,
            latency_ms=latency_ms,
            raw_model_output=raw,
        ).compute_totals()
