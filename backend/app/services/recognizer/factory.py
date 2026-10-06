"""
.env 의 RECOGNIZER 로 인식기를 선택하는 팩토리.
get_recognizer("gemini") 처럼 이름으로 강제 지정 가능(비교실험).

**운영에서는 대체 인식기로 내려가지 않는다(#2812).** 스텁은 사진을 보지 않고 늘
같은 음식을 돌려주므로, 운영에서 키가 빠진 채 쓰이면 가짜 끼니가 저장되고 포인트가
나간다. 운영 설정 검증(`Settings._guard_prod_secrets`)이 기동부터 막고, 여기서도
한 번 더 [RecognizerUnavailable] 로 거절한다 — 라우터가 503 으로 옮긴다.
"""
from __future__ import annotations

from functools import lru_cache

from app.core.config import get_settings
from app.services.recognizer.base import FoodRecognizer

_REGISTRY: dict[str, type[FoodRecognizer]] = {}

#: 개발용 고정 식단 인식기의 이름. 이 엔진의 결과는 포인트·식판 조건에 세지 않는다.
STUB_ENGINE = "stub"


class RecognizerUnavailable(RuntimeError):
    """지금 설정으로는 실제 사진 인식을 할 수 없다(운영에서 키 없음·스텁 지정)."""


def _registry() -> dict[str, type[FoodRecognizer]]:
    if not _REGISTRY:
        from app.services.recognizer.gemini import GeminiVisionRecognizer
        from app.services.recognizer.stub import StubFoodRecognizer
        from app.services.recognizer.litellm_vision import LiteLLMVisionRecognizer

        _REGISTRY["gemini"] = GeminiVisionRecognizer
        _REGISTRY["litellm"] = LiteLLMVisionRecognizer  # LiteLLM 프록시 뒤의 비전 모델
        _REGISTRY[STUB_ENGINE] = StubFoodRecognizer  # 오프라인 폴백(키 불필요, 개발 전용)
    return _REGISTRY


@lru_cache
def _build(name: str) -> FoodRecognizer:
    reg = _registry()
    if name not in reg:
        raise ValueError(f"알 수 없는 인식 엔진: '{name}'. 사용 가능: {list(reg.keys())}")
    return reg[name]()


def get_recognizer(name: str | None = None) -> FoodRecognizer:
    """설정된 인식기를 반환.

    개발·테스트에서는 gemini 인데 키가 없으면 오프라인 스텁으로 폴백한다(키 없이도
    /diet/analyze 가 동작하도록). 운영에서는 폴백하지 않고 [RecognizerUnavailable].
    """
    s = get_settings()
    engine = (name or s.recognizer).lower()
    if s.is_prod:
        if engine == STUB_ENGINE or (engine == "gemini" and not s.gemini_api_key):
            raise RecognizerUnavailable(f"운영에서 쓸 수 없는 인식기 설정: {engine}")
    elif engine == "gemini" and not s.gemini_api_key:
        engine = STUB_ENGINE
    return _build(engine)
