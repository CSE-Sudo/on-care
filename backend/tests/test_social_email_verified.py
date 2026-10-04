"""소셜 로그인 이메일 자동 연결은 provider 가 확인한 이메일만 (#1551).

provider 가 준 이메일과 같은 기존 계정에 확인 없이 소셜 계정을 연결하면, provider
계정에 남의 주소를 적어 넣는 것만으로 그 사람의 On-Care 계정에 로그인된다. 여기서 본다.

- adapter 가 provider 별 검증 플래그를 `SocialIdentity.email_verified` 로 옮기는지.
  - google: tokeninfo `email_verified`(문자열 "true"/"false", bool 도 받는다)
  - kakao: `kakao_account.is_email_valid` 와 `is_email_verified` 가 **둘 다** 참
  - naver: 공식 검증 플래그가 없어 늘 거짓
  - apple: `email_verified`(문자열·bool)
- 확인되지 않은 이메일은 기존 계정에 연결하지 않고, 새 계정의 이메일로도 쓰지 않는다
  (`{provider}_{id}@social.oncare` 대체 이메일).
- 확인된 이메일은 지금처럼 같은 이메일 계정에 연결된다.

단위 테스트는 DB 가 필요 없다. provider HTTP 는 `httpx.MockTransport` 로 흉내 낸다.
"""
from __future__ import annotations

import asyncio
from datetime import datetime, timedelta, timezone
from uuid import uuid4

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from sqlalchemy import func, select

from app.models.models import SocialAccount, User
from app.services.social import apple as apple_mod
from app.services.social.apple import AppleVerifier
from app.services.social.base import SocialIdentity, SocialProviderResponseError
from app.services.social.google import GoogleVerifier
from app.services.social.kakao import KakaoVerifier
from app.services.social.naver import NaverVerifier
from tests.social_provider_fakes import (
    GOOGLE_CLAIMS,
    SECRET_TOKEN,
    kakao_token_info,
    respond_json,
    respond_kakao,
    use_app_ids,
)


@pytest.fixture(autouse=True)
def _app_ids(monkeypatch):
    use_app_ids(monkeypatch)


def _google_body(**overrides) -> dict:
    body = {**GOOGLE_CLAIMS, "sub": "g-1551", "email": "g1551@oncare.com", "name": "구글"}
    body.update(overrides)
    return {k: v for k, v in body.items() if v is not None}


def _kakao_body(uid: int, **account) -> dict:
    return {
        "id": uid,
        "kakao_account": {"email": "k1551@oncare.com", "profile": {"nickname": "카카오"}, **account},
    }


# ── google ──────────────────────────────────────────────────────────


@pytest.mark.parametrize(
    "flag, expected",
    [
        ("true", True),
        ("True", True),
        (True, True),
        ("false", False),
        (False, False),
        (None, False),  # 필드 없음
    ],
)
def test_google_reads_email_verified(monkeypatch, flag, expected):
    respond_json(monkeypatch, _google_body(email_verified=flag))

    identity = asyncio.run(GoogleVerifier().verify(SECRET_TOKEN))

    assert identity.email == "g1551@oncare.com"
    assert identity.email_verified is expected


def test_google_verified_flag_without_email_is_not_verified(monkeypatch):
    respond_json(monkeypatch, _google_body(email=None, email_verified="true"))

    identity = asyncio.run(GoogleVerifier().verify(SECRET_TOKEN))

    assert identity.email == ""
    assert identity.email_verified is False


@pytest.mark.parametrize("flag", [1, "yes", ["true"], {"v": True}])
def test_google_malformed_email_verified_is_bad_response(monkeypatch, flag):
    """참으로 넘겨짚지 않는다 — 약속과 다른 형식은 다른 필드처럼 형식 이상(502)."""
    respond_json(monkeypatch, _google_body(email_verified=flag))

    with pytest.raises(SocialProviderResponseError):
        asyncio.run(GoogleVerifier().verify(SECRET_TOKEN))


# ── kakao ───────────────────────────────────────────────────────────


@pytest.mark.parametrize(
    "valid, verified, expected",
    [
        (True, True, True),
        (True, False, False),  # 인증하지 않은 이메일
        (False, True, False),  # 다른 카카오계정에 쓰여 만료된 이메일
        (False, False, False),
        (None, True, False),  # 필드 없음
        (True, None, False),
    ],
)
def test_kakao_needs_both_valid_and_verified(monkeypatch, valid, verified, expected):
    uid = 155101
    account = {}
    if valid is not None:
        account["is_email_valid"] = valid
    if verified is not None:
        account["is_email_verified"] = verified
    respond_kakao(monkeypatch, token_info=kakao_token_info(uid), user=_kakao_body(uid, **account))

    identity = asyncio.run(KakaoVerifier().verify(SECRET_TOKEN))

    assert identity.email == "k1551@oncare.com"
    assert identity.email_verified is expected


def test_kakao_malformed_flag_is_bad_response(monkeypatch):
    uid = 155102
    body = _kakao_body(uid, is_email_valid=True, is_email_verified=1)
    respond_kakao(monkeypatch, token_info=kakao_token_info(uid), user=body)

    with pytest.raises(SocialProviderResponseError):
        asyncio.run(KakaoVerifier().verify(SECRET_TOKEN))


# ── naver ───────────────────────────────────────────────────────────


@pytest.mark.parametrize("extra", [{}, {"email_verified": True}, {"is_email_verified": True}])
def test_naver_email_is_never_verified(monkeypatch, extra):
    """네이버 프로필에는 공식 검증 플래그가 없다. 비공식 필드가 와도 믿지 않는다."""
    respond_json(
        monkeypatch,
        {"resultcode": "00", "message": "success",
         "response": {"id": "n-1551", "email": "n1551@oncare.com", "name": "네이버", **extra}},
    )

    identity = asyncio.run(NaverVerifier().read_profile(SECRET_TOKEN))

    assert identity.email == "n1551@oncare.com"
    assert identity.email_verified is False


# ── apple ───────────────────────────────────────────────────────────


@pytest.fixture(scope="module")
def apple_key():
    return rsa.generate_private_key(public_exponent=65537, key_size=2048)


@pytest.fixture
def apple(monkeypatch, apple_key):
    """JWKS 대신 테스트 공개키로 검증한다(네트워크 없음)."""

    class _Key:
        key = apple_key.public_key()

    class _Client:
        def get_signing_key_from_jwt(self, token):
            return _Key()

    monkeypatch.setattr(apple_mod, "_allowed_audiences", lambda: ["com.oncare.app"])
    monkeypatch.setattr(apple_mod, "_jwk_client", lambda: _Client())

    def _verify(**claims) -> SocialIdentity:
        now = datetime.now(tz=timezone.utc)
        payload = {
            "iss": apple_mod.APPLE_ISSUER,
            "aud": "com.oncare.app",
            "sub": "001551.apple",
            "email": "a1551@privaterelay.appleid.com",
            "iat": now,
            "exp": now + timedelta(minutes=10),
        }
        payload.update(claims)
        payload = {k: v for k, v in payload.items() if v is not None}
        token = jwt.encode(payload, apple_key, algorithm="RS256", headers={"kid": "k1551"})
        return asyncio.run(AppleVerifier().verify(token))

    return _verify


@pytest.mark.parametrize(
    "flag, expected",
    [
        ("true", True),
        (True, True),
        ("false", False),
        (False, False),
        (None, False),
        (1, False),  # 서명된 토큰이라 막지는 않지만 참으로 넘겨짚지 않는다
    ],
)
def test_apple_reads_email_verified_string_or_bool(apple, flag, expected):
    identity = apple(email_verified=flag)

    assert identity.email == "a1551@privaterelay.appleid.com"
    assert identity.email_verified is expected


def test_apple_verified_flag_without_email_is_not_verified(apple):
    identity = apple(email=None, email_verified="true")

    assert identity.email == ""
    assert identity.email_verified is False


# ── API: 확인되지 않은 이메일은 기존 계정에 연결되지 않는다 ─────────────


def _existing_user(db) -> User:
    user = User(
        id=f"user-1551-{uuid4().hex[:8]}",
        email=f"owner-{uuid4().hex[:10]}@oncare.com",
        name="기존회원",
        hashed_password="x",
    )
    db.add(user)
    db.commit()
    return user


def _links(db, user_id: str) -> int:
    db.expire_all()
    return db.scalar(
        select(func.count()).select_from(SocialAccount).where(SocialAccount.user_id == user_id)
    )


def _me(client, token: str) -> dict:
    r = client.get("/v1/users/me", headers={"Authorization": f"Bearer {token}"})
    assert r.status_code == 200, r.text
    return r.json()


def _fake_identity(monkeypatch, identity: SocialIdentity) -> None:
    import app.api.v1.social as social_mod

    class _FakeVerifier:
        async def verify(self, token):
            return identity

    monkeypatch.setattr(social_mod, "get_verifier", lambda provider: _FakeVerifier())


@pytest.mark.parametrize("provider", ["google", "kakao", "naver", "apple"])
def test_unverified_email_does_not_link_existing_account(client, db_session, monkeypatch, provider):
    owner = _existing_user(db_session)
    uid = f"{provider}-{uuid4().hex[:10]}"
    _fake_identity(
        monkeypatch,
        SocialIdentity(provider=provider, provider_user_id=uid, email=owner.email.upper(), name="남"),
    )

    r = client.post(f"/v1/auth/social/{provider}", json={"token": "any"})

    assert r.status_code == 200, r.text
    me = _me(client, r.json()["access_token"])
    assert me["id"] != owner.id
    # 확인 안 된 주소를 새 계정에도 쓰지 않는다 — 대체 이메일
    assert me["email"] == f"{provider}_{uid}@social.oncare".lower()
    assert _links(db_session, owner.id) == 0

    # 다시 로그인해도 같은 새 계정(소셜 계정 연결로 찾는다), 기존 계정은 그대로
    again = client.post(f"/v1/auth/social/{provider}", json={"token": "any"})
    assert _me(client, again.json()["access_token"])["id"] == me["id"]
    assert _links(db_session, owner.id) == 0


def test_unverified_email_is_not_stored_on_new_account(client, db_session, monkeypatch):
    """아무도 쓰지 않는 주소여도 확인 안 됐으면 계정 이메일로 선점하지 않는다."""
    unclaimed = f"unclaimed-{uuid4().hex[:10]}@oncare.com"
    uid = f"kakao-{uuid4().hex[:10]}"
    _fake_identity(
        monkeypatch, SocialIdentity(provider="kakao", provider_user_id=uid, email=unclaimed)
    )

    r = client.post("/v1/auth/social/kakao", json={"token": "any"})

    assert r.status_code == 200, r.text
    assert _me(client, r.json()["access_token"])["email"] == f"kakao_{uid}@social.oncare"
    db_session.expire_all()
    assert db_session.scalar(select(User).where(func.lower(User.email) == unclaimed)) is None


@pytest.mark.parametrize("provider", ["google", "kakao", "apple"])
def test_verified_email_still_links_existing_account(client, db_session, monkeypatch, provider):
    owner = _existing_user(db_session)
    _fake_identity(
        monkeypatch,
        SocialIdentity(
            provider=provider,
            provider_user_id=f"{provider}-{uuid4().hex[:10]}",
            email=owner.email.upper(),
            email_verified=True,
        ),
    )

    r = client.post(f"/v1/auth/social/{provider}", json={"token": "any"})

    assert r.status_code == 200, r.text
    assert _me(client, r.json()["access_token"])["id"] == owner.id
    assert _links(db_session, owner.id) == 1


def test_api_kakao_unverified_email_through_adapter_does_not_link(client, db_session, monkeypatch):
    """adapter 부터 라우터까지: 카카오가 인증 안 됐다고 한 이메일은 연결하지 않는다."""
    owner = _existing_user(db_session)
    uid = int(uuid4().int % 10**10)
    user = _kakao_body(uid, is_email_valid=True, is_email_verified=False)
    user["kakao_account"]["email"] = owner.email
    respond_kakao(monkeypatch, token_info=kakao_token_info(uid), user=user)

    r = client.post("/v1/auth/social/kakao", json={"token": SECRET_TOKEN})

    assert r.status_code == 200, r.text
    assert _links(db_session, owner.id) == 0


def test_api_google_unverified_email_through_adapter_does_not_link(client, db_session, monkeypatch):
    owner = _existing_user(db_session)
    respond_json(
        monkeypatch,
        _google_body(sub=f"g-{uuid4().hex[:10]}", email=owner.email, email_verified="false"),
    )

    r = client.post("/v1/auth/social/google", json={"token": SECRET_TOKEN})

    assert r.status_code == 200, r.text
    assert _links(db_session, owner.id) == 0
