"""모든 식단 인식 엔진이 따르는 공통 인터페이스."""
from __future__ import annotations

from abc import ABC, abstractmethod

from app.schemas.diet import DietAnalysis

#: 외부 비전 모델 응답의 출력 토큰 상한(#3032). 음식 몇 개와 식단평 두세 문장이 들어가는
#: 값이다. `LLM_MAX_OUTPUT_TOKENS` 가 더 작으면 그 값을 쓴다.
RECOGNIZER_MAX_OUTPUT_TOKENS = 2048


class FoodRecognizer(ABC):
    name: str = "base"

    @abstractmethod
    async def recognize(self, image_bytes: bytes, mime_type: str) -> DietAnalysis:
        raise NotImplementedError
