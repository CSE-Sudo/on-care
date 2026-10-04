"""provider 응답 파싱 — 형식이 어긋난 응답을 SocialAuthError 계열로 바꾼다 (#1550).

HTTP 요청 예외만 잡고 `resp.json()`·`.get()` 을 그대로 쓰면, provider 가 200 에 HTML
(점검 페이지·WAF 차단 화면)이나 깨진 JSON, 객체가 아닌 JSON 을 줄 때
JSONDecodeError·AttributeError 가 라우터까지 올라가 500 이 되고 실패 감사 로그도
빠진다. 세 adapter(google/kakao/naver)가 같은 규칙으로 응답을 읽도록 여기 모은다.

실패는 두 갈래로 나눈다.

- **필수 식별자 누락** → `SocialAuthError`(401). 형식은 맞는데 사용자를 특정할 수
  없는 응답이라, 기존 계약대로 인증 실패다.
- **응답 형식 이상** → `SocialProviderResponseError`(502). JSON 이 아니거나, 객체가
  아니거나, 필드 타입이 약속과 다르다. 사용자의 토큰 문제가 아니라 provider 쪽 문제다.

예외 메시지에는 응답 본문과 토큰을 담지 않는다. 메시지는 로그로 흘러갈 수 있다.
"""
from __future__ import annotations

from typing import Any

import httpx

from app.services.social.base import SocialAuthError, SocialProviderResponseError


def json_object(provider: str, resp: httpx.Response) -> dict[str, Any]:
    """응답 본문을 JSON 객체(dict)로 읽는다. 아니면 SocialProviderResponseError."""
    try:
        data = resp.json()
    except ValueError as exc:
        # JSONDecodeError(HTML·깨진 JSON·빈 본문)와 UnicodeDecodeError(깨진 인코딩)
        # 모두 ValueError 다. 원인은 체인으로만 보존하고 본문은 메시지에 넣지 않는다.
        raise SocialProviderResponseError(
            f"{provider} 응답이 JSON 이 아님({type(exc).__name__})"
        ) from exc
    if not isinstance(data, dict):
        raise SocialProviderResponseError(
            f"{provider} 응답이 JSON 객체가 아님({type(data).__name__})"
        )
    return data


def optional_object(provider: str, data: dict[str, Any], key: str) -> dict[str, Any]:
    """선택 하위 객체. 없거나 null 이면 빈 dict, 객체가 아니면 형식 이상."""
    value = data.get(key)
    if value is None:
        return {}
    if not isinstance(value, dict):
        raise SocialProviderResponseError(
            f"{provider} 응답의 {key} 가 객체가 아님({type(value).__name__})"
        )
    return value


def optional_str(provider: str, data: dict[str, Any], key: str) -> str:
    """선택 문자열 필드. 없거나 null 이면 빈 문자열, 문자열이 아니면 형식 이상."""
    value = data.get(key)
    if value is None:
        return ""
    if not isinstance(value, str):
        raise SocialProviderResponseError(
            f"{provider} 응답의 {key} 가 문자열이 아님({type(value).__name__})"
        )
    return value


def optional_flag(provider: str, data: dict[str, Any], key: str) -> bool:
    """선택 참/거짓 필드(#1551). 없거나 null 이면 거짓, 형식이 틀리면 형식 이상.

    google tokeninfo 는 `email_verified` 를 문자열("true"/"false")로, kakao 는 bool 로
    준다. 둘 다 받는다. 그 밖의 값(숫자·"yes"·객체 등)은 참으로 넘겨짚지 않는다.
    """
    value = data.get(key)
    if value is None:
        return False
    if isinstance(value, bool):
        return value
    if isinstance(value, str) and value.strip().lower() in ("true", "false"):
        return value.strip().lower() == "true"
    raise SocialProviderResponseError(
        f"{provider} 응답의 {key} 형식 이상({type(value).__name__})"
    )


def required_id(provider: str, data: dict[str, Any], key: str) -> str:
    """필수 사용자 식별자. 없거나 비면 인증 실패(401), 타입이 틀리면 형식 이상(502).

    kakao 는 id 를 정수로, google·naver 는 문자열로 준다. bool 은 int 의 하위
    타입이라 따로 막는다(`True` 가 사용자 id "True" 가 되면 안 된다).
    """
    value = data.get(key)
    if value is None or value == "":
        raise SocialAuthError(f"{provider} 사용자 id({key}) 없음")
    if isinstance(value, bool) or not isinstance(value, (str, int)):
        raise SocialProviderResponseError(
            f"{provider} 응답의 {key} 타입 이상({type(value).__name__})"
        )
    uid = str(value).strip()
    if not uid:
        raise SocialAuthError(f"{provider} 사용자 id({key}) 없음")
    return uid
