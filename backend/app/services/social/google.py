"""Google 로그인 검증 — id_token 을 tokeninfo 로 확인.

운영 규모에서는 Google JWKS 로컬 검증(google-auth)이 권장되나,
MVP 단계에서는 tokeninfo 엔드포인트로 검증한다.

id_token 은 URL 쿼리가 아니라 POST form 본문(`id_token=`)으로 보낸다(#2351).
tokeninfo 는 GET·POST 모두 `id_token` 파라미터를 받는다. 쿼리에 실으면 요청 URL 을
남기는 로그(httpx 요청 로그·프록시·게이트웨이 액세스 로그)에 토큰이 그대로 남는다.

tokeninfo 는 **구글이 서명한 유효한 토큰인지**만 본다. 그 토큰이 **우리 앱 앞으로**
발급되었는지는 서버가 따로 확인해야 한다(#3035). 안 그러면 같은 구글 계정으로 다른
앱에 로그인하며 받은 id_token 을 넣어 그 사람으로 On-Care 에 로그인할 수 있다.

- `aud`(발급 대상 client_id)가 `GOOGLE_CLIENT_IDS` 안에 있어야 한다.
- `iss` 는 `accounts.google.com` 또는 `https://accounts.google.com`.
- `exp` 는 tokeninfo 가 이미 보지만, 응답 값으로 한 번 더 확인한다.
- 허용 목록이 비면 Apple 과 같이 **거부**한다(조용히 통과시키지 않는다).
"""
from __future__ import annotations

import logging

import httpx

from app.core import clock
from app.core.config import get_settings
from app.services.social._response import json_object, optional_str, required_id
from app.services.social.base import (
    SocialAuthError,
    SocialIdentity,
    SocialProviderResponseError,
    SocialVerifier,
)

logger = logging.getLogger(__name__)

_TOKENINFO = "https://oauth2.googleapis.com/tokeninfo"
#: 구글 id_token 의 발급자. 구글 문서가 두 표기를 모두 쓴다.
GOOGLE_ISSUERS = frozenset({"accounts.google.com", "https://accounts.google.com"})


def _allowed_audiences() -> list[str]:
    """허용할 `aud` 목록 — iOS·Android·Web client_id 가 서로 달라 복수를 허용한다."""
    return get_settings().google_client_id_list


def _expiry(data: dict) -> int:
    """`exp`(초 단위 epoch). tokeninfo 는 문자열로 준다. 없으면 401, 숫자가 아니면 502."""
    value = data.get("exp")
    if value is None or value == "":
        raise SocialAuthError("google 토큰 만료 시각(exp) 없음")
    if isinstance(value, bool):
        raise SocialProviderResponseError("google 응답의 exp 타입 이상(bool)")
    if isinstance(value, int):
        return value
    if isinstance(value, str) and value.strip().isdigit():
        return int(value.strip())
    raise SocialProviderResponseError(f"google 응답의 exp 형식 이상({type(value).__name__})")


def check_issued_for_us(data: dict, audiences: list[str]) -> None:
    """tokeninfo 응답이 우리 앱 앞으로 발급된 유효한 토큰인지 본다. 아니면 SocialAuthError.

    어느 검사에서 떨어졌는지는 서버 로그에만 남긴다(토큰·응답 값은 남기지 않는다).
    클라이언트는 라우터가 주는 같은 401 을 받는다.
    """
    aud = optional_str("google", data, "aud")
    if not aud or aud not in audiences:
        logger.warning("google 로그인 거부: 토큰 발급 앱(aud)이 허용 목록에 없음")
        raise SocialAuthError("google 토큰 발급 앱(aud) 불일치")

    iss = optional_str("google", data, "iss")
    if iss not in GOOGLE_ISSUERS:
        logger.warning("google 로그인 거부: 발급자(iss)가 구글이 아님")
        raise SocialAuthError("google 토큰 발급자(iss) 불일치")

    if _expiry(data) <= int(clock.now().timestamp()):
        logger.info("google 로그인 거부: 만료된 토큰")
        raise SocialAuthError("google 토큰 만료")


class GoogleVerifier(SocialVerifier):
    provider = "google"

    async def verify(self, token: str) -> SocialIdentity:
        audiences = _allowed_audiences()
        if not audiences:
            # 설정이 없다고 aud 검사를 건너뛰면 다른 앱용 구글 토큰으로도 로그인이 뚫린다.
            # 외부 호출 없이 바로 막고, 운영자가 원인을 알 수 있게 설정 문제임을 남긴다.
            logger.error("GOOGLE_CLIENT_IDS 미설정 — Google 로그인을 검증할 수 없어 거부합니다.")
            raise SocialAuthError("GOOGLE_CLIENT_IDS 미설정")

        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                resp = await client.post(_TOKENINFO, data={"id_token": token})
        except httpx.HTTPError as exc:
            raise SocialAuthError(f"google 요청 실패: {exc}") from exc

        if resp.status_code != 200:
            raise SocialAuthError(f"google 토큰 검증 실패({resp.status_code})")

        data = json_object("google", resp)
        check_issued_for_us(data, audiences)
        uid = required_id("google", data, "sub")

        return SocialIdentity(
            provider="google",
            provider_user_id=uid,
            email=optional_str("google", data, "email"),
            name=optional_str("google", data, "name"),
        )
