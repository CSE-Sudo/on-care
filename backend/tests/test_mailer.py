"""메일 발송 계층과 발송 설정(#2824) — DB 불필요.

실제 SMTP 서버에는 붙지 않는다. `smtplib.SMTP` 를 가짜로 바꿔 끼워 무엇을 어떤
순서로 부르는지만 본다.
"""
from __future__ import annotations

import logging
import smtplib

import pytest
from pydantic import ValidationError

from app.core.config import Settings
from app.services import mailer
from app.services.mailer import (
    LogMailer,
    MailDeliveryError,
    OutgoingMail,
    SmtpMailer,
    get_mailer,
    mask_email,
    warn_if_disabled,
)

_PROD = dict(
    _env_file=None,
    env="prod",
    jwt_secret="a-strong-random-secret-value",
    cors_allow_origins="https://app.example.com",
    seed_demo_data=False,
    auto_create_tables=False,
    gemini_api_key="test-gemini-key",  # 운영 AI 키 가드(#2812) 충족
)

_SMTP = dict(smtp_host="smtp.example.com", mail_from="On-Care <no-reply@example.com>")


def _mail() -> OutgoingMail:
    return OutgoingMail(to="member@example.com", subject="제목", body="본문 CODE-1234")


# ---- 설정 ----


def test_auto_without_smtp_is_log_backend():
    s = Settings(_env_file=None)
    assert s.mail_provider == "auto"
    assert s.mail_backend == "log"


def test_auto_with_smtp_host_and_sender_is_smtp():
    assert Settings(_env_file=None, **_SMTP).mail_backend == "smtp"


def test_auto_with_host_but_no_sender_stays_log():
    """발신 주소가 없으면 보낼 수 없다 — 반쪽 설정으로 smtp 를 고르지 않는다."""
    assert Settings(_env_file=None, smtp_host="smtp.example.com").mail_backend == "log"


def test_dev_log_backend_keeps_reset_enabled():
    """개발은 로그 발송으로도 재설정을 켠다 — 로그에서 코드를 읽어 확인한다."""
    assert Settings(_env_file=None).mail_enabled is True


def test_prod_without_mail_disables_reset_but_boots():
    """운영에서 발송 수단이 없으면 재설정만 꺼진다. 기동은 막지 않는다."""
    s = Settings(**_PROD)
    assert s.mail_backend == "log"
    assert s.mail_enabled is False


def test_prod_with_smtp_enables_reset():
    assert Settings(**_PROD, **_SMTP).mail_enabled is True


def test_prod_forced_log_is_disabled():
    """운영에서 log 를 고르면 꺼진다 — 로그를 읽는 사람이 계정을 되찾게 된다."""
    assert Settings(**_PROD, **_SMTP, mail_provider="log").mail_enabled is False


@pytest.mark.parametrize(
    "kw",
    [
        {"mail_provider": "smtp"},
        {"mail_provider": "smtp", "smtp_host": "smtp.example.com"},
        {"mail_provider": "smtp", "mail_from": "no-reply@example.com"},
    ],
)
def test_explicit_smtp_without_host_or_sender_fails_boot(kw):
    """SMTP 를 명시하고 반쪽만 채우면 설정 실수 — 조용히 log 로 떨어뜨리지 않는다."""
    with pytest.raises(ValidationError):
        Settings(_env_file=None, **kw)


def test_reset_defaults():
    s = Settings(_env_file=None)
    assert s.password_reset_token_minutes == 30
    assert s.password_reset_email_per_window == 3
    assert s.password_reset_email_window_minutes == 15
    assert s.password_reset_member_url == ""
    assert s.password_reset_trainer_url == ""


# ---- 고르기 ----


def test_get_mailer_picks_backend():
    assert isinstance(get_mailer(Settings(_env_file=None)), LogMailer)
    assert isinstance(get_mailer(Settings(_env_file=None, **_SMTP)), SmtpMailer)


def test_warn_if_disabled_logs_error_in_prod(caplog):
    with caplog.at_level(logging.ERROR, logger=mailer.__name__):
        assert warn_if_disabled(Settings(**_PROD)) is False
    assert any(r.levelno == logging.ERROR for r in caplog.records)


def test_warn_if_disabled_ok_with_smtp(caplog):
    with caplog.at_level(logging.WARNING, logger=mailer.__name__):
        assert warn_if_disabled(Settings(**_PROD, **_SMTP)) is True
    assert not caplog.records


def test_warn_if_disabled_warns_in_dev_log_mode(caplog):
    with caplog.at_level(logging.WARNING, logger=mailer.__name__):
        assert warn_if_disabled(Settings(_env_file=None)) is True
    assert any(r.levelno == logging.WARNING for r in caplog.records)


# ---- 가림 ----


@pytest.mark.parametrize(
    ("address", "masked"),
    [
        ("member@example.com", "me***@example.com"),
        ("a@example.com", "a***@example.com"),
        ("not-an-email", "***"),
    ],
)
def test_mask_email(address, masked):
    assert mask_email(address) == masked


# ---- log ----


def test_log_mailer_keeps_body_out_of_warning(caplog):
    """본문(코드)은 DEBUG 로만 — 운영 로그 수준에서는 코드가 남지 않는다."""
    with caplog.at_level(logging.WARNING, logger=mailer.__name__):
        LogMailer().send(_mail())
    text = "\n".join(r.getMessage() for r in caplog.records)
    assert "CODE-1234" not in text
    assert "member@example.com" not in text
    assert "me***@example.com" in text


def test_log_mailer_body_at_debug(caplog):
    with caplog.at_level(logging.DEBUG, logger=mailer.__name__):
        LogMailer().send(_mail())
    assert any("CODE-1234" in r.getMessage() for r in caplog.records)


# ---- smtp ----


class _FakeSMTP:
    instances: list["_FakeSMTP"] = []
    fail_on: str | None = None

    def __init__(self, host, port, timeout=None, context=None):
        self.host, self.port, self.timeout = host, port, timeout
        self.calls: list[str] = []
        self.sent = []
        _FakeSMTP.instances.append(self)
        if _FakeSMTP.fail_on == "connect":
            raise OSError("connection refused")

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.calls.append("quit")
        return False

    def starttls(self, context=None):
        self.calls.append("starttls")

    def login(self, user, password):
        self.calls.append(f"login:{user}")
        if _FakeSMTP.fail_on == "login":
            raise smtplib.SMTPAuthenticationError(535, b"bad credentials")

    def send_message(self, msg):
        self.calls.append("send")
        self.sent.append(msg)


@pytest.fixture
def fake_smtp(monkeypatch):
    _FakeSMTP.instances = []
    _FakeSMTP.fail_on = None
    monkeypatch.setattr(mailer.smtplib, "SMTP", _FakeSMTP)
    monkeypatch.setattr(mailer.smtplib, "SMTP_SSL", _FakeSMTP)
    return _FakeSMTP


def test_smtp_starttls_login_send(fake_smtp):
    s = Settings(
        _env_file=None, **_SMTP, smtp_username="user", smtp_password="pw", smtp_port=587
    )
    SmtpMailer(s).send(_mail())
    conn = fake_smtp.instances[0]
    assert (conn.host, conn.port) == ("smtp.example.com", 587)
    assert conn.calls == ["starttls", "login:user", "send", "quit"]
    msg = conn.sent[0]
    assert msg["To"] == "member@example.com"
    assert msg["Subject"] == "제목"
    assert "no-reply@example.com" in msg["From"]
    assert "CODE-1234" in msg.get_content()


def test_smtp_without_username_skips_login(fake_smtp):
    SmtpMailer(Settings(_env_file=None, **_SMTP)).send(_mail())
    assert fake_smtp.instances[0].calls == ["starttls", "send", "quit"]


def test_smtp_ssl_skips_starttls(fake_smtp):
    SmtpMailer(Settings(_env_file=None, **_SMTP, smtp_ssl=True, smtp_port=465)).send(
        _mail()
    )
    assert "starttls" not in fake_smtp.instances[0].calls


@pytest.mark.parametrize("stage", ["connect", "login"])
def test_smtp_failure_becomes_delivery_error(fake_smtp, stage):
    fake_smtp.fail_on = stage
    s = Settings(_env_file=None, **_SMTP, smtp_username="user", smtp_password="pw")
    with pytest.raises(MailDeliveryError):
        SmtpMailer(s).send(_mail())
