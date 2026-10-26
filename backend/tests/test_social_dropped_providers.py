"""네이버 로그인 제거 (#3218) — 애플은 #3499 에서 다시 제공한다.

#3218 에서 네이버·애플 로그인을 함께 접었다. 애플은 유료 Apple Developer Program 계정이
생기고 App Store 심사(Guideline 4.8)가 요구해 #3499 에서 되살렸다 — 그 검증은
`test_social_apple.py` 가 본다. 네이버는 여전히 제공하지 않으므로 다른 모르는 provider 와
똑같이 취급돼야 한다 — 새 분기를 두지 않고 팩토리의 `ValueError` → 엔드포인트의 400
규칙을 그대로 탄다. 네이버가 쓰던 501(`아직 지원하지 않는…`)은 "지원 예정"이라는 뜻이라
더는 맞지 않는다.
"""
from __future__ import annotations

import pytest
from sqlalchemy import func, select

from app.core import startup_checks
from app.core.config import Settings
from app.services.social import factory
from app.services.social.factory import get_verifier


UNSUPPORTED_DETAIL = "지원하지 않는 소셜 로그인이에요."
DROPPED = ("naver",)


# ── 팩토리 ────────────────────────────────────────────────────────


@pytest.mark.parametrize("provider", ["naver", "NAVER", "Naver"])
def test_factory_rejects_dropped_providers_like_any_unknown(provider):
    with pytest.raises(ValueError):
        get_verifier(provider)


def test_factory_registers_only_the_offered_providers():
    assert set(factory._VERIFIERS) == {"kakao", "google", "apple"}


@pytest.mark.parametrize("module", ["app.services.social.naver"])
def test_dropped_verifier_modules_are_gone(module):
    with pytest.raises(ModuleNotFoundError):
        __import__(module)


# ── API ──────────────────────────────────────────────────────────


@pytest.mark.parametrize("provider", ["naver", "NAVER"])
def test_api_dropped_provider_answers_400_unsupported(client, provider):
    r = client.post(f"/v1/auth/social/{provider}", json={"token": "any"})
    assert r.status_code == 400, r.text
    assert r.json()["detail"] == UNSUPPORTED_DETAIL


@pytest.mark.parametrize("provider", DROPPED)
def test_api_dropped_provider_matches_an_unknown_provider(client, provider):
    """응답만 보고 한때 지원(또는 예고)됐는지 알 수 없다 — 모르는 provider 와 같다."""
    dropped = client.post(f"/v1/auth/social/{provider}", json={"token": "x"})
    unknown = client.post("/v1/auth/social/myspace", json={"token": "x"})
    assert dropped.status_code == unknown.status_code == 400
    assert dropped.json() == unknown.json()


@pytest.mark.parametrize("provider", DROPPED)
def test_api_dropped_provider_is_not_501_anymore(client, provider):
    """네이버의 501 '아직 지원하지 않는'(#3035)은 지원 예정이라는 뜻이라 쓰지 않는다."""
    r = client.post(f"/v1/auth/social/{provider}", json={"token": "x"})
    assert r.status_code != 501
    assert "아직" not in r.json()["detail"]


@pytest.mark.parametrize("provider", DROPPED)
def test_api_dropped_provider_creates_nothing(client, db_session, provider):
    from app.models.models import SocialAccount, User

    db_session.expire_all()
    accounts = db_session.scalar(select(func.count()).select_from(SocialAccount))
    users = db_session.scalar(select(func.count()).select_from(User))

    r = client.post(f"/v1/auth/social/{provider}", json={"token": "header.payload.sig"})

    assert r.status_code == 400, r.text
    db_session.expire_all()
    assert db_session.scalar(select(func.count()).select_from(SocialAccount)) == accounts
    assert db_session.scalar(select(func.count()).select_from(User)) == users


# ── 설정·기동 점검 ────────────────────────────────────────────────


def test_settings_have_no_dropped_provider_fields():
    assert not [name for name in Settings.model_fields if name.startswith(DROPPED)]


def test_startup_check_mentions_no_dropped_provider():
    settings = Settings(_env_file=None)
    for item in startup_checks.unconfigured_social_providers(settings):
        assert not item.lower().startswith(DROPPED), item


def test_startup_is_quiet_with_the_offered_providers_configured():
    settings = Settings(
        _env_file=None, google_client_ids="g.test", kakao_app_id="1",
        apple_client_ids="com.example.oncare",
    )
    assert startup_checks.unconfigured_social_providers(settings) == []
