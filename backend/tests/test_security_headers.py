"""API 응답 보안 헤더(#2828) — 순수 단위 + API(DB 필요, 로컬 skip)."""
from __future__ import annotations

import pytest

from app.core.security_headers import (
    API_CONTENT_SECURITY_POLICY,
    HSTS_VALUE,
    security_headers_for,
)

# ---------- 순수 ----------


def test_api_paths_get_the_full_set():
    h = security_headers_for("/v1/users/me", hsts=False)
    assert h["X-Content-Type-Options"] == "nosniff"
    assert h["X-Frame-Options"] == "DENY"
    assert h["Referrer-Policy"] == "no-referrer"
    assert h["Content-Security-Policy"] == API_CONTENT_SECURITY_POLICY
    assert "Strict-Transport-Security" not in h


def test_api_csp_allows_nothing_and_no_framing():
    directives = {
        part.strip().split()[0]: part.strip().split()[1:]
        for part in API_CONTENT_SECURITY_POLICY.split(";")
        if part.strip()
    }
    assert directives["default-src"] == ["'none'"]
    assert directives["frame-ancestors"] == ["'none'"]
    assert directives["base-uri"] == ["'none'"]
    assert directives["form-action"] == ["'none'"]
    assert "'unsafe-inline'" not in API_CONTENT_SECURITY_POLICY


def test_hsts_only_when_requested():
    assert security_headers_for("/v1/ping", hsts=True)["Strict-Transport-Security"] == HSTS_VALUE
    assert "includeSubDomains" in HSTS_VALUE
    assert "max-age=63072000" in HSTS_VALUE


@pytest.mark.parametrize("path", ["/docs", "/docs/oauth2-redirect", "/redoc"])
def test_docs_pages_skip_csp_but_keep_other_headers(path):
    h = security_headers_for(path, hsts=False)
    assert "Content-Security-Policy" not in h
    assert h["X-Frame-Options"] == "DENY"
    assert h["X-Content-Type-Options"] == "nosniff"


@pytest.mark.parametrize("path", ["/docsearch", "/v1/docs", "/redocs", "/openapi.json"])
def test_lookalike_paths_still_get_csp(path):
    assert "Content-Security-Policy" in security_headers_for(path, hsts=False)


# ---------- API(DB) ----------


def test_api_response_carries_csp(client):
    r = client.get("/v1/ping")
    assert r.status_code == 200
    assert r.headers.get("Content-Security-Policy") == API_CONTENT_SECURITY_POLICY
    assert r.headers.get("X-Frame-Options") == "DENY"


def test_error_response_carries_csp(client):
    r = client.post("/v1/auth/refresh", json={"refresh_token": "not-a-token"})
    assert r.status_code == 401
    assert r.headers.get("Content-Security-Policy") == API_CONTENT_SECURITY_POLICY
    assert r.headers.get("X-Content-Type-Options") == "nosniff"


def test_docs_page_still_renders_without_csp(client):
    r = client.get("/docs")
    assert r.status_code == 200
    assert "Content-Security-Policy" not in r.headers
