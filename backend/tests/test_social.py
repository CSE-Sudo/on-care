"""소셜 로그인 — 팩토리(순수) + 엔드포인트(DB, verifier 모킹)."""
from __future__ import annotations

from uuid import uuid4

import pytest

from app.services.social.base import SocialIdentity
from app.services.social.factory import get_verifier
from app.services.social.kakao import KakaoVerifier


def test_factory_returns_provider_verifier():
    assert isinstance(get_verifier("kakao"), KakaoVerifier)
    assert get_verifier("GOOGLE").provider == "google"


def test_factory_unknown_provider_raises():
    with pytest.raises(ValueError):
        get_verifier("myspace")


def test_social_login_creates_then_reuses_user(client, monkeypatch):
    import app.api.v1.social as social_mod

    email = f"soc-{uuid4().hex[:8]}@oncare.com"
    identity = SocialIdentity(
        provider="kakao",
        provider_user_id=f"kakao-{uuid4().hex[:8]}",
        email=email,
        name="소셜유저",
        email_verified=True,
    )

    class _FakeVerifier:
        async def verify(self, token):  # noqa: ARG002
            return identity

    monkeypatch.setattr(social_mod, "get_verifier", lambda provider: _FakeVerifier())

    r = client.post("/v1/auth/social/kakao", json={"token": "any"})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["access_token"] and body["refresh_token"]

    me = client.get("/v1/users/me", headers={"Authorization": f"Bearer {body['access_token']}"})
    assert me.status_code == 200
    assert me.json()["email"] == email
    uid = me.json()["id"]

    # 같은 소셜 신원으로 다시 로그인 → 같은 사용자
    r2 = client.post("/v1/auth/social/kakao", json={"token": "any"})
    me2 = client.get("/v1/users/me", headers={"Authorization": f"Bearer {r2.json()['access_token']}"})
    assert me2.json()["id"] == uid


def test_social_login_unsupported_provider_400(client):
    r = client.post("/v1/auth/social/myspace", json={"token": "x"})
    assert r.status_code == 400
