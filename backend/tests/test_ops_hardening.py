"""운영 하드닝 잔여 항목. (#2913)

- 접근 토큰 수명 기본 60분(환경변수로 조정)
- 같은 이메일 가입 반복 제한 — IP 를 바꿔도 한 버킷, 회원·트레이너 가입 공용
- `POST /trainer/me/password` 현재 비밀번호 연속 실패 잠금(사용자 단위) + 감사 로그
- AI 문장 검사 탈락 로그에 원문이 INFO 로 남지 않는다

앞부분(설정·키·로그)은 DB 없이 돈다. `client` 픽스처를 쓰는 부분은 CI 의 Postgres 에서 돈다.
"""
from __future__ import annotations

import logging
from datetime import datetime, timezone
from uuid import uuid4

import jwt
import pytest

from app.core.config import Settings
from app.core.rate_limit import password_change_fail_key, register_email_key

_PW = "pw!12345"
_NEW_PW = "pw!67890"


def _settings(**overrides) -> Settings:
    return Settings(_env_file=None, **overrides)


# ---- 접근 토큰 수명 (DB 불필요) ----


def test_access_token_default_is_one_hour(monkeypatch):
    monkeypatch.delenv("ACCESS_TOKEN_EXPIRE_MINUTES", raising=False)
    s = _settings()
    assert s.access_token_expire_minutes == 60
    # refresh 는 그대로 — 짧은 접근 토큰을 refresh 로 이어 간다.
    assert s.refresh_token_expire_days == 30


def test_access_token_lifetime_follows_the_environment(monkeypatch):
    monkeypatch.setenv("ACCESS_TOKEN_EXPIRE_MINUTES", "1440")
    assert Settings(_env_file=None).access_token_expire_minutes == 1440


def test_issued_access_token_uses_the_setting():
    from app.core import security

    token = security.create_access_token("user-ttl")
    claims = jwt.decode(
        token,
        security.settings.jwt_secret,
        algorithms=[security.settings.jwt_algorithm],
    )
    lifetime = claims["exp"] - claims["iat"]
    assert lifetime == security.settings.access_token_expire_minutes * 60
    exp = datetime.fromtimestamp(claims["exp"], tz=timezone.utc)
    assert exp > datetime.now(timezone.utc)


# ---- 버킷 키 (DB 불필요) ----


def test_register_key_ignores_case_and_spaces():
    assert register_email_key(" Member@OnCare.com ") == register_email_key("member@oncare.com")
    assert register_email_key("a@x.com") != register_email_key("b@x.com")


def test_password_key_is_per_user():
    assert password_change_fail_key("u1") != password_change_fail_key("u2")
    assert password_change_fail_key("u1") == password_change_fail_key("u1")


def test_new_limits_have_sane_defaults():
    s = _settings()
    assert 1 <= s.register_per_email_per_hour <= 10
    assert 1 <= s.password_change_max_failures <= 10


# ---- AI 문장 로그 (DB 불필요) ----


def _ai():
    from app.services import diet_ai_sentence

    return diet_ai_sentence


@pytest.mark.parametrize(
    ("text", "limit", "reason"),
    [
        ("", 20, "empty"),
        ("아주 길고 긴 문장이라서 한도를 넘는 조언입니다.", 10, "too_long"),
        ("나트륨을 1,800mg 아래로 줄여요.", 40, "measure"),
        ("국물은 반만 드세요.", 40, None),
    ],
)
def test_rejection_reason(text, limit, reason):
    ai = _ai()
    assert ai.rejection_reason(text, limit) == reason
    assert ai.valid(text, limit) is (reason is None)


_SECRET_MENU = "짬뽕 국물 1,800mg"


def _generate_rejected(monkeypatch):
    ai = _ai()
    bad = iter(
        [f'{{"sentence": "{_SECRET_MENU} 줄여요"}}', f'{{"sentence": "{_SECRET_MENU} 남겨요"}}']
    )
    monkeypatch.setattr(ai, "_call_llm", lambda s, u: next(bad))
    return ai.generate(
        lang="ko",
        analysis_text="이번 주 나트륨을 **3일** 넘겼어요.",
        finding="f",
        records=["월 점심: 짬뽕"],
        notes=[],
        goal="",
        metric="diet_test",
    )


def test_rejected_sentence_is_not_logged_at_info(monkeypatch, caplog):
    caplog.set_level(logging.INFO, logger=_ai().logger.name)
    assert _generate_rejected(monkeypatch) is None

    rejected = [r for r in caplog.records if "검사 탈락" in r.getMessage()]
    assert len(rejected) == 2
    for record in caplog.records:
        assert _SECRET_MENU not in record.getMessage()
        assert "짬뽕" not in record.getMessage()
    message = rejected[0].getMessage()
    assert "diet_test" in message
    assert "reason=measure" in message
    assert "len=" in message


def test_rejected_sentence_raw_text_is_never_logged(monkeypatch, caplog):
    # LLM 출력 원문은 DEBUG 로도 남기지 않는다(#3090) — 회원 기록이 섞인 문장이 로그로
    # 새지 않게, 탈락 사유·길이·지표 이름만 남긴다.
    caplog.set_level(logging.DEBUG, logger=_ai().logger.name)
    _generate_rejected(monkeypatch)

    assert not [r for r in caplog.records if _SECRET_MENU in r.getMessage()]


# ---- 같은 이메일 가입 반복 (DB) ----


@pytest.fixture
def per_ip_relaxed(client, monkeypatch):
    """IP 버킷은 넉넉히, 프록시 1단을 믿게 해 요청마다 다른 IP 로 보낸다."""
    from app.core.config import get_settings

    settings = get_settings()
    monkeypatch.setattr(settings, "rate_limit_enabled", True)
    monkeypatch.setattr(settings, "rate_limit_auth_per_minute", 1000)
    monkeypatch.setattr(settings, "trusted_proxy_hops", 1)
    return settings


def _ip_headers(n: int) -> dict:
    return {"X-Forwarded-For": f"203.0.113.{n % 250 + 1}"}


def _register(client, email: str, n: int, path: str = "/v1/auth/register"):
    return client.post(
        path,
        json={"email": email, "password": _PW, "name": "가입"},
        headers=_ip_headers(n),
    )


def test_same_email_from_many_ips_is_limited(client, per_ip_relaxed):
    email = f"reg-limit-{uuid4().hex[:8]}@oncare.com"
    limit = per_ip_relaxed.register_per_email_per_hour

    assert _register(client, email, 0).status_code == 201
    for n in range(1, limit):
        assert _register(client, email, n).status_code == 409
    blocked = _register(client, email, limit)
    assert blocked.status_code == 429, blocked.text
    assert "Retry-After" in blocked.headers


def test_email_bucket_ignores_case(client, per_ip_relaxed):
    email = f"reg-case-{uuid4().hex[:8]}@oncare.com"
    limit = per_ip_relaxed.register_per_email_per_hour
    for n in range(limit):
        variant = email.upper() if n % 2 else email
        assert _register(client, variant, n).status_code in (201, 409)
    assert _register(client, email.title(), limit).status_code == 429


def test_member_and_trainer_signup_share_the_email_bucket(client, per_ip_relaxed):
    email = f"reg-share-{uuid4().hex[:8]}@oncare.com"
    limit = per_ip_relaxed.register_per_email_per_hour
    for n in range(limit):
        _register(client, email, n)
    blocked = _register(client, email, limit, "/v1/auth/trainer/register")
    assert blocked.status_code == 429, blocked.text


def test_other_emails_are_not_affected(client, per_ip_relaxed):
    email = f"reg-a-{uuid4().hex[:8]}@oncare.com"
    limit = per_ip_relaxed.register_per_email_per_hour
    for n in range(limit + 1):
        _register(client, email, n)
    other = f"reg-b-{uuid4().hex[:8]}@oncare.com"
    assert _register(client, other, 99).status_code == 201


def test_conflict_message_is_unchanged_under_the_limit(client, per_ip_relaxed):
    email = f"reg-msg-{uuid4().hex[:8]}@oncare.com"
    assert _register(client, email, 0).status_code == 201
    again = _register(client, email, 1)
    assert again.status_code == 409
    assert again.json()["detail"] == "이미 가입된 이메일이에요."


def test_email_bucket_is_off_when_rate_limit_is_disabled(client, monkeypatch):
    from app.core.config import get_settings

    monkeypatch.setattr(get_settings(), "rate_limit_enabled", False)
    email = f"reg-off-{uuid4().hex[:8]}@oncare.com"
    limit = get_settings().register_per_email_per_hour
    codes = {_register(client, email, n).status_code for n in range(limit + 2)}
    assert 429 not in codes


# ---- 트레이너 비밀번호 변경 시도 제한 (DB) ----


@pytest.fixture
def trainer(client, db_session):
    from app.core.security import create_access_token, hash_password
    from app.models.models import User

    trainer_id = f"pw-limit-{uuid4().hex[:10]}"
    user = User(
        id=trainer_id,
        email=f"{trainer_id}@oncare.com",
        name="잠금",
        hashed_password=hash_password(_PW),
        role="trainer",
    )
    db_session.add(user)
    db_session.commit()
    return trainer_id, {"Authorization": f"Bearer {create_access_token(trainer_id)}"}


def _change(client, headers, current: str, n: int = 0):
    return client.post(
        "/v1/trainer/me/password",
        json={"current_password": current, "new_password": _NEW_PW},
        headers={**headers, **_ip_headers(n)},
    )


@pytest.fixture
def lock_settings(client, monkeypatch):
    from app.core.config import get_settings

    settings = get_settings()
    monkeypatch.setattr(settings, "rate_limit_enabled", True)
    monkeypatch.setattr(settings, "rate_limit_auth_per_minute", 1000)
    monkeypatch.setattr(settings, "trusted_proxy_hops", 1)
    return settings


def test_repeated_wrong_current_password_is_429(client, trainer, lock_settings):
    _, headers = trainer
    limit = lock_settings.password_change_max_failures
    for n in range(limit):
        r = _change(client, headers, "wrong-pw-1", n)
        assert r.status_code == 400, r.text
    blocked = _change(client, headers, "wrong-pw-1", limit)
    assert blocked.status_code == 429, blocked.text
    assert "Retry-After" in blocked.headers


def test_locked_account_does_not_check_the_password(client, db_session, trainer, lock_settings):
    """잠긴 동안에는 맞는 비밀번호도 받지 않는다 — 맞혔는지가 응답에 드러나지 않는다."""
    from app.core.security import verify_password
    from app.models.models import User

    trainer_id, headers = trainer
    for n in range(lock_settings.password_change_max_failures):
        _change(client, headers, "wrong-pw-1", n)
    assert _change(client, headers, _PW, 50).status_code == 429

    db_session.expire_all()
    assert verify_password(_PW, db_session.get(User, trainer_id).hashed_password)


def test_failures_are_audited(client, db_session, trainer, lock_settings):
    from sqlalchemy import select

    from app.models.models import AuditLog

    trainer_id, headers = trainer
    _change(client, headers, "wrong-pw-1")
    _change(client, headers, "wrong-pw-2")
    db_session.expire_all()
    rows = db_session.scalars(
        select(AuditLog).where(
            AuditLog.event == "auth.password_change", AuditLog.user_id == trainer_id
        )
    ).all()
    assert len(rows) == 2
    assert all(row.success is False for row in rows)
    # 감사 로그에 입력한 비밀번호가 남지 않는다.
    assert all("wrong-pw" not in (row.detail or "") for row in rows)


def test_success_clears_earlier_failures(client, trainer, lock_settings):
    from app.core.rate_limit import limiter

    trainer_id, headers = trainer
    key = password_change_fail_key(trainer_id)
    limit = lock_settings.password_change_max_failures
    for n in range(limit - 1):
        _change(client, headers, "wrong-pw-1", n)
    ok = _change(client, headers, _PW, 60)
    assert ok.status_code == 200, ok.text
    assert limiter.retry_after(key, 1, float(lock_settings.login_lockout_seconds)) is None


def test_lock_is_per_trainer(client, db_session, trainer, lock_settings):
    from app.core.security import create_access_token, hash_password
    from app.models.models import User

    _, headers = trainer
    for n in range(lock_settings.password_change_max_failures + 1):
        _change(client, headers, "wrong-pw-1", n)

    other_id = f"pw-limit-other-{uuid4().hex[:8]}"
    db_session.add(
        User(
            id=other_id,
            email=f"{other_id}@oncare.com",
            name="다른",
            hashed_password=hash_password(_PW),
            role="trainer",
        )
    )
    db_session.commit()
    other_headers = {"Authorization": f"Bearer {create_access_token(other_id)}"}
    assert _change(client, other_headers, "wrong-pw-1", 70).status_code == 400


def test_password_change_has_an_ip_bucket_too(client, trainer, monkeypatch):
    """IP 버킷 — 같은 IP 에서 분당 한도를 넘기면 사용자 잠금과 별개로 429."""
    from app.core.config import get_settings

    settings = get_settings()
    monkeypatch.setattr(settings, "rate_limit_enabled", True)
    monkeypatch.setattr(settings, "rate_limit_auth_per_minute", 2)
    monkeypatch.setattr(settings, "password_change_max_failures", 100)
    _, headers = trainer
    codes = [_change(client, headers, "wrong-pw-1").status_code for _ in range(3)]
    assert codes == [400, 400, 429]
