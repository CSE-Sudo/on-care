"""소셜 토큰 발급 앱 확인 — 다른 앱 토큰으로 로그인되지 않는다 (#3035).

provider 서명·조회만 보고 로그인시키면, 같은 provider 를 쓰는 다른 앱이 받은 사용자
토큰을 그대로 넣어 그 사람의 On-Care 계정을 얻을 수 있다(토큰 대체). 여기서 본다.

- 구글: tokeninfo 의 `aud` 가 `GOOGLE_CLIENT_IDS` 에 있고 `iss`·`exp` 가 맞아야 통과.
- 카카오: 토큰 정보 조회의 `app_id` 가 `KAKAO_APP_ID` 와 같고, 두 응답의 `id` 가 같아야 통과.
- 네이버·애플: 제공하지 않는다(#3218). API 는 모르는 provider 와 같은 400 이고 외부 호출이 없다.
- 허용 설정이 비면 외부 호출 없이 거부하고, 기동 점검이 경고를 남긴다.
- API: 다른 앱 토큰은 같은 이메일의 기존 계정에 소셜 연결을 만들지 않는다.

단위 테스트는 DB 가 필요 없다. provider HTTP 는 `httpx.MockTransport` 로 흉내 낸다.
"""
from __future__ import annotations

import asyncio
import logging
from uuid import uuid4

import pytest
from sqlalchemy import func, select

from app.core import startup_checks
from app.core.config import Settings
from app.services.social.base import SocialAuthError, SocialProviderResponseError
from app.services.social.google import GOOGLE_ISSUERS, GoogleVerifier
from app.services.social.kakao import KakaoVerifier
from tests.social_provider_fakes import (
    BODY_MARKER,
    FAR_FUTURE_EXP,
    GOOGLE_CLAIMS,
    KAKAO_TOKEN_INFO_PATH,
    OTHER_GOOGLE_CLIENT_ID,
    OTHER_KAKAO_APP_ID,
    SECRET_TOKEN,
    TEST_GOOGLE_CLIENT_IDS,
    TEST_KAKAO_APP_ID,
    install_transport,
    kakao_token_info,
    respond_json,
    respond_kakao,
    use_app_ids,
)

AUTH_FAILED_DETAIL = "소셜 인증에 실패했습니다."
BAD_RESPONSE_DETAIL = "소셜 로그인 제공자의 응답을 확인하지 못했습니다. 잠시 후 다시 시도해 주세요."
UNSUPPORTED_DETAIL = "지원하지 않는 소셜 로그인입니다."


@pytest.fixture(autouse=True)
def _app_ids(monkeypatch):
    use_app_ids(monkeypatch)


def _plain_auth_error(exc: BaseException) -> bool:
    return isinstance(exc, SocialAuthError) and not isinstance(exc, SocialProviderResponseError)


def _google_body(**overrides) -> dict:
    body = {**GOOGLE_CLAIMS, "sub": "g-3035", "email": "g3035@oncare.com", "name": "구글"}
    body.update(overrides)
    return {k: v for k, v in body.items() if v is not None}


def _verify_google():
    return asyncio.run(GoogleVerifier().verify(SECRET_TOKEN))


def _verify_kakao():
    return asyncio.run(KakaoVerifier().verify(SECRET_TOKEN))


def _no_network(monkeypatch) -> list:
    """요청이 나가면 기록만 하고 실패시킨다 — '외부 호출 없음'을 확인하는 데 쓴다."""

    def _fail(request):
        raise AssertionError(f"외부 호출이 나가면 안 된다: {request.url.host}")

    return install_transport(monkeypatch, _fail)


# ── 구글 ─────────────────────────────────────────────────────────


@pytest.mark.parametrize("aud", TEST_GOOGLE_CLIENT_IDS)
def test_google_any_allowed_audience_passes(monkeypatch, aud):
    respond_json(monkeypatch, _google_body(aud=aud))
    identity = _verify_google()
    assert identity.provider_user_id == "g-3035"


@pytest.mark.parametrize("iss", sorted(GOOGLE_ISSUERS))
def test_google_both_issuer_spellings_pass(monkeypatch, iss):
    respond_json(monkeypatch, _google_body(iss=iss))
    assert _verify_google().provider_user_id == "g-3035"


def test_google_integer_exp_is_accepted(monkeypatch):
    respond_json(monkeypatch, _google_body(exp=int(FAR_FUTURE_EXP)))
    assert _verify_google().provider_user_id == "g-3035"


@pytest.mark.parametrize(
    "overrides",
    [
        {"aud": OTHER_GOOGLE_CLIENT_ID},
        {"aud": None},
        {"aud": ""},
        {"aud": TEST_GOOGLE_CLIENT_IDS[0].upper()},
        {"aud": f" {TEST_GOOGLE_CLIENT_IDS[0]}"},
        {"iss": "https://evil.example.com"},
        {"iss": None},
        {"iss": "accounts.google.com.evil"},
        {"exp": "1"},
        {"exp": None},
        {"exp": ""},
    ],
    ids=[
        "other_app", "aud_missing", "aud_empty", "aud_case", "aud_padded",
        "wrong_iss", "iss_missing", "iss_lookalike",
        "expired", "exp_missing", "exp_empty",
    ],
)
def test_google_token_not_issued_for_us_is_rejected(monkeypatch, overrides):
    respond_json(monkeypatch, _google_body(**overrides))
    with pytest.raises(SocialAuthError) as info:
        _verify_google()
    assert _plain_auth_error(info.value)
    assert SECRET_TOKEN not in str(info.value)


def test_google_exp_equal_to_now_is_expired(monkeypatch):
    from app.core import clock

    now = int(clock.now().timestamp())
    respond_json(monkeypatch, _google_body(exp=str(now)))
    with pytest.raises(SocialAuthError):
        _verify_google()


@pytest.mark.parametrize(
    "overrides",
    [{"aud": ["a"]}, {"aud": 1}, {"iss": {"x": 1}}, {"exp": "soon"}, {"exp": True}, {"exp": 1.5}],
    ids=["aud_list", "aud_int", "iss_obj", "exp_word", "exp_bool", "exp_float"],
)
def test_google_malformed_claims_are_provider_response_errors(monkeypatch, overrides):
    respond_json(monkeypatch, _google_body(**overrides))
    with pytest.raises(SocialProviderResponseError):
        _verify_google()


@pytest.mark.parametrize("raw", ["", " ", " , ,"], ids=["empty", "blank", "only_commas"])
def test_google_without_allowed_ids_rejects_without_calling_google(monkeypatch, caplog, raw):
    use_app_ids(monkeypatch, google=raw)
    seen = _no_network(monkeypatch)
    caplog.set_level(logging.ERROR)
    with pytest.raises(SocialAuthError) as info:
        _verify_google()
    assert _plain_auth_error(info.value)
    assert seen == []
    assert any("GOOGLE_CLIENT_IDS" in r.getMessage() for r in caplog.records)


def test_google_audience_is_checked_before_reading_the_user(monkeypatch):
    """다른 앱 토큰이면 sub·email 형식이 이상해도 401 — 사용자 정보까지 가지 않는다."""
    respond_json(monkeypatch, _google_body(aud=OTHER_GOOGLE_CLIENT_ID, email=1))
    with pytest.raises(SocialAuthError) as info:
        _verify_google()
    assert _plain_auth_error(info.value)


# ── 카카오 ───────────────────────────────────────────────────────


def _kakao_user(uid=4815162342):
    return {"id": uid, "kakao_account": {"email": "k3035@oncare.com", "profile": {"nickname": "카카오"}}}


def test_kakao_matching_app_passes(monkeypatch):
    seen = respond_kakao(monkeypatch, token_info=kakao_token_info(4815162342), user=_kakao_user())
    identity = _verify_kakao()
    assert identity.provider_user_id == "4815162342"
    assert [r.url.path for r in seen] == [KAKAO_TOKEN_INFO_PATH, "/v2/user/me"]


def test_kakao_string_app_id_from_provider_is_compared_as_text(monkeypatch):
    info = {"id": 7, "expires_in": 100, "app_id": TEST_KAKAO_APP_ID}
    respond_kakao(monkeypatch, token_info=info, user=_kakao_user(7))
    assert _verify_kakao().provider_user_id == "7"


def test_kakao_setting_is_trimmed(monkeypatch):
    use_app_ids(monkeypatch, kakao=f"  {TEST_KAKAO_APP_ID} ")
    respond_kakao(monkeypatch, token_info=kakao_token_info(7), user=_kakao_user(7))
    assert _verify_kakao().provider_user_id == "7"


def test_kakao_other_app_is_rejected_before_reading_the_user(monkeypatch):
    seen = respond_kakao(
        monkeypatch,
        token_info=kakao_token_info(4815162342, app_id=OTHER_KAKAO_APP_ID),
        user=_kakao_user(),
    )
    with pytest.raises(SocialAuthError) as info:
        _verify_kakao()
    assert _plain_auth_error(info.value)
    assert [r.url.path for r in seen] == [KAKAO_TOKEN_INFO_PATH]


@pytest.mark.parametrize("app_id", [None, ""], ids=["missing", "empty"])
def test_kakao_token_info_without_app_id_is_rejected(monkeypatch, app_id):
    info = {"id": 7, "expires_in": 100}
    if app_id is not None:
        info["app_id"] = app_id
    respond_kakao(monkeypatch, token_info=info, user=_kakao_user(7))
    with pytest.raises(SocialAuthError) as exc:
        _verify_kakao()
    assert _plain_auth_error(exc.value)


@pytest.mark.parametrize("app_id", [True, 1.5, [424242], {"id": 1}], ids=["bool", "float", "list", "dict"])
def test_kakao_malformed_app_id_is_provider_response_error(monkeypatch, app_id):
    respond_kakao(
        monkeypatch, token_info={"id": 7, "app_id": app_id}, user=_kakao_user(7)
    )
    with pytest.raises(SocialProviderResponseError):
        _verify_kakao()


@pytest.mark.parametrize("status", [400, 401, 403, 500])
def test_kakao_token_info_rejection_is_auth_error(monkeypatch, status):
    seen = respond_kakao(
        monkeypatch,
        token_info={"msg": BODY_MARKER, "code": -401},
        token_info_status=status,
        user=_kakao_user(),
    )
    with pytest.raises(SocialAuthError) as info:
        _verify_kakao()
    assert _plain_auth_error(info.value)
    assert str(status) in str(info.value)
    assert BODY_MARKER not in str(info.value)
    assert [r.url.path for r in seen] == [KAKAO_TOKEN_INFO_PATH]


def test_kakao_token_info_html_is_provider_response_error(monkeypatch):
    respond_kakao(monkeypatch, token_info=f"<html>{BODY_MARKER}</html>".encode(), user=_kakao_user())
    with pytest.raises(SocialProviderResponseError) as info:
        _verify_kakao()
    assert BODY_MARKER not in str(info.value)


def test_kakao_user_id_must_match_token_info(monkeypatch):
    respond_kakao(monkeypatch, token_info=kakao_token_info(111), user=_kakao_user(222))
    with pytest.raises(SocialAuthError) as info:
        _verify_kakao()
    assert _plain_auth_error(info.value)


def test_kakao_token_info_without_user_id_is_rejected(monkeypatch):
    respond_kakao(
        monkeypatch,
        token_info={"expires_in": 100, "app_id": int(TEST_KAKAO_APP_ID)},
        user=_kakao_user(),
    )
    with pytest.raises(SocialAuthError) as info:
        _verify_kakao()
    assert _plain_auth_error(info.value)


def test_kakao_without_app_id_setting_rejects_without_calling_kakao(monkeypatch, caplog):
    use_app_ids(monkeypatch, kakao="  ")
    seen = _no_network(monkeypatch)
    caplog.set_level(logging.ERROR)
    with pytest.raises(SocialAuthError) as info:
        _verify_kakao()
    assert _plain_auth_error(info.value)
    assert seen == []
    assert any("KAKAO_APP_ID" in r.getMessage() for r in caplog.records)


# ── 설정 파싱 ─────────────────────────────────────────────────────


@pytest.mark.parametrize(
    "raw,expected",
    [
        ("", []),
        ("   ", []),
        (",,", []),
        ("a", ["a"]),
        (" a , b ", ["a", "b"]),
        ("a,,b,", ["a", "b"]),
        ("a,b,a", ["a", "b"]),
    ],
)
def test_client_id_lists_are_parsed(raw, expected):
    settings = Settings(_env_file=None, google_client_ids=raw)
    assert settings.google_client_id_list == expected


@pytest.mark.parametrize("raw,expected", [("", ""), ("  ", ""), (" 424242 ", "424242")])
def test_kakao_app_id_is_trimmed(raw, expected):
    assert Settings(_env_file=None, kakao_app_id=raw).kakao_app_id_value == expected


def test_social_app_settings_default_to_empty():
    settings = Settings(_env_file=None)
    assert settings.google_client_id_list == []
    assert settings.kakao_app_id_value == ""


# ── 기동 점검 ─────────────────────────────────────────────────────


def test_startup_warns_about_every_unconfigured_provider(caplog):
    caplog.set_level(logging.WARNING, logger="app.startup")
    warnings = startup_checks.check(Settings(_env_file=None))
    [social] = [w for w in warnings if "소셜 로그인" in w]
    for name in ("GOOGLE_CLIENT_IDS", "KAKAO_APP_ID"):
        assert name in social
    assert any("소셜 로그인" in r.getMessage() for r in caplog.records)


def test_startup_names_only_the_missing_provider():
    settings = Settings(_env_file=None, google_client_ids="g.apps.googleusercontent.com", kakao_app_id="")
    [social] = [w for w in startup_checks.check(settings) if "소셜 로그인" in w]
    assert "KAKAO_APP_ID" in social
    assert "GOOGLE_CLIENT_IDS" not in social


def test_startup_is_quiet_when_every_provider_is_configured():
    settings = Settings(_env_file=None, google_client_ids="g.apps.googleusercontent.com", kakao_app_id="1")
    assert not any("소셜 로그인" in w for w in startup_checks.check(settings))
    assert startup_checks.unconfigured_social_providers(settings) == []


# ── API: 다른 앱 토큰은 기존 계정에 연결되지 않는다 ───────────────────


def _login(client, provider: str):
    return client.post(f"/v1/auth/social/{provider}", json={"token": SECRET_TOKEN})


def _register(client) -> str:
    email = f"sub-{uuid4().hex[:10]}@oncare.com"
    r = client.post(
        "/v1/auth/register", json={"email": email, "password": "test-pw-1234", "name": "기존회원"}
    )
    assert r.status_code in (200, 201), r.text
    return email


def _social_links(db, email: str) -> int:
    from app.models.models import SocialAccount, User

    db.expire_all()
    return db.scalar(
        select(func.count())
        .select_from(SocialAccount)
        .join(User, User.id == SocialAccount.user_id)
        .where(func.lower(User.email) == email)
    )


def _failed_audits(db, provider: str) -> int:
    from app.models.models import AuditLog

    db.expire_all()
    return db.scalar(
        select(func.count()).select_from(AuditLog).where(
            AuditLog.event == "auth.social",
            AuditLog.success.is_(False),
            AuditLog.detail == provider,
        )
    )


def test_api_google_token_of_another_app_does_not_take_over_an_account(client, db_session, monkeypatch):
    email = _register(client)
    before = _failed_audits(db_session, "google")
    respond_json(
        monkeypatch,
        _google_body(aud=OTHER_GOOGLE_CLIENT_ID, sub=f"g-{uuid4().hex[:8]}", email=email),
    )

    r = _login(client, "google")

    assert r.status_code == 401, r.text
    assert r.json()["detail"] == AUTH_FAILED_DETAIL
    assert "access_token" not in r.json()
    assert _social_links(db_session, email) == 0
    assert _failed_audits(db_session, "google") == before + 1


def test_api_kakao_token_of_another_app_does_not_take_over_an_account(client, db_session, monkeypatch):
    email = _register(client)
    before = _failed_audits(db_session, "kakao")
    uid = int(uuid4().int % 10**10)
    user = {"id": uid, "kakao_account": {"email": email, "profile": {"nickname": "남의앱"}}}
    respond_kakao(
        monkeypatch, token_info=kakao_token_info(uid, app_id=OTHER_KAKAO_APP_ID), user=user
    )

    r = _login(client, "kakao")

    assert r.status_code == 401, r.text
    assert r.json()["detail"] == AUTH_FAILED_DETAIL
    assert _social_links(db_session, email) == 0
    assert _failed_audits(db_session, "kakao") == before + 1


def test_api_kakao_token_of_our_app_still_links_the_same_email(client, db_session, monkeypatch):
    """회귀: 우리 앱 토큰이면 지금처럼 같은 이메일 계정에 연결된다(#1551 범위는 그대로)."""
    email = _register(client)
    uid = int(uuid4().int % 10**10)
    user = {"id": uid, "kakao_account": {"email": email, "profile": {"nickname": "우리앱"}}}
    respond_kakao(monkeypatch, token_info=kakao_token_info(uid), user=user)

    r = _login(client, "kakao")

    assert r.status_code == 200, r.text
    assert _social_links(db_session, email) == 1


@pytest.mark.parametrize("provider", ["google", "kakao"])
def test_api_unconfigured_provider_answers_401(client, db_session, monkeypatch, provider):
    use_app_ids(monkeypatch, google="", kakao="")
    seen = _no_network(monkeypatch)
    before = _failed_audits(db_session, provider)

    r = _login(client, provider)

    assert r.status_code == 401, r.text
    assert r.json()["detail"] == AUTH_FAILED_DETAIL
    assert seen == []
    assert _failed_audits(db_session, provider) == before + 1


def test_api_malformed_kakao_token_info_answers_502(client, monkeypatch):
    respond_kakao(monkeypatch, token_info=b"<html>maintenance</html>", user=_kakao_user())

    r = _login(client, "kakao")

    assert r.status_code == 502, r.text
    assert r.json()["detail"] == BAD_RESPONSE_DETAIL


@pytest.mark.parametrize("provider", ["naver", "apple"])
def test_api_dropped_provider_answers_400_and_creates_nothing(
    client, db_session, monkeypatch, provider
):
    """네이버·애플은 제공하지 않는다(#3218) — 외부 호출 없이 모르는 provider 와 같은 400."""
    from app.models.models import SocialAccount

    seen = _no_network(monkeypatch)
    db_session.expire_all()
    before = db_session.scalar(select(func.count()).select_from(SocialAccount))

    r = _login(client, provider)

    assert r.status_code == 400, r.text
    assert r.json()["detail"] == UNSUPPORTED_DETAIL
    assert seen == []
    db_session.expire_all()
    assert db_session.scalar(select(func.count()).select_from(SocialAccount)) == before
