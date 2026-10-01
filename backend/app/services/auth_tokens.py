"""계정 토큰 발급·세대 관리(#2766).

로그인·회전·소셜 로그인·비밀번호 변경이 모두 같은 방식으로 토큰을 내도록 한 곳에
모은다. 발급하는 토큰에는 사용자 행의 `token_version` 을 싣고, 검증하는 쪽
(`api/deps.py`, `/auth/refresh`)은 `is_current` 로 같은 세대인지 본다.
"""
from __future__ import annotations

from sqlalchemy.orm import Session

from app.core.security import create_access_token, create_refresh_token
from app.models.models import User
from app.schemas.user import LoginToken, Token
from app.services import signup_consent


def current_version(user: User) -> int:
    """사용자 행의 토큰 세대. 아직 flush 전인 새 객체는 0으로 본다."""
    return user.token_version or 0


def is_current(user: User, token_version: int) -> bool:
    """토큰에 실린 세대가 지금 계정 세대와 같은가."""
    return token_version == current_version(user)


def issue_token_pair(user: User) -> Token:
    """지금 세대로 접근·refresh 토큰 한 쌍을 만든다."""
    version = current_version(user)
    return Token(
        access_token=create_access_token(user.id, token_version=version),
        refresh_token=create_refresh_token(user.id, token_version=version),
    )


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
