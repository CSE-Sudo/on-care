"""Naver 로그인 — 발급 앱을 확인할 수단이 갖춰질 때까지 닫아 둔다 (#3035).

네이버 프로필 API(`/v1/nid/me`)는 **유효한 네이버 토큰이면 어느 앱이 받은 것이든**
프로필을 돌려주고, 그 토큰을 발급한 client 를 알려 주지 않는다. 앱이 보낸
access_token 만으로는 "우리 앱 앞으로 발급된 토큰인가"를 서버가 확인할 수 없어,
그대로 열어 두면 다른 네이버 앱이 받은 사용자 토큰으로 그 사람의 On-Care 계정에
로그인된다.

확인할 수 있는 방법은 **서버 측 코드 교환**이다. 앱이 인가 코드(+state)를 보내고,
서버가 우리 `client_id`·`client_secret` 으로 토큰을 교환하면 그 토큰은 정의상 우리
앱 것이다. 그 흐름(앱이 코드를 보내도록 바꾸는 일 포함, #330)이 들어오기 전까지
`verify` 는 `NotImplementedError` 로 끝나고 라우터는 501 로 답한다 — 검증하지 못하는
provider 를 열어 두는 것보다 낫다.

`read_profile` 은 코드 교환으로 얻은 **우리 앱의** access_token 으로 프로필을 읽는
뒷부분이다. 교환이 들어오면 그대로 이어 쓴다.
"""
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
        # 앱이 보낸 access_token 은 발급 앱을 확인할 수 없어 받지 않는다. 외부 호출도
        # 하지 않는다(토큰을 네이버로 보낼 이유가 없다).
        raise NotImplementedError("naver 로그인은 서버 측 코드 교환 전까지 닫혀 있음")

    async def read_profile(self, access_token: str) -> SocialIdentity:
        """우리 앱이 교환해 받은 access_token 으로 프로필을 읽는다."""
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                resp = await client.get(
                    _USERINFO, headers={"Authorization": f"Bearer {access_token}"}
                )
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
