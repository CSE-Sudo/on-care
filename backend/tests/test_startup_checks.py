"""기동 설정 점검 — DB 불필요. (#2817·#2821·#3029)"""
from __future__ import annotations

import logging

import pytest

from app.core import startup_checks
from app.core.config import Settings


def _prod(**kw) -> Settings:
    base = dict(
        _env_file=None,
        env="prod",
        jwt_secret="a-strong-random-secret-value-for-prod-tests",
        cors_allow_origins="https://app.oncare.com",
        seed_demo_data=False,
        auto_create_tables=False,
        # 운영은 사진 인식·임베딩 키가 필수다(#2812). conftest 가 EMBEDDER=hash 를
        # 환경변수로 심으므로 운영 값을 명시한다.
        gemini_api_key="test-gemini-key",
        recognizer="gemini",
        embedder="gemini",
        # 운영은 장소 검색 키가 비면 오류 로그를 남긴다(#3161).
        kakao_rest_api_key="test-kakao-rest-key",
        # 운영은 첨부를 S3 에 둬야 기동한다(#3029).
        attachment_s3_bucket="oncare-prod",
        # 운영은 소셜 토큰의 발급 앱을 확인한다(#3035). 비우면 그 provider 로그인을
        # 거부한다는 경고가 뜬다.
        google_client_ids="test-google-client.apps.googleusercontent.com",
        kakao_app_id="1234567",
        apple_client_ids="com.example.oncare",
        # 운영은 메일 발송 설정이 필수다 — 없으면 가입 인증 코드를 못 보내 기동 거부(#3131).
        smtp_host="smtp.example.com",
        mail_from="no-reply@example.com",
    )
    base.update(kw)
    return Settings(**base)


def test_forcing_s3_without_a_bucket_stops_startup():
    settings = Settings(_env_file=None, attachment_storage="s3")
    with pytest.raises(startup_checks.StartupConfigError):
        startup_checks.check(settings)


def test_prod_on_local_disk_is_refused():
    # 키를 빠뜨려 auto 가 로컬로 풀리면 경고가 아니라 기동 거부다(#3029).
    with pytest.raises(startup_checks.StartupConfigError, match="ATTACHMENT_S3_BUCKET"):
        startup_checks.check(_prod(attachment_s3_bucket=""))


def test_prod_forcing_local_storage_is_refused():
    with pytest.raises(startup_checks.StartupConfigError, match="ATTACHMENT_STORAGE=s3"):
        startup_checks.check(_prod(attachment_storage="local"))


def test_prod_with_blank_bucket_is_refused():
    # 공백만 있는 버킷 이름도 비어 있는 것으로 본다.
    with pytest.raises(startup_checks.StartupConfigError):
        startup_checks.check(_prod(attachment_s3_bucket="   "))


def test_prod_alias_production_is_also_refused():
    with pytest.raises(startup_checks.StartupConfigError):
        startup_checks.check(_prod(env="production", attachment_s3_bucket=""))


def test_prod_with_a_bucket_has_no_storage_warning():
    warnings = startup_checks.check(_prod(attachment_s3_bucket="oncare-prod"))
    assert not any("ATTACHMENT_S3_BUCKET" in w for w in warnings)


def test_prod_forcing_s3_with_a_bucket_passes():
    warnings = startup_checks.check(
        _prod(attachment_storage="s3", attachment_s3_bucket="oncare-prod")
    )
    assert warnings == []


def test_staging_on_local_disk_is_only_warned(caplog):
    settings = Settings(_env_file=None, env="staging")
    with caplog.at_level(logging.WARNING, logger="app.startup"):
        warnings = startup_checks.check(settings)
    assert any("ATTACHMENT_S3_BUCKET" in w for w in warnings)
    assert "ATTACHMENT_S3_BUCKET" in caplog.text


def test_local_development_on_disk_is_not_warned_about_storage():
    warnings = startup_checks.check(Settings(_env_file=None))
    assert not any("ATTACHMENT_S3_BUCKET" in w for w in warnings)


# --- 데모 폴백·데모 시드(#2821) ---


def test_demo_fallback_on_is_warned(caplog):
    settings = Settings(_env_file=None, allow_demo_fallback=True)
    with caplog.at_level(logging.WARNING, logger="app.startup"):
        warnings = startup_checks.check(settings)
    assert any("데모 폴백" in w for w in warnings)
    assert "데모 폴백" in caplog.text


def test_default_settings_have_no_demo_fallback_warning(monkeypatch):
    monkeypatch.delenv("ALLOW_DEMO_FALLBACK", raising=False)
    warnings = startup_checks.check(Settings(_env_file=None))
    assert not any("데모 폴백" in w for w in warnings)


def test_prod_with_demo_seed_is_refused_before_startup_checks():
    # 경고로 남기지 않고 설정 단계에서 막는다 — 비밀번호가 강해도 같다(#2811).
    with pytest.raises(ValueError, match="SEED_DEMO_DATA"):
        _prod(seed_demo_data=True, demo_login_password="a-long-demo-password")


def test_prod_without_demo_seed_has_no_demo_warning():
    warnings = startup_checks.check(_prod())
    # 운영에서는 폴백이 늘 꺼지고 시드도 켤 수 없어 데모 경고가 없다.
    assert not any("데모" in w for w in warnings)


# --- 비밀번호 재설정 메일 링크(#3033) ---

_MEMBER_HASH_URL = "https://oncare.example/frontend/#/auth/password-reset"
_TRAINER_HASH_URL = "https://oncare.example/trainer/#/auth/password-reset"


def _reset_warnings(settings: Settings) -> list[str]:
    return [w for w in startup_checks.check(settings) if "PASSWORD_RESET_" in w]


def test_prod_path_style_reset_url_is_warned(caplog):
    settings = _prod(
        attachment_s3_bucket="oncare-prod",
        password_reset_member_url="https://oncare.example/auth/password-reset",
        password_reset_trainer_url=_TRAINER_HASH_URL,
    )
    with caplog.at_level(logging.WARNING, logger="app.startup"):
        warnings = _reset_warnings(settings)
    assert len(warnings) == 1
    assert "PASSWORD_RESET_MEMBER_URL" in warnings[0]
    assert "PASSWORD_RESET_MEMBER_URL" in caplog.text


def test_prod_plain_http_reset_url_is_warned():
    settings = _prod(
        attachment_s3_bucket="oncare-prod",
        password_reset_trainer_url="http://oncare.example/trainer/#/auth/password-reset",
    )
    warnings = _reset_warnings(settings)
    assert len(warnings) == 1
    assert "PASSWORD_RESET_TRAINER_URL" in warnings[0]


def test_prod_hash_style_reset_urls_are_not_warned():
    settings = _prod(
        attachment_s3_bucket="oncare-prod",
        password_reset_member_url=_MEMBER_HASH_URL,
        password_reset_trainer_url=_TRAINER_HASH_URL,
    )
    assert _reset_warnings(settings) == []


def test_prod_empty_reset_urls_are_not_warned():
    """비어 있으면 코드만 보내는 정상 동작이다."""
    assert _reset_warnings(_prod(attachment_s3_bucket="oncare-prod")) == []


def test_dev_reset_urls_are_not_checked():
    settings = Settings(
        _env_file=None,
        password_reset_member_url="http://localhost:5173/auth/password-reset",
    )
    assert _reset_warnings(settings) == []
