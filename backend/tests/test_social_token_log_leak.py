"""소셜 로그인 토큰의 로그 노출 차단 (#2351).

구글 검증이 tokeninfo URL 쿼리에 id_token 을 붙여 보냈고, 루트 로거가 INFO 라서
httpx 의 요청 로그(`HTTP Request: GET https://...?id_token=...`)가 토큰째 남았다.
두 겹으로 막는다.

- 구글 id_token 은 URL 이 아니라 POST form 본문으로 보낸다.
- `setup_logging` 이 httpx·httpcore 로거를 WARNING 으로 고정해, 외부 호출 URL 이
  INFO 로그에 남지 않는다.

여기서는 테스트 전용 캡처가 아니라 **운영과 같은 `setup_logging` 설정**을 적용하고,
그 핸들러가 실제로 찍는 전체 출력(모든 로거)에 토큰이 없는지 본다.
"""
from __future__ import annotations

import asyncio
import io
import logging
from urllib.parse import parse_qs

import httpx
import pytest

from app.core import observability
from app.services.social.base import SocialAuthError, SocialProviderResponseError
from tests.social_provider_fakes import (
    BODY_MARKER,
    GOOGLE_CLAIMS,
    KAKAO_TOKEN_INFO_PATH,
    OPEN_PROVIDERS,
    OTHER_GOOGLE_CLIENT_ID,
    OTHER_KAKAO_APP_ID,
    PROVIDERS,
    SECRET_TOKEN,
    install_transport,
    kakao_token_info,
    respond_json,
    respond_kakao,
    respond_raw,
    use_app_ids,
)

PROVIDER_NAMES = sorted(PROVIDERS)
#: API 로 로그인이 열린 provider(네이버·애플은 제공하지 않아 400, #3218).
API_PROVIDER_NAMES = sorted(OPEN_PROVIDERS)
HTTP_CLIENT_LOGGERS = ("httpx", "httpcore")


@pytest.fixture(autouse=True)
def _app_ids(monkeypatch):
    use_app_ids(monkeypatch)


@pytest.fixture
def real_logging():
    """운영 `setup_logging` 을 적용하고 그 핸들러 출력을 문자열로 모은다.

    반환값 `apply(level)` 은 루트 수준을 받아 설정을 적용하고 출력 버퍼를 돌려준다.
    테스트가 끝나면 루트 핸들러·수준과 HTTP 클라이언트 로거 수준을 되돌린다.
    """
    root = logging.getLogger()
    saved_handlers = root.handlers[:]
    saved_level = root.level
    saved_client_levels = {n: logging.getLogger(n).level for n in HTTP_CLIENT_LOGGERS}

    def apply(level: str = "INFO") -> io.StringIO:
        observability.setup_logging(level)
        [handler] = logging.getLogger().handlers
        buf = io.StringIO()
        handler.setStream(buf)  # 운영 포맷터·필터는 그대로, 출력만 버퍼로
        return buf

    try:
        yield apply
    finally:
        root.handlers = saved_handlers
        root.setLevel(saved_level)
        for name, level in saved_client_levels.items():
            logging.getLogger(name).setLevel(level)


def _verify(provider: str, token: str = SECRET_TOKEN):
    return asyncio.run(PROVIDERS[provider].read(token))


def _assert_clean(out: str) -> None:
    assert SECRET_TOKEN not in out
    assert BODY_MARKER not in out


# ── setup_logging: HTTP 클라이언트 로거 수준 ────────────────────────


@pytest.mark.parametrize("root_level", ["DEBUG", "INFO", "WARNING"])
@pytest.mark.parametrize("name", HTTP_CLIENT_LOGGERS)
def test_setup_logging_pins_http_client_loggers_to_warning(real_logging, root_level, name):
    real_logging(root_level)
    logger = logging.getLogger(name)
    assert logger.level == logging.WARNING
    assert not logger.isEnabledFor(logging.INFO)
    assert not logger.isEnabledFor(logging.DEBUG)
    assert logger.isEnabledFor(logging.WARNING)


@pytest.mark.parametrize("name", HTTP_CLIENT_LOGGERS)
def test_setup_logging_pins_again_after_level_was_lowered(real_logging, name):
    real_logging("INFO")
    logging.getLogger(name).setLevel(logging.DEBUG)
    real_logging("INFO")
    assert logging.getLogger(name).level == logging.WARNING


@pytest.mark.parametrize("name", ["httpx", "httpcore", "httpx._client", "httpcore.http11"])
def test_http_client_info_and_debug_are_dropped(real_logging, name):
    out = real_logging("DEBUG")
    logging.getLogger(name).info("info from %s %s", name, SECRET_TOKEN)
    logging.getLogger(name).debug("debug from %s %s", name, SECRET_TOKEN)
    assert out.getvalue() == ""


@pytest.mark.parametrize("name", HTTP_CLIENT_LOGGERS)
def test_http_client_warnings_still_reach_the_log(real_logging, name):
    out = real_logging("INFO")
    logging.getLogger(name).warning("client warning from %s", name)
    logging.getLogger(name).error("client error from %s", name)
    text = out.getvalue()
    assert f"client warning from {name}" in text
    assert f"client error from {name}" in text


def test_app_info_logs_are_unaffected(real_logging):
    out = real_logging("INFO")
    logging.getLogger("app.access").info("access line kept")
    logging.getLogger("app.api.v1.social").info("social line kept")
    text = out.getvalue()
    assert "access line kept" in text
    assert "social line kept" in text


def test_root_level_still_follows_setting(real_logging):
    real_logging("WARNING")
    assert logging.getLogger().level == logging.WARNING
    real_logging("DEBUG")
    assert logging.getLogger().level == logging.DEBUG


def test_app_startup_applies_the_http_client_levels():
    import app.main  # noqa: F401 — 모듈 로드 시 setup_logging 이 적용된다

    for name in HTTP_CLIENT_LOGGERS:
        assert logging.getLogger(name).level == logging.WARNING


def test_url_query_token_is_not_logged_even_if_sent(real_logging, monkeypatch):
    """로거 조치 단독 검증: URL 쿼리에 토큰이 실린 외부 요청도 로그에 남지 않는다."""
    out = real_logging("INFO")
    install_transport(monkeypatch, lambda _req: httpx.Response(200, json={}))

    async def _call():
        async with httpx.AsyncClient() as client:
            await client.get("https://example.invalid/verify", params={"id_token": SECRET_TOKEN})

    asyncio.run(_call())
    assert SECRET_TOKEN not in out.getvalue()


def test_without_the_level_pin_httpx_would_log_the_url(real_logging, monkeypatch):
    """회귀 근거: httpx 로거가 INFO 면 요청 URL 이 그대로 찍힌다(이 조치가 막는 경로)."""
    out = real_logging("INFO")
    logging.getLogger("httpx").setLevel(logging.INFO)
    install_transport(monkeypatch, lambda _req: httpx.Response(200, json={}))

    async def _call():
        async with httpx.AsyncClient() as client:
            await client.get("https://example.invalid/verify", params={"q": "visible-query"})

    asyncio.run(_call())
    assert "visible-query" in out.getvalue()


# ── 구글 요청 형태 ────────────────────────────────────────────────


def test_google_sends_token_only_in_post_form_body(monkeypatch):
    seen = respond_json(monkeypatch, PROVIDERS["google"].valid_body("g-1"))
    _verify("google")

    [req] = seen
    assert req.method == "POST"
    assert req.url.scheme == "https"
    assert req.url.host == "oauth2.googleapis.com"
    assert req.url.path == "/tokeninfo"
    assert req.url.query == b""
    assert SECRET_TOKEN not in str(req.url)
    assert SECRET_TOKEN not in req.url.raw_path.decode()
    assert req.headers["content-type"] == "application/x-www-form-urlencoded"
    assert parse_qs(req.content.decode()) == {"id_token": [SECRET_TOKEN]}
    for value in req.headers.values():
        assert SECRET_TOKEN not in value


@pytest.mark.parametrize(
    "token",
    ["a.b.c", "tok+with/slash=and&amp", "tok with space", "토큰-한글", "x" * 4096],
    ids=["jwt_like", "reserved_chars", "space", "non_ascii", "long"],
)
def test_google_form_body_round_trips_token(monkeypatch, token):
    seen = respond_json(monkeypatch, PROVIDERS["google"].valid_body("g-1"))
    _verify("google", token)

    [req] = seen
    assert req.url.query == b""
    assert parse_qs(req.content.decode(), keep_blank_values=True) == {"id_token": [token]}


def test_google_success_still_parses_identity(monkeypatch):
    respond_json(monkeypatch, PROVIDERS["google"].valid_body("g-42"))
    identity = _verify("google")
    assert identity.provider == "google"
    assert identity.provider_user_id == "g-42"
    assert identity.email == "g@oncare.com"


@pytest.mark.parametrize("provider", ["kakao"])
def test_header_providers_keep_token_out_of_url(monkeypatch, provider):
    seen = respond_json(monkeypatch, PROVIDERS[provider].valid_body("uid"))
    _verify(provider)

    # 카카오는 토큰 정보 조회(#3035)가 앞에 붙는다. 그 요청도 헤더로만 보낸다.
    assert len(seen) == (2 if provider == "kakao" else 1)
    for req in seen:
        assert req.method == "GET"
        assert req.url.query == b""
        assert SECRET_TOKEN not in str(req.url)
        assert req.headers["authorization"] == f"Bearer {SECRET_TOKEN}"


# ── 발급 앱 불일치(#3035): 거부 사유는 남기되 토큰·응답 값은 남기지 않는다 ──────


def test_google_audience_mismatch_logs_reason_only(real_logging, monkeypatch):
    out = real_logging("DEBUG")
    respond_json(
        monkeypatch,
        {**GOOGLE_CLAIMS, "aud": OTHER_GOOGLE_CLIENT_ID, "sub": BODY_MARKER, "email": "x@oncare.com"},
    )
    with pytest.raises(SocialAuthError) as info:
        _verify("google")
    text = out.getvalue()
    _assert_clean(text)
    assert OTHER_GOOGLE_CLIENT_ID not in text
    assert "aud" in text
    assert SECRET_TOKEN not in str(info.value)


def test_kakao_app_mismatch_logs_reason_only(real_logging, monkeypatch):
    out = real_logging("DEBUG")
    seen = respond_kakao(
        monkeypatch,
        token_info=kakao_token_info(BODY_MARKER, app_id=OTHER_KAKAO_APP_ID),
        user={"id": BODY_MARKER},
    )
    with pytest.raises(SocialAuthError) as info:
        _verify("kakao")
    text = out.getvalue()
    _assert_clean(text)
    assert OTHER_KAKAO_APP_ID not in text
    assert "app_id" in text
    assert SECRET_TOKEN not in str(info.value)
    # 다른 앱 토큰이면 사용자 정보는 부르지도 않는다.
    assert [r.url.path for r in seen] == [KAKAO_TOKEN_INFO_PATH]


# ── 운영 로깅 설정에서 adapter 전체 로그 ─────────────────────────────


@pytest.mark.parametrize("root_level", ["DEBUG", "INFO"])
@pytest.mark.parametrize("provider", PROVIDER_NAMES)
def test_success_leaves_no_token_in_any_log(real_logging, monkeypatch, provider, root_level):
    out = real_logging(root_level)
    respond_json(monkeypatch, PROVIDERS[provider].valid_body("uid-ok"))
    assert _verify(provider).provider_user_id == "uid-ok"
    _assert_clean(out.getvalue())


@pytest.mark.parametrize("status", [400, 401, 403, 500, 503])
@pytest.mark.parametrize("provider", PROVIDER_NAMES)
def test_rejection_leaves_no_token_in_any_log(real_logging, monkeypatch, provider, status):
    out = real_logging("DEBUG")
    respond_raw(monkeypatch, f'{{"error": "{BODY_MARKER}"}}'.encode(), "application/json", status=status)
    with pytest.raises(SocialAuthError) as info:
        _verify(provider)
    _assert_clean(out.getvalue())
    assert SECRET_TOKEN not in str(info.value)


@pytest.mark.parametrize("provider", PROVIDER_NAMES)
def test_bad_body_leaves_no_token_in_any_log(real_logging, monkeypatch, provider):
    out = real_logging("DEBUG")
    respond_raw(monkeypatch, f"<html>{BODY_MARKER}</html>".encode(), "text/html")
    with pytest.raises(SocialProviderResponseError):
        _verify(provider)
    _assert_clean(out.getvalue())


@pytest.mark.parametrize("provider", PROVIDER_NAMES)
def test_missing_id_leaves_no_token_in_any_log(real_logging, monkeypatch, provider):
    out = real_logging("DEBUG")
    respond_json(monkeypatch, PROVIDERS[provider].missing_id_body)
    with pytest.raises(SocialAuthError):
        _verify(provider)
    _assert_clean(out.getvalue())


@pytest.mark.parametrize(
    "error",
    [httpx.ConnectError, httpx.ReadTimeout, httpx.ConnectTimeout, httpx.RemoteProtocolError],
)
@pytest.mark.parametrize("provider", PROVIDER_NAMES)
def test_transport_error_leaves_no_token_in_log_or_error(real_logging, monkeypatch, provider, error):
    out = real_logging("DEBUG")

    def _boom(request):
        raise error("network down", request=request)

    install_transport(monkeypatch, _boom)
    with pytest.raises(SocialAuthError) as info:
        _verify(provider)
    _assert_clean(out.getvalue())
    assert SECRET_TOKEN not in str(info.value)


# ── API 경로: 운영 로깅 설정 + 로그인 요청 전체 ─────────────────────


def _login(client, provider: str):
    return client.post(f"/v1/auth/social/{provider}", json={"token": SECRET_TOKEN})


@pytest.mark.parametrize("provider", API_PROVIDER_NAMES)
def test_api_login_success_leaves_no_token_in_any_log(client, real_logging, monkeypatch, provider):
    out = real_logging("INFO")
    respond_json(monkeypatch, PROVIDERS[provider].valid_body(f"{provider}-2351-ok"))

    r = _login(client, provider)

    assert r.status_code == 200, r.text
    text = out.getvalue()
    _assert_clean(text)
    assert SECRET_TOKEN not in r.text
    # 액세스 로그는 그대로 남는다(경로만).
    assert f"/v1/auth/social/{provider}" in text


@pytest.mark.parametrize(
    "respond",
    [
        pytest.param(lambda mp: respond_raw(mp, b'{"error": "invalid_token"}', "application/json", 400), id="rejected"),
        pytest.param(lambda mp: respond_raw(mp, f"<html>{BODY_MARKER}</html>".encode(), "text/html"), id="bad_body"),
        pytest.param(lambda mp: respond_json(mp, {}), id="missing_id"),
    ],
)
@pytest.mark.parametrize("provider", API_PROVIDER_NAMES)
def test_api_login_failure_leaves_no_token_in_any_log(client, real_logging, monkeypatch, provider, respond):
    out = real_logging("INFO")
    respond(monkeypatch)

    r = _login(client, provider)

    assert r.status_code in (401, 502), r.text
    _assert_clean(out.getvalue())
    assert SECRET_TOKEN not in r.text


@pytest.mark.parametrize("provider", API_PROVIDER_NAMES)
def test_api_transport_error_leaves_no_token_in_any_log(client, real_logging, monkeypatch, provider):
    out = real_logging("DEBUG")

    def _boom(request):
        raise httpx.ConnectError("network down", request=request)

    install_transport(monkeypatch, _boom)

    r = _login(client, provider)

    assert r.status_code == 401, r.text
    _assert_clean(out.getvalue())


def test_api_google_login_sends_post_without_token_in_url(client, real_logging, monkeypatch):
    real_logging("INFO")
    seen = respond_json(monkeypatch, PROVIDERS["google"].valid_body("google-2351-post"))

    assert _login(client, "google").status_code == 200

    [req] = seen
    assert req.method == "POST"
    assert SECRET_TOKEN not in str(req.url)
    assert parse_qs(req.content.decode()) == {"id_token": [SECRET_TOKEN]}


@pytest.mark.parametrize("provider", ["naver", "apple"])
def test_api_dropped_provider_is_rejected_without_calling_out(
    client, real_logging, monkeypatch, provider
):
    """네이버·애플은 제공하지 않는다(#3218) — 400 이고, 앱이 보낸 토큰을 어디로도 보내지도 남기지도 않는다."""
    out = real_logging("DEBUG")
    seen = respond_json(monkeypatch, PROVIDERS["kakao"].valid_body("dropped-3218"))

    r = _login(client, provider)

    assert r.status_code == 400, r.text
    assert seen == []
    _assert_clean(out.getvalue())
    assert SECRET_TOKEN not in r.text
