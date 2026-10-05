"""
관측성(운영 장애 추적) — 요청 ID · 구조화 액세스 로그 · 전역 예외 처리 · 로깅 설정.

- 요청마다 request ID 를 부여한다. 외부 `X-Request-ID` 는 **형식 검증**을 통과한 값만
  재사용하고(로그 인젝션 방지), 아니면 새 UUID 를 생성한다.
- 모든 응답에 `X-Request-ID` 헤더를 실어 클라이언트↔서버 로그를 상관지을 수 있게 한다.
- 액세스 로그는 method·path·status·duration·request_id 만 남긴다(쿼리/바디/Authorization
  등 민감정보는 남기지 않는다).
- 처리되지 않은 예외는 서버 로그에 stack trace 를 **한 번** 남기고, 클라이언트에는 내부
  상세를 감춘 공통 500 응답(request_id 포함)만 반환한다.
- 에러 추적(Sentry)이 켜져 있으면 같은 예외를 요청 id 와 함께 보낸다(`error_tracking`).
"""
from __future__ import annotations

import logging
import re
import time
import uuid
from collections.abc import Collection
from contextvars import ContextVar

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from app.core import error_tracking
from app.core.locale import get_request_locale, localized

# 로그·헤더에 그대로 싣기 안전한 request ID 형식(영숫자 . _ -, 1~64자). 그 외 입력은 신뢰하지 않는다.
_REQUEST_ID_RE = re.compile(r"^[A-Za-z0-9._-]{1,64}$")
_REQUEST_ID_HEADER = "X-Request-ID"

# 현재 요청의 ID. 로그 필터가 여기서 읽어 모든 로그 레코드에 붙인다.
request_id_ctx: ContextVar[str] = ContextVar("request_id", default="-")

logger = logging.getLogger("app.access")


def new_request_id() -> str:
    return uuid.uuid4().hex


def _resolve_request_id(raw: str | None) -> str:
    """외부 헤더 값은 형식 검증을 통과할 때만 재사용하고, 아니면 새로 생성한다.

    fullmatch 로 문자열 전체를 검사한다 — match+$ 는 'abc\\n' 처럼 끝의 개행 직전까지만
    매치될 수 있어(로그 인젝션 여지) 안전하지 않다.
    """
    if raw and _REQUEST_ID_RE.fullmatch(raw):
        return raw
    return new_request_id()


class RequestIdLogFilter(logging.Filter):
    """모든 로그 레코드에 현재 request_id 를 주입한다(포맷 문자열에서 %(request_id)s 사용)."""

    def filter(self, record: logging.LogRecord) -> bool:
        record.request_id = request_id_ctx.get()
        return True


# 외부 호출 HTTP 클라이언트 로거. httpx 는 INFO 로 요청마다 전체 URL(쿼리 포함)을 남기고
# httpcore 는 DEBUG 로 연결 단계를 남긴다. 외부 API 의 URL 쿼리에는 토큰·키가 실릴 수
# 있으므로 루트 수준과 상관없이 WARNING 이상만 남긴다(#2351).
_QUIET_HTTP_CLIENT_LOGGERS = ("httpx", "httpcore")


def setup_logging(level: str = "INFO") -> None:
    """루트 로거를 request_id 포함 포맷으로 설정한다(호출당 핸들러 1개로 재설정).

    외부 호출 HTTP 클라이언트 로거(httpx·httpcore)는 WARNING 으로 고정한다 — 요청 URL 이
    INFO 로그에 남지 않게 한다.
    """
    handler = logging.StreamHandler()
    handler.setFormatter(logging.Formatter(
        "%(asctime)s %(levelname)s [%(request_id)s] %(name)s: %(message)s"
    ))
    handler.addFilter(RequestIdLogFilter())
    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(level)
    for name in _QUIET_HTTP_CLIENT_LOGGERS:
        logging.getLogger(name).setLevel(logging.WARNING)


# LB/오케스트레이터가 자주 폴링하는 헬스 경로는 액세스 로그에서 제외(로그 도배 방지).
# readiness 실패의 원인은 system.readyz 가 별도로 logger.exception 으로 남긴다.
_ACCESS_LOG_SKIP_SUFFIXES = ("/ping", "/healthz", "/readyz")


def _cors_headers(request: Request, origins: Collection[str]) -> dict[str, str]:
    """전역 500 응답에 붙일 CORS 헤더. `CORSMiddleware` 와 같은 규칙이다. (#3242)

    전역 예외 핸들러는 가장 바깥 `ServerErrorMiddleware` 에서 돌아 CORS 미들웨어를
    거치지 않는다. 헤더가 없으면 브라우저가 응답을 가려, 두 웹은 500 을 CORS 오류로만
    보고 본문의 `request_id` 를 읽지 못한다. 그래서 여기서 같은 판정을 한 번 더 한다.

    - 출처 목록에 `*` 가 있으면 자격증명 없이 `*`(main.py 의 설정과 같다).
    - 목록에 있는 출처면 그 출처를 돌려주고 자격증명을 허용한다.
    - 그 밖의 출처나 `Origin` 이 없는 요청(앱·서버 간 호출)에는 붙이지 않는다.
    """
    origin = request.headers.get("origin")
    if not origin:
        return {}
    if "*" in origins:
        return {"Access-Control-Allow-Origin": "*"}
    if origin in origins:
        return {
            "Access-Control-Allow-Origin": origin,
            "Access-Control-Allow-Credentials": "true",
            "Vary": "Origin",
        }
    return {}


def install(app: FastAPI, *, cors_origins: Collection[str] = ()) -> None:
    """request-id 미들웨어 + 액세스 로그 + 전역 예외 핸들러를 앱에 설치한다.

    [cors_origins] 는 `CORSMiddleware` 에 준 출처 목록이다 — 전역 500 응답에도 같은
    CORS 헤더를 붙이는 데 쓴다([_cors_headers]).
    """
    cors_origins = tuple(cors_origins)

    @app.middleware("http")
    async def _request_context(request: Request, call_next):
        rid = _resolve_request_id(request.headers.get(_REQUEST_ID_HEADER))
        # request.state 에도 실어 둔다 — 전역 예외 핸들러는 이 미들웨어 바깥에서 실행되어
        # contextvar 가 이미 리셋됐을 수 있으므로, 핸들러는 request.state 에서 rid 를 읽는다.
        request.state.request_id = rid
        token = request_id_ctx.set(rid)
        # 에러 추적 이벤트에도 같은 요청 id 를 달아 서버 로그와 잇는다(#2839).
        error_tracking.tag_request(rid)
        start = time.monotonic()
        # 액세스 로그·응답 헤더는 반드시 reset 이전에 처리한다 — reset 뒤에 로그하면
        # contextvar 가 이미 '-' 라 로그의 request_id 가 비어 상관관계가 끊긴다.
        # path 는 %r 로 남긴다 — 인코딩된 CR/LF 등이 로그 행을 깨거나 위조하지 못하게.
        try:
            response = await call_next(request)
            duration_ms = (time.monotonic() - start) * 1000
            # 민감정보(쿼리/바디/헤더)는 남기지 않는다 — method·path·상태·소요시간만.
            # 헬스 폴링 경로는 로그에서 제외한다.
            if not request.url.path.endswith(_ACCESS_LOG_SKIP_SUFFIXES):
                logger.info(
                    "%s %r -> %d (%.1fms)",
                    request.method, request.url.path, response.status_code, duration_ms,
                )
            response.headers[_REQUEST_ID_HEADER] = rid
            return response
        except Exception:
            duration_ms = (time.monotonic() - start) * 1000
            # 성공 경로와 동일하게 헬스 폴링 경로는 로그 제외 — 헬스 핸들러의 미처리 예외가
            # 폴링 빈도만큼 로그를 도배하지 않도록(리뷰 일관성).
            if not request.url.path.endswith(_ACCESS_LOG_SKIP_SUFFIXES):
                logger.info("%s %r -> 500 (%.1fms)", request.method, request.url.path, duration_ms)
            raise
        finally:
            request_id_ctx.reset(token)

    @app.exception_handler(Exception)
    async def _unhandled_exception(request: Request, exc: Exception):
        rid = getattr(request.state, "request_id", "-")
        token = request_id_ctx.set(rid)  # 핸들러 로깅에도 rid 가 찍히도록
        try:
            # stack trace 는 서버 로그에만 한 번. 클라이언트엔 내부 상세를 노출하지 않는다.
            logging.getLogger("app.error").exception(
                "unhandled error: %s %r", request.method, request.url.path
            )
        finally:
            request_id_ctx.reset(token)
        # 에러 추적 도구로도 보낸다(요청 id 태그, 본문·헤더 제외). DSN 이 없으면 무시된다.
        error_tracking.capture_unhandled(exc, request_id=rid)
        return JSONResponse(
            status_code=500,
            # 이 핸들러는 요청 언어 미들웨어 바깥에서 돌아 컨텍스트가 이미 되돌려졌을 수
            # 있다 — 언어는 요청에서 직접 읽는다(#2297).
            content={
                "detail": localized(
                    "내부 서버 오류가 발생했습니다.",
                    "An internal server error occurred.",
                    get_request_locale(request),
                ),
                "request_id": rid,
            },
            headers={_REQUEST_ID_HEADER: rid, **_cors_headers(request, cors_origins)},
        )
