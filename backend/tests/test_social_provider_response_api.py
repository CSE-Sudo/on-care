"""소셜 provider 비정상 응답 — API 단위 (#1550).

`POST /v1/auth/social/{provider}` 가 provider 의 비정상 응답에 500 을 내지 않고
계약대로 답하는지, 실패 감사 로그가 남는지, 토큰·응답 본문이 응답·감사·로그 어디에도
남지 않는지 본다. verifier 는 가짜로 바꾸지 않고, provider HTTP 만 MockTransport 로
흉내 내 실제 adapter 파싱 경로를 탄다.

- 필수 id 누락·토큰 거절(비 200)·요청 실패 → 401
- 응답 형식 이상(HTML·깨진 JSON·객체 아님·타입 이상·빈 본문) → 502

API 로 로그인이 열린 provider(구글·카카오)만 돈다. 네이버는 서버 측 코드 교환 전까지
501 로 닫혀 있다(#3035).
"""
from __future__ import annotations

import logging
from uuid import uuid4

import httpx
import pytest
from sqlalchemy import func, select

from app.models.models import AuditLog
from tests.social_provider_fakes import (
    BODY_MARKER,
    GOOGLE_CLAIMS,
    NON_OBJECT_BODIES,
    OPEN_PROVIDERS,
    PROVIDERS,
    SECRET_TOKEN,
    install_transport,
    respond_json,
    respond_raw,
    use_app_ids,
)

PROVIDER_NAMES = sorted(OPEN_PROVIDERS)
BAD_RESPONSE_DETAIL = "소셜 로그인 제공자의 응답을 확인하지 못했어요. 잠시 후 다시 시도해 주세요."
AUTH_FAILED_DETAIL = "소셜 계정을 인증하지 못했어요."


@pytest.fixture(autouse=True)
def _app_ids(monkeypatch):
    use_app_ids(monkeypatch)


def _failed_count(db, provider: str) -> int:
    db.expire_all()
    return db.scalar(
        select(func.count()).select_from(AuditLog).where(
            AuditLog.event == "auth.social",
            AuditLog.success.is_(False),
            AuditLog.detail == provider,
        )
    )


def _login(client, provider: str, token: str = SECRET_TOKEN):
    return client.post(f"/v1/auth/social/{provider}", json={"token": token})


def _assert_nothing_leaked(resp, db, caplog) -> None:
    assert SECRET_TOKEN not in resp.text
    assert BODY_MARKER not in resp.text
    db.expire_all()
    leaked = db.scalars(
        select(AuditLog).where(
            AuditLog.detail.contains(SECRET_TOKEN) | AuditLog.detail.contains(BODY_MARKER)
        )
    ).all()
    assert leaked == []
    # 앱 로거만이 아니라 httpx 등 모든 로거가 남긴 로그 전체를 본다(#2351).
    logged = caplog.text + "\n".join(r.getMessage() for r in caplog.records)
    assert SECRET_TOKEN not in logged
    assert BODY_MARKER not in logged


# ── 형식 이상 → 502 + 실패 감사 ─────────────────────────────────────


@pytest.mark.parametrize("provider", PROVIDER_NAMES)
@pytest.mark.parametrize(
    "content,content_type",
    [(c, t) for _, c, t in NON_OBJECT_BODIES],
    ids=[i for i, _, _ in NON_OBJECT_BODIES],
)
def test_non_object_body_returns_502_and_audits(
    client, db_session, monkeypatch, caplog, provider, content, content_type
):
    caplog.set_level(logging.INFO)
    before = _failed_count(db_session, provider)
    respond_raw(monkeypatch, content, content_type)

    r = _login(client, provider)

    assert r.status_code == 502, r.text
    assert r.json()["detail"] == BAD_RESPONSE_DETAIL
    assert _failed_count(db_session, provider) == before + 1
    _assert_nothing_leaked(r, db_session, caplog)


@pytest.mark.parametrize("provider", PROVIDER_NAMES)
@pytest.mark.parametrize("uid", [{"v": 1}, ["a"], True, 1.5], ids=["dict", "list", "bool", "float"])
def test_wrong_id_type_returns_502(client, db_session, monkeypatch, caplog, provider, uid):
    caplog.set_level(logging.INFO)
    before = _failed_count(db_session, provider)
    respond_json(monkeypatch, PROVIDERS[provider].valid_body(uid))

    r = _login(client, provider)

    assert r.status_code == 502, r.text
    assert _failed_count(db_session, provider) == before + 1
    _assert_nothing_leaked(r, db_session, caplog)


@pytest.mark.parametrize(
    "provider,body",
    [
        ("google", {**GOOGLE_CLAIMS, "sub": "g", "email": 1}),
        ("google", {**GOOGLE_CLAIMS, "sub": "g", "exp": "soon"}),
        ("kakao", {"id": 1, "kakao_account": []}),
        ("kakao", {"id": 1, "kakao_account": {"profile": "p"}}),
    ],
)
def test_wrong_nested_type_returns_502(client, db_session, monkeypatch, provider, body):
    before = _failed_count(db_session, provider)
    respond_json(monkeypatch, body)

    r = _login(client, provider)

    assert r.status_code == 502, r.text
    assert _failed_count(db_session, provider) == before + 1


@pytest.mark.parametrize("provider", PROVIDER_NAMES)
def test_bad_response_does_not_create_user(client, db_session, monkeypatch, provider):
    from app.models.models import SocialAccount

    db_session.expire_all()
    before = db_session.scalar(select(func.count()).select_from(SocialAccount))
    respond_raw(monkeypatch, b"<html>down</html>", "text/html")

    assert _login(client, provider).status_code == 502

    db_session.expire_all()
    assert db_session.scalar(select(func.count()).select_from(SocialAccount)) == before


# ── 필수 id 누락·토큰 거절 → 401 + 실패 감사 ─────────────────────────


@pytest.mark.parametrize("provider", PROVIDER_NAMES)
def test_missing_id_returns_401_and_audits(client, db_session, monkeypatch, caplog, provider):
    caplog.set_level(logging.INFO)
    before = _failed_count(db_session, provider)
    respond_json(monkeypatch, PROVIDERS[provider].missing_id_body)

    r = _login(client, provider)

    assert r.status_code == 401, r.text
    assert r.json()["detail"] == AUTH_FAILED_DETAIL
    assert _failed_count(db_session, provider) == before + 1
    _assert_nothing_leaked(r, db_session, caplog)


@pytest.mark.parametrize("provider", PROVIDER_NAMES)
@pytest.mark.parametrize("uid", [None, ""], ids=["null", "empty"])
def test_empty_id_returns_401(client, db_session, monkeypatch, provider, uid):
    before = _failed_count(db_session, provider)
    respond_json(monkeypatch, PROVIDERS[provider].valid_body(uid))

    assert _login(client, provider).status_code == 401
    assert _failed_count(db_session, provider) == before + 1


@pytest.mark.parametrize("provider", PROVIDER_NAMES)
def test_empty_object_returns_401(client, db_session, monkeypatch, provider):
    before = _failed_count(db_session, provider)
    respond_json(monkeypatch, {})

    assert _login(client, provider).status_code == 401
    assert _failed_count(db_session, provider) == before + 1


@pytest.mark.parametrize("provider", PROVIDER_NAMES)
@pytest.mark.parametrize("status", [401, 403, 500, 503])
def test_provider_rejection_stays_401(client, db_session, monkeypatch, provider, status):
    before = _failed_count(db_session, provider)
    respond_raw(monkeypatch, f"<html>{BODY_MARKER}</html>".encode(), "text/html", status=status)

    r = _login(client, provider)

    assert r.status_code == 401, r.text
    assert _failed_count(db_session, provider) == before + 1
    assert BODY_MARKER not in r.text


@pytest.mark.parametrize("provider", PROVIDER_NAMES)
def test_transport_error_stays_401(client, db_session, monkeypatch, provider):
    def _boom(request):
        raise httpx.ReadTimeout("timed out", request=request)

    install_transport(monkeypatch, _boom)
    before = _failed_count(db_session, provider)

    assert _login(client, provider).status_code == 401
    assert _failed_count(db_session, provider) == before + 1


# ── adapter 가 놓친 예외도 500 이 아니라 502 + 감사 ─────────────────


def test_unexpected_verifier_error_returns_502_and_audits(client, db_session, monkeypatch, caplog):
    import app.api.v1.social as social_mod

    caplog.set_level(logging.INFO)

    class _Broken:
        async def verify(self, token):
            raise RuntimeError(f"unexpected {token} {BODY_MARKER}")

    monkeypatch.setattr(social_mod, "get_verifier", lambda provider: _Broken())
    before = _failed_count(db_session, "kakao")

    r = _login(client, "kakao")

    assert r.status_code == 502, r.text
    assert r.json()["detail"] == BAD_RESPONSE_DETAIL
    assert _failed_count(db_session, "kakao") == before + 1
    _assert_nothing_leaked(r, db_session, caplog)
    assert any(
        r.name == "app.api.v1.social" and "RuntimeError" in r.getMessage()
        for r in caplog.records
    )


def test_bad_response_is_logged_with_provider(client, monkeypatch, caplog):
    caplog.set_level(logging.INFO)
    respond_raw(monkeypatch, b"<html>down</html>", "text/html")

    assert _login(client, "kakao").status_code == 502

    msgs = [r.getMessage() for r in caplog.records if r.name == "app.api.v1.social"]
    assert any("provider=kakao" in m for m in msgs)


# ── 정상 경로 회귀 ────────────────────────────────────────────────


@pytest.mark.parametrize("provider", PROVIDER_NAMES)
def test_valid_response_logs_in_and_audits_success(client, db_session, monkeypatch, provider):
    uid = f"{provider}-{uuid4().hex[:10]}"
    body = PROVIDERS[provider].valid_body(uid)
    # 이메일은 매 실행 고유하게 — 기존 사용자에 연결되는 경로를 피한다.
    email = f"{uid}@oncare.com"
    if provider == "google":
        body["email"] = email
    else:
        body["kakao_account"]["email"] = email
    respond_json(monkeypatch, body)

    r = _login(client, provider)

    assert r.status_code == 200, r.text
    assert r.json()["access_token"] and r.json()["refresh_token"]
    db_session.expire_all()
    ok = db_session.scalars(
        select(AuditLog).where(
            AuditLog.event == "auth.social",
            AuditLog.success.is_(True),
            AuditLog.detail == provider,
        )
    ).all()
    assert ok
    assert all(SECRET_TOKEN not in row.detail for row in ok)
