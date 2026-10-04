"""Apple 로그인 검증 — identity_token(JWT) 을 Apple 공개키로 서명 검증.

카카오/구글과 달리 Apple 은 토큰을 확인해 주는 조회 엔드포인트가 없다. 클라이언트가
받은 identity_token 자체가 JWT 이고, 서버는 이걸 Apple 의 공개키(JWKS)로 **직접
검증**해야 한다. 그래서 이 파일만 다른 provider 와 구조가 다르다.

검증 항목(하나라도 빠지면 우회가 생긴다):
- 서명: JWKS 의 공개키로. `kid` 로 키를 고르고, Apple 이 키를 회전해도 따라가야 한다.
- `iss`: 반드시 https://appleid.apple.com
- `aud`: **우리 앱의 client_id**. 이걸 확인하지 않으면 다른 앱용으로 발급된 유효한
  Apple 토큰으로도 로그인이 뚫린다.
- `exp`: 만료. PyJWT 가 기본으로 검사한다.

JWKS 는 `PyJWKClient` 가 캐싱하고 키 회전 시 다시 가져온다. 매 로그인마다 Apple 에
네트워크 요청을 보내지 않도록 클라이언트를 모듈 수준에서 재사용한다.
"""
from __future__ import annotations

import asyncio
import logging
from functools import lru_cache

import jwt
from jwt import PyJWKClient

from app.core.config import get_settings
from app.services.social.base import SocialAuthError, SocialIdentity, SocialVerifier

logger = logging.getLogger(__name__)

APPLE_ISSUER = "https://appleid.apple.com"
APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys"

#: JWKS 캐시 수명(초). Apple 은 키를 자주 바꾸지 않지만, 회전 후에도 낡은 키를 계속
#: 쓰면 정상 로그인이 실패한다. PyJWKClient 는 캐시에 없는 kid 를 만나면 다시 받아온다.
_JWKS_CACHE_LIFESPAN = 600

#: JWKS 조회 HTTP 타임아웃(초). 기본값 30 초는 로그인 한 번이 30 초를 기다린다는 뜻이라
#: 너무 길다. 스레드로 넘겨 이벤트 루프는 막히지 않지만, 그 스레드도 오래 잡혀 있으면
#: 안 되므로 짧게 끊고 실패시킨다(다른 provider 의 httpx timeout=5.0 과 맞춤).
_JWKS_TIMEOUT_SEC = 5


@lru_cache
def _jwk_client() -> PyJWKClient:
    """JWKS 클라이언트(프로세스당 1개).

    매 로그인마다 새로 만들면 캐시가 의미를 잃고 Apple 에 매번 요청이 나간다.
    """
    return PyJWKClient(
        APPLE_JWKS_URL,
        cache_keys=True,
        lifespan=_JWKS_CACHE_LIFESPAN,
        timeout=_JWKS_TIMEOUT_SEC,
    )


def _allowed_audiences() -> list[str]:
    """허용할 `aud` 목록.

    iOS 앱은 번들 ID, 웹은 Service ID 로 서로 다른 aud 를 받기 때문에 복수를 허용한다.
    """
    return get_settings().apple_client_id_list


def _claim_true(value: object) -> bool:
    """Apple 의 참/거짓 클레임(#1551). 문자열("true")·bool 둘 다 온다.

    Apple 문서는 `email_verified` 를 "string or Boolean" 으로 적는다. 그 밖의 값은
    참으로 넘겨짚지 않는다(서명이 맞는 토큰이므로 형식 이상으로 막지는 않는다).
    """
    if isinstance(value, bool):
        return value
    return isinstance(value, str) and value.strip().lower() == "true"


class AppleVerifier(SocialVerifier):
    provider = "apple"

    async def verify(self, token: str) -> SocialIdentity:
        audiences = _allowed_audiences()
        if not audiences:
            # 설정이 없다고 검증을 건너뛰면 안 된다. aud 를 확인하지 않는 순간 다른
            # 앱용 Apple 토큰으로도 로그인이 뚫리므로, 조용히 통과시키는 대신 막는다.
            # (다른 provider 는 키가 없으면 폴백하지만, 인증은 폴백 대상이 아니다.)
            #
            # 클라이언트에는 라우터가 일반화된 401 을 주므로, 운영자가 원인을 알 수
            # 있도록 여기서 설정 문제임을 로그로 남긴다 — 안 그러면 "토큰이 잘못됐나"
            # 를 한참 들여다보게 된다.
            logger.error(
                "APPLE_CLIENT_IDS 미설정 — Apple 로그인을 검증할 수 없어 거부합니다."
            )
            raise SocialAuthError("APPLE_CLIENT_IDS 미설정")

        try:
            # PyJWKClient 는 urllib 기반이라 **동기 블로킹**이다(다른 provider 는
            # httpx.AsyncClient 라 이 문제가 없다). 캐시가 비었거나 Apple 이 키를
            # 회전한 직후에는 여기서 실제 HTTP 요청이 나가는데, async 핸들러에서
            # 그대로 호출하면 그동안 **이벤트 루프 전체가 멈춰** 무관한 요청까지
            # 함께 지연된다. 스레드로 넘겨 루프를 놓아 준다.
            signing_key = await asyncio.to_thread(
                _jwk_client().get_signing_key_from_jwt, token
            )
        except Exception as exc:  # noqa: BLE001 — JWKS 조회 실패·kid 불일치 등
            raise SocialAuthError(f"apple 공개키 조회 실패: {exc}") from exc

        try:
            claims = jwt.decode(
                token,
                signing_key.key,
                algorithms=["RS256"],
                audience=audiences,
                issuer=APPLE_ISSUER,
                options={"require": ["exp", "iss", "aud", "sub"]},
            )
        except jwt.InvalidTokenError as exc:
            # 만료·aud 불일치·서명 위조 모두 여기로 온다. 원인은 로그로만 남기고
            # 클라이언트에는 라우터가 일반화된 401 을 준다.
            raise SocialAuthError(f"apple 토큰 검증 실패: {exc}") from exc

        uid = str(claims.get("sub") or "")
        if not uid:
            raise SocialAuthError("apple 사용자 id(sub) 없음")

        # Apple 은 이름을 토큰에 담지 않는다. 최초 로그인 때 클라이언트가 별도로 한 번만
        # 받으므로, 서버는 이름을 비워 두고 이메일만 취한다.
        email = str(claims.get("email") or "")
        return SocialIdentity(
            provider="apple",
            provider_user_id=uid,
            email=email,
            name="",
            email_verified=bool(email) and _claim_true(claims.get("email_verified")),
        )
