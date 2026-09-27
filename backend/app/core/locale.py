"""요청 로케일(#2297) — 클라이언트가 보낸 `Accept-Language` 로 서버 문장의 언어를 고른다.

회원 앱·트레이너 웹은 화면 언어(`ko`·`en`)를 모든 요청의 `Accept-Language` 로 보낸다.
서버가 만드는 문장(리포트 요약·조언·라벨·AI 추천·알림 등)은 이 값을 보고 언어를 고른다.

쓰는 방법은 두 가지다.

- **서비스 코드**: 인자를 따로 넘기지 않고 :func:`current_locale` 을 부른다.
  :class:`RequestLocaleMiddleware` 가 요청마다 컨텍스트 변수를 채우므로, 같은 요청 안의
  어느 깊이에서든(동기 엔드포인트의 스레드풀 포함) 그 요청의 언어가 나온다.
- **라우터**: ``locale: RequestLocale`` 처럼 의존성으로 받는다(:func:`get_request_locale`).

지원 언어는 ``ko`` 와 ``en`` 뿐이다. 헤더가 없거나, 지원 언어가 하나도 없거나,
형식이 깨졌으면 기본값 ``ko`` 다 — 지금까지의 동작(모든 문장이 한국어)과 같다.
"""
from __future__ import annotations

from contextvars import ContextVar
from typing import Annotated, Literal

from fastapi import Depends, Request
from starlette.types import ASGIApp, Receive, Scope, Send

Locale = Literal["ko", "en"]

#: 서버가 문장을 만들 수 있는 언어. 이 순서는 우선순위가 아니다 — 가중치(q)가
#: 같으면 **헤더에 적힌 순서**로 가린다.
SUPPORTED_LOCALES: tuple[Locale, ...] = ("ko", "en")

#: 헤더가 없거나 고를 수 있는 언어가 없을 때의 언어.
DEFAULT_LOCALE: Locale = "ko"

#: 한 헤더에서 살펴보는 최대 길이·항목 수. 비정상적으로 긴 헤더로 파싱에 시간을
#: 쓰게 만들지 못하게 앞부분만 본다(실제 브라우저 헤더는 수십 바이트다).
_MAX_HEADER_LENGTH = 1024
_MAX_ENTRIES = 32

_request_locale_ctx: ContextVar[Locale] = ContextVar(
    "request_locale", default=DEFAULT_LOCALE
)


def _parse_q(params: list[str]) -> float | None:
    """`;q=0.8` 같은 매개변수에서 가중치를 읽는다. 없으면 1, 깨졌으면 ``None``."""
    for param in params:
        name, sep, value = param.partition("=")
        if name.strip().lower() != "q":
            continue
        if not sep:
            return None
        try:
            q = float(value.strip())
        except ValueError:
            return None
        # nan·inf·범위 밖 값은 형식 위반이다.
        if not 0.0 <= q <= 1.0:
            return None
        return q
    return 1.0


def parse_accept_language(header: str | None) -> Locale:
    """`Accept-Language` 값에서 지원 언어 하나를 고른다.

    - 언어 태그는 주 언어만 본다(``en-US`` → ``en``, ``ko-KR`` → ``ko``), 대소문자 무관.
    - 가중치(``q``)가 가장 큰 지원 언어를 고르고, 같으면 헤더에서 먼저 나온 것이다.
    - ``q=0`` 은 "받지 않음"이라 고르지 않는다.
    - ``*`` 와 지원하지 않는 언어, 형식이 깨진 항목은 건너뛴다.
    - 고를 것이 없으면 :data:`DEFAULT_LOCALE`.
    """
    if not header:
        return DEFAULT_LOCALE

    best: Locale | None = None
    best_q = 0.0
    entries = header[:_MAX_HEADER_LENGTH].split(",")[:_MAX_ENTRIES]
    for entry in entries:
        tag, *params = entry.split(";")
        primary = tag.strip().split("-", 1)[0].split("_", 1)[0].lower()
        if primary not in SUPPORTED_LOCALES:
            continue
        q = _parse_q(params)
        if q is None or q <= 0.0:
            continue
        if best is None or q > best_q:
            best, best_q = primary, q  # type: ignore[assignment]
    return best or DEFAULT_LOCALE


def current_locale() -> Locale:
    """지금 처리 중인 요청의 언어. 요청 밖(배치·스케줄러·테스트)에서는 기본값이다."""
    return _request_locale_ctx.get()


def localized(ko: str, en: str, locale: Locale | None = None) -> str:
    """언어에 맞는 문장을 고른다. ``locale`` 을 생략하면 :func:`current_locale`."""
    return en if (locale or current_locale()) == "en" else ko


def get_request_locale(request: Request) -> Locale:
    """라우터 의존성 — 이 요청의 언어.

    미들웨어가 정해 둔 값이 있으면 그것을, 없으면(미들웨어 없이 조립한 테스트 앱,
    미들웨어 바깥에서 도는 예외 핸들러) 헤더를 직접 읽는다.
    """
    cached = request.scope.get("state", {}).get("locale")
    if cached in SUPPORTED_LOCALES:
        return cached
    return parse_accept_language(request.headers.get("accept-language"))


#: 라우터 매개변수 타입: ``def handler(locale: RequestLocale): ...``
RequestLocale = Annotated[Locale, Depends(get_request_locale)]


class RequestLocaleMiddleware:
    """요청마다 `Accept-Language` 를 읽어 :func:`current_locale` 을 채운다.

    순수 ASGI 미들웨어다. 값은 요청이 끝나면 되돌려 놓아 다른 요청으로 새지 않는다 —
    동시에 도는 요청은 각자의 컨텍스트를 가지므로 서로의 언어를 보지 않는다.
    """

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        header: str | None = None
        for name, value in scope.get("headers", ()):
            if name == b"accept-language":
                header = value.decode("latin-1")
                break
        locale = parse_accept_language(header)
        # request.state 에도 실어 둔다 — 컨텍스트가 이미 되돌려진 뒤에 도는 전역 예외
        # 핸들러도 같은 언어를 쓸 수 있게.
        scope.setdefault("state", {})["locale"] = locale
        token = _request_locale_ctx.set(locale)
        try:
            await self.app(scope, receive, send)
        finally:
            _request_locale_ctx.reset(token)
