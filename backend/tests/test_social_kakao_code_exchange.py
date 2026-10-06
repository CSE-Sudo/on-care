"""카카오 웹 로그인 인가 코드 교환 — `POST /v1/auth/social/kakao/code` (#330).

웹(회원 웹·트레이너 웹)은 카카오 로그인 창이 돌려준 인가 코드만 받는다. 서버가 그 코드를
우리 앱 키(`KAKAO_LOGIN_REST_API_KEY`)로 카카오 access_token 으로 바꿔 주고, 앱은 그
토큰으로 기존 `POST /v1/auth/social/kakao` 를 탄다. 여기서 본다.

- 정상: 카카오 토큰 엔드포인트에 정해진 폼으로 요청하고 access_token 만 돌려준다.
- 클라이언트 시크릿을 켜면 폼에 함께 넣고, 끄면 넣지 않는다.
- 설정이 비면 카카오로 요청을 보내지 않고 401.
- 카카오 거절(만료·재사용·redirect_uri 불일치)은 401, 형식 이상은 502. 둘 다 실패 감사.
- 코드·토큰·시크릿은 응답 detail·로그·감사 기록에 남지 않는다.
- 교환한 토큰으로 로그인하면 기존 검증(app_id·id 확인)을 그대로 탄다.

provider HTTP 는 `httpx.MockTransport` 로 흉내 낸다.
"""
from __future__ import annotations

import asyncio
import logging
from urllib.parse import parse_qs
from uuid import uuid4

import httpx
import pytest
from sqlalchemy import func, select

from app.core.config import get_settings
from app.services.social.base import SocialAuthError, SocialProviderResponseError
from app.services.social.kakao import exchange_code
from tests.social_provider_fakes import (
    KAKAO_TOKEN_INFO_PATH,
    NON_OBJECT_BODIES,
    TEST_KAKAO_APP_ID,
    install_transport,
    kakao_token_info,
    use_app_ids,
)

LOGIN_KEY = "testloginrestkey0330"
SECRET = "client-secret-0330-do-not-log"
CODE = "auth-code-0330-do-not-log"
ACCESS = "kakao-access-0330-do-not-log"
REDIRECT = "https://app.example.com/kakao_login_callback.html"
TOKEN_PATH = "/oauth/token"

AUTH_FAILED_DETAIL = "소셜 계정을 인증하지 못했어요."
BAD_RESPONSE_DETAIL = "소셜 로그인 제공자의 응답을 확인하지 못했어요. 잠시 후 다시 시도해 주세요."


@pytest.fixture(autouse=True)
def _kakao_settings(monkeypatch):
    use_app_ids(monkeypatch)
    settings = get_settings()
    monkeypatch.setattr(settings, "kakao_login_rest_api_key", LOGIN_KEY)
    monkeypatch.setattr(settings, "kakao_client_secret", "")


def _token_ok(request: httpx.Request) -> httpx.Response:
    return httpx.Response(
        200,
        json={
            "token_type": "bearer",
            "access_token": ACCESS,
            "expires_in": 21599,
            "refresh_token": "kakao-refresh-should-not-leave",
            "refresh_token_expires_in": 5183999,
        },
    )


def _form(request: httpx.Request) -> dict[str, str]:
    return {k: v[0] for k, v in parse_qs(request.content.decode()).items()}


def _exchange() -> str:
    return asyncio.run(exchange_code(CODE, REDIRECT))


def _no_network(monkeypatch) -> list:
    def _fail(request):
        raise AssertionError(f"외부 호출이 나가면 안 된다: {request.url.host}")

    return install_transport(monkeypatch, _fail)


# ── 서비스 단위 ──────────────────────────────────────────────────────


def test_exchange_posts_authorization_code_form(monkeypatch):
    seen = install_transport(monkeypatch, _token_ok)

    assert _exchange() == ACCESS

    [req] = seen
    assert req.method == "POST"
    assert req.url.host == "kauth.kakao.com"
    assert req.url.path == TOKEN_PATH
    assert req.headers["content-type"].startswith("application/x-www-form-urlencoded")
    assert _form(req) == {
        "grant_type": "authorization_code",
        "client_id": LOGIN_KEY,
        "redirect_uri": REDIRECT,
        "code": CODE,
    }


def test_exchange_sends_client_secret_when_configured(monkeypatch):
    monkeypatch.setattr(get_settings(), "kakao_client_secret", f"  {SECRET}  ")
    seen = install_transport(monkeypatch, _token_ok)

    _exchange()

    assert _form(seen[0])["client_secret"] == SECRET


def test_exchange_omits_client_secret_when_blank(monkeypatch):
    monkeypatch.setattr(get_settings(), "kakao_client_secret", "   ")
    seen = install_transport(monkeypatch, _token_ok)

    _exchange()

    assert "client_secret" not in _form(seen[0])


@pytest.mark.parametrize(
    "field, value",
    [("kakao_app_id", ""), ("kakao_login_rest_api_key", ""), ("kakao_login_rest_api_key", "   ")],
)
def test_exchange_refuses_without_network_when_unconfigured(monkeypatch, field, value):
    monkeypatch.setattr(get_settings(), field, value)
    seen = _no_network(monkeypatch)

    with pytest.raises(SocialAuthError) as info:
        _exchange()

    assert not isinstance(info.value, SocialProviderResponseError)
    assert seen == []


@pytest.mark.parametrize("status", [400, 401, 403, 500])
def test_exchange_rejection_is_auth_error(monkeypatch, status):
    install_transport(
        monkeypatch,
        lambda _r: httpx.Response(
            status,
            json={
                "error": "invalid_grant",
                "error_description": f"authorization code {CODE} not found",
                "error_code": "KOE320",
            },
        ),
    )

    with pytest.raises(SocialAuthError) as info:
        _exchange()

    assert not isinstance(info.value, SocialProviderResponseError)
    assert CODE not in str(info.value)


def test_exchange_rejection_logs_only_the_error_code(monkeypatch, caplog):
    caplog.set_level(logging.DEBUG)
    install_transport(
        monkeypatch,
        lambda _r: httpx.Response(
            400,
            json={"error": "invalid_grant", "error_description": f"code {CODE}", "error_code": "KOE320"},
        ),
    )

    with pytest.raises(SocialAuthError):
        _exchange()

    assert "KOE320" in caplog.text
    assert CODE not in caplog.text
    assert LOGIN_KEY not in caplog.text


def test_exchange_rejection_with_non_json_body_logs_dash(monkeypatch, caplog):
    caplog.set_level(logging.WARNING)
    install_transport(
        monkeypatch,
        lambda _r: httpx.Response(502, content=f"<html>{CODE}</html>".encode(), headers={"content-type": "text/html"}),
    )

    with pytest.raises(SocialAuthError):
        _exchange()

    assert "502, -" in caplog.text
    assert CODE not in caplog.text


def test_exchange_transport_error_is_auth_error(monkeypatch):
    def _boom(request):
        raise httpx.ConnectTimeout(f"timeout {CODE}", request=request)

    install_transport(monkeypatch, _boom)

    with pytest.raises(SocialAuthError) as info:
        _exchange()

    assert not isinstance(info.value, SocialProviderResponseError)
    assert CODE not in str(info.value)


@pytest.mark.parametrize(
    "content, content_type", [(c, t) for _id, c, t in NON_OBJECT_BODIES], ids=[i for i, _c, _t in NON_OBJECT_BODIES]
)
def test_exchange_non_object_body_is_bad_response(monkeypatch, content, content_type):
    install_transport(
        monkeypatch, lambda _r: httpx.Response(200, content=content, headers={"content-type": content_type})
    )

    with pytest.raises(SocialProviderResponseError):
        _exchange()


@pytest.mark.parametrize("body", [{}, {"access_token": None}, {"access_token": ""}, {"access_token": "   "}])
def test_exchange_without_access_token_is_auth_error(monkeypatch, body):
    install_transport(monkeypatch, lambda _r: httpx.Response(200, json=body))

    with pytest.raises(SocialAuthError) as info:
        _exchange()

    assert not isinstance(info.value, SocialProviderResponseError)


@pytest.mark.parametrize("value", [12345, ["tok"], {"t": 1}, True])
def test_exchange_wrong_access_token_type_is_bad_response(monkeypatch, value):
    install_transport(monkeypatch, lambda _r: httpx.Response(200, json={"access_token": value}))

    with pytest.raises(SocialProviderResponseError):
        _exchange()


# ── API ───────────────────────────────────────────────────────────────


def _post(client, code: str = CODE, redirect_uri: str = REDIRECT):
    return client.post(
        "/v1/auth/social/kakao/code", json={"code": code, "redirect_uri": redirect_uri}
    )


def _failed_code_audits(db) -> int:
    from app.models.models import AuditLog

    db.expire_all()
    return db.scalar(
        select(func.count()).select_from(AuditLog).where(
            AuditLog.event == "auth.social",
            AuditLog.success.is_(False),
            AuditLog.detail == "kakao code",
        )
    )


def _all_audit_text(db) -> str:
    from app.models.models import AuditLog

    db.expire_all()
    rows = db.scalars(select(AuditLog)).all()
    return " ".join(f"{r.event} {r.detail} {r.ip}" for r in rows)


def test_api_exchange_returns_only_the_access_token(client, monkeypatch):
    install_transport(monkeypatch, _token_ok)

    r = _post(client)

    assert r.status_code == 200, r.text
    assert r.json() == {"access_token": ACCESS}


def test_api_exchange_does_not_log_in_or_create_users(client, db_session, monkeypatch):
    from app.models.models import User

    db_session.expire_all()
    before = db_session.scalar(select(func.count()).select_from(User))
    install_transport(monkeypatch, _token_ok)

    r = _post(client)

    assert r.status_code == 200, r.text
    assert "refresh_token" not in r.json()
    db_session.expire_all()
    assert db_session.scalar(select(func.count()).select_from(User)) == before


def test_api_rejected_code_is_401_and_audited(client, db_session, monkeypatch, caplog):
    caplog.set_level(logging.DEBUG)
    before = _failed_code_audits(db_session)
    install_transport(
        monkeypatch,
        lambda _r: httpx.Response(400, json={"error": "invalid_grant", "error_code": "KOE320"}),
    )

    r = _post(client)

    assert r.status_code == 401, r.text
    assert r.json()["detail"] == AUTH_FAILED_DETAIL
    assert _failed_code_audits(db_session) == before + 1
    assert CODE not in r.text
    assert CODE not in caplog.text
    assert CODE not in _all_audit_text(db_session)


def test_api_unconfigured_is_401_without_network(client, db_session, monkeypatch):
    monkeypatch.setattr(get_settings(), "kakao_login_rest_api_key", "")
    seen = _no_network(monkeypatch)
    before = _failed_code_audits(db_session)

    r = _post(client)

    assert r.status_code == 401, r.text
    assert seen == []
    assert _failed_code_audits(db_session) == before + 1


def test_api_bad_response_is_502_and_audited(client, db_session, monkeypatch):
    before = _failed_code_audits(db_session)
    install_transport(
        monkeypatch,
        lambda _r: httpx.Response(200, content=b"<html>maintenance</html>", headers={"content-type": "text/html"}),
    )

    r = _post(client)

    assert r.status_code == 502, r.text
    assert r.json()["detail"] == BAD_RESPONSE_DETAIL
    assert _failed_code_audits(db_session) == before + 1


def test_api_unexpected_error_is_502_and_audited(client, db_session, monkeypatch, caplog):
    import app.api.v1.social as social_mod

    async def _explode(code, redirect_uri):
        raise RuntimeError(f"boom {CODE}")

    monkeypatch.setattr(social_mod.kakao_social, "exchange_code", _explode)
    caplog.set_level(logging.DEBUG)
    before = _failed_code_audits(db_session)

    r = _post(client)

    assert r.status_code == 502, r.text
    assert _failed_code_audits(db_session) == before + 1
    assert CODE not in caplog.text


@pytest.mark.parametrize(
    "payload",
    [
        {},
        {"code": CODE},
        {"redirect_uri": REDIRECT},
        {"code": "", "redirect_uri": REDIRECT},
        {"code": CODE, "redirect_uri": ""},
        {"code": "x" * 2049, "redirect_uri": REDIRECT},
        {"code": CODE, "redirect_uri": "h" * 2049},
    ],
)
def test_api_rejects_malformed_payload_before_calling_kakao(client, monkeypatch, payload):
    seen = _no_network(monkeypatch)

    r = client.post("/v1/auth/social/kakao/code", json=payload)

    assert r.status_code == 422, r.text
    assert seen == []


def test_api_code_route_is_not_taken_by_the_provider_route(client, monkeypatch):
    """`/auth/social/{provider}` 가 `kakao/code` 를 가로채지 않는다(라우트 순서)."""
    install_transport(monkeypatch, _token_ok)

    r = _post(client)

    assert r.status_code == 200, r.text
    assert "access_token" in r.json()


def test_api_exchanged_token_logs_in_through_the_usual_verification(client, db_session, monkeypatch):
    """교환 → 로그인 전체 흐름. 로그인은 교환한 토큰으로 app_id·id 확인을 그대로 탄다."""
    uid = int(uuid4().int % 10**10)
    email = f"kweb-{uuid4().hex[:8]}@oncare.com"
    seen_tokens: list[str] = []

    def _handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == TOKEN_PATH:
            return _token_ok(request)
        seen_tokens.append(request.headers.get("authorization", ""))
        if request.url.path == KAKAO_TOKEN_INFO_PATH:
            return httpx.Response(200, json=kakao_token_info(uid))
        return httpx.Response(
            200, json={"id": uid, "kakao_account": {"email": email, "profile": {"nickname": "웹카카오"}}}
        )

    install_transport(monkeypatch, _handler)

    exchanged = _post(client)
    assert exchanged.status_code == 200, exchanged.text
    login = client.post("/v1/auth/social/kakao", json={"token": exchanged.json()["access_token"]})

    assert login.status_code == 200, login.text
    assert login.json()["access_token"]
    assert seen_tokens and all(t == f"Bearer {ACCESS}" for t in seen_tokens)


def test_api_exchanged_token_of_another_app_still_fails_login(client, monkeypatch):
    """교환이 성공해도 로그인 검증은 생략되지 않는다 — app_id 가 다르면 401."""
    uid = int(uuid4().int % 10**10)

    def _handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == TOKEN_PATH:
            return _token_ok(request)
        if request.url.path == KAKAO_TOKEN_INFO_PATH:
            return httpx.Response(200, json=kakao_token_info(uid, app_id="999001"))
        return httpx.Response(200, json={"id": uid})

    install_transport(monkeypatch, _handler)

    token = _post(client).json()["access_token"]
    r = client.post("/v1/auth/social/kakao", json={"token": token})

    assert r.status_code == 401, r.text
    assert TEST_KAKAO_APP_ID != "999001"
