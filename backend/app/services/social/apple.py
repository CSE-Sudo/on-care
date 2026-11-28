"""Apple 로그인 검증 — identity_token(JWT) 을 Apple 공개키로 서명 검증 (#3499).

카카오/구글과 달리 Apple 은 토큰을 확인해 주는 조회 엔드포인트가 없다. 앱이 받은
identity_token 자체가 JWT 이고, 서버는 이걸 Apple 의 공개키(JWKS)로 **직접 검증**해야
한다. 그래서 이 파일만 다른 provider 와 구조가 다르다.

검증 항목(하나라도 빠지면 우회가 생긴다):
- 서명: JWKS 의 공개키로. `kid` 로 키를 고르고, Apple 이 키를 회전해도 따라가야 한다.
- `iss`: 반드시 https://appleid.apple.com
- `aud`: **우리 앱의 client_id**(iOS 는 번들 ID). 이걸 확인하지 않으면 다른 앱용으로
  발급된 유효한 Apple 토큰으로도 로그인이 뚫린다.
- `exp`: 만료. PyJWT 가 기본으로 검사한다.

이메일은 토큰의 `email_verified` 가 참일 때만 확인된 것으로 넘긴다(#1551). Apple 은
이 값을 불리언이나 문자열 `"true"` 로 준다. 이메일 가리기를 고른 회원은
`@privaterelay.appleid.com` 주소가 오는데, 이 주소도 Apple 이 전달을 보장하는
확인된 주소다.

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
    """허용할 `aud` 목록(iOS 앱은 번들 ID)."""
    return get_settings().apple_client_id_list


def _flag(value: object) -> bool:
    """Apple 이 불리언이나 문자열(`"true"`)로 주는 참거짓 클레임."""
    if isinstance(value, bool):
        return value
    return isinstance(value, str) and value.strip().lower() == "true"


class AppleVerifier(SocialVerifier):
    provider = "apple"

    async def verify(self, token: str) -> SocialIdentity:
        audiences = _allowed_audiences()
        if not audiences:
            # 설정이 없다고 aud 검사를 건너뛰면 다른 앱용 Apple 토큰으로도 로그인이
            # 뚫린다. 외부 호출 없이 바로 막고, 운영자가 원인을 알 수 있게 설정 문제임을
            # 남긴다 — 클라이언트는 라우터가 주는 같은 401 을 받는다.
            logger.error("APPLE_CLIENT_IDS 미설정 — Apple 로그인을 검증할 수 없어 거부합니다.")
            raise SocialAuthError("APPLE_CLIENT_IDS 미설정")

        try:
            # PyJWKClient 는 urllib 기반이라 **동기 블로킹**이다. 캐시가 비었거나 Apple 이
            # 키를 회전한 직후에는 여기서 실제 HTTP 요청이 나가는데, async 핸들러에서
            # 그대로 부르면 그동안 이벤트 루프 전체가 멈춘다. 스레드로 넘긴다.
            signing_key = await asyncio.to_thread(
                _jwk_client().get_signing_key_from_jwt, token
            )
        except Exception as exc:  # noqa: BLE001 — JWKS 조회 실패·kid 불일치·깨진 토큰 등
            raise SocialAuthError(f"apple 공개키 조회 실패: {type(exc).__name__}") from exc

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
            # 만료·aud 불일치·서명 위조 모두 여기로 온다. 어느 검사인지는 서버 로그에만
            # 남기고(토큰 값은 남기지 않는다) 클라이언트에는 같은 401 을 준다.
            logger.warning("apple 로그인 거부: %s", type(exc).__name__)
            raise SocialAuthError(f"apple 토큰 검증 실패: {type(exc).__name__}") from exc

        uid = str(claims.get("sub") or "")
        if not uid:
            raise SocialAuthError("apple 사용자 id(sub) 없음")

        email = str(claims.get("email") or "")
        # Apple 은 이름을 토큰에 담지 않는다. 첫 로그인 때 앱에만 한 번 주므로, 앱이
        # 로그인 요청의 `name` 으로 따로 보낸다(`api/v1/social.py`).
        return SocialIdentity(
            provider="apple",
            provider_user_id=uid,
            email=email,
            name="",
            email_verified=bool(email) and _flag(claims.get("email_verified")),
        )
