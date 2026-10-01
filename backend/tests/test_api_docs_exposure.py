"""운영 환경 API 문서 노출 차단 — /docs·/redoc·/openapi.json. (#2834)

문서는 엔드포인트 전체 목록·요청 스키마·docstring 의 내부 설계 설명을 인증 없이
보여 준다. 운영(ENV=prod)은 기본으로 닫고, 그 밖은 열며, `EXPOSE_API_DOCS` 로
명시하면 그 값을 따른다.

- 설정·경로 계산은 DB 없이 돈다.
- 앱 단위 검사는 같은 설정으로 만든 작은 FastAPI 앱에 실제 라우터를 붙여 본다
  (lifespan 을 돌리지 않으므로 DB 가 필요 없다).
"""
from __future__ import annotations

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.core.config import Settings

DOC_PATHS = ("/docs", "/redoc", "/openapi.json")
_REAL_DOC_PATHS = {*DOC_PATHS, "/docs/oauth2-redirect"}


def _settings(**overrides) -> Settings:
    base = {"env": "dev"}
    base.update(overrides)
    return Settings(_env_file=None, **base)


def _prod(**overrides) -> Settings:
    # 운영 설정 검사(JWT 기본값·CORS 와일드카드 거부 등)를 통과하는 최소값.
    return _settings(
        env="prod",
        jwt_secret="x" * 40,
        cors_allow_origins="https://oncare.example",
        seed_demo_data=False,
        auto_create_tables=False,
        **overrides,
    )


# ---- 설정 (DB 불필요) ----


def test_docs_are_open_outside_prod_by_default():
    assert _settings().expose_api_docs is None
    assert _settings().api_docs_enabled is True
    assert _settings(env="staging").api_docs_enabled is True


def test_docs_are_closed_in_prod_by_default():
    assert _prod().api_docs_enabled is False


@pytest.mark.parametrize(("env", "flag", "expected"), [
    ("prod", True, True),
    ("prod", False, False),
    ("dev", False, False),
    ("dev", True, True),
])
def test_explicit_flag_wins(env, flag, expected):
    assert _settings(env=env, expose_api_docs=flag).api_docs_enabled is expected


def test_flag_is_read_from_the_environment(monkeypatch):
    monkeypatch.setenv("ENV", "dev")
    monkeypatch.setenv("EXPOSE_API_DOCS", "false")
    assert Settings(_env_file=None).api_docs_enabled is False

    monkeypatch.setenv("EXPOSE_API_DOCS", "true")
    assert Settings(_env_file=None).api_docs_enabled is True


# ---- 문서 경로 계산 (DB 불필요) ----


def test_urls_are_none_when_closed():
    from app.main import api_docs_urls

    assert api_docs_urls(_prod()) == {
        "docs_url": None,
        "redoc_url": None,
        "openapi_url": None,
    }


def test_urls_are_the_defaults_when_open():
    from app.main import api_docs_urls

    assert api_docs_urls(_settings()) == {
        "docs_url": "/docs",
        "redoc_url": "/redoc",
        "openapi_url": "/openapi.json",
    }


def test_the_running_app_follows_its_settings():
    """모듈의 app 이 같은 계산으로 만들어졌는지 — 문서 경로를 따로 하드코딩하지 않는다."""
    from app.main import api_docs_urls, app, settings

    urls = api_docs_urls(settings)
    assert app.docs_url == urls["docs_url"]
    assert app.redoc_url == urls["redoc_url"]
    assert app.openapi_url == urls["openapi_url"]


# ---- 앱 단위 (DB 불필요) ----


def _app_with(s: Settings) -> TestClient:
    """주 앱과 같은 방식으로 문서 경로를 정한 앱에 실제 v1 라우트를 붙인다."""
    from app.main import api_docs_urls
    from app.main import app as real_app

    probe = FastAPI(title="probe", **api_docs_urls(s))
    # 주 앱이 만든 문서 경로는 빼고 API 라우트만 옮긴다(CI 는 dev 라 문서가 열려 있다).
    probe.router.routes.extend(
        r for r in real_app.router.routes if getattr(r, "path", None) not in _REAL_DOC_PATHS
    )
    return TestClient(probe)


@pytest.mark.parametrize("path", DOC_PATHS)
def test_prod_returns_404_for_docs(path):
    client = _app_with(_prod())
    assert client.get(path).status_code == 404


@pytest.mark.parametrize("path", DOC_PATHS)
def test_dev_serves_docs(path):
    client = _app_with(_settings())
    assert client.get(path).status_code == 200


@pytest.mark.parametrize("path", DOC_PATHS)
def test_prod_with_explicit_flag_serves_docs(path):
    client = _app_with(_prod(expose_api_docs=True))
    assert client.get(path).status_code == 200


def test_openapi_lists_the_api_when_open():
    body = _app_with(_settings()).get("/openapi.json").json()
    assert any(p.startswith("/v1/") for p in body["paths"])


def test_closing_docs_does_not_hide_the_api():
    """문서만 닫힌다 — 헬스 체크(DB 무관) 같은 일반 라우트는 그대로다."""
    from app.main import settings

    client = _app_with(_prod())
    r = client.get(f"{settings.api_v1_prefix}/healthz")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"
