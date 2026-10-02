"""기동 설정 점검 — DB 불필요. (#2817·#2821)"""
from __future__ import annotations

import logging

import pytest

from app.core import startup_checks
from app.core.config import Settings


def _prod(**kw) -> Settings:
    base = dict(
        _env_file=None,
        env="prod",
        jwt_secret="a-strong-random-secret-value",
        cors_allow_origins="https://app.oncare.com",
        seed_demo_data=False,
        auto_create_tables=False,
        # 운영은 사진 인식·임베딩 키가 필수다(#2812). conftest 가 EMBEDDER=hash 를
        # 환경변수로 심으므로 운영 값을 명시한다.
        gemini_api_key="test-gemini-key",
        recognizer="gemini",
        embedder="gemini",
    )
    base.update(kw)
    return Settings(**base)


def test_forcing_s3_without_a_bucket_stops_startup():
    settings = Settings(_env_file=None, attachment_storage="s3")
    with pytest.raises(startup_checks.StartupConfigError):
        startup_checks.check(settings)


def test_prod_on_local_disk_is_warned(caplog):
    with caplog.at_level(logging.WARNING, logger="app.startup"):
        warnings = startup_checks.check(_prod())
    assert any("ATTACHMENT_S3_BUCKET" in w for w in warnings)
    assert "ATTACHMENT_S3_BUCKET" in caplog.text


def test_prod_with_a_bucket_has_no_storage_warning():
    warnings = startup_checks.check(_prod(attachment_s3_bucket="oncare-prod"))
    assert not any("ATTACHMENT_S3_BUCKET" in w for w in warnings)


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


def test_prod_with_demo_seed_is_warned():
    settings = _prod(seed_demo_data=True, demo_login_password="a-long-demo-password")
    warnings = startup_checks.check(settings)
    assert any("SEED_DEMO_DATA" in w for w in warnings)
    # 운영에서는 폴백이 늘 꺼지므로 폴백 경고는 없다.
    assert not any("데모 폴백" in w for w in warnings)
