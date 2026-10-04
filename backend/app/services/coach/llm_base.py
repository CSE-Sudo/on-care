"""코치 LLM 공통 인터페이스. 토큰 사용량 기록(모델 비교용)."""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field


@dataclass
class LLMResult:
    text: str
    model: str
    prompt_tokens: int = 0
    completion_tokens: int = 0
    total_tokens: int = 0
    extra: dict = field(default_factory=dict)
    #: 출력 토큰 상한에 걸려 응답이 중간에 끊겼다(#3032). JSON 을 받는 호출처는 이
    #: 값이 참이면 계약 위반으로 보고 규칙형 폴백으로 내린다.
    truncated: bool = False


def is_truncated(result: object) -> bool:
    """응답이 출력 상한에 잘렸는가. 테스트 스텁처럼 필드가 없는 응답은 거짓이다.

    `is True` 로 본다 — 속성을 무엇이든 만들어 주는 목 객체를 잘림으로 읽지 않게.
    """
    return getattr(result, "truncated", False) is True


def output_cap(preferred: int | None = None) -> int | None:
    """이번 호출에 넘길 출력 토큰 상한(#3032).

    설정 `llm_max_output_tokens` 가 천장이다 — 호출처가 [preferred] 를 주면 둘 중
    작은 값을 쓴다. 설정이 0 이면 상한을 넘기지 않는다(None).
    """
    from app.core.config import get_settings

    ceiling = max(get_settings().llm_max_output_tokens, 0)
    if ceiling <= 0:
        return None
    if preferred is None or preferred <= 0:
        return ceiling
    return min(ceiling, preferred)


class CoachLLM(ABC):
    name: str = "base"

    @property
    def model_name(self) -> str:
        """호출하는 모델 id. 구현이 `_model` 로 들고 있다 — 운영 로그용(#1559)."""
        return str(getattr(self, "_model", "") or "")

    @abstractmethod
    def generate(
        self,
        system_prompt: str,
        user_prompt: str,
        *,
        json_mode: bool = False,
        thinking_budget: int | None = None,
        timeout_seconds: float | None = None,
        max_output_tokens: int | None = None,
    ) -> LLMResult:
        """텍스트 생성.

        선택 인자는 **구조화된 짧은 출력**을 요구하는 호출부(추천·루틴 옵션 등)를
        위한 것이다. 기본값은 기존 동작 그대로라 산문 응답(챗봇)은 영향받지 않는다.

        - `json_mode`: 응답을 JSON 으로 강제(지원하지 않는 구현은 무시).
        - `thinking_budget`: 사고 토큰 상한. Gemini 계열은 기본적으로 사고가 켜져
          있어 짧은 JSON 하나를 뽑는 데도 10초 이상 걸린다. 작은 값을 주면 체감
          지연이 크게 준다(실측: 12.9s → 1.5s). 지원하지 않는 구현은 무시한다.
        - `timeout_seconds`: 이 호출의 전송 계층 제한. 호출부의 대기 제한보다 실제
          HTTP 요청이 오래 살아 worker를 점유하지 않게 한다.
        - `max_output_tokens`: 출력 토큰 상한(#3032). 주지 않으면 설정
          `llm_max_output_tokens` 를 쓴다([output_cap]). 상한에 걸려 끊긴 응답은
          `LLMResult.truncated` 가 참이다.
        """
        raise NotImplementedError
