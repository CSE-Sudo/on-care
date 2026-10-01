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
