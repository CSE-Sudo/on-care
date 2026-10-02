"""웹 클라이언트 refresh 수명 — 로그인·회전 API(#2828). DB 필요(로컬 skip, CI 실행)."""
from __future__ import annotations

from datetime import timedelta
from uuid import uuid4

import jwt

from app.core.config import get_settings
from app.core.security import decode_refresh_claims

settings = get_settings()
WEB = {"X-Client-Platform": "web"}


def _lifetime(token: str) -> timedelta:
    payload = jwt.decode(
        token, settings.jwt_secret, algorithms=[settings.jwt_algorithm]
    )
    return timedelta(seconds=payload["exp"] - payload["iat"])


def _register(client) -> tuple[str, str]:
    email = f"webttl-{uuid4().hex[:8]}@oncare.com"
    password = "pw-12345!"
    created = client.post(
        "/v1/auth/register",
        json={"email": email, "password": password, "name": "웹수명"},
    )
    assert created.status_code == 201, created.text
    return email, password


def _login(client, email: str, password: str, headers=None) -> dict:
    r = client.post(
        "/v1/auth/login",
        data={"username": email, "password": password},
        headers=headers or {},
    )
    assert r.status_code == 200, r.text
    return r.json()


def test_mobile_login_keeps_thirty_day_refresh(client):
    email, password = _register(client)
    tokens = _login(client, email, password)
    assert _lifetime(tokens["refresh_token"]) == timedelta(
        days=settings.refresh_token_expire_days
    )
    assert decode_refresh_claims(tokens["refresh_token"]).web is False


def test_web_login_gets_short_refresh(client):
    email, password = _register(client)
    tokens = _login(client, email, password, headers=WEB)
    assert _lifetime(tokens["refresh_token"]) == timedelta(
        days=settings.web_refresh_token_expire_days
    )
    assert decode_refresh_claims(tokens["refresh_token"]).web is True


def test_web_login_access_token_is_unchanged(client):
    email, password = _register(client)
    web = _login(client, email, password, headers=WEB)
    mobile = _login(client, email, password)
    assert _lifetime(web["access_token"]) == _lifetime(mobile["access_token"])
    # 웹 접근 토큰으로도 그대로 API 를 쓴다.
    me = client.get(
        "/v1/users/me", headers={"Authorization": f"Bearer {web['access_token']}"}
    )
    assert me.status_code == 200, me.text


def test_web_refresh_stays_short_even_without_header(client):
    """헤더를 빼고 회전해도 30일짜리를 다시 얻지 못한다."""
    email, password = _register(client)
    tokens = _login(client, email, password, headers=WEB)

    rotated = client.post(
        "/v1/auth/refresh", json={"refresh_token": tokens["refresh_token"]}
    )
    assert rotated.status_code == 200, rotated.text
    new_refresh = rotated.json()["refresh_token"]
    assert decode_refresh_claims(new_refresh).web is True
    assert _lifetime(new_refresh) == timedelta(
        days=settings.web_refresh_token_expire_days
    )


def test_web_rotation_with_header_stays_short(client):
    email, password = _register(client)
    tokens = _login(client, email, password, headers=WEB)
    rotated = client.post(
        "/v1/auth/refresh",
        json={"refresh_token": tokens["refresh_token"]},
        headers=WEB,
    )
    assert rotated.status_code == 200, rotated.text
    assert decode_refresh_claims(rotated.json()["refresh_token"]).web is True


def test_mobile_token_rotated_from_web_becomes_short(client):
    """예전(모바일 수명) 토큰을 웹이 회전하면 그때부터 웹 수명이다."""
    email, password = _register(client)
    tokens = _login(client, email, password)
    rotated = client.post(
        "/v1/auth/refresh",
        json={"refresh_token": tokens["refresh_token"]},
        headers=WEB,
    )
    assert rotated.status_code == 200, rotated.text
    assert _lifetime(rotated.json()["refresh_token"]) == timedelta(
        days=settings.web_refresh_token_expire_days
    )


def test_mobile_rotation_keeps_full_lifetime(client):
    email, password = _register(client)
    tokens = _login(client, email, password)
    rotated = client.post(
        "/v1/auth/refresh", json={"refresh_token": tokens["refresh_token"]}
    )
    assert rotated.status_code == 200, rotated.text
    assert _lifetime(rotated.json()["refresh_token"]) == timedelta(
        days=settings.refresh_token_expire_days
    )


def test_web_refresh_token_is_still_single_use(client):
    email, password = _register(client)
    tokens = _login(client, email, password, headers=WEB)
    first = client.post(
        "/v1/auth/refresh", json={"refresh_token": tokens["refresh_token"]}, headers=WEB
    )
    assert first.status_code == 200
    replay = client.post(
        "/v1/auth/refresh", json={"refresh_token": tokens["refresh_token"]}, headers=WEB
    )
    assert replay.status_code == 401


def test_web_logout_revokes_short_refresh(client):
    email, password = _register(client)
    tokens = _login(client, email, password, headers=WEB)
    out = client.post(
        "/v1/auth/logout", json={"refresh_token": tokens["refresh_token"]}, headers=WEB
    )
    assert out.status_code == 204
    denied = client.post(
        "/v1/auth/refresh", json={"refresh_token": tokens["refresh_token"]}, headers=WEB
    )
    assert denied.status_code == 401


def test_cors_preflight_allows_platform_header(client):
    """웹은 다른 출처에서 이 헤더를 싣는다 — preflight 가 막으면 로그인이 깨진다."""
    origins = [o for o in settings.cors_origin_list if o != "*"]
    origin = origins[0] if origins else "http://localhost:3000"
    r = client.options(
        "/v1/auth/login",
        headers={
            "Origin": origin,
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "x-client-platform,content-type",
        },
    )
    assert r.status_code == 200, r.text
    allowed = r.headers.get("access-control-allow-headers", "").lower()
    assert "x-client-platform" in allowed or allowed == "*"
