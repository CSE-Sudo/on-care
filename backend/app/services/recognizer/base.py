"""모든 식단 인식 엔진이 따르는 공통 인터페이스.

입력 계약(#3041): `recognize` 가 받는 바이트는 `POST /diet/analyze` 가
`image_sanitize.to_jpeg` 로 **이미 정리한 JPEG** 이다 — 회전이 픽셀에 적용됐고
EXIF(촬영 위치·시각·기기) 등 메타데이터가 없으며 장변이
`image_sanitize.RECOGNITION_MAX_EDGE` 이하다. `mime_type` 은 늘 `image/jpeg` 다.
엔진은 받은 바이트를 그대로 외부로 보내면 된다. 정리는 진입점 한 곳에서 하므로
엔진마다 메타데이터를 떼는 처리를 따로 두지 않는다 — 새 엔진도 같은 입력을 받는다.
"""
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
        """정리된 JPEG(위 입력 계약)에서 음식을 찾는다."""
        raise NotImplementedError
