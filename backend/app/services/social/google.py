"""Google 로그인 검증 — id_token 을 tokeninfo 로 확인.

운영 규모에서는 Google JWKS 로컬 검증(google-auth)이 권장되나,
MVP 단계에서는 tokeninfo 엔드포인트로 검증한다.

id_token 은 URL 쿼리가 아니라 POST form 본문(`id_token=`)으로 보낸다(#2351).
tokeninfo 는 GET·POST 모두 `id_token` 파라미터를 받는다. 쿼리에 실으면 요청 URL 을
남기는 로그(httpx 요청 로그·프록시·게이트웨이 액세스 로그)에 토큰이 그대로 남는다.
"""
from __future__ import annotations

import httpx

from app.services.social._response import json_object, optional_str, required_id
from app.services.social.base import SocialAuthError, SocialIdentity, SocialVerifier

_TOKENINFO = "https://oauth2.googleapis.com/tokeninfo"


class GoogleVerifier(SocialVerifier):
    provider = "google"

    async def verify(self, token: str) -> SocialIdentity:
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                resp = await client.post(_TOKENINFO, data={"id_token": token})
        except httpx.HTTPError as exc:
            raise SocialAuthError(f"google 요청 실패: {exc}") from exc

        if resp.status_code != 200:
            raise SocialAuthError(f"google 토큰 검증 실패({resp.status_code})")

        data = json_object("google", resp)
        uid = required_id("google", data, "sub")

        return SocialIdentity(
            provider="google",
            provider_user_id=uid,
            email=optional_str("google", data, "email"),
            name=optional_str("google", data, "name"),
        )
