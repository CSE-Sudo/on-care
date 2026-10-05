"""Kakao 로그인 검증 — 토큰 발급 앱 확인 뒤 사용자 정보 조회.

사용자 정보 조회(`/v2/user/me`)는 **유효한 카카오 토큰이면 어느 앱이 받은 것이든**
답한다. 그것만 보면 다른 카카오 앱이 받은 사용자 토큰으로 그 사람의 On-Care 계정에
로그인할 수 있다(#3035). 그래서 먼저 토큰 정보 조회(`/v1/user/access_token_info`)로
발급 앱(`app_id`)이 우리 앱(`KAKAO_APP_ID`)인지 확인하고, 같을 때만 사용자 정보를
읽는다. 두 응답의 사용자 `id` 가 같은지도 본다.

`KAKAO_APP_ID` 가 비면 Google 과 같이 **거부**한다.
"""
from __future__ import annotations

import logging

import httpx

from app.core.config import get_settings
from app.services.social._response import (
    json_object,
    optional_object,
    optional_str,
    required_id,
)
from app.services.social.base import (
    SocialAuthError,
    SocialIdentity,
    SocialProviderResponseError,
    SocialVerifier,
)

logger = logging.getLogger(__name__)

_TOKEN_INFO = "https://kapi.kakao.com/v1/user/access_token_info"
_USERINFO = "https://kapi.kakao.com/v2/user/me"


def _app_id(data: dict) -> str:
    """토큰 정보의 `app_id`(카카오는 정수로 준다). 없으면 401, 타입이 틀리면 502."""
    value = data.get("app_id")
    if value is None or value == "":
        raise SocialAuthError("kakao 토큰 발급 앱(app_id) 없음")
    if isinstance(value, bool) or not isinstance(value, (int, str)):
        raise SocialProviderResponseError(
            f"kakao 응답의 app_id 타입 이상({type(value).__name__})"
        )
    return str(value).strip()


class KakaoVerifier(SocialVerifier):
    provider = "kakao"

    async def verify(self, token: str) -> SocialIdentity:
        app_id = get_settings().kakao_app_id_value
        if not app_id:
            logger.error("KAKAO_APP_ID 미설정 — 카카오 로그인을 검증할 수 없어 거부합니다.")
            raise SocialAuthError("KAKAO_APP_ID 미설정")

        headers = {"Authorization": f"Bearer {token}"}
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                info_resp = await client.get(_TOKEN_INFO, headers=headers)
                if info_resp.status_code != 200:
                    raise SocialAuthError(
                        f"kakao 토큰 정보 조회 실패({info_resp.status_code})"
                    )
                info = json_object("kakao", info_resp)
                if _app_id(info) != app_id:
                    # 어느 앱인지(값)는 남기지 않는다. 불일치 사실만 서버 로그에.
                    logger.warning("kakao 로그인 거부: 토큰 발급 앱(app_id)이 우리 앱이 아님")
                    raise SocialAuthError("kakao 토큰 발급 앱(app_id) 불일치")
                token_uid = required_id("kakao", info, "id")

                resp = await client.get(_USERINFO, headers=headers)
        except httpx.HTTPError as exc:
            raise SocialAuthError(f"kakao 요청 실패: {exc}") from exc

        if resp.status_code != 200:
            raise SocialAuthError(f"kakao 토큰 검증 실패({resp.status_code})")

        data = json_object("kakao", resp)
        uid = required_id("kakao", data, "id")
        if uid != token_uid:
            logger.warning("kakao 로그인 거부: 토큰 정보와 사용자 정보의 id 불일치")
            raise SocialAuthError("kakao 사용자 id 불일치")

        account = optional_object("kakao", data, "kakao_account")
        profile = optional_object("kakao", account, "profile")
        return SocialIdentity(
            provider="kakao",
            provider_user_id=uid,
            email=optional_str("kakao", account, "email"),
            name=optional_str("kakao", profile, "nickname"),
        )
