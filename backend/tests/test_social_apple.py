"""Apple 로그인 검증 (#330, #3499 에서 되살림).

App Store 심사(Guideline 4.8)가 카카오·구글과 동등한 로그인으로 Sign in with Apple 을
요구해 #3218 에서 걷어낸 검증기를 다시 넣었다. Apple 은 토큰을 확인해 주는 조회
엔드포인트가 없어 서버가 JWT 를 직접 검증한다.
검증이 한 군데라도 비면 우회가 생기므로, **뚫리는 경우가 실제로 막히는지**를 본다:
만료·aud 불일치·iss 위조·서명 위조·alg 강등(none).

테스트용 RSA 키쌍을 만들어 JWKS 를 대신하므로 네트워크가 필요 없다(CI 에 Apple
자격증명이 없고, 있더라도 실제 Apple 토큰은 재현할 수 없다).
"""
from __future__ import annotations

import asyncio
import threading
from datetime import datetime, timedelta, timezone

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa

from sqlalchemy import select

from app.models.models import SocialAccount, User
from app.services.social import apple as apple_mod
from app.services.social.apple import AppleVerifier
from app.services.social.base import SocialAuthError

_KID = "test-key-1"


@pytest.fixture(scope="module")
def keypair():
    """서명용 개인키와 검증용 공개키."""
    private = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    return private, private.public_key()


@pytest.fixture(autouse=True)
def _apple_client_ids(monkeypatch):
    """허용 aud 를 고정한다(설정 파일·환경에 의존하지 않도록)."""
    monkeypatch.setattr(
        apple_mod, "_allowed_audiences", lambda: ["com.oncare.app", "com.oncare.web"]
    )


@pytest.fixture(autouse=True)
def _stub_jwks(monkeypatch, keypair):
    """JWKS 조회를 테스트 공개키로 대체 — 네트워크를 타지 않는다.

    조회가 **어느 스레드에서 실행됐는지**도 기록한다. 이벤트 루프를 막지 않는지
    검증하는 데 쓴다.
    """
    _, public = keypair

    class _Key:
        key = public

    class _Client:
        called_on: list[int] = []

        def get_signing_key_from_jwt(self, token):  # noqa: ANN001
            _Client.called_on.append(threading.get_ident())
            return _Key()

    _Client.called_on = []
    monkeypatch.setattr(apple_mod, "_jwk_client", lambda: _Client())
    return _Client


def _token(keypair, **overrides) -> str:
    private, _ = keypair
    now = datetime.now(tz=timezone.utc)
    claims = {
        "iss": apple_mod.APPLE_ISSUER,
        "aud": "com.oncare.app",
        "sub": "001234.abcdef.5678",
        "email": "user@privaterelay.appleid.com",
        "email_verified": True,
        "iat": now,
        "exp": now + timedelta(minutes=10),
    }
    claims.update(overrides)
    return jwt.encode(claims, private, algorithm="RS256", headers={"kid": _KID})


def _token_without(keypair, claim: str) -> str:
    private, _ = keypair
    now = datetime.now(tz=timezone.utc)
    claims = {
        "iss": apple_mod.APPLE_ISSUER,
        "aud": "com.oncare.app",
        "sub": "001234.abcdef.5678",
        "email": "user@privaterelay.appleid.com",
        "email_verified": "true",
        "iat": now,
        "exp": now + timedelta(minutes=10),
    }
    claims.pop(claim)
    return jwt.encode(claims, private, algorithm="RS256", headers={"kid": _KID})


def _verify(token: str):
    """검증 실행.

    이 저장소엔 pytest-asyncio 가 없고 async 테스트도 이것뿐이라, 의존성을 늘리는
    대신 코루틴을 직접 돌린다.
    """
    return asyncio.run(AppleVerifier().verify(token))


def test_valid_token_returns_identity(keypair):
    identity = _verify(_token(keypair))

    assert identity.provider == "apple"
    assert identity.provider_user_id == "001234.abcdef.5678"
    assert identity.email == "user@privaterelay.appleid.com"
    # 이메일 가리기 주소도 Apple 이 확인한 주소다.
    assert identity.email_verified is True
    # Apple 은 이름을 토큰에 담지 않는다(최초 로그인 때 클라이언트가 따로 받는다).
    assert identity.name == ""


@pytest.mark.parametrize("flag,expected", [
    (True, True), ("true", True), ("TRUE", True),
    (False, False), ("false", False), (None, False), ("yes", False),
])
def test_email_verified_reads_bool_and_string(keypair, flag, expected):
    """Apple 은 `email_verified` 를 불리언이나 문자열로 준다(#1551 과 같은 판정)."""
    overrides = {"email_verified": flag} if flag is not None else {}
    token = _token(keypair, **overrides)
    if flag is None:
        token = _token_without(keypair, "email_verified")
    assert _verify(token).email_verified is expected


def test_token_without_email_is_not_verified(keypair):
    identity = _verify(_token_without(keypair, "email"))
    assert identity.email == ""
    assert identity.email_verified is False


def test_web_audience_is_also_accepted(keypair):
    """iOS 는 번들 ID, 웹은 Service ID 로 서로 다른 aud 를 받는다."""
    identity = _verify(_token(keypair, aud="com.oncare.web"))
    assert identity.provider_user_id


def test_token_for_another_app_is_rejected(keypair):
    """aud 를 확인하지 않으면 **다른 앱용 유효한 Apple 토큰**으로 로그인이 뚫린다."""
    with pytest.raises(SocialAuthError):
        _verify(_token(keypair, aud="com.someone-else.app"))


def test_expired_token_is_rejected(keypair):
    past = datetime.now(tz=timezone.utc) - timedelta(hours=1)
    with pytest.raises(SocialAuthError):
        _verify(_token(keypair, exp=past, iat=past - timedelta(minutes=10)))


def test_forged_issuer_is_rejected(keypair):
    with pytest.raises(SocialAuthError):
        _verify(_token(keypair, iss="https://evil.example.com"))


def test_token_signed_by_another_key_is_rejected(keypair):
    """서명 검증이 실제로 도는지 — 남의 키로 서명한 토큰은 통과하면 안 된다."""
    attacker = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    now = datetime.now(tz=timezone.utc)
    forged = jwt.encode(
        {
            "iss": apple_mod.APPLE_ISSUER,
            "aud": "com.oncare.app",
            "sub": "001234.abcdef.5678",
            "iat": now,
            "exp": now + timedelta(minutes=10),
        },
        attacker,
        algorithm="RS256",
        headers={"kid": _KID},
    )
    with pytest.raises(SocialAuthError):
        _verify(forged)


def test_unsigned_token_is_rejected(keypair):
    """alg=none 강등 — 서명 없는 토큰을 받아 주면 아무나 로그인할 수 있다."""
    now = datetime.now(tz=timezone.utc)
    unsigned = jwt.encode(
        {
            "iss": apple_mod.APPLE_ISSUER,
            "aud": "com.oncare.app",
            "sub": "001234.abcdef.5678",
            "iat": now,
            "exp": now + timedelta(minutes=10),
        },
        key="",
        algorithm="none",
    )
    with pytest.raises(SocialAuthError):
        _verify(unsigned)


def test_token_without_sub_is_rejected(keypair):
    with pytest.raises(SocialAuthError):
        _verify(_token(keypair, sub=""))


def test_missing_client_id_config_refuses_instead_of_skipping(
    monkeypatch, keypair
):
    """설정이 없으면 **검증을 건너뛰지 않고 거부**한다.

    다른 provider 는 키가 없으면 폴백하지만 인증은 폴백 대상이 아니다. aud 확인을
    생략하는 순간 다른 앱용 토큰으로 로그인이 뚫린다.
    """
    monkeypatch.setattr(apple_mod, "_allowed_audiences", list)

    with pytest.raises(SocialAuthError):
        _verify(_token(keypair))


# ───────────────────────────────────────────────────────── 엔드포인트(DB) ──


def test_endpoint_no_longer_returns_501(client):
    """`POST /auth/social/apple` 이 더 이상 "미지원(501)"이 아니다.

    이 이슈의 출발점이 501 이었다. 이제 검증을 실제로 수행하므로, 잘못된 토큰은
    다른 provider 와 똑같이 401 로 거절돼야 한다(구현 여부가 응답으로 드러나면
    안 된다).
    """
    res = client.post("/v1/auth/social/apple", json={"token": "not-a-real-token"})

    assert res.status_code != 501
    assert res.status_code == 401


def test_endpoint_rejection_matches_other_providers(client):
    """apple 이 kakao/google 과 같은 형태로 거절되는지 — 응답만 보고 어떤 provider 가
    구현됐는지 알 수 없어야 한다."""
    apple = client.post("/v1/auth/social/apple", json={"token": "bad"})
    google = client.post("/v1/auth/social/google", json={"token": "bad"})

    assert apple.status_code == google.status_code == 401
    assert apple.json()["detail"] == google.json()["detail"]


def test_jwks_lookup_runs_off_the_event_loop(keypair, _stub_jwks):
    """JWKS 조회는 이벤트 루프 밖(다른 스레드)에서 실행돼야 한다.

    PyJWKClient 는 urllib 기반이라 동기 블로킹이다. 캐시가 비었거나 Apple 이 키를
    회전한 직후에는 실제 HTTP 요청이 나가는데, async 핸들러에서 그대로 호출하면
    그동안 이벤트 루프가 멈춰 **무관한 요청까지 함께 지연된다.**
    """
    main_thread = threading.get_ident()

    async def _run():
        await AppleVerifier().verify(_token(keypair))
        return threading.get_ident()

    loop_thread = asyncio.run(_run())

    assert _stub_jwks.called_on, "JWKS 조회가 호출되지 않았다"
    # 코루틴이 도는 스레드와 JWKS 조회가 실행된 스레드가 달라야 한다.
    assert _stub_jwks.called_on[0] != loop_thread
    assert _stub_jwks.called_on[0] != main_thread


def test_factory_registers_apple():
    from app.services.social.factory import get_verifier

    assert isinstance(get_verifier("apple"), AppleVerifier)
    assert isinstance(get_verifier("Apple"), AppleVerifier)


# ─────────────────────────────────────────────── 로그인 → 계정 (DB, #3499) ──


@pytest.fixture
def apple_users(db_session):
    """테스트가 만든 애플 연결 사용자를 지운다."""
    subs: list[str] = []
    yield subs
    db_session.expire_all()
    for sub in subs:
        account = db_session.scalar(
            select(SocialAccount).where(
                SocialAccount.provider == "apple", SocialAccount.provider_user_id == sub
            )
        )
        if account is None:
            continue
        user = db_session.get(User, account.user_id)
        if user is not None:
            db_session.delete(user)
    db_session.commit()


def _sub() -> str:
    import uuid

    return f"000{uuid.uuid4().hex[:6]}.{uuid.uuid4().hex}.0{uuid.uuid4().hex[:3]}"


def _login(client, token: str, **extra):
    return client.post("/v1/auth/social/apple", json={"token": token, **extra})


def _user_for(db_session, sub: str) -> User:
    db_session.expire_all()
    account = db_session.scalar(
        select(SocialAccount).where(
            SocialAccount.provider == "apple", SocialAccount.provider_user_id == sub
        )
    )
    assert account is not None
    return db_session.get(User, account.user_id)


def test_first_login_creates_account_with_app_name(client, db_session, keypair, apple_users):
    """Apple 은 이름을 첫 로그인 때 앱에만 준다 — 앱이 보낸 이름이 계정 이름이 된다."""
    sub = _sub()
    apple_users.append(sub)
    email = f"apple3499-{sub[:9]}@privaterelay.appleid.com"

    res = _login(client, _token(keypair, sub=sub, email=email), name="  김애플 ")

    assert res.status_code == 200, res.text
    assert res.json()["access_token"]
    user = _user_for(db_session, sub)
    assert user.name == "김애플"
    # 확인된 가리기 주소가 계정 이메일이 된다(대체 이메일이 아니다).
    assert user.email == email


def test_login_without_name_falls_back_to_provider(client, db_session, keypair, apple_users):
    sub = _sub()
    apple_users.append(sub)
    res = _login(client, _token(keypair, sub=sub, email=f"apple3499-{sub[:9]}@example.com"))
    assert res.status_code == 200, res.text
    assert _user_for(db_session, sub).name == "apple"


@pytest.mark.parametrize("name", ["", "   ", "가" * 101])
def test_unusable_name_does_not_block_login(client, db_session, keypair, apple_users, name):
    sub = _sub()
    apple_users.append(sub)
    res = _login(
        client, _token(keypair, sub=sub, email=f"apple3499-{sub[:9]}@example.com"), name=name
    )
    assert res.status_code == 200, res.text
    assert _user_for(db_session, sub).name == "apple"


def test_later_login_does_not_rename_the_account(client, db_session, keypair, apple_users):
    """이름은 새 계정을 만들 때만 쓴다 — 회원이 MY 에서 바꾼 이름을 덮지 않는다."""
    sub = _sub()
    apple_users.append(sub)
    email = f"apple3499-{sub[:9]}@example.com"
    assert _login(client, _token(keypair, sub=sub, email=email), name="처음").status_code == 200

    again = _login(client, _token(keypair, sub=sub, email=email), name="다른이름")

    assert again.status_code == 200, again.text
    assert _user_for(db_session, sub).name == "처음"


def test_unverified_email_does_not_become_the_account_email(
    client, db_session, keypair, apple_users
):
    sub = _sub()
    apple_users.append(sub)
    res = _login(
        client,
        _token(keypair, sub=sub, email=f"apple3499-{sub[:9]}@example.com", email_verified=False),
    )
    assert res.status_code == 200, res.text
    assert _user_for(db_session, sub).email.endswith("@social.oncare")


def test_login_for_another_app_creates_nothing(client, db_session, keypair):
    db_session.expire_all()
    before = len(db_session.scalars(select(SocialAccount.id)).all())
    res = _login(client, _token(keypair, sub=_sub(), aud="com.someone-else.app"))
    assert res.status_code == 401
    db_session.expire_all()
    assert len(db_session.scalars(select(SocialAccount.id)).all()) == before
