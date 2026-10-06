"""소셜 로그인 이메일 자동 연결은 provider 가 확인한 이메일만 (#1551).

provider 가 준 이메일과 같은 기존 계정에 확인 없이 소셜 계정을 연결하면, provider
계정에 남의 주소를 적어 넣는 것만으로 그 사람의 On-Care 계정에 로그인된다. 여기서 본다.

- adapter 가 provider 별 검증 플래그를 `SocialIdentity.email_verified` 로 옮기는지.
  - google: tokeninfo `email_verified`(문자열 "true"/"false", bool 도 받는다)
  - kakao: `kakao_account.is_email_valid` 와 `is_email_verified` 가 **둘 다** 참
- 확인되지 않은 이메일이 기존 계정의 이메일과 같으면 연결도, 새 계정도 만들지 않고
  409 `social_email_in_use` 로 "처음 가입한 방법으로 로그인" 을 안내한다.
- 같은 계정이 없으면 새 계정을 만들되 그 주소를 계정 이메일로 쓰지 않는다
  (`{provider}_{id}@social.oncare` 대체 이메일).
- 확인된 이메일은 지금처럼 같은 이메일 계정에 연결된다.

단위 테스트는 DB 가 필요 없다. provider HTTP 는 `httpx.MockTransport` 로 흉내 낸다.
"""
from __future__ import annotations

import asyncio
from uuid import uuid4

import pytest
from sqlalchemy import func, select

from app.models.models import AuditLog, SocialAccount, User
from app.services.social.base import SocialIdentity, SocialProviderResponseError
from app.services.social.google import GoogleVerifier
from app.services.social.kakao import KakaoVerifier
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


def _user_by_email(db, email: str) -> User | None:
    db.expire_all()
    return db.scalar(select(User).where(func.lower(User.email) == email.lower()))


def _social_account(db, provider: str, uid: str) -> SocialAccount | None:
    db.expire_all()
    return db.scalar(
        select(SocialAccount).where(
            SocialAccount.provider == provider, SocialAccount.provider_user_id == uid
        )
    )


def _email_in_use_audits(db, provider: str) -> int:
    db.expire_all()
    return db.scalar(
        select(func.count()).select_from(AuditLog).where(
            AuditLog.event == "auth.social",
            AuditLog.success.is_(False),
            AuditLog.detail == f"{provider} reason=email_in_use",
        )
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


@pytest.mark.parametrize("provider", ["google", "kakao"])
def test_unverified_email_does_not_link_existing_account(client, db_session, monkeypatch, provider):
    owner = _existing_user(db_session)
    uid = f"{provider}-{uuid4().hex[:10]}"
    _fake_identity(
        monkeypatch,
        SocialIdentity(provider=provider, provider_user_id=uid, email=owner.email.upper(), name="남"),
    )

    before = _email_in_use_audits(db_session, provider)

    r = client.post(f"/v1/auth/social/{provider}", json={"token": "any"})

    # 로그인시키지 않고, 같은 이메일의 계정이 있다고 알린다. 토큰은 없다.
    assert r.status_code == 409, r.text
    assert r.json()["detail"]["code"] == "social_email_in_use"
    assert r.json()["detail"]["message"]
    assert "access_token" not in r.json()
    assert _links(db_session, owner.id) == 0
    # 조용히 따로 계정을 만들지도 않는다.
    assert _user_by_email(db_session, f"{provider}_{uid}@social.oncare") is None
    assert _social_account(db_session, provider, uid) is None
    # 인증은 됐지만 로그인하지 않았다 — 실패 감사에 이유가 붙는다.
    assert _email_in_use_audits(db_session, provider) == before + 1


def test_unverified_email_is_not_stored_on_new_account(client, db_session, monkeypatch):
    """아무도 쓰지 않는 주소여도 확인 안 됐으면 계정 이메일로 선점하지 않는다."""
    unclaimed = f"unclaimed-{uuid4().hex[:10]}@oncare.com"
    uid = f"kakao-{uuid4().hex[:10]}"
    _fake_identity(
        monkeypatch, SocialIdentity(provider="kakao", provider_user_id=uid, email=unclaimed)
    )

    r = client.post("/v1/auth/social/kakao", json={"token": "any"})

    assert r.status_code == 200, r.text
    me = _me(client, r.json()["access_token"])
    assert me["email"] == f"kakao_{uid}@social.oncare"
    assert _user_by_email(db_session, unclaimed) is None

    # 다시 로그인해도 같은 계정이다(소셜 계정 연결로 찾는다).
    again = client.post("/v1/auth/social/kakao", json={"token": "any"})
    assert again.status_code == 200, again.text
    assert _me(client, again.json()["access_token"])["id"] == me["id"]


def test_already_linked_account_logs_in_even_if_email_now_unverified(
    client, db_session, monkeypatch
):
    """이미 연결된 소셜 계정은 이메일 확인과 무관하게 그 계정으로 들어간다."""
    owner = _existing_user(db_session)
    uid = f"kakao-{uuid4().hex[:10]}"
    _fake_identity(
        monkeypatch,
        SocialIdentity(
            provider="kakao", provider_user_id=uid, email=owner.email, email_verified=True
        ),
    )
    assert client.post("/v1/auth/social/kakao", json={"token": "any"}).status_code == 200

    _fake_identity(
        monkeypatch,
        SocialIdentity(provider="kakao", provider_user_id=uid, email=owner.email),
    )
    r = client.post("/v1/auth/social/kakao", json={"token": "any"})

    assert r.status_code == 200, r.text
    assert _me(client, r.json()["access_token"])["id"] == owner.id


@pytest.mark.parametrize("provider", ["google", "kakao"])
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

    assert r.status_code == 409, r.text
    assert r.json()["detail"]["code"] == "social_email_in_use"
    assert _links(db_session, owner.id) == 0


def test_api_google_unverified_email_through_adapter_does_not_link(client, db_session, monkeypatch):
    owner = _existing_user(db_session)
    respond_json(
        monkeypatch,
        _google_body(sub=f"g-{uuid4().hex[:10]}", email=owner.email, email_verified="false"),
    )

    r = client.post("/v1/auth/social/google", json={"token": SECRET_TOKEN})

    assert r.status_code == 409, r.text
    assert r.json()["detail"]["code"] == "social_email_in_use"
    assert _links(db_session, owner.id) == 0
