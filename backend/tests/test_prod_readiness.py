"""운영 배포 안전장치 — 데모 폴백 기본값·/healthz 설정 노출. (#2821)

백엔드의 안전장치는 대부분 `ENV=prod` 일 때만 켜진다. 그 값을 빠뜨린 채 뜬
서버가 로그인 없는 요청을 데모 회원으로 처리하지 않는지, 배포 직후 어떤 설정으로
떴는지 `/healthz` 로 읽을 수 있는지를 본다.

DB 가 필요하므로 로컬에서는 skip 되고 CI(Postgres) 에서 실행된다.
"""
from __future__ import annotations

import pytest

from app.core.config import get_settings


@pytest.fixture
def fallback_off(monkeypatch):
    """환경변수 없이 뜬 서버 — 설정 기본값(데모 폴백 꺼짐)."""
    monkeypatch.setattr(get_settings(), "allow_demo_fallback", False)


@pytest.mark.parametrize("path", ["/v1/users/me", "/v1/users/me/health"])
def test_member_api_without_a_token_is_401_by_default(client, fallback_off, path):
    response = client.get(path)
    assert response.status_code == 401
    assert response.headers.get("www-authenticate") == "Bearer"


def test_an_invalid_token_is_401_by_default(client, fallback_off):
    response = client.get(
        "/v1/users/me", headers={"Authorization": "Bearer not-a-real-token"}
    )
    assert response.status_code == 401


def test_local_development_still_falls_back_when_enabled(client, monkeypatch):
    """로컬 개발(.env.example 이 켬)은 지금처럼 데모 회원으로 화면이 뜬다."""
    monkeypatch.setattr(get_settings(), "allow_demo_fallback", True)
    response = client.get("/v1/users/me")
    assert response.status_code == 200
    assert response.json()["id"] == "user-7d4e9a2c5f18"


def test_healthz_reports_the_running_configuration(client, fallback_off, monkeypatch):
    settings = get_settings()
    monkeypatch.setattr(settings, "env", " Staging ")
    monkeypatch.setattr(settings, "seed_demo_data", False)
    monkeypatch.setattr(settings, "attachment_storage", "local")

    body = client.get("/v1/healthz").json()

    assert body["status"] == "ok"
    assert body["env"] == "staging"
    assert body["demo_fallback"] is False
    assert body["demo_seed"] is False
    assert body["attachment_storage"] == "local"


def test_healthz_shows_when_demo_fallback_is_on(client, monkeypatch):
    settings = get_settings()
    monkeypatch.setattr(settings, "env", "dev")
    monkeypatch.setattr(settings, "allow_demo_fallback", True)

    body = client.get("/v1/healthz").json()

    assert body["env"] == "dev"
    assert body["demo_fallback"] is True


def test_healthz_reports_prod_as_never_falling_back(client, monkeypatch):
    """운영에서는 ALLOW_DEMO_FALLBACK 을 켜도 폴백이 꺼져 있다고 보고한다."""
    settings = get_settings()
    monkeypatch.setattr(settings, "env", "prod")
    monkeypatch.setattr(settings, "allow_demo_fallback", True)

    body = client.get("/v1/healthz").json()

    assert body["env"] == "prod"
    assert body["demo_fallback"] is False


def test_healthz_does_not_leak_secrets(client):
    body = client.get("/v1/healthz").json()
    assert set(body) == {
        "status",
        "backend",
        "env",
        "demo_fallback",
        "demo_seed",
        "attachment_storage",
        "commit_sha",
    }
