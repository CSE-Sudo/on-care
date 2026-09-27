"""Kakao 로그인 검증 — access_token 으로 사용자 정보 조회."""
from __future__ import annotations

import httpx

from app.services.social._response import (
    json_object,
    optional_object,
    optional_str,
    required_id,
)
from app.services.social.base import SocialAuthError, SocialIdentity, SocialVerifier

_USERINFO = "https://kapi.kakao.com/v2/user/me"


class KakaoVerifier(SocialVerifier):
    provider = "kakao"

    async def verify(self, token: str) -> SocialIdentity:
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                resp = await client.get(_USERINFO, headers={"Authorization": f"Bearer {token}"})
        except httpx.HTTPError as exc:
            raise SocialAuthError(f"kakao 요청 실패: {exc}") from exc

        if resp.status_code != 200:
            raise SocialAuthError(f"kakao 토큰 검증 실패({resp.status_code})")

        data = json_object("kakao", resp)
        uid = required_id("kakao", data, "id")

        account = optional_object("kakao", data, "kakao_account")
        profile = optional_object("kakao", account, "profile")
        return SocialIdentity(
            provider="kakao",
            provider_user_id=uid,
            email=optional_str("kakao", account, "email"),
            name=optional_str("kakao", profile, "nickname"),
        )
