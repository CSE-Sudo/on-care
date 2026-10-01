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


#: 토큰에 실리는 계정 토큰 세대 클레임 이름(#2766).
#:
#: 사용자 행의 `token_version` 을 발급 시점에 그대로 적는다. 비밀번호를 바꾸면 행의
#: 값이 올라가 그 전에 발급된 토큰(접근·refresh 모두)이 한꺼번에 무효가 된다.
#: `iat` 와 변경 시각을 비교하는 방식은 `iat` 가 초 단위라 변경 직후 같은 초에
#: 새로 발급한 토큰까지 거부하거나 그 초의 옛 토큰을 살리는 경계 문제가 있어,
#: 정수 세대를 쓴다. 클레임이 없는 토큰(이 변경 전에 발급된 것)은 0세대로 본다 —
#: 모든 계정이 0에서 시작하므로 배포만으로 기존 세션이 끊기지 않는다.
TOKEN_VERSION_CLAIM = "tv"

#: 웹 클라이언트에 발급한 refresh 토큰에 붙는 클레임(#2828). 값은 ``"web"``.
#:
#: 회전 때 이 클레임을 보고 새 토큰도 웹 수명으로 낸다 — 요청 헤더만 보면 헤더를 빼고
#: 회전해 원래 수명(30일)을 다시 얻을 수 있다.
CLIENT_CLAIM = "cli"


def _encode(
    subject: str,
    token_type: str,
    ttl: timedelta,
    *,
    jti: str | None = None,
    token_version: int = 0,
    client: str | None = None,
) -> str:
    now = datetime.now(timezone.utc)
    payload = {
        "sub": subject,
        "type": token_type,
        "iat": now,
        "exp": now + ttl,
        TOKEN_VERSION_CLAIM: token_version,
    }
    if jti is not None:
        payload["jti"] = jti
    if client is not None:
        payload[CLIENT_CLAIM] = client
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def _token_version_of(payload: dict) -> int:
    """클레임의 토큰 세대. 없으면 0, 정수가 아니면 위조·손상으로 보고 거부한다."""
    value = payload.get(TOKEN_VERSION_CLAIM, 0)
    # bool 은 int 의 하위형이라 따로 막는다 — `true` 가 1세대로 통하면 안 된다.
    if isinstance(value, bool) or not isinstance(value, int):
        raise jwt.InvalidTokenError("토큰 세대 형식 오류")
    return value


def create_access_token(subject: str, *, token_version: int = 0) -> str:
    return _encode(
        subject,
        "access",
        timedelta(minutes=settings.access_token_expire_minutes),
        token_version=token_version,
    )


def refresh_token_ttl(*, web: bool = False) -> timedelta:
    """refresh 토큰 수명. 웹 클라이언트는 더 짧다(#2828)."""
    days = (
        settings.web_refresh_token_expire_days
        if web
        else settings.refresh_token_expire_days
    )
    return timedelta(days=days)


def create_refresh_token(
    subject: str, *, token_version: int = 0, web: bool = False
) -> str:
    """폐기 가능한 refresh 토큰을 만든다.

    `jti` 는 이 토큰 한 장의 이름이다. 로그아웃과 회전이 "이 토큰은 이제 쓸 수
    없다"고 남길 대상이 있어야 서버가 세션을 끊을 수 있다(#966).
    `token_version` 은 계정 단위로 한꺼번에 끊는 기준이다(#2766).
    `web` 이면 웹 수명으로 내고 :data:`CLIENT_CLAIM` 을 붙인다(#2828).
    """
    return _encode(
        subject,
        "refresh",
        refresh_token_ttl(web=web),
        jti=uuid.uuid4().hex,
        token_version=token_version,
        client="web" if web else None,
    )


@dataclass(frozen=True)
class AccessClaims:
    """접근 토큰에서 사용자 확인에 필요한 값만 뽑은 것."""

    subject: str
    token_version: int


def decode_access_claims(token: str) -> AccessClaims:
    """접근 토큰을 검증하고 `sub`·토큰 세대를 돌려준다.

    토큰 세대가 사용자 행의 값과 같은지는 호출하는 쪽(`api/deps.py`)이 본다 —
    여기서는 DB 를 모른다.
    """
    payload = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
    # refresh 토큰을 액세스로 오용하는 것을 차단 (구버전 토큰은 type 이 없어 허용)
    if payload.get("type") == "refresh":
        raise jwt.InvalidTokenError("refresh 토큰은 액세스로 사용할 수 없습니다.")
    sub = payload.get("sub")
    if sub is None:
        raise jwt.InvalidTokenError("sub 없음")
    return AccessClaims(subject=str(sub), token_version=_token_version_of(payload))


def decode_access_token(token: str) -> str:
    """접근 토큰의 `sub` 만 필요할 때. 세대 확인이 필요하면 `decode_access_claims`."""
    return decode_access_claims(token).subject


@dataclass(frozen=True)
class RefreshClaims:
    """refresh 토큰에서 폐기 판단에 필요한 값만 뽑은 것."""

    subject: str
    jti: str
    expires_at: datetime
    token_version: int = 0
    #: 웹 클라이언트에 발급된 토큰인가(#2828). 회전도 웹 수명으로 이어 간다.
    web: bool = False


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
        token_version=_token_version_of(payload),
        web=payload.get(CLIENT_CLAIM) == "web",
    )
