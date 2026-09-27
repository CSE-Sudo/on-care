"""Naver 로그인 검증 — access_token 으로 프로필 조회."""
from __future__ import annotations

import httpx

from app.services.social._response import (
    json_object,
    optional_object,
    optional_str,
    required_id,
)
from app.services.social.base import SocialAuthError, SocialIdentity, SocialVerifier

_USERINFO = "https://openapi.naver.com/v1/nid/me"


class NaverVerifier(SocialVerifier):
    provider = "naver"

    async def verify(self, token: str) -> SocialIdentity:
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                resp = await client.get(_USERINFO, headers={"Authorization": f"Bearer {token}"})
        except httpx.HTTPError as exc:
            raise SocialAuthError(f"naver 요청 실패: {exc}") from exc

        if resp.status_code != 200:
            raise SocialAuthError(f"naver 토큰 검증 실패({resp.status_code})")

        body = json_object("naver", resp)
        profile = optional_object("naver", body, "response")
        uid = required_id("naver", profile, "id")

        return SocialIdentity(
            provider="naver",
            provider_user_id=uid,
            email=optional_str("naver", profile, "email"),
            name=optional_str("naver", profile, "name")
            or optional_str("naver", profile, "nickname"),
        )
