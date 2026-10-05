"""시스템 엔드포인트 스모크 — DB 필요(로컬 skip, CI 실행)."""
from __future__ import annotations

from app.core.config import get_settings

SAMPLE_SHA = "0123456789abcdef0123456789abcdef01234567"


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
    assert "commit_sha" in body


def test_version_reports_configured_commit_sha(client, monkeypatch):
    # 배포 이미지는 GIT_SHA 를 환경변수로 갖는다(#3029).
    monkeypatch.setattr(get_settings(), "git_sha", SAMPLE_SHA)
    body = client.get("/v1/version").json()
    assert body["commit_sha"] == SAMPLE_SHA


def test_version_commit_sha_is_unknown_without_build_arg(client, monkeypatch):
    monkeypatch.setattr(get_settings(), "git_sha", "")
    assert client.get("/v1/version").json()["commit_sha"] == "unknown"


def test_healthz_reports_commit_sha_and_storage(client, monkeypatch):
    monkeypatch.setattr(get_settings(), "git_sha", SAMPLE_SHA)
    body = client.get("/v1/healthz").json()
    assert body["commit_sha"] == SAMPLE_SHA
    # 배포 워크플로가 운영에서 s3 인지 본다(#3029). 테스트 서버는 버킷이 없어 local.
    assert body["attachment_storage"] in {"local", "s3", "misconfigured"}


def test_version_does_not_expose_other_build_details(client):
    assert set(client.get("/v1/version").json()) == {
        "api_version",
        "app_version",
        "min_app_version",
        "commit_sha",
    }


def test_version_min_app_version_null_when_unset(client, monkeypatch):
    """최소 지원 버전을 설정하지 않으면 `null` — 회원 앱은 검사하지 않는다(#3045)."""
    monkeypatch.setattr(get_settings(), "min_member_app_version", "")
    body = client.get("/v1/version").json()
    assert "min_app_version" in body
    assert body["min_app_version"] is None
    # 기존 키는 그대로 둔다(하위 호환).
    assert body["api_version"] == "v1"
    assert body["app_version"] == get_settings().app_version


def test_version_min_app_version_from_settings(client, monkeypatch):
    monkeypatch.setattr(get_settings(), "min_member_app_version", "1.2.0")
    body = client.get("/v1/version").json()
    assert body["min_app_version"] == "1.2.0"


def test_version_needs_no_auth(client):
    """로그인 전에 부르므로 토큰 없이 200."""
    r = client.get("/v1/version", headers={"Authorization": ""})
    assert r.status_code == 200
