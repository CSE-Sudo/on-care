"""웹 클라이언트의 짧은 refresh 토큰(#2828) — 순수 단위(DB 불필요).

웹 빌드는 토큰을 브라우저 탭 단위 저장소에 둔다. 새어 나갔을 때 쓸 수 있는 기간을
줄이려고 웹(`X-Client-Platform: web`)에서 온 로그인·회전에는 짧은 refresh 토큰을 준다.
모바일은 지금 수명(30일)을 그대로 쓴다.
"""
from __future__ import annotations

import asyncio
from datetime import datetime, timedelta, timezone

import jwt
import pytest

from app.core import client_platform
from app.core.client_platform import (
    CLIENT_PLATFORM_HEADER,
    RequestClientPlatformMiddleware,
    is_web_client,
    parse_client_platform,
)
from app.core.config import Settings, get_settings
from app.core.security import (
    CLIENT_CLAIM,
    create_access_token,
    create_refresh_token,
    decode_refresh_claims,
    refresh_token_ttl,
)
from app.models.models import User
from app.services import auth_tokens

settings = get_settings()


def _lifetime(token: str) -> timedelta:
    payload = jwt.decode(
        token, settings.jwt_secret, algorithms=[settings.jwt_algorithm]
    )
    return datetime.fromtimestamp(payload["exp"], tz=timezone.utc) - datetime.fromtimestamp(
        payload["iat"], tz=timezone.utc
    )


def _user() -> User:
    return User(id="user-web", email="web@example.invalid", token_version=0)


# ---------- 설정 ----------


def test_web_refresh_lifetime_defaults_to_seven_days():
    s = Settings(_env_file=None)
    assert s.web_refresh_token_expire_days == 7
    # 모바일 수명은 그대로다.
    assert s.refresh_token_expire_days == 30


def test_web_refresh_lifetime_is_shorter_than_mobile():
    assert settings.web_refresh_token_expire_days < settings.refresh_token_expire_days


# ---------- 토큰 발급 ----------


def test_ttl_helper_picks_lifetime_by_client():
    assert refresh_token_ttl() == timedelta(days=settings.refresh_token_expire_days)
    assert refresh_token_ttl(web=True) == timedelta(
        days=settings.web_refresh_token_expire_days
    )


def test_mobile_refresh_token_keeps_full_lifetime_and_no_client_claim():
    token = create_refresh_token("user-1")
    assert _lifetime(token) == timedelta(days=settings.refresh_token_expire_days)
    payload = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
    assert CLIENT_CLAIM not in payload
    assert decode_refresh_claims(token).web is False


def test_web_refresh_token_is_short_and_marked():
    token = create_refresh_token("user-1", web=True)
    assert _lifetime(token) == timedelta(days=settings.web_refresh_token_expire_days)
    payload = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
    assert payload[CLIENT_CLAIM] == "web"
    claims = decode_refresh_claims(token)
    assert claims.web is True
    assert claims.subject == "user-1"


def test_web_refresh_token_keeps_generation_and_unique_jti():
    first = decode_refresh_claims(create_refresh_token("u", token_version=2, web=True))
    second = decode_refresh_claims(create_refresh_token("u", token_version=2, web=True))
    assert first.token_version == second.token_version == 2
    assert first.jti != second.jti


def test_unknown_client_claim_is_not_web():
    """클레임 값이 `web` 이 아니면 웹으로 보지 않는다(짧게 만드는 쪽으로만 쓴다)."""
    now = datetime.now(timezone.utc)
    token = jwt.encode(
        {
            "sub": "u",
            "type": "refresh",
            "iat": now,
            "exp": now + timedelta(days=1),
            "jti": "abc",
            CLIENT_CLAIM: "ios",
        },
        settings.jwt_secret,
        algorithm=settings.jwt_algorithm,
    )
    assert decode_refresh_claims(token).web is False


def test_access_token_lifetime_does_not_depend_on_client():
    assert _lifetime(create_access_token("u")) == timedelta(
        minutes=settings.access_token_expire_minutes
    )


# ---------- 헤더 판별 ----------


@pytest.mark.parametrize("value", ["web", "WEB", " web ", "Web"])
def test_header_values_meaning_web(value):
    assert parse_client_platform(value) is True


@pytest.mark.parametrize("value", [None, "", "ios", "android", "webview", "mobile,web"])
def test_header_values_not_web(value):
    assert parse_client_platform(value) is False


def test_outside_a_request_is_not_web():
    assert is_web_client() is False


# ---------- 미들웨어 ----------


def _run(middleware_headers: list[tuple[bytes, bytes]], scope_type: str = "http") -> list[bool]:
    seen: list[bool] = []

    async def app(scope, receive, send):
        seen.append(is_web_client())

    async def receive():  # pragma: no cover - 호출되지 않는다
        return {"type": "http.request"}

    async def send(message):  # pragma: no cover - 호출되지 않는다
        return None

    mw = RequestClientPlatformMiddleware(app)
    asyncio.run(
        mw({"type": scope_type, "headers": middleware_headers}, receive, send)
    )
    return seen


def test_middleware_marks_web_requests():
    key = CLIENT_PLATFORM_HEADER.lower().encode()
    assert _run([(key, b"web")]) == [True]


def test_middleware_leaves_mobile_requests_alone():
    assert _run([(b"accept-language", b"ko")]) == [False]
    assert _run([]) == [False]


def test_middleware_resets_after_the_request():
    key = CLIENT_PLATFORM_HEADER.lower().encode()
    _run([(key, b"web")])
    assert is_web_client() is False


def test_middleware_ignores_non_http_scopes():
    key = CLIENT_PLATFORM_HEADER.lower().encode()
    assert _run([(key, b"web")], scope_type="lifespan") == [False]


# ---------- 발급 서비스 ----------


def test_issue_pair_uses_mobile_lifetime_by_default():
    pair = auth_tokens.issue_token_pair(_user())
    assert decode_refresh_claims(pair.refresh_token).web is False
    assert _lifetime(pair.refresh_token) == timedelta(
        days=settings.refresh_token_expire_days
    )


def test_issue_pair_follows_the_request_client():
    token = client_platform._is_web_ctx.set(True)
    try:
        pair = auth_tokens.issue_token_pair(_user())
    finally:
        client_platform._is_web_ctx.reset(token)
    assert decode_refresh_claims(pair.refresh_token).web is True
    assert _lifetime(pair.refresh_token) == timedelta(
        days=settings.web_refresh_token_expire_days
    )


def test_issue_pair_web_flag_wins_without_header():
    """웹으로 발급된 토큰의 회전은 헤더가 없어도 웹 수명이다."""
    pair = auth_tokens.issue_token_pair(_user(), web=True)
    assert decode_refresh_claims(pair.refresh_token).web is True
