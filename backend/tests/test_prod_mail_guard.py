"""운영 메일 미설정 기동 거부(#3131) — DB 불필요.

운영은 가입 이메일 확인을 끌 수 없다(#3038). 메일을 보낼 수 없으면 가입 인증 코드를
받을 수 없어 회원 앱·트레이너 웹의 신규 가입이 모두 막히고, 비밀번호 재설정도 503 이
된다. 그런 배포가 헬스체크·배포 검증을 통과한 뒤 첫 가입 시도에서야 드러나지 않도록
`Settings` 생성 단계에서 막는지 본다.
"""
from __future__ import annotations

import pytest
from pydantic import ValidationError

from app.core.config import Settings

_PROD = dict(
    _env_file=None,
    env="prod",
    jwt_secret="a-strong-random-secret-value-for-prod-tests",
    cors_allow_origins="https://app.oncare.com",
    seed_demo_data=False,
    auto_create_tables=False,
    # 운영 AI 키 가드(#2812) 충족. conftest 가 EMBEDDER=hash 를 환경변수로 심으므로
    # 운영 값을 명시한다.
    gemini_api_key="test-gemini-key",
    recognizer="gemini",
    embedder="gemini",
)

_SMTP = dict(smtp_host="smtp.example.com", mail_from="On-Care <no-reply@example.com>")


def _prod(**kw) -> Settings:
    return Settings(**{**_PROD, **kw})


# ---- 운영: 기동 거부 ----


def test_prod_without_any_mail_setting_fails():
    with pytest.raises(ValidationError) as excinfo:
        _prod()
    message = str(excinfo.value)
    # 무엇이 막히는지(가입·재설정)와 무엇을 채워야 하는지 함께 알려 준다.
    assert "가입" in message
    assert "재설정" in message
    for key in ("SMTP_HOST", "MAIL_FROM", "SMTP_USERNAME", "SMTP_PASSWORD"):
        assert key in message, key


@pytest.mark.parametrize(
    "kw",
    [
        {"smtp_host": "smtp.example.com"},
        {"mail_from": "no-reply@example.com"},
        {"smtp_host": "   ", "mail_from": "no-reply@example.com"},
        {"smtp_host": "smtp.example.com", "mail_from": "  "},
    ],
    ids=["host-only", "sender-only", "blank-host", "blank-sender"],
)
def test_prod_with_half_mail_setting_fails(kw):
    """서버·발신 주소 중 하나라도 비면 auto 는 log 로 떨어진다 — 운영에서는 거부."""
    with pytest.raises(ValidationError, match="메일 발송 설정"):
        _prod(**kw)


def test_prod_forcing_log_backend_fails_even_with_smtp_values():
    """운영에서 log 발송은 메일을 끈 것과 같다 — 코드가 로그에만 남는다."""
    with pytest.raises(ValidationError, match="메일 발송 설정"):
        _prod(**_SMTP, mail_provider="log")


def test_prod_alias_production_is_also_guarded():
    with pytest.raises(ValidationError, match="메일 발송 설정"):
        _prod(env="production")


# ---- 운영: 정상 기동 ----


def test_prod_with_smtp_host_and_sender_boots():
    s = _prod(**_SMTP)
    assert s.is_prod is True
    assert s.mail_backend == "smtp"
    assert s.mail_enabled is True


def test_prod_with_explicit_smtp_provider_boots():
    s = _prod(**_SMTP, mail_provider="smtp")
    assert s.mail_backend == "smtp"
    assert s.mail_enabled is True


def test_prod_mail_guard_runs_after_other_prod_guards():
    """다른 운영 가드가 먼저 걸리면 그 문구가 그대로 나온다 — 기존 오류 안내가 가려지지 않는다."""
    with pytest.raises(ValidationError, match="AUTO_CREATE_TABLES"):
        _prod(auto_create_tables=True)


# ---- 개발·스테이징: 지금처럼 로그 발송으로 뜬다 ----


@pytest.mark.parametrize("env", ["dev", "staging"])
def test_non_prod_boots_without_mail(env):
    s = Settings(_env_file=None, env=env)
    assert s.mail_backend == "log"
    assert s.mail_enabled is True
