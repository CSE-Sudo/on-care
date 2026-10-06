"""Kakao 로그인 검증 — 토큰 발급 앱 확인 뒤 사용자 정보 조회.

사용자 정보 조회(`/v2/user/me`)는 **유효한 카카오 토큰이면 어느 앱이 받은 것이든**
답한다. 그것만 보면 다른 카카오 앱이 받은 사용자 토큰으로 그 사람의 On-Care 계정에
로그인할 수 있다(#3035). 그래서 먼저 토큰 정보 조회(`/v1/user/access_token_info`)로
발급 앱(`app_id`)이 우리 앱(`KAKAO_APP_ID`)인지 확인하고, 같을 때만 사용자 정보를
읽는다. 두 응답의 사용자 `id` 가 같은지도 본다.

`KAKAO_APP_ID` 가 비면 Google 과 같이 **거부**한다.

웹(회원 웹·트레이너 웹)은 카카오 SDK 가 access_token 을 직접 주지 않는다(#330). 웹은
카카오 로그인 창에서 받은 **인가 코드**를 서버로 보내고, 서버가 우리 앱의 REST API 키
(`KAKAO_LOGIN_REST_API_KEY`, 있으면 `KAKAO_CLIENT_SECRET`)로 토큰을 교환해 access_token 만
돌려준다(`exchange_code`). 앱은 그 토큰으로 모바일과 같은 `POST /auth/social/kakao`·본인
확인을 탄다 — 교환 단계가 로그인 규칙을 따로 갖지 않게 한다. 클라이언트 시크릿은 서버에만 있다.
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
_TOKEN = "https://kauth.kakao.com/oauth/token"


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


async def exchange_code(code: str, redirect_uri: str) -> str:
    """웹 로그인 창이 받은 인가 코드를 access_token 으로 바꾼다. 실패면 SocialAuthError.

    교환은 우리 앱 키로만 되므로, 성공한 토큰은 정의상 우리 앱 앞으로 발급된 것이다. 그래도
    로그인 자체는 이 토큰으로 `KakaoVerifier` 를 다시 탄다(app_id·id 확인이 한 곳에 남게).

    - 설정(`KAKAO_APP_ID`·`KAKAO_LOGIN_REST_API_KEY`)이 비면 카카오로 요청을 보내지 않고 거부한다.
    - 카카오가 코드를 거절하면(만료·재사용·redirect_uri 불일치, 보통 400) 401 갈래다.
    - 200 인데 JSON 이 아니거나 `access_token` 타입이 틀리면 형식 이상(502 갈래)이다.

    코드·토큰·응답 본문은 예외 메시지와 로그에 담지 않는다.
    """
    settings = get_settings()
    if not settings.kakao_app_id_value:
        logger.error("KAKAO_APP_ID 미설정 — 카카오 웹 로그인 코드를 교환하지 않고 거부합니다.")
        raise SocialAuthError("KAKAO_APP_ID 미설정")
    client_id = settings.kakao_login_rest_api_key_value
    if not client_id:
        logger.error("KAKAO_LOGIN_REST_API_KEY 미설정 — 카카오 웹 로그인 코드를 교환할 수 없어 거부합니다.")
        raise SocialAuthError("KAKAO_LOGIN_REST_API_KEY 미설정")

    form = {
        "grant_type": "authorization_code",
        "client_id": client_id,
        "redirect_uri": redirect_uri,
        "code": code,
    }
    secret = settings.kakao_client_secret_value
    if secret:
        form["client_secret"] = secret

    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.post(_TOKEN, data=form)
    except httpx.HTTPError as exc:
        # 예외 문자열에는 요청 정보가 섞일 수 있어 종류만 남긴다.
        raise SocialAuthError(f"kakao 코드 교환 요청 실패({type(exc).__name__})") from exc

    if resp.status_code != 200:
        # 카카오는 거절 사유를 error_code(KOE…)로 준다. 코드 값은 비밀이 아니라 운영자가
        # 콘솔 설정(redirect URI·시크릿) 문제를 찾는 데 필요하므로 그 값만 남긴다.
        logger.warning(
            "kakao 코드 교환 거절(%s, %s)", resp.status_code, _error_code(resp)
        )
        raise SocialAuthError(f"kakao 코드 교환 실패({resp.status_code})")

    data = json_object("kakao", resp)
    token = optional_str("kakao", data, "access_token").strip()
    if not token:
        raise SocialAuthError("kakao 코드 교환 응답에 access_token 없음")
    return token


def _error_code(resp: httpx.Response) -> str:
    """카카오 오류 응답의 `error_code`(KOE…)·`error`. 읽지 못하면 "-"."""
    try:
        data = resp.json()
    except ValueError:
        return "-"
    if not isinstance(data, dict):
        return "-"
    for key in ("error_code", "error"):
        value = data.get(key)
        # 짧은 식별자만 남긴다 — 설명 문구(error_description)는 남기지 않는다.
        if isinstance(value, str) and value.replace("_", "").replace("-", "").isalnum() and len(value) <= 40:
            return value
    return "-"
