"""카카오·구글 로그인 실연동 설정과 API 경계 (#330).

- 기동 점검: 허용 앱 값의 **형식**이 틀리면 기동을 막는다(비운 값은 경고만, #3035).
  카카오 앱 ID 자리에 REST 키를, 구글 client_id 자리에 다른 값을 넣는 실수를 잡는다.
- 기동 점검: 카카오 앱 ID 만 있고 웹 로그인 키가 없으면 경고한다(웹만 401 이 되는 상황).
- API: 만료 토큰은 401, 이메일이 없거나 동의하지 않은 계정은 자리표시 이메일로 새 계정을
  만들고, 같은 provider 계정으로 다시 들어오면 같은 사용자다.

provider HTTP 는 `httpx.MockTransport` 로 흉내 낸다.
"""
from __future__ import annotations

from uuid import uuid4

import httpx
import pytest
from sqlalchemy import select

from app.core import startup_checks
from app.core.config import Settings
from app.core.startup_checks import StartupConfigError
from tests.social_provider_fakes import (
    GOOGLE_CLAIMS,
    KAKAO_TOKEN_INFO_PATH,
    SECRET_TOKEN,
    TEST_GOOGLE_CLIENT_IDS,
    install_transport,
    kakao_token_info,
    respond_json,
    respond_kakao,
    use_app_ids,
)

AUTH_FAILED_DETAIL = "소셜 인증에 실패했습니다."
WEB_KEY_WARNING = "KAKAO_LOGIN_REST_API_KEY"


def _settings(**kw) -> Settings:
    base = dict(
        _env_file=None,
        google_client_ids="web.apps.googleusercontent.com",
        kakao_app_id="1234567",
        kakao_login_rest_api_key="testloginkey",
    )
    base.update(kw)
    return Settings(**base)


# ── 기동 점검: 형식 ──────────────────────────────────────────────────


def test_valid_social_settings_have_no_problems():
    settings = _settings(
        google_client_ids=(
            "123-web.apps.googleusercontent.com, 123-android.apps.googleusercontent.com,"
            "123-ios.apps.googleusercontent.com"
        )
    )
    assert startup_checks.social_setting_problems(settings) == []


def test_empty_social_settings_are_not_format_problems():
    """비운 값은 그 provider 만 거부하는 경고 대상이지 형식 오류가 아니다."""
    settings = _settings(google_client_ids="", kakao_app_id="", kakao_login_rest_api_key="")
    assert startup_checks.social_setting_problems(settings) == []


@pytest.mark.parametrize(
    "value",
    ["0123456789abcdef0123456789abcdef", "kakao-app", "12 34", "-1234", "1234.0"],
)
def test_non_numeric_kakao_app_id_stops_startup(value):
    settings = _settings(kakao_app_id=value)

    [problem] = startup_checks.social_setting_problems(settings)
    assert "KAKAO_APP_ID" in problem
    assert value not in problem
    with pytest.raises(StartupConfigError) as info:
        startup_checks.check(settings)
    assert "KAKAO_APP_ID" in str(info.value)


def test_kakao_app_id_surrounding_spaces_are_ignored():
    assert startup_checks.social_setting_problems(_settings(kakao_app_id="  1234567  ")) == []


@pytest.mark.parametrize(
    "value",
    [
        "GOCSPX-not-a-client-id",
        "123456789012",
        "apps.googleusercontent.com",
        "web.apps.googleusercontent.com.evil.example",
        "web.apps.googleusercontent.test",
    ],
)
def test_malformed_google_client_id_stops_startup(value):
    settings = _settings(google_client_ids=f"ok.apps.googleusercontent.com,{value}")

    [problem] = startup_checks.social_setting_problems(settings)
    assert "GOOGLE_CLIENT_IDS" in problem
    assert "1개" in problem
    assert value not in problem
    with pytest.raises(StartupConfigError):
        startup_checks.check(settings)


def test_both_problems_are_reported_together():
    settings = _settings(kakao_app_id="restkey", google_client_ids="secret,other")

    problems = startup_checks.social_setting_problems(settings)

    assert len(problems) == 2
    assert "2개" in problems[1]
    with pytest.raises(StartupConfigError) as info:
        startup_checks.check(settings)
    assert "KAKAO_APP_ID" in str(info.value)
    assert "GOOGLE_CLIENT_IDS" in str(info.value)


# ── 기동 점검: 웹 로그인 키 ──────────────────────────────────────────


def test_kakao_app_id_without_web_login_key_warns():
    warnings = startup_checks.check(_settings(kakao_login_rest_api_key=""))

    [warning] = [w for w in warnings if WEB_KEY_WARNING in w]
    assert "KAKAO_APP_ID" in warning
    # 소셜 허용 앱 누락 경고(#3035)와 섞이지 않는다.
    assert "소셜 로그인" not in warning


def test_web_login_key_present_is_quiet():
    warnings = startup_checks.check(_settings())
    assert not any(WEB_KEY_WARNING in w for w in warnings)


def test_no_kakao_app_means_no_web_key_warning():
    """카카오 자체를 끈 환경에는 웹 키 경고를 따로 내지 않는다(누락 경고 하나로 충분)."""
    warnings = startup_checks.check(_settings(kakao_app_id="", kakao_login_rest_api_key=""))
    assert not any(WEB_KEY_WARNING in w for w in warnings)


def test_web_login_settings_are_stripped_and_secret_hidden():
    settings = _settings(kakao_login_rest_api_key="  key  ", kakao_client_secret="  s3cret  ")

    assert settings.kakao_login_rest_api_key_value == "key"
    assert settings.kakao_client_secret_value == "s3cret"
    assert "s3cret" not in repr(settings)


# ── API: 만료·이메일 없음 ────────────────────────────────────────────


@pytest.fixture()
def _app_ids(monkeypatch):
    use_app_ids(monkeypatch)


def _login(client, provider: str):
    return client.post(f"/v1/auth/social/{provider}", json={"token": SECRET_TOKEN})


def _user_of(db, provider: str, provider_user_id: str):
    from app.models.models import SocialAccount, User

    db.expire_all()
    account = db.scalar(
        select(SocialAccount).where(
            SocialAccount.provider == provider,
            SocialAccount.provider_user_id == provider_user_id,
        )
    )
    if account is None:
        return None
    return db.scalar(select(User).where(User.id == account.user_id))


@pytest.mark.usefixtures("_app_ids")
def test_api_expired_google_token_is_401(client, monkeypatch):
    respond_json(monkeypatch, {**GOOGLE_CLAIMS, "exp": "1000", "sub": f"g-{uuid4().hex[:8]}"})

    r = _login(client, "google")

    assert r.status_code == 401, r.text
    assert r.json()["detail"] == AUTH_FAILED_DETAIL


@pytest.mark.usefixtures("_app_ids")
def test_api_google_rejecting_the_token_is_401(client, monkeypatch):
    """tokeninfo 는 만료·위조 토큰에 400 invalid_token 을 준다."""
    install_transport(
        monkeypatch,
        lambda _r: httpx.Response(400, json={"error": "invalid_token", "error_description": "Invalid Value"}),
    )

    r = _login(client, "google")

    assert r.status_code == 401, r.text


@pytest.mark.usefixtures("_app_ids")
def test_api_expired_kakao_token_is_401(client, monkeypatch):
    """카카오는 만료 토큰에 토큰 정보 조회부터 401(code -401)을 준다."""
    respond_kakao(
        monkeypatch,
        token_info={"msg": "this access token does not exist", "code": -401},
        token_info_status=401,
        user={"id": 1},
    )

    r = _login(client, "kakao")

    assert r.status_code == 401, r.text
    assert r.json()["detail"] == AUTH_FAILED_DETAIL


@pytest.mark.usefixtures("_app_ids")
def test_api_google_without_email_creates_placeholder_account(client, db_session, monkeypatch):
    sub = f"g-{uuid4().hex[:10]}"
    respond_json(monkeypatch, {**GOOGLE_CLAIMS, "aud": TEST_GOOGLE_CLIENT_IDS[1], "sub": sub})

    r = _login(client, "google")

    assert r.status_code == 200, r.text
    user = _user_of(db_session, "google", sub)
    assert user is not None
    assert user.email == f"google_{sub}@social.oncare".lower()
    assert user.name == "google"


@pytest.mark.usefixtures("_app_ids")
@pytest.mark.parametrize(
    "account",
    [
        None,
        {},
        # 이메일 동의 항목을 거부하면 email 없이 email_needs_agreement 만 온다.
        {"has_email": True, "email_needs_agreement": True, "profile": {"nickname": "동의안함"}},
        {"has_email": False, "profile_nickname_needs_agreement": True},
    ],
    ids=["no_account", "empty_account", "email_not_consented", "no_email"],
)
def test_api_kakao_without_email_creates_placeholder_account(client, db_session, monkeypatch, account):
    uid = int(uuid4().int % 10**10)
    user_body: dict = {"id": uid}
    if account is not None:
        user_body["kakao_account"] = account
    respond_kakao(monkeypatch, token_info=kakao_token_info(uid), user=user_body)

    r = _login(client, "kakao")

    assert r.status_code == 200, r.text
    user = _user_of(db_session, "kakao", str(uid))
    assert user is not None
    assert user.email == f"kakao_{uid}@social.oncare"


@pytest.mark.usefixtures("_app_ids")
def test_api_kakao_without_email_returns_to_the_same_account(client, db_session, monkeypatch):
    uid = int(uuid4().int % 10**10)
    respond_kakao(monkeypatch, token_info=kakao_token_info(uid), user={"id": uid})

    first = _login(client, "kakao")
    second = _login(client, "kakao")

    assert first.status_code == 200, first.text
    assert second.status_code == 200, second.text
    user = _user_of(db_session, "kakao", str(uid))
    assert user is not None
    from app.models.models import SocialAccount

    db_session.expire_all()
    links = db_session.scalars(
        select(SocialAccount).where(SocialAccount.provider == "kakao", SocialAccount.provider_user_id == str(uid))
    ).all()
    assert len(links) == 1


@pytest.mark.usefixtures("_app_ids")
def test_api_kakao_with_consented_email_uses_it(client, db_session, monkeypatch):
    uid = int(uuid4().int % 10**10)
    email = f"KWeb-{uuid4().hex[:8]}@Oncare.com"
    respond_kakao(
        monkeypatch,
        token_info=kakao_token_info(uid),
        user={
            "id": uid,
            "kakao_account": {
                "email": email,
                "is_email_valid": True,
                "is_email_verified": True,
                "profile": {"nickname": "동의함"},
            },
        },
    )

    r = _login(client, "kakao")

    assert r.status_code == 200, r.text
    user = _user_of(db_session, "kakao", str(uid))
    assert user.email == email.lower()
    assert user.name == "동의함"


@pytest.mark.usefixtures("_app_ids")
def test_api_kakao_token_info_and_profile_ids_must_match(client, monkeypatch):
    """토큰 정보와 사용자 정보의 id 가 다르면(응답 혼선) 로그인시키지 않는다."""
    respond_kakao(monkeypatch, token_info=kakao_token_info(111), user={"id": 222})

    r = _login(client, "kakao")

    assert r.status_code == 401, r.text


def test_api_kakao_web_token_path_matches_mobile(client, monkeypatch):
    """웹(코드 교환 뒤)과 모바일(SDK)은 같은 엔드포인트·같은 검증을 탄다 — 토큰 정보 조회가 먼저."""
    use_app_ids(monkeypatch)
    uid = int(uuid4().int % 10**10)
    order: list[str] = []

    def _handler(request: httpx.Request) -> httpx.Response:
        order.append(request.url.path)
        if request.url.path == KAKAO_TOKEN_INFO_PATH:
            return httpx.Response(200, json=kakao_token_info(uid))
        return httpx.Response(200, json={"id": uid})

    install_transport(monkeypatch, _handler)

    r = _login(client, "kakao")

    assert r.status_code == 200, r.text
    assert order[0] == KAKAO_TOKEN_INFO_PATH
    assert order[-1] == "/v2/user/me"
