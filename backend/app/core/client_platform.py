"""요청을 보낸 클라이언트 종류(#2828) — 웹 빌드는 `X-Client-Platform: web` 을 싣는다.

웹 빌드(회원 앱 웹·트레이너 웹)는 토큰을 브라우저 탭 단위 저장소에 두므로 오래 가는
refresh 토큰이 필요 없고, 새어 나갔을 때 쓸 수 있는 기간은 짧을수록 좋다. 그래서 웹에서
온 로그인·토큰 회전에는 :attr:`Settings.web_refresh_token_expire_days` 수명의 refresh
토큰을 준다. 모바일 앱은 헤더를 보내지 않아 지금 수명을 그대로 쓴다.

헤더는 클라이언트가 스스로 밝히는 값이라 **수명을 줄이는 쪽으로만** 쓴다 — 헤더를
빼서 얻는 것은 원래 수명뿐이다. 한 번 웹으로 발급된 refresh 토큰은 회전 때 헤더가
없어도 웹 수명을 이어 간다(토큰 클레임으로 판단, `app/core/security.py`).

:class:`RequestClientPlatformMiddleware` 가 요청마다 컨텍스트 변수를 채우므로, 토큰을
발급하는 곳(`services/auth_tokens.py`)은 인자 없이 :func:`is_web_client` 를 부른다.
"""
from __future__ import annotations

from contextvars import ContextVar

from starlette.types import ASGIApp, Receive, Scope, Send

#: 클라이언트 종류 헤더 이름.
CLIENT_PLATFORM_HEADER = "X-Client-Platform"

#: 웹 빌드가 싣는 값.
WEB_PLATFORM = "web"

_HEADER_KEY = CLIENT_PLATFORM_HEADER.lower().encode("latin-1")

_is_web_ctx: ContextVar[bool] = ContextVar("client_platform_is_web", default=False)


def parse_client_platform(value: str | None) -> bool:
    """헤더 값이 웹인가. 대소문자·앞뒤 공백은 무시하고, 그 밖의 값은 모두 웹이 아니다."""
    if not value:
        return False
    return value.strip().lower() == WEB_PLATFORM


def is_web_client() -> bool:
    """지금 처리 중인 요청이 웹 빌드에서 왔는가. 요청 밖(배치·테스트)에서는 ``False``."""
    return _is_web_ctx.get()


class RequestClientPlatformMiddleware:
    """요청마다 :data:`CLIENT_PLATFORM_HEADER` 를 읽어 :func:`is_web_client` 를 채운다.

    순수 ASGI 미들웨어다. 값은 요청이 끝나면 되돌려 다른 요청으로 새지 않는다.
    """

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        value: str | None = None
        for name, raw in scope.get("headers", ()):
            if name == _HEADER_KEY:
                value = raw.decode("latin-1")
                break
        token = _is_web_ctx.set(parse_client_platform(value))
        try:
            await self.app(scope, receive, send)
        finally:
            _is_web_ctx.reset(token)
