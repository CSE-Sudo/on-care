"""HTTPS 강제(운영) — 로드 밸런서 헬스체크 경로만 리다이렉트에서 뺀다(#3130).

운영은 `FORCE_HTTPS=true` 로 뜨고, 사용자 요청은 로드 밸런서가 붙인
`X-Forwarded-Proto` 를 uvicorn `--proxy-headers` 가 읽어 https 로 본다. 그런데 대상
그룹의 헬스체크는 컨테이너에 **평문 HTTP 로 직접** 들어오고 이 헤더를 붙이지 않는다.
Starlette 의 :class:`HTTPSRedirectMiddleware` 를 모든 경로에 걸면 `/v1/healthz` 가
200 대신 307 을 돌려줘 대상이 unhealthy 로 판정되고, ECS 가 태스크를 계속 갈아 치운다.

그래서 헬스체크 경로(:data:`HEALTH_CHECK_PATHS`)는 리다이렉트 없이 그대로 통과시키고,
나머지 경로는 지금처럼 https 로 보낸다. 두 경로는 비밀을 싣지 않는 공개 엔드포인트라
평문으로 답해도 새는 것이 없다. HSTS 헤더 처리(`app/core/security_headers.py`)는 그대로다.
"""
from __future__ import annotations

from collections.abc import Iterable

from fastapi import FastAPI
from starlette.middleware.httpsredirect import HTTPSRedirectMiddleware
from starlette.types import ASGIApp, Receive, Scope, Send

from app.core.config import Settings

#: 리다이렉트하지 않는 헬스체크 경로(API prefix 뒤). 로드 밸런서 헬스체크
#: (`infra/backend-service.yml` 의 HealthCheckPath)와 배포 검증이 부르는 두 경로다.
HEALTH_CHECK_PATHS: tuple[str, ...] = ("/healthz", "/readyz")


def exempt_paths(s: Settings) -> frozenset[str]:
    """리다이렉트에서 뺄 전체 경로 — 예: ``{"/v1/healthz", "/v1/readyz"}``."""
    prefix = s.api_v1_prefix.rstrip("/")
    return frozenset(f"{prefix}{path}" for path in HEALTH_CHECK_PATHS)


class HTTPSRedirectExceptHealthMiddleware:
    """헬스체크 경로를 뺀 나머지 http·ws 요청을 https·wss 로 리다이렉트한다.

    경로는 정확히 같을 때만 뺀다 — `/v1/healthz/x` 나 `/v1/healthzz` 는 리다이렉트된다.
    """

    def __init__(self, app: ASGIApp, exempt: Iterable[str]) -> None:
        self.app = app
        self.redirect = HTTPSRedirectMiddleware(app)
        self.exempt = frozenset(exempt)

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] == "http" and scope["path"] in self.exempt:
            await self.app(scope, receive, send)
            return
        await self.redirect(scope, receive, send)


def install(app: FastAPI, s: Settings) -> None:
    """`FORCE_HTTPS` 가 켜져 있으면 헬스체크를 뺀 HTTPS 리다이렉트를 건다."""
    if not s.force_https:
        return
    app.add_middleware(HTTPSRedirectExceptHealthMiddleware, exempt=exempt_paths(s))
