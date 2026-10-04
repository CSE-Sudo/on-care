"""하루 AI 호출 상한(#3032)을 HTTP 응답으로 옮긴다.

상한은 서비스 깊은 곳([app.services.ai_call_quota.acquire])에서 걸린다. 라우터마다
같은 `try/except` 를 두면 새 AI 엔드포인트가 그것을 빠뜨려 500 이 되므로, 앱 전역
예외 처리기로 한 곳에서 바꾼다. 본문은 다른 한도와 같은 `detail: {code, message}` 다.

- 트레이너 상한 → **429 `daily_limit`** + `Retry-After`(다음 KST 자정까지 초).
  회원 AI 코치의 하루 한도와 같은 코드라 앱이 같은 안내 길을 쓴다.
- 서버 전체 상한 → **503 `ai_capacity`** + `Retry-After`. 규칙형 폴백이 있는 기능은
  여기까지 오지 않는다(서비스가 폴백으로 답한다). AI 코치 채팅·사진 분석처럼 대안이
  없는 기능만 이 응답을 본다.
"""
from __future__ import annotations

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse

from app.core.locale import Locale, get_request_locale, localized
from app.services.ai_call_quota import AiCapacityReached, TrainerAiDailyLimitReached

AI_CAPACITY_CODE = "ai_capacity"
DAILY_LIMIT_CODE = "daily_limit"


def capacity_detail(locale: Locale | None = None) -> dict[str, str]:
    return {
        "code": AI_CAPACITY_CODE,
        "message": localized(
            "지금은 AI 기능 이용이 많아 잠시 쉬어요. 내일 다시 이용해 주세요.",
            "AI features are taking a break due to high demand. Please try again tomorrow.",
            locale,
        ),
    }


def trainer_daily_limit_detail(locale: Locale | None = None) -> dict[str, str]:
    return {
        "code": DAILY_LIMIT_CODE,
        "message": localized(
            "오늘 AI 생성 한도를 다 썼어요. 내일 다시 이용해 주세요.",
            "You've used today's AI limit. Please try again tomorrow.",
            locale,
        ),
    }


def _retry_after(seconds: int) -> dict[str, str]:
    return {"Retry-After": str(max(1, int(seconds)))}


def capacity_http_error(exc: AiCapacityReached) -> HTTPException:
    """라우터가 직접 정리할 일이 있을 때(사진 분석의 회원 몫 반환) 쓰는 503."""
    return HTTPException(
        status_code=503,
        detail=capacity_detail(),
        headers=_retry_after(exc.retry_after_seconds),
    )


def install(app: FastAPI) -> None:
    @app.exception_handler(TrainerAiDailyLimitReached)
    async def _trainer_daily_limit(request: Request, exc: TrainerAiDailyLimitReached):
        return JSONResponse(
            status_code=429,
            content={"detail": trainer_daily_limit_detail(get_request_locale(request))},
            headers=_retry_after(exc.retry_after_seconds),
        )

    @app.exception_handler(AiCapacityReached)
    async def _ai_capacity(request: Request, exc: AiCapacityReached):
        return JSONResponse(
            status_code=503,
            content={"detail": capacity_detail(get_request_locale(request))},
            headers=_retry_after(exc.retry_after_seconds),
        )
