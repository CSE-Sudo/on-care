"""HTTPS 강제에서 헬스체크 경로만 리다이렉트하지 않는다(#3130) — DB 불필요.

로드 밸런서 헬스체크는 컨테이너에 평문 HTTP 로 직접 들어오고 `X-Forwarded-Proto` 를
붙이지 않는다. `FORCE_HTTPS=true` 에서 `/v1/healthz` 가 307 을 돌려주면 대상이 unhealthy 로
판정되어 ECS 가 태스크를 계속 갈아 치운다. 여기서는 실제 시스템 라우터를 `http://`
TestClient 로 불러 헬스체크는 200(또는 readyz 의 정상 상태 코드), 나머지 경로는 지금처럼
https 리다이렉트임을 본다. DB 는 가짜 세션으로 바꾼다.
"""
from __future__ import annotations

import inspect
import re
from pathlib import Path

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from starlette.middleware.httpsredirect import HTTPSRedirectMiddleware
from uvicorn.middleware.proxy_headers import ProxyHeadersMiddleware

from app.api.v1 import system
from app.core import https_redirect
from app.core.config import Settings
from app.core.https_redirect import (
    HEALTH_CHECK_PATHS,
    HTTPSRedirectExceptHealthMiddleware,
    exempt_paths,
)
from app.db.session import get_db

SERVICE_TEMPLATE = Path(__file__).resolve().parents[2] / "infra" / "backend-service.yml"


class _FakeSession:
    """readyz 가 부르는 `execute`·`rollback` 만 흉내 낸다."""

    def __init__(self, fail: bool = False) -> None:
        self.fail = fail
        self.rolled_back = False

    def execute(self, *_args, **_kwargs) -> None:
        if self.fail:
            raise RuntimeError("db down")

    def rollback(self) -> None:
        self.rolled_back = True


def _settings(**overrides) -> Settings:
    return Settings(_env_file=None, **overrides)


def _app(*, force_https: bool = True, db_fails: bool = False, prefix: str = "/v1") -> FastAPI:
    """main.py 와 같은 방식(install)으로 리다이렉트를 건 작은 앱."""
    s = _settings(force_https=force_https, api_v1_prefix=prefix)
    app = FastAPI()
    app.include_router(system.router, prefix=s.api_v1_prefix)

    @app.post(f"{s.api_v1_prefix}/auth/login")
    def login() -> dict[str, str]:
        return {"status": "login"}

    @app.get(f"{s.api_v1_prefix}/healthz/extra")
    def healthz_extra() -> dict[str, str]:
        return {"status": "extra"}

    app.dependency_overrides[get_db] = lambda: _FakeSession(fail=db_fails)
    https_redirect.install(app, s)
    return app


def _http_client(app) -> TestClient:
    return TestClient(app, base_url="http://testserver", follow_redirects=False)


# ---------- 예외 목록 ----------


def test_health_check_paths_are_the_two_probes():
    assert HEALTH_CHECK_PATHS == ("/healthz", "/readyz")


def test_exempt_paths_follow_the_api_prefix():
    assert exempt_paths(_settings()) == frozenset({"/v1/healthz", "/v1/readyz"})
    assert exempt_paths(_settings(api_v1_prefix="/api/v2/")) == frozenset(
        {"/api/v2/healthz", "/api/v2/readyz"}
    )


def test_load_balancer_health_check_path_is_exempt():
    # 템플릿의 대상 그룹 헬스체크 경로가 예외 목록에 있어야 307 을 받지 않는다.
    text = SERVICE_TEMPLATE.read_text(encoding="utf-8")
    match = re.search(r"^\s*HealthCheckPath:\s*(\S+)\s*$", text, re.MULTILINE)
    assert match, "infra/backend-service.yml 에 HealthCheckPath 가 없다"
    assert match.group(1) in exempt_paths(_settings())


# ---------- FORCE_HTTPS=true, http:// 요청 ----------


@pytest.mark.parametrize("path", ["/v1/healthz", "/v1/readyz"])
def test_health_checks_answer_over_plain_http(path):
    with _http_client(_app()) as client:
        response = client.get(path)
    assert response.status_code == 200
    assert "location" not in response.headers


def test_healthz_body_is_unchanged_over_plain_http():
    with _http_client(_app()) as client:
        body = client.get("/v1/healthz").json()
    assert body["status"] == "ok"
    assert body["backend"] == "fastapi"


def test_readyz_reports_ready_over_plain_http():
    with _http_client(_app()) as client:
        assert client.get("/v1/readyz").json() == {"status": "ready"}


def test_readyz_failure_is_503_not_a_redirect():
    # DB 가 죽었을 때도 리다이렉트로 가리지 않고 503 을 그대로 보인다.
    with _http_client(_app(db_fails=True)) as client:
        response = client.get("/v1/readyz")
    assert response.status_code == 503
    assert "location" not in response.headers


def test_head_health_check_is_not_redirected():
    with _http_client(_app()) as client:
        response = client.head("/v1/healthz")
    assert response.status_code != 307
    assert "location" not in response.headers


@pytest.mark.parametrize(
    ("method", "path", "query"),
    [
        ("post", "/v1/auth/login", ""),
        ("get", "/v1/ping", ""),
        ("get", "/v1/version", "?x=1"),
        # 정확히 같은 경로만 뺀다.
        ("get", "/v1/healthz/extra", ""),
        ("get", "/v1/healthzz", ""),
        ("get", "/healthz", ""),
    ],
)
def test_other_paths_still_redirect_to_https(method, path, query):
    with _http_client(_app()) as client:
        response = getattr(client, method)(f"{path}{query}")
    assert response.status_code == 307
    assert response.headers["location"] == f"https://testserver{path}{query}"


def test_custom_prefix_moves_the_exemption():
    with _http_client(_app(prefix="/api")) as client:
        assert client.get("/api/healthz").status_code == 200
        assert client.get("/api/readyz").status_code == 200
        assert client.get("/api/ping").status_code == 307


# ---------- 프록시가 https 라고 알려 준 요청(기존 동작) ----------


def test_forwarded_https_request_is_not_redirected():
    # uvicorn --proxy-headers 와 같은 처리: X-Forwarded-Proto 를 읽어 scheme 을 https 로 바꾼다.
    proxied = ProxyHeadersMiddleware(_app(), trusted_hosts="*")
    with _http_client(proxied) as client:
        login = client.post("/v1/auth/login", headers={"X-Forwarded-Proto": "https"})
        health = client.get("/v1/healthz", headers={"X-Forwarded-Proto": "https"})
    assert login.status_code == 200
    assert login.json() == {"status": "login"}
    assert health.status_code == 200


def test_forwarded_http_request_still_redirects():
    proxied = ProxyHeadersMiddleware(_app(), trusted_hosts="*")
    with _http_client(proxied) as client:
        response = client.post("/v1/auth/login", headers={"X-Forwarded-Proto": "http"})
    assert response.status_code == 307
    assert response.headers["location"].startswith("https://")


def test_https_base_url_is_not_redirected():
    with TestClient(_app(), base_url="https://testserver", follow_redirects=False) as client:
        assert client.post("/v1/auth/login").status_code == 200
        assert client.get("/v1/healthz").status_code == 200


# ---------- FORCE_HTTPS=false ----------


def test_nothing_is_installed_without_force_https():
    app = _app(force_https=False)
    classes = {m.cls for m in app.user_middleware}
    assert HTTPSRedirectExceptHealthMiddleware not in classes
    assert HTTPSRedirectMiddleware not in classes


@pytest.mark.parametrize("path", ["/v1/healthz", "/v1/readyz", "/v1/ping"])
def test_plain_http_is_served_without_force_https(path):
    with _http_client(_app(force_https=False)) as client:
        assert client.get(path).status_code == 200
    with _http_client(_app(force_https=False)) as client:
        assert client.post("/v1/auth/login").status_code == 200


def test_force_https_installs_the_health_aware_middleware_only():
    app = _app(force_https=True)
    classes = [m.cls for m in app.user_middleware]
    assert classes.count(HTTPSRedirectExceptHealthMiddleware) == 1
    # 모든 경로를 리다이렉트하는 원래 미들웨어를 따로 걸지 않는다.
    assert HTTPSRedirectMiddleware not in classes


# ---------- main.py 연결 ----------


def test_main_uses_the_health_aware_redirect():
    import app.main as main

    source = inspect.getsource(main)
    assert "https_redirect.install(app, settings)" in source
    assert "HTTPSRedirectMiddleware" not in source
    # 테스트 설정(force_https=False)에서는 어떤 리다이렉트도 걸리지 않는다.
    classes = {m.cls for m in main.app.user_middleware}
    assert HTTPSRedirectMiddleware not in classes
    if not main.settings.force_https:
        assert HTTPSRedirectExceptHealthMiddleware not in classes
