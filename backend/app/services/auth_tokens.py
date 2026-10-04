"""계정 토큰 발급·세대 관리(#2766).

로그인·회전·소셜 로그인·비밀번호 변경이 모두 같은 방식으로 토큰을 내도록 한 곳에
모은다. 발급하는 토큰에는 사용자 행의 `token_version` 을 싣고, 검증하는 쪽
(`api/deps.py`, `/auth/refresh`)은 `is_current` 로 같은 세대인지 본다.
"""
from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy.orm import Session

from app.core.client_platform import is_web_client
from app.core.security import (
    RefreshClaims,
    create_access_token,
    create_refresh_token,
    session_max_age,
)
from app.models.models import User
from app.schemas.user import LoginToken, Token
from app.services import signup_consent


def current_version(user: User) -> int:
    """사용자 행의 토큰 세대. 아직 flush 전인 새 객체는 0으로 본다."""
    return user.token_version or 0


def is_current(user: User, token_version: int) -> bool:
    """토큰에 실린 세대가 지금 계정 세대와 같은가."""
    return token_version == current_version(user)


def issue_token_pair(
    user: User,
    *,
    web: bool = False,
    session_id: str | None = None,
    auth_time: datetime | None = None,
) -> Token:
    """지금 세대로 접근·refresh 토큰 한 쌍을 만든다.

    웹 클라이언트(요청 헤더 `X-Client-Platform: web`, 또는 ``web=True`` — 웹으로 발급된
    refresh 토큰의 회전)에는 짧은 수명의 refresh 토큰을 준다(#2828).

    `session_id`·`auth_time` 을 주면 그 로그인 세션을 이어 받는다 — 회전이 그렇다.
    비우면(로그인·소셜 로그인·비밀번호 변경) 새 세션을 연다(#3086). 둘 중 하나만
    있는 토큰은 이어 받을 기준이 없어 새 세션으로 본다.
    """
    version = current_version(user)
    if session_id is None or auth_time is None:
        session_id, auth_time = None, None
    return Token(
        access_token=create_access_token(user.id, token_version=version),
        refresh_token=create_refresh_token(
            user.id,
            token_version=version,
            web=web or is_web_client(),
            session_id=session_id,
            auth_time=auth_time,
        ),
    )


def session_expires_at(claims: RefreshClaims) -> datetime:
    """그 토큰이 속한 로그인 세션의 절대 수명이 끝나는 시각(#3086).

    최초 인증 시각이 없는 토큰(세션 값이 생기기 전 발급)은 토큰 자신의 만료로 본다 —
    첫 회전에서 새 세션을 받는다.
    """
    if claims.auth_time is None:
        return claims.expires_at
    return claims.auth_time + session_max_age(web=claims.web)


def session_expired(claims: RefreshClaims, *, now: datetime | None = None) -> bool:
    """최초 로그인으로부터 세션 절대 수명이 지났는가(#3086)."""
    if claims.auth_time is None:
        return False
    return (now or datetime.now(timezone.utc)) >= session_expires_at(claims)


def issue_login_tokens(db: Session, user: User) -> LoginToken:
    """로그인·소셜 로그인 응답 — 토큰 한 쌍과 동의 화면이 필요한지. (#2819)"""
    pair = issue_token_pair(user)
    return LoginToken(
        access_token=pair.access_token,
        refresh_token=pair.refresh_token,
        consent_required=signup_consent.is_required(db, user),
    )


def bump_version(user: User) -> None:
    """세대를 올려 그 전에 발급된 이 계정의 토큰을 모두 무효로 만든다.

    커밋은 호출하는 쪽이 한다 — 비밀번호 교체와 같은 트랜잭션에 묶어야 둘 중
    하나만 반영되는 일이 없다.
    """
    user.token_version = current_version(user) + 1
