"""AI 호출 폴백 로그의 공용 규칙. (#3090)

회원 AI 코치(`coach/chat.py:_log_fallback`, #1559)가 먼저 세운 원칙을 모든 AI 경로가
같이 쓴다 — **사유·오류 유형·HTTP 상태·발생 위치·식별자만 남기고, 예외 메시지와
스택은 남기지 않는다.**

- provider SDK 는 오류 메시지에 요청 본문(프롬프트: 회원 프로필·식단·대화)이나 키
  일부를 되풀이하는 일이 있다.
- 파이단틱 `ValidationError` 문자열은 `input_value=` 로 모델이 낸 값을 그대로 싣는다.
- 스택(`exc_info`)도 마지막 줄에 같은 메시지를 찍는다.

우리 쪽 버그를 찾는 데 필요한 것은 "어디서" 다. 그래서 스택 대신 예외가 난 가장
안쪽 위치(파일·줄·함수)만 `origin` 으로 남긴다. 요청 상관관계는 로깅 필터가 모든
레코드에 붙이는 `request_id` 로 잇는다.
"""
from __future__ import annotations

import logging
import os
from typing import Any

#: 로그 레코드의 `event` 기본값 — 로그 수집기에서 AI 폴백만 골라 볼 때 쓰는 키.
AI_FALLBACK_EVENT = "ai_fallback"


def error_type(exc: BaseException | None) -> str:
    """`모듈.클래스` 형태의 예외 유형. 없으면 `-`."""
    if exc is None:
        return "-"
    return f"{type(exc).__module__}.{type(exc).__qualname__}"


def http_status(exc: BaseException | None) -> int | None:
    """provider SDK 예외에 실린 HTTP 상태(401·429·5xx…). 없으면 None.

    SDK 마다 이름이 달라(`status_code`·`code`) 정수인 것만 쓴다 — 인증 오류와
    한도 초과를 운영에서 가르는 데 가장 쓸모 있는 값이다.
    """
    if exc is None:
        return None
    for attr in ("status_code", "code"):
        value = getattr(exc, attr, None)
        if isinstance(value, int) and not isinstance(value, bool):
            return value
    return None


def error_origin(exc: BaseException | None) -> str:
    """예외가 난 가장 안쪽 위치 `파일:줄 in 함수`. 트레이스백이 없으면 `-`."""
    tb = exc.__traceback__ if exc is not None else None
    if tb is None:
        return "-"
    while tb.tb_next is not None:
        tb = tb.tb_next
    code = tb.tb_frame.f_code
    return f"{os.path.basename(code.co_filename)}:{tb.tb_lineno} in {code.co_name}"


def log_ai_fallback(
    logger: logging.Logger,
    what: str,
    reason: str,
    *,
    exc: BaseException | None = None,
    level: int = logging.WARNING,
    event: str = AI_FALLBACK_EVENT,
    **ids: Any,
) -> None:
    """AI 폴백 한 건을 구조화 로그로 남긴다.

    ``what`` 은 어느 기능인지(예: `diet_recommendation`), ``reason`` 은 왜 폴백했는지
    (`contract`·`error`·`timeout` …)다. ``ids`` 에는 trainer_id·member_id 같은
    식별자만 넣는다 — 모델 출력·프롬프트·회원이 쓴 글은 넣지 않는다.
    """
    fields: dict[str, Any] = {
        "event": event,
        "ai_feature": what,
        "fallback_reason": reason,
        "error_type": error_type(exc),
        "http_status": http_status(exc),
        "error_origin": error_origin(exc),
        **ids,
    }
    status = fields["http_status"]
    id_part = "".join(f" {key}=%s" for key in ids)
    logger.log(
        level,
        "AI 폴백 feature=%s reason=%s error_type=%s http_status=%s origin=%s" + id_part,
        what,
        reason,
        fields["error_type"],
        status if status is not None else "-",
        fields["error_origin"],
        *ids.values(),
        extra=fields,
    )
