"""시스템 엔드포인트 스모크 — DB 필요(로컬 skip, CI 실행)."""
from __future__ import annotations


def test_ping(client):
    r = client.get("/v1/ping")
    assert r.status_code == 200


def test_healthz(client):
    r = client.get("/v1/healthz")
    assert r.status_code == 200


def test_version(client):
    r = client.get("/v1/version")
    assert r.status_code == 200
    body = r.json()
    assert body["api_version"] == "v1"
    assert "app_version" in body


def test_version_min_app_version_null_when_unset(client, monkeypatch):
    """최소 지원 버전을 설정하지 않으면 `null` — 회원 앱은 검사하지 않는다(#3045)."""
    from app.api.v1 import system

    monkeypatch.setattr(system.settings, "min_member_app_version", "")
    body = client.get("/v1/version").json()
    assert "min_app_version" in body
    assert body["min_app_version"] is None
    # 기존 키는 그대로 둔다(하위 호환).
    assert body["api_version"] == "v1"
    assert body["app_version"] == system.settings.app_version


def test_version_min_app_version_from_settings(client, monkeypatch):
    from app.api.v1 import system

    monkeypatch.setattr(system.settings, "min_member_app_version", "1.2.0")
    body = client.get("/v1/version").json()
    assert body["min_app_version"] == "1.2.0"


def test_version_needs_no_auth(client):
    """로그인 전에 부르므로 토큰 없이 200."""
    r = client.get("/v1/version", headers={"Authorization": ""})
    assert r.status_code == 200
