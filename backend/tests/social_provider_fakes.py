"""소셜 provider 응답을 흉내 내는 테스트 도구 (#1550).

adapter 는 `httpx.AsyncClient` 로 provider 를 부른다. 네트워크 대신
`httpx.MockTransport` 가 정해 둔 응답을 돌려주도록 `AsyncClient` 를 바꿔 끼운다.
adapter 코드를 고치지 않고 실제 파싱 경로를 그대로 탄다.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Callable

import httpx

from app.services.social.google import GoogleVerifier
from app.services.social.kakao import KakaoVerifier
from app.services.social.naver import NaverVerifier

#: 로그·응답·감사 기록에 새면 안 되는 값. 토큰과 응답 본문에 각각 심어 둔다.
SECRET_TOKEN = "tok-secret-1550-do-not-log"
BODY_MARKER = "body-marker-1550-do-not-log"


@dataclass(frozen=True)
class ProviderCase:
    name: str
    verifier: type
    #: 사용자 id 값을 받아 정상 형식의 응답 본문(dict)을 만든다.
    valid_body: Callable[[Any], dict]
    #: 필수 id 를 뺀 본문(형식은 정상).
    missing_id_body: dict


PROVIDERS: dict[str, ProviderCase] = {
    "google": ProviderCase(
        name="google",
        verifier=GoogleVerifier,
        valid_body=lambda uid: {"sub": uid, "email": "g@oncare.com", "name": "구글유저"},
        missing_id_body={"email": "g@oncare.com", "name": "구글유저"},
    ),
    "kakao": ProviderCase(
        name="kakao",
        verifier=KakaoVerifier,
        valid_body=lambda uid: {
            "id": uid,
            "kakao_account": {"email": "k@oncare.com", "profile": {"nickname": "카카오유저"}},
        },
        missing_id_body={"kakao_account": {"email": "k@oncare.com"}},
    ),
    "naver": ProviderCase(
        name="naver",
        verifier=NaverVerifier,
        valid_body=lambda uid: {
            "resultcode": "00",
            "message": "success",
            "response": {"id": uid, "email": "n@oncare.com", "name": "네이버유저"},
        },
        missing_id_body={"resultcode": "00", "message": "success", "response": {"email": "n@oncare.com"}},
    ),
}


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
    return install_transport(monkeypatch, lambda _req: httpx.Response(status, json=body))
