"""소셜 provider 비정상 응답 — adapter 단위 (#1550).

google/kakao/naver adapter 가 200 인데 약속과 다른 응답(HTML·깨진 JSON·객체가 아닌
JSON·필드 타입 이상·빈 본문)을 받으면 JSONDecodeError·AttributeError 가 새지 않고
SocialAuthError 계열로 바뀌는지 본다.

- 필수 id 누락 → `SocialAuthError`(형식 이상 아님) → 라우터 401
- 형식 이상 → `SocialProviderResponseError` → 라우터 502

DB 가 필요 없다. 네트워크 대신 `httpx.MockTransport` 로 응답을 흉내 낸다.
"""
from __future__ import annotations

import asyncio
import logging
from urllib.parse import parse_qs

import httpx
import pytest

from app.services.social import _response
from app.services.social.base import (
    SocialAuthError,
    SocialIdentity,
    SocialProviderResponseError,
)
from tests.social_provider_fakes import (
    BODY_MARKER,
    NON_OBJECT_BODIES,
    PROVIDERS,
    SECRET_TOKEN,
    respond_json,
    respond_raw,
)

PROVIDER_NAMES = sorted(PROVIDERS)


def _verify(provider: str, token: str = SECRET_TOKEN) -> SocialIdentity:
    return asyncio.run(PROVIDERS[provider].verifier().verify(token))


def _assert_clean(exc: BaseException) -> None:
    """예외 메시지에 토큰·응답 본문이 담기지 않았다."""
    text = str(exc)
    assert SECRET_TOKEN not in text
    assert BODY_MARKER not in text


# ── 정상 응답 (회귀) ──────────────────────────────────────────────


@pytest.mark.parametrize("provider", PROVIDER_NAMES)
def test_valid_response_still_parses(monkeypatch, provider):
    respond_json(monkeypatch, PROVIDERS[provider].valid_body("uid-1550"))
    identity = _verify(provider)
    assert identity.provider == provider
    assert identity.provider_user_id == "uid-1550"
    assert identity.email.endswith("@oncare.com")
    assert identity.name


def test_kakao_integer_id_becomes_string(monkeypatch):
    respond_json(monkeypatch, PROVIDERS["kakao"].valid_body(4815162342))
    assert _verify("kakao").provider_user_id == "4815162342"


def test_kakao_without_account_keeps_empty_profile(monkeypatch):
    respond_json(monkeypatch, {"id": 7})
    identity = _verify("kakao")
    assert (identity.provider_user_id, identity.email, identity.name) == ("7", "", "")


def test_kakao_null_account_and_profile_are_treated_as_absent(monkeypatch):
    respond_json(monkeypatch, {"id": 7, "kakao_account": {"email": None, "profile": None}})
    identity = _verify("kakao")
    assert (identity.email, identity.name) == ("", "")


def test_naver_name_falls_back_to_nickname(monkeypatch):
    respond_json(monkeypatch, {"response": {"id": "n-1", "nickname": "닉네임"}})
    assert _verify("naver").name == "닉네임"


def test_naver_empty_name_falls_back_to_nickname(monkeypatch):
    respond_json(monkeypatch, {"response": {"id": "n-1", "name": "", "nickname": "닉네임"}})
    assert _verify("naver").name == "닉네임"


def test_google_optional_fields_absent(monkeypatch):
    respond_json(monkeypatch, {"sub": "g-1"})
    identity = _verify("google")
    assert (identity.email, identity.name) == ("", "")


@pytest.mark.parametrize("provider", PROVIDER_NAMES)
def test_id_is_trimmed(monkeypatch, provider):
    respond_json(monkeypatch, PROVIDERS[provider].valid_body("  uid-trim  "))
    assert _verify(provider).provider_user_id == "uid-trim"


@pytest.mark.parametrize("provider", PROVIDER_NAMES)
def test_token_is_sent_to_provider(monkeypatch, provider):
    seen = respond_json(monkeypatch, PROVIDERS[provider].valid_body("uid"))
    _verify(provider)
    assert len(seen) == 1
    req = seen[0]
    if provider == "google":
        # 토큰은 URL 이 아니라 POST form 본문으로만 간다(#2351).
        assert req.method == "POST"
        assert SECRET_TOKEN not in str(req.url)
        assert req.url.query == b""
        assert req.headers["content-type"] == "application/x-www-form-urlencoded"
        assert parse_qs(req.content.decode()) == {"id_token": [SECRET_TOKEN]}
    else:
        assert SECRET_TOKEN not in str(req.url)
        assert req.headers["authorization"] == f"Bearer {SECRET_TOKEN}"


# ── 200 인데 JSON 객체가 아님 → 형식 이상 ─────────────────────────


@pytest.mark.parametrize("provider", PROVIDER_NAMES)
@pytest.mark.parametrize(
    "content,content_type",
    [(c, t) for _, c, t in NON_OBJECT_BODIES],
    ids=[i for i, _, _ in NON_OBJECT_BODIES],
)
def test_non_object_body_is_provider_response_error(monkeypatch, provider, content, content_type):
    respond_raw(monkeypatch, content, content_type)
    with pytest.raises(SocialProviderResponseError) as info:
        _verify(provider)
    assert provider in str(info.value)
    _assert_clean(info.value)


@pytest.mark.parametrize("provider", PROVIDER_NAMES)
def test_decode_failure_keeps_cause(monkeypatch, provider):
    respond_raw(monkeypatch, b"<html>maintenance</html>", "text/html")
    with pytest.raises(SocialProviderResponseError) as info:
        _verify(provider)
    assert isinstance(info.value.__cause__, ValueError)


@pytest.mark.parametrize("provider", PROVIDER_NAMES)
def test_provider_response_error_is_still_auth_error(monkeypatch, provider):
    """형식 이상을 모르는 호출부도 최소한 인증 실패로는 잡는다."""
    respond_raw(monkeypatch, b"not json", "text/plain")
    with pytest.raises(SocialAuthError):
        _verify(provider)


# ── 필수 id 누락 → 인증 실패(형식 이상 아님) ────────────────────────


def _is_plain_auth_error(exc: BaseException) -> bool:
    return isinstance(exc, SocialAuthError) and not isinstance(exc, SocialProviderResponseError)


@pytest.mark.parametrize("provider", PROVIDER_NAMES)
def test_missing_id_is_auth_error(monkeypatch, provider):
    respond_json(monkeypatch, PROVIDERS[provider].missing_id_body)
    with pytest.raises(SocialAuthError) as info:
        _verify(provider)
    assert _is_plain_auth_error(info.value)
    _assert_clean(info.value)


@pytest.mark.parametrize("provider", PROVIDER_NAMES)
@pytest.mark.parametrize("uid", [None, "", "   "], ids=["null", "empty", "blank"])
def test_empty_id_is_auth_error(monkeypatch, provider, uid):
    respond_json(monkeypatch, PROVIDERS[provider].valid_body(uid))
    with pytest.raises(SocialAuthError) as info:
        _verify(provider)
    assert _is_plain_auth_error(info.value)


@pytest.mark.parametrize("provider", PROVIDER_NAMES)
def test_empty_object_is_auth_error(monkeypatch, provider):
    respond_json(monkeypatch, {})
    with pytest.raises(SocialAuthError) as info:
        _verify(provider)
    assert _is_plain_auth_error(info.value)


def test_naver_without_response_object_is_auth_error(monkeypatch):
    respond_json(monkeypatch, {"resultcode": "024", "message": "Authentication failed"})
    with pytest.raises(SocialAuthError) as info:
        _verify("naver")
    assert _is_plain_auth_error(info.value)


# ── 필드 타입 이상 → 형식 이상 ────────────────────────────────────


@pytest.mark.parametrize("provider", PROVIDER_NAMES)
@pytest.mark.parametrize(
    "uid",
    [{"v": 1}, ["a"], True, False, 1.5],
    ids=["dict", "list", "true", "false", "float"],
)
def test_wrong_id_type_is_provider_response_error(monkeypatch, provider, uid):
    respond_json(monkeypatch, PROVIDERS[provider].valid_body(uid))
    with pytest.raises(SocialProviderResponseError) as info:
        _verify(provider)
    _assert_clean(info.value)


@pytest.mark.parametrize(
    "provider,body",
    [
        ("google", {"sub": "g", "email": 1}),
        ("google", {"sub": "g", "email": ["a@b.c"]}),
        ("google", {"sub": "g", "name": {"first": "a"}}),
        ("google", {"sub": "g", "name": False}),
        ("kakao", {"id": 1, "kakao_account": []}),
        ("kakao", {"id": 1, "kakao_account": "account"}),
        ("kakao", {"id": 1, "kakao_account": 3}),
        ("kakao", {"id": 1, "kakao_account": {"profile": "p"}}),
        ("kakao", {"id": 1, "kakao_account": {"profile": ["p"]}}),
        ("kakao", {"id": 1, "kakao_account": {"email": 5}}),
        ("kakao", {"id": 1, "kakao_account": {"profile": {"nickname": 9}}}),
        ("naver", {"response": []}),
        ("naver", {"response": "profile"}),
        ("naver", {"response": 0}),
        ("naver", {"response": {"id": "n", "email": 1}}),
        ("naver", {"response": {"id": "n", "name": ["a"]}}),
        ("naver", {"response": {"id": "n", "nickname": {"x": 1}}}),
    ],
)
def test_wrong_nested_type_is_provider_response_error(monkeypatch, provider, body):
    respond_json(monkeypatch, body)
    with pytest.raises(SocialProviderResponseError):
        _verify(provider)


# ── 기존 경로 회귀: 비 200·요청 실패는 여전히 인증 실패 ──────────────


@pytest.mark.parametrize("provider", PROVIDER_NAMES)
@pytest.mark.parametrize("status", [400, 401, 403, 500, 503])
def test_non_200_is_auth_error_even_with_html(monkeypatch, provider, status):
    respond_raw(monkeypatch, b"<html>error</html>", "text/html", status=status)
    with pytest.raises(SocialAuthError) as info:
        _verify(provider)
    assert _is_plain_auth_error(info.value)
    assert str(status) in str(info.value)


@pytest.mark.parametrize("provider", PROVIDER_NAMES)
def test_transport_error_is_auth_error(monkeypatch, provider):
    from tests.social_provider_fakes import install_transport

    def _boom(request):
        raise httpx.ConnectError("connection refused", request=request)

    install_transport(monkeypatch, _boom)
    with pytest.raises(SocialAuthError) as info:
        _verify(provider)
    assert _is_plain_auth_error(info.value)


@pytest.mark.parametrize("provider", PROVIDER_NAMES)
def test_adapter_does_not_log_token_or_body(monkeypatch, caplog, provider):
    caplog.set_level(logging.DEBUG)
    respond_raw(monkeypatch, f"<html>{BODY_MARKER}</html>".encode(), "text/html")
    with pytest.raises(SocialProviderResponseError):
        _verify(provider)
    # 이 저장소 코드(app.*)가 남긴 로그만 본다. httpx 자체의 요청 로그는 이 변경의
    # 범위 밖이다.
    ours = "\n".join(r.getMessage() for r in caplog.records if r.name.startswith("app"))
    assert SECRET_TOKEN not in ours
    assert BODY_MARKER not in ours


# ── 헬퍼 단위 ─────────────────────────────────────────────────────


def _resp(content: bytes, content_type: str = "application/json") -> httpx.Response:
    return httpx.Response(200, content=content, headers={"content-type": content_type})


def test_json_object_returns_dict():
    assert _response.json_object("p", _resp(b'{"a": 1}')) == {"a": 1}


@pytest.mark.parametrize(
    "content",
    [c for _, c, _ in NON_OBJECT_BODIES],
    ids=[i for i, _, _ in NON_OBJECT_BODIES],
)
def test_json_object_rejects_non_object(content):
    with pytest.raises(SocialProviderResponseError):
        _response.json_object("p", _resp(content))


@pytest.mark.parametrize("value,expected", [(None, {}), ({}, {}), ({"k": 1}, {"k": 1})])
def test_optional_object_accepts(value, expected):
    assert _response.optional_object("p", {"x": value}, "x") == expected


def test_optional_object_absent_key():
    assert _response.optional_object("p", {}, "x") == {}


@pytest.mark.parametrize("value", [[], "s", 0, 1.0, True])
def test_optional_object_rejects(value):
    with pytest.raises(SocialProviderResponseError):
        _response.optional_object("p", {"x": value}, "x")


@pytest.mark.parametrize("value,expected", [(None, ""), ("", ""), ("abc", "abc")])
def test_optional_str_accepts(value, expected):
    assert _response.optional_str("p", {"x": value}, "x") == expected


@pytest.mark.parametrize("value", [1, 0, 1.5, True, [], {}])
def test_optional_str_rejects(value):
    with pytest.raises(SocialProviderResponseError):
        _response.optional_str("p", {"x": value}, "x")


@pytest.mark.parametrize("value,expected", [("abc", "abc"), (" abc ", "abc"), (0, "0"), (123, "123")])
def test_required_id_accepts(value, expected):
    assert _response.required_id("p", {"id": value}, "id") == expected


@pytest.mark.parametrize("data", [{}, {"id": None}, {"id": ""}, {"id": "  "}])
def test_required_id_missing_is_plain_auth_error(data):
    with pytest.raises(SocialAuthError) as info:
        _response.required_id("p", data, "id")
    assert _is_plain_auth_error(info.value)


@pytest.mark.parametrize("value", [True, False, 1.0, [], {}, ["1"]])
def test_required_id_wrong_type_is_provider_response_error(value):
    with pytest.raises(SocialProviderResponseError):
        _response.required_id("p", {"id": value}, "id")
