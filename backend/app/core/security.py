"""비밀번호 해싱 + JWT 토큰."""
from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

import jwt
from pwdlib import PasswordHash
from pwdlib.hashers.bcrypt import BcryptHasher

from app.core.config import get_settings

settings = get_settings()
_password_hash = PasswordHash((BcryptHasher(),))


def hash_password(plain: str) -> str:
    return _password_hash.hash(plain)


#: bcrypt 가 보는 최대 길이(UTF-8 바이트). 새 비밀번호의 상한도 이 값이다
#: (`password_policy.PASSWORD_MAX_BYTES`, #1555).
BCRYPT_MAX_BYTES = 72


def verify_password(plain: str, hashed: str) -> bool:
    if not hashed:
        return False
    # bcrypt 5 는 72바이트를 넘는 값을 자르지 않고 ValueError 로 거절한다. 그대로
    # 두면 긴 값을 친 로그인이 500 이 된다. 새 비밀번호는 72바이트까지만 받으므로
    # (#1555) 그보다 긴 값은 어떤 저장된 비밀번호와도 같을 수 없다 — 틀린
    # 비밀번호와 똑같이 다룬다.
    if len(plain.encode("utf-8")) > BCRYPT_MAX_BYTES:
        return False
    return _password_hash.verify(plain, hashed)


def _encode(
    subject: str, token_type: str, ttl: timedelta, *, jti: str | None = None
) -> str:
    now = datetime.now(timezone.utc)
    payload = {"sub": subject, "type": token_type, "iat": now, "exp": now + ttl}
    if jti is not None:
        payload["jti"] = jti
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def create_access_token(subject: str) -> str:
    return _encode(subject, "access", timedelta(minutes=settings.access_token_expire_minutes))


def create_refresh_token(subject: str) -> str:
    """폐기 가능한 refresh 토큰을 만든다.

    `jti` 는 이 토큰 한 장의 이름이다. 로그아웃과 회전이 "이 토큰은 이제 쓸 수
    없다"고 남길 대상이 있어야 서버가 세션을 끊을 수 있다(#966).
    """
    return _encode(
        subject,
        "refresh",
        timedelta(days=settings.refresh_token_expire_days),
        jti=uuid.uuid4().hex,
    )


def decode_access_token(token: str) -> str:
    payload = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
    # refresh 토큰을 액세스로 오용하는 것을 차단 (구버전 토큰은 type 이 없어 허용)
    if payload.get("type") == "refresh":
        raise jwt.InvalidTokenError("refresh 토큰은 액세스로 사용할 수 없습니다.")
    sub = payload.get("sub")
    if sub is None:
        raise jwt.InvalidTokenError("sub 없음")
    return str(sub)


@dataclass(frozen=True)
class RefreshClaims:
    """refresh 토큰에서 폐기 판단에 필요한 값만 뽑은 것."""

    subject: str
    jti: str
    expires_at: datetime


def decode_refresh_claims(token: str) -> RefreshClaims:
    """refresh 토큰을 검증하고 `sub`·`jti`·`exp` 를 돌려준다.

    `jti` 가 없는 토큰(#966 이전에 발급된 것)은 거부한다. 폐기 표에 적을 이름이
    없어 **일회용으로 만들 수 없는** 토큰이라, 받아 주면 로그아웃도 재사용 탐지도
    그 토큰만 비껴간다. 거부의 대가는 한 번의 재로그인이다.
    """
    payload = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
    if payload.get("type") != "refresh":
        raise jwt.InvalidTokenError("refresh 토큰이 아닙니다.")
    sub = payload.get("sub")
    if sub is None:
        raise jwt.InvalidTokenError("sub 없음")
    jti = payload.get("jti")
    if not jti:
        raise jwt.InvalidTokenError("jti 없음 — 폐기할 수 없는 토큰")
    exp = payload.get("exp")
    if exp is None:
        raise jwt.InvalidTokenError("exp 없음")
    return RefreshClaims(
        subject=str(sub),
        jti=str(jti),
        expires_at=datetime.fromtimestamp(float(exp), tz=timezone.utc),
    )
