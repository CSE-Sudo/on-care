"""탈퇴한 회원의 Apple 토큰 철회 (#3499).

Apple 은 Sign in with Apple 계정을 앱에서 지울 때 REST API 로 토큰을 철회하라고
안내한다(App Review Guideline 5.1.1(v)). 서버는 탈퇴 본인 확인 때 앱이 받은
`authorization_code` 를 토큰으로 바꿔(`/auth/token`) 철회한다(`/auth/revoke`).
철회는 탈퇴를 막지 않는다 — 실패해도 False 만 돌려주고 예외를 던지지 않는다.

Apple 호출은 `httpx.MockTransport` 로 대신해 네트워크가 필요 없다. 앞부분은 DB 없이
돌고, 탈퇴 엔드포인트 테스트만 DB 가 필요하다(로컬 skip, CI 실행).
"""
from __future__ import annotations

from collections.abc import Iterator
from urllib.parse import parse_qs
from uuid import uuid4

import httpx
import jwt
import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec

from app.core.config import Settings
from app.core.security import create_access_token
from app.models.models import SocialAccount, User
from app.services import reauth
from app.services.social import apple_revoke
from app.services.social.base import SocialAuthError, SocialIdentity

BUNDLE_ID = "com.csesudo.oncare"


@pytest.fixture(scope="module")
def p8() -> tuple[str, ec.EllipticCurvePublicKey]:
    """Sign in with Apple 키(.p8)와 같은 형식의 P-256 개인키(PEM)와 그 공개키."""
    private = ec.generate_private_key(ec.SECP256R1())
    pem = private.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    ).decode()
    return pem, private.public_key()


def _settings(p8, **overrides) -> Settings:
    pem, _ = p8
    values = {
        "apple_client_ids": f"{BUNDLE_ID},com.csesudo.oncare.web",
        "apple_team_id": "TEAM123456",
        "apple_key_id": "KEY1234567",
        "apple_private_key": pem,
    }
    values.update(overrides)
    return Settings(_env_file=None, **values)


class _Apple:
    """Apple `/auth/token`·`/auth/revoke` 흉내. 받은 요청을 기록한다."""

    def __init__(
        self,
        *,
        token_status: int = 200,
        token_body: object | None = None,
        revoke_status: int = 200,
        raise_on: str | None = None,
    ) -> None:
        self.token_status = token_status
        self.token_body = (
            {"access_token": "at-1", "refresh_token": "rt-1", "id_token": "x"}
            if token_body is None
            else token_body
        )
        self.revoke_status = revoke_status
        self.raise_on = raise_on
        self.calls: list[tuple[str, dict[str, list[str]]]] = []

    def __call__(self, request: httpx.Request) -> httpx.Response:
        form = parse_qs(request.content.decode())
        url = str(request.url)
        self.calls.append((url, form))
        if self.raise_on and url == self.raise_on:
            raise httpx.ConnectError("down", request=request)
        if url == apple_revoke.TOKEN_URL:
            if isinstance(self.token_body, str):
                return httpx.Response(self.token_status, text=self.token_body)
            return httpx.Response(self.token_status, json=self.token_body)
        if url == apple_revoke.REVOKE_URL:
            return httpx.Response(self.revoke_status)
        return httpx.Response(404)

    def client(self) -> httpx.Client:
        return httpx.Client(transport=httpx.MockTransport(self))


# ---- client secret ----


def test_client_secret_is_es256_jwt_apple_expects(p8):
    _, public = p8
    settings = _settings(p8)

    secret = apple_revoke.client_secret(settings, BUNDLE_ID, now=1_700_000_000)

    header = jwt.get_unverified_header(secret)
    assert header["alg"] == "ES256"
    assert header["kid"] == "KEY1234567"
    claims = jwt.decode(
        secret,
        public,
        algorithms=["ES256"],
        audience="https://appleid.apple.com",
        options={"verify_exp": False},
    )
    assert claims["iss"] == "TEAM123456"
    assert claims["sub"] == BUNDLE_ID
    assert claims["iat"] == 1_700_000_000
    # Apple 은 최대 6개월을 허용한다. 호출마다 새로 만들므로 짧게 둔다.
    assert 0 < claims["exp"] - claims["iat"] <= 600


def test_key_with_escaped_newlines_is_accepted(p8):
    """비밀 저장소가 PEM 줄바꿈을 `\\n` 글자로 담아 줘도 서명할 수 있다."""
    pem, public = p8
    settings = _settings(p8, apple_private_key=pem.strip().replace("\n", "\\n"))
    secret = apple_revoke.client_secret(settings, BUNDLE_ID)
    jwt.decode(secret, public, algorithms=["ES256"], audience="https://appleid.apple.com")


# ---- 건너뛰기 ----


@pytest.mark.parametrize("code", [None, "", "   "])
def test_without_code_nothing_is_sent(p8, code):
    apple = _Apple()
    assert apple_revoke.revoke_with_code(code, settings=_settings(p8), http=apple.client()) is False
    assert apple.calls == []


@pytest.mark.parametrize(
    "missing", ["apple_team_id", "apple_key_id", "apple_private_key", "apple_client_ids"]
)
def test_without_keys_nothing_is_sent(p8, missing):
    apple = _Apple()
    settings = _settings(p8, **{missing: ""})
    assert settings.apple_revoke_configured is False
    assert apple_revoke.revoke_with_code("code-1", settings=settings, http=apple.client()) is False
    assert apple.calls == []


def test_broken_key_is_reported_not_raised(p8):
    apple = _Apple()
    settings = _settings(p8, apple_private_key="not a pem")
    assert apple_revoke.revoke_with_code("code-1", settings=settings, http=apple.client()) is False
    assert apple.calls == []


# ---- 철회 ----


def test_code_is_exchanged_then_refresh_token_revoked(p8):
    apple = _Apple()

    assert apple_revoke.revoke_with_code(
        " code-1 ", settings=_settings(p8), http=apple.client()
    ) is True

    (token_url, token_form), (revoke_url, revoke_form) = apple.calls
    assert token_url == apple_revoke.TOKEN_URL
    assert token_form["grant_type"] == ["authorization_code"]
    assert token_form["code"] == ["code-1"]
    # 앱의 코드는 번들 ID 앞으로 발급된다 — 허용 목록의 첫 값.
    assert token_form["client_id"] == [BUNDLE_ID]
    assert token_form["client_secret"][0].count(".") == 2
    assert revoke_url == apple_revoke.REVOKE_URL
    assert revoke_form["token"] == ["rt-1"]
    assert revoke_form["token_type_hint"] == ["refresh_token"]
    assert revoke_form["client_id"] == [BUNDLE_ID]


def test_access_token_is_revoked_when_no_refresh_token(p8):
    apple = _Apple(token_body={"access_token": "at-only"})
    assert apple_revoke.revoke_with_code("code-1", settings=_settings(p8), http=apple.client())
    _, revoke_form = apple.calls[1]
    assert revoke_form["token"] == ["at-only"]
    assert revoke_form["token_type_hint"] == ["access_token"]


@pytest.mark.parametrize(
    "apple",
    [
        _Apple(token_status=400, token_body={"error": "invalid_grant"}),
        _Apple(token_body={}),
        _Apple(token_body=["not", "a", "dict"]),
        _Apple(token_body="<html>oops</html>"),
        _Apple(revoke_status=400),
        _Apple(raise_on=apple_revoke.TOKEN_URL),
        _Apple(raise_on=apple_revoke.REVOKE_URL),
    ],
    ids=[
        "code-rejected", "no-token", "not-object", "not-json",
        "revoke-rejected", "token-network", "revoke-network",
    ],
)
def test_apple_failures_return_false_without_raising(p8, apple):
    assert apple_revoke.revoke_with_code(
        "code-1", settings=_settings(p8), http=apple.client()
    ) is False


def test_logs_never_carry_code_or_tokens(p8, caplog):
    caplog.set_level("DEBUG", logger=apple_revoke.__name__)
    apple_revoke.revoke_with_code(
        "secret-code-xyz", settings=_settings(p8), http=_Apple().client()
    )
    apple_revoke.revoke_with_code(
        "secret-code-xyz", settings=_settings(p8), http=_Apple(revoke_status=500).client()
    )
    text = caplog.text
    for value in ("secret-code-xyz", "rt-1", "at-1", "BEGIN PRIVATE KEY"):
        assert value not in text


# ---- 탈퇴 엔드포인트 (DB) ----


class _FakeVerifier:
    def __init__(self, provider: str) -> None:
        self.provider = provider

    async def verify(self, token: str) -> SocialIdentity:
        if not token.startswith("good-"):
            raise SocialAuthError("bad token")
        return SocialIdentity(provider=self.provider, provider_user_id=token[5:])


@pytest.fixture
def revokes(monkeypatch) -> list[str | None]:
    """탈퇴가 철회를 불렀는지, 어떤 코드로 불렀는지 기록한다."""
    seen: list[str | None] = []

    def _record(code, **_kwargs):
        seen.append(code)
        return True

    monkeypatch.setattr(reauth, "get_verifier", lambda provider: _FakeVerifier(provider))
    monkeypatch.setattr(apple_revoke, "revoke_with_code", _record)
    return seen


@pytest.fixture
def made(db_session) -> Iterator[list[str]]:
    ids: list[str] = []
    yield ids
    db_session.expire_all()
    for user_id in ids:
        row = db_session.get(User, user_id)
        if row is not None:
            db_session.delete(row)
    db_session.commit()


def _member(db_session, made, provider: str, uid: str) -> User:
    user = User(
        id=f"member-{uuid4().hex[:12]}",
        email=f"revoke3499-{uuid4().hex[:10]}@oncare.com",
        name="철회",
        hashed_password="",
        role="member",
    )
    db_session.add(user)
    db_session.commit()
    db_session.add(SocialAccount(user_id=user.id, provider=provider, provider_user_id=uid))
    db_session.commit()
    made.append(user.id)
    return user


def _delete(client, user: User, **body):
    return client.request(
        "DELETE",
        "/v1/users/me",
        json=body,
        headers={"Authorization": f"Bearer {create_access_token(user.id)}"},
    )


def _gone(db_session, user_id: str) -> bool:
    db_session.expire_all()
    return db_session.get(User, user_id) is None


def test_apple_member_delete_revokes_with_the_reauth_code(client, db_session, made, revokes):
    uid = f"apple-{uuid4().hex[:8]}"
    user = _member(db_session, made, "apple", uid)

    res = _delete(
        client, user,
        social_provider="apple", social_token=f"good-{uid}",
        apple_authorization_code="code-from-app",
    )

    assert res.status_code == 200, res.text
    assert _gone(db_session, user.id)
    assert revokes == ["code-from-app"]


def test_apple_member_delete_without_code_still_deletes(client, db_session, made, revokes):
    """철회는 탈퇴를 막지 않는다 — 코드가 없어도 계정은 지워진다."""
    uid = f"apple-{uuid4().hex[:8]}"
    user = _member(db_session, made, "apple", uid)

    res = _delete(client, user, social_provider="apple", social_token=f"good-{uid}")

    assert res.status_code == 200, res.text
    assert _gone(db_session, user.id)
    assert revokes == [None]


def test_failed_revoke_does_not_undo_delete(client, db_session, made, monkeypatch):
    uid = f"apple-{uuid4().hex[:8]}"
    user = _member(db_session, made, "apple", uid)
    monkeypatch.setattr(reauth, "get_verifier", lambda provider: _FakeVerifier(provider))
    monkeypatch.setattr(apple_revoke, "revoke_with_code", lambda code, **_kw: False)

    res = _delete(
        client, user, social_provider="apple", social_token=f"good-{uid}",
        apple_authorization_code="code",
    )

    assert res.status_code == 200, res.text
    assert _gone(db_session, user.id)


def test_kakao_member_delete_does_not_call_apple(client, db_session, made, revokes):
    uid = f"kakao-{uuid4().hex[:8]}"
    user = _member(db_session, made, "kakao", uid)

    res = _delete(
        client, user, social_provider="kakao", social_token=f"good-{uid}",
        apple_authorization_code="ignored",
    )

    assert res.status_code == 200, res.text
    assert revokes == []


def test_failed_reauth_does_not_revoke(client, db_session, made, revokes):
    uid = f"apple-{uuid4().hex[:8]}"
    user = _member(db_session, made, "apple", uid)

    res = _delete(
        client, user, social_provider="apple", social_token="bad",
        apple_authorization_code="code",
    )

    assert res.status_code == 400
    assert not _gone(db_session, user.id)
    assert revokes == []


def test_overlong_code_is_rejected(client, db_session, made, revokes):
    uid = f"apple-{uuid4().hex[:8]}"
    user = _member(db_session, made, "apple", uid)

    res = _delete(
        client, user, social_provider="apple", social_token=f"good-{uid}",
        apple_authorization_code="x" * 1025,
    )

    assert res.status_code == 422
    assert not _gone(db_session, user.id)
