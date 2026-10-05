"""소셜 provider 응답을 흉내 내는 테스트 도구 (#1550).

adapter 는 `httpx.AsyncClient` 로 provider 를 부른다. 네트워크 대신
`httpx.MockTransport` 가 정해 둔 응답을 돌려주도록 `AsyncClient` 를 바꿔 끼운다.
adapter 코드를 고치지 않고 실제 파싱 경로를 그대로 탄다.

발급 앱 확인(#3035) 이후의 약속:

- 구글 정상 본문에는 우리 앱의 `aud`·`iss`·`exp` 가 들어 있다(`GOOGLE_CLAIMS`).
- 카카오는 토큰 정보 조회(`/v1/user/access_token_info`)를 먼저 부른다. `respond_json`
  은 그 요청에 우리 앱 `app_id` 와 **본문의 `id` 를 그대로** 담은 토큰 정보를 돌려줘,
  기존 사용자 정보 본문만으로 정상 경로를 탈 수 있게 한다. `respond_raw` 는 두 요청에
  같은 본문을 준다(형식 이상·비 200 은 첫 요청에서 끝난다).
- 네이버·애플 로그인은 제공하지 않는다(#3218). API 로 여는 provider 는 `OPEN_PROVIDERS` 다.
- `use_app_ids(monkeypatch)` 로 허용 앱 설정을 테스트 값으로 고정한다.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Awaitable, Callable

import httpx

from app.core.config import get_settings
from app.services.social.base import SocialIdentity
from app.services.social.google import GoogleVerifier
from app.services.social.kakao import KakaoVerifier

#: 로그·응답·감사 기록에 새면 안 되는 값. 토큰과 응답 본문에 각각 심어 둔다.
SECRET_TOKEN = "tok-secret-1550-do-not-log"
BODY_MARKER = "body-marker-1550-do-not-log"

#: 테스트용 허용 앱 값(#3035). 실제 콘솔 값이 아니다.
TEST_GOOGLE_CLIENT_IDS = ("oncare-ios.apps.googleusercontent.test", "oncare-web.apps.googleusercontent.test")
TEST_KAKAO_APP_ID = "424242"
#: 다른 앱 값 — 토큰 대체 공격 흉내.
OTHER_GOOGLE_CLIENT_ID = "other-app.apps.googleusercontent.test"
OTHER_KAKAO_APP_ID = "999001"
#: 2100-01-01 UTC. 테스트 시계와 상관없이 늘 미래다.
FAR_FUTURE_EXP = "4102444800"

#: 구글 정상 본문의 발급 정보. tokeninfo 는 exp 를 문자열로 준다.
GOOGLE_CLAIMS: dict[str, str] = {
    "aud": TEST_GOOGLE_CLIENT_IDS[0],
    "iss": "https://accounts.google.com",
    "exp": FAR_FUTURE_EXP,
}

KAKAO_TOKEN_INFO_PATH = "/v1/user/access_token_info"


def use_app_ids(monkeypatch, *, google: str | None = None, kakao: str | None = None) -> None:
    """허용 앱 설정을 테스트 값으로 고정한다(설정 파일·환경에 의존하지 않게)."""
    settings = get_settings()
    monkeypatch.setattr(
        settings, "google_client_ids", ",".join(TEST_GOOGLE_CLIENT_IDS) if google is None else google
    )
    monkeypatch.setattr(settings, "kakao_app_id", TEST_KAKAO_APP_ID if kakao is None else kakao)


def kakao_token_info(uid: Any, app_id: Any = TEST_KAKAO_APP_ID) -> dict:
    """카카오 토큰 정보 조회 응답. 카카오는 app_id·id 를 정수로 준다."""
    return {"id": uid, "expires_in": 21599, "app_id": int(app_id) if str(app_id).isdigit() else app_id}


@dataclass(frozen=True)
class ProviderCase:
    name: str
    verifier: type
    #: 사용자 id 값을 받아 정상 형식의 응답 본문(dict)을 만든다.
    valid_body: Callable[[Any], dict]
    #: 필수 id 를 뺀 본문(형식은 정상).
    missing_id_body: dict
    #: 토큰을 받아 adapter 의 파싱 경로를 탄다.
    read: Callable[[str], Awaitable[SocialIdentity]]


PROVIDERS: dict[str, ProviderCase] = {
    "google": ProviderCase(
        name="google",
        verifier=GoogleVerifier,
        valid_body=lambda uid: {**GOOGLE_CLAIMS, "sub": uid, "email": "g@oncare.com", "name": "구글유저"},
        missing_id_body={**GOOGLE_CLAIMS, "email": "g@oncare.com", "name": "구글유저"},
        read=lambda token: GoogleVerifier().verify(token),
    ),
    "kakao": ProviderCase(
        name="kakao",
        verifier=KakaoVerifier,
        valid_body=lambda uid: {
            "id": uid,
            "kakao_account": {"email": "k@oncare.com", "profile": {"nickname": "카카오유저"}},
        },
        missing_id_body={"kakao_account": {"email": "k@oncare.com"}},
        read=lambda token: KakaoVerifier().verify(token),
    ),
}

#: `POST /v1/auth/social/{provider}` 로 로그인이 열린 provider.
OPEN_PROVIDERS: tuple[str, ...] = ("google", "kakao")


#: 200 이지만 JSON 객체가 아닌 본문들: (id, content, content-type)
NON_OBJECT_BODIES: list[tuple[str, bytes, str]] = [
    ("html", f"<html><body>점검 중 {BODY_MARKER}</body></html>".encode(), "text/html; charset=utf-8"),
    ("waf_html", f"<!DOCTYPE html><title>403</title>{BODY_MARKER}".encode(), "text/html"),
    ("broken_json", f'{{"sub": "{BODY_MARKER}", '.encode(), "application/json"),
    ("truncated_json", b'{"id": 12', "application/json"),
    ("plain_text", f"OK {BODY_MARKER}".encode(), "text/plain"),
    ("empty", b"", "application/json"),
    ("whitespace", b"   \n", "application/json"),
    ("list_json", f'["{BODY_MARKER}"]'.encode(), "application/json"),
    ("empty_list_json", b"[]", "application/json"),
    ("string_json", f'"{BODY_MARKER}"'.encode(), "application/json"),
    ("number_json", b"42", "application/json"),
    ("bool_json", b"true", "application/json"),
    ("null_json", b"null", "application/json"),
    ("invalid_utf8", b"\xff\xfe\xfa\x00{", "application/json"),
]


def install_transport(monkeypatch, handler: Callable[[httpx.Request], httpx.Response]) -> list[httpx.Request]:
    """이후 만들어지는 AsyncClient 가 handler 로 응답하게 한다. 받은 요청 목록을 돌려준다."""
    seen: list[httpx.Request] = []
    real = httpx.AsyncClient

    def _record(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return handler(request)

    class _MockedAsyncClient(real):  # type: ignore[misc, valid-type]
        def __init__(self, *args, **kwargs):
            kwargs["transport"] = httpx.MockTransport(_record)
            super().__init__(*args, **kwargs)

    monkeypatch.setattr(httpx, "AsyncClient", _MockedAsyncClient)
    return seen


def respond_raw(monkeypatch, content: bytes, content_type: str, status: int = 200) -> list[httpx.Request]:
    return install_transport(
        monkeypatch,
        lambda _req: httpx.Response(status, content=content, headers={"content-type": content_type}),
    )


def respond_json(monkeypatch, body: Any, status: int = 200) -> list[httpx.Request]:
    """모든 요청에 body 를 준다. 단 카카오 토큰 정보 조회에는 우리 앱 토큰 정보를 준다."""

    def _handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == KAKAO_TOKEN_INFO_PATH and isinstance(body, dict):
            return httpx.Response(status, json=kakao_token_info(body.get("id")))
        return httpx.Response(status, json=body)

    return install_transport(monkeypatch, _handler)


def respond_kakao(
    monkeypatch,
    *,
    token_info: Any,
    user: Any,
    token_info_status: int = 200,
    user_status: int = 200,
) -> list[httpx.Request]:
    """카카오 두 요청에 각각 다른 응답을 준다(bytes 면 그대로, 아니면 JSON)."""

    def _response(status: int, body: Any) -> httpx.Response:
        if isinstance(body, bytes):
            return httpx.Response(status, content=body, headers={"content-type": "text/html"})
        return httpx.Response(status, json=body)

    def _handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == KAKAO_TOKEN_INFO_PATH:
            return _response(token_info_status, token_info)
        return _response(user_status, user)

    return install_transport(monkeypatch, _handler)
