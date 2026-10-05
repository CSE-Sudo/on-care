"""애플 로그인 제거 (#3218).

Sign in with Apple 은 유료 Apple Developer Program 이 있어야 쓸 수 있는데, 팀이 이
계정을 쓰지 않기로 해 애플 로그인을 제공하지 않는다. 검증기(#458)를 지웠으므로
`apple` 은 다른 모르는 provider 와 똑같이 취급돼야 한다 — 새 분기를 두지 않고
팩토리의 `ValueError` → 엔드포인트의 400 규칙을 그대로 탄다.

설정 표면(`APPLE_CLIENT_IDS`·`AppleClientIds`)도 함께 지웠다. 쓰지 않는 값이
환경 예시·배포 템플릿에 남아 있으면 운영자가 채워야 할 값으로 오해한다.
"""
from __future__ import annotations

from pathlib import Path

import pytest
from sqlalchemy import func, select

from app.core import startup_checks
from app.core.config import Settings
from app.services.social import factory
from app.services.social.factory import get_verifier

BACKEND_DIR = Path(__file__).resolve().parents[1]
TEMPLATE = BACKEND_DIR.parent / "infra" / "backend-service.yml"

UNSUPPORTED_DETAIL = "지원하지 않는 소셜 로그인입니다."


# ── 팩토리 ────────────────────────────────────────────────────────


@pytest.mark.parametrize("provider", ["apple", "APPLE", "Apple"])
def test_factory_rejects_apple_like_any_unknown_provider(provider):
    with pytest.raises(ValueError):
        get_verifier(provider)


def test_factory_registers_only_the_offered_providers():
    assert set(factory._VERIFIERS) == {"kakao", "google", "naver"}


def test_apple_verifier_module_is_gone():
    with pytest.raises(ModuleNotFoundError):
        __import__("app.services.social.apple")


# ── API ──────────────────────────────────────────────────────────


@pytest.mark.parametrize("provider", ["apple", "APPLE"])
def test_api_apple_answers_400_unsupported(client, provider):
    r = client.post(f"/v1/auth/social/{provider}", json={"token": "any"})
    assert r.status_code == 400, r.text
    assert r.json()["detail"] == UNSUPPORTED_DETAIL


def test_api_apple_matches_an_unknown_provider(client):
    """응답만 보고 apple 이 한때 지원됐는지 알 수 없다 — 모르는 provider 와 같다."""
    apple = client.post("/v1/auth/social/apple", json={"token": "x"})
    unknown = client.post("/v1/auth/social/myspace", json={"token": "x"})
    assert apple.status_code == unknown.status_code == 400
    assert apple.json() == unknown.json()


def test_api_apple_creates_nothing(client, db_session):
    from app.models.models import SocialAccount, User

    db_session.expire_all()
    accounts = db_session.scalar(select(func.count()).select_from(SocialAccount))
    users = db_session.scalar(select(func.count()).select_from(User))

    r = client.post("/v1/auth/social/apple", json={"token": "header.payload.sig"})

    assert r.status_code == 400, r.text
    db_session.expire_all()
    assert db_session.scalar(select(func.count()).select_from(SocialAccount)) == accounts
    assert db_session.scalar(select(func.count()).select_from(User)) == users


# ── 설정·기동 점검 ────────────────────────────────────────────────


def test_settings_have_no_apple_fields():
    settings = Settings(_env_file=None)
    assert not hasattr(settings, "apple_client_ids")
    assert not hasattr(settings, "apple_client_id_list")
    assert "apple_client_ids" not in Settings.model_fields


def test_leftover_apple_env_is_ignored(monkeypatch):
    """이미 배포 환경에 남아 있는 APPLE_CLIENT_IDS 가 기동을 막지 않는다(extra=ignore)."""
    monkeypatch.setenv("APPLE_CLIENT_IDS", "com.example.oncare")
    settings = Settings(_env_file=None)
    assert not hasattr(settings, "apple_client_ids")


def test_startup_check_no_longer_mentions_apple():
    settings = Settings(_env_file=None)
    missing = startup_checks.unconfigured_social_providers(settings)
    assert not any("apple" in item.lower() for item in missing)
    social = [w for w in startup_checks.check(settings) if "소셜 로그인" in w]
    assert all("APPLE" not in w for w in social)


def test_startup_is_quiet_with_only_google_and_kakao_configured():
    settings = Settings(_env_file=None, google_client_ids="g.test", kakao_app_id="1")
    assert startup_checks.unconfigured_social_providers(settings) == []


# ── 환경 예시·배포 템플릿 ─────────────────────────────────────────


@pytest.mark.parametrize("name", [".env.example", ".env.aws.example"])
def test_env_examples_have_no_apple_key(name):
    text = (BACKEND_DIR / name).read_text(encoding="utf-8")
    assert "APPLE_CLIENT_IDS" not in text
    assert "AppleClientIds" not in text


@pytest.mark.skipif(not TEMPLATE.exists(), reason="infra 가 없는 체크아웃")
def test_deploy_template_has_no_apple_parameter():
    text = TEMPLATE.read_text(encoding="utf-8")
    assert "AppleClientIds" not in text
    assert "HasAppleClientIds" not in text
    assert "APPLE_CLIENT_IDS" not in text
