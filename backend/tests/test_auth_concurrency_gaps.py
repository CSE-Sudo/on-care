"""인증 경로의 동시성 빈틈과 응답 시간 차이(#3238).

1. 실패 잠금 — 시도를 확인 **전에** 센다(`claim_attempt`). 보고 나서 세면 확인을
   기다리는 동시 요청이 모두 잠금 판정을 통과했다.
2. 가입 인증 코드 — 시도 횟수를 DB 에서 원자적으로 올린다. 파이썬 `+= 1` 은 동시
   요청끼리 증가분을 덮어썼다.
3. 비밀번호 재설정 요청 — 메일을 응답 뒤로 미룬다. 계정이 있을 때만 SMTP 를 기다리면
   응답 시간으로 가입 여부가 드러났다.
4. 토큰 칸 길이 상한 — 무인증 경로의 토큰 칸에 4096자 상한.
5. 소셜 로그인 — 쉬는 계정은 401, 같은 신원의 첫 로그인이 겹치면 같은 계정으로.

앞부분은 DB 없이 돈다. `client`·`db_session` 픽스처를 쓰는 뒷부분은 CI 의 Postgres 에서 돈다.
"""
from __future__ import annotations

import threading
import uuid
from datetime import timedelta
from uuid import uuid4

import pytest
from fastapi import HTTPException
from pydantic import ValidationError
from sqlalchemy import delete, select
from sqlalchemy.exc import IntegrityError

from app.core import clock, rate_limit
from app.core.config import get_settings
from app.core.rate_limit import RateLimiter
from app.models import models
from app.schemas.user import RefreshRequest, SocialLoginRequest, TOKEN_MAX_LENGTH
from app.services.social.base import SocialIdentity

PASSWORD = "race-gap-pw-1234"


# ---------- 1. 실패 잠금: 판정과 기록이 한 번에 (DB 불필요) ----------


def test_try_acquire_lets_exactly_the_limit_through_under_contention():
    store = RateLimiter()
    limit = 5
    allowed: list[int] = []
    guard = threading.Lock()
    start = threading.Barrier(20)

    def worker(n: int) -> None:
        start.wait()
        if store.try_acquire("login-fail:race@x.com", limit, 900.0) is None:
            with guard:
                allowed.append(n)

    threads = [threading.Thread(target=worker, args=(n,)) for n in range(20)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert len(allowed) == limit


def test_try_acquire_reports_remaining_time_and_does_not_count_blocked_tries():
    store = RateLimiter()
    assert store.try_acquire("k", 2, 60.0) is None
    assert store.try_acquire("k", 2, 60.0) is None
    retry = store.try_acquire("k", 2, 60.0)
    assert retry is not None and 1 <= retry <= 60
    # 막힌 시도는 기록하지 않는다 — 기록은 한도 그대로 둘이다.
    assert len(store._hits["k"]) == 2
    store.reset("k")
    assert store.try_acquire("k", 2, 60.0) is None


def test_try_acquire_with_zero_limit_blocks_without_recording():
    store = RateLimiter()
    assert store.try_acquire("k", 0, 30.0) == 30
    assert "k" not in store._hits


def test_claim_attempt_raises_429_with_retry_after(monkeypatch):
    monkeypatch.setattr(get_settings(), "rate_limit_enabled", True)
    monkeypatch.setattr(get_settings(), "rate_limit_store", "memory")
    key = f"login-fail:{uuid4().hex}@x.com"
    rate_limit.claim_attempt(key, 1, 900.0)
    with pytest.raises(HTTPException) as exc:
        rate_limit.claim_attempt(key, 1, 900.0)
    assert exc.value.status_code == 429
    assert 1 <= int(exc.value.headers["Retry-After"]) <= 900
    rate_limit.clear_failures(key)
    rate_limit.claim_attempt(key, 1, 900.0)


def test_claim_attempt_is_off_with_the_switch(monkeypatch):
    monkeypatch.setattr(get_settings(), "rate_limit_enabled", False)
    for _ in range(10):
        rate_limit.claim_attempt("k", 1, 60.0)


class _Recorder:
    def __init__(self) -> None:
        self.calls: list[tuple] = []

    def try_acquire(self, key, limit, window):
        self.calls.append(("try_acquire", key, limit, window))
        return 9

    def clear(self):
        self.calls.append(("clear",))


def test_claim_attempt_goes_to_the_configured_store(monkeypatch):
    rec = _Recorder()
    monkeypatch.setattr(rate_limit.limiter, "database", rec)
    monkeypatch.setattr(get_settings(), "rate_limit_enabled", True)
    monkeypatch.setattr(get_settings(), "rate_limit_store", "database")
    with pytest.raises(HTTPException) as exc:
        rate_limit.claim_attempt("login-fail:a@x.com", 5, 900.0)
    assert exc.value.headers["Retry-After"] == "9"
    assert rec.calls == [("try_acquire", "login-fail:a@x.com", 5, 900.0)]


# ---------- 4. 토큰 칸 길이 상한 (DB 불필요) ----------


def test_token_fields_have_a_length_cap():
    RefreshRequest(refresh_token="t" * TOKEN_MAX_LENGTH)
    SocialLoginRequest(token="t" * TOKEN_MAX_LENGTH)
    with pytest.raises(ValidationError):
        RefreshRequest(refresh_token="t" * (TOKEN_MAX_LENGTH + 1))
    with pytest.raises(ValidationError):
        SocialLoginRequest(token="t" * (TOKEN_MAX_LENGTH + 1))


# ---------- 공용 (DB) ----------


@pytest.fixture
def lock_settings(monkeypatch):
    settings = get_settings()
    monkeypatch.setattr(settings, "rate_limit_enabled", True)
    monkeypatch.setattr(settings, "rate_limit_auth_per_minute", 1000)
    monkeypatch.setattr(settings, "trusted_proxy_hops", 1)
    return settings


@pytest.fixture
def member(client, db_session):
    email = f"race-gap-{uuid4().hex[:8]}@oncare.com"
    res = client.post(
        "/v1/auth/register", json={"email": email, "password": PASSWORD, "name": "동시성"}
    )
    assert res.status_code == 201, res.text
    yield email
    db_session.expire_all()
    row = db_session.get(models.User, res.json()["id"])
    if row is not None:
        db_session.delete(row)
        db_session.commit()


# ---------- 1. 실패 잠금: 확인 전에 센다 (DB) ----------


def test_login_counts_the_attempt_before_checking_the_password(
    client, member, lock_settings, monkeypatch
):
    """bcrypt 확인 중인 시도는 이미 잠금 버킷에 있다 — 동시 요청이 그 틈으로 지나가지 않는다."""
    import app.api.v1.users as users_mod

    monkeypatch.setattr(lock_settings, "login_max_failures", 1)
    key = users_mod._login_lock_key(member)
    window = float(lock_settings.login_lockout_seconds)
    seen: list[int | None] = []
    real_verify = users_mod.verify_password

    def spying_verify(plain, hashed):
        # 확인하는 동안 같은 계정으로 다른 요청이 오면 잠금 판정은 이 값을 본다.
        seen.append(rate_limit.limiter.retry_after(key, 1, window))
        return real_verify(plain, hashed)

    monkeypatch.setattr(users_mod, "verify_password", spying_verify)
    res = client.post("/v1/auth/login", data={"username": member, "password": "wrong-pw-0000"})
    assert res.status_code == 401
    assert len(seen) == 1 and seen[0] is not None
    # 한도 1 — 다음 시도는 확인에 들어가지 못한다.
    blocked = client.post("/v1/auth/login", data={"username": member, "password": PASSWORD})
    assert blocked.status_code == 429
    assert len(seen) == 1


def test_successful_login_clears_the_counted_attempt(client, member, lock_settings):
    import app.api.v1.users as users_mod

    key = users_mod._login_lock_key(member)
    window = float(lock_settings.login_lockout_seconds)
    res = client.post("/v1/auth/login", data={"username": member, "password": PASSWORD})
    assert res.status_code == 200, res.text
    assert rate_limit.limiter.retry_after(key, 1, window) is None


def test_password_change_counts_the_attempt_before_checking(
    client, db_session, member, lock_settings, monkeypatch
):
    import app.api.v1.users as users_mod

    monkeypatch.setattr(lock_settings, "password_change_max_failures", 1)
    user_id = db_session.scalar(select(models.User.id).where(models.User.email == member))
    key = rate_limit.password_change_fail_key(user_id)
    window = float(lock_settings.login_lockout_seconds)
    token = client.post(
        "/v1/auth/login", data={"username": member, "password": PASSWORD}
    ).json()["access_token"]
    seen: list[int | None] = []
    real_verify = users_mod.verify_password

    def spying_verify(plain, hashed):
        seen.append(rate_limit.limiter.retry_after(key, 1, window))
        return real_verify(plain, hashed)

    monkeypatch.setattr(users_mod, "verify_password", spying_verify)
    res = client.post(
        "/v1/users/me/password",
        json={"current_password": "not-my-pw-1", "new_password": "race-gap-new-5678"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert res.status_code == 400, res.text
    assert seen and seen[0] is not None
    locked = client.post(
        "/v1/users/me/password",
        json={"current_password": PASSWORD, "new_password": "race-gap-new-5678"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert locked.status_code == 429


def test_database_store_try_acquire_holds_the_limit_across_instances(client):
    from app.core.rate_limit import DatabaseRateLimiter

    store = DatabaseRateLimiter()
    store.clear()
    key = f"login-fail:race-{uuid4().hex[:10]}@oncare.com"
    allowed: list[int] = []
    guard = threading.Lock()
    start = threading.Barrier(8)

    def worker(n: int) -> None:
        start.wait()
        if DatabaseRateLimiter().try_acquire(key, 3, 900.0) is None:
            with guard:
                allowed.append(n)

    try:
        threads = [threading.Thread(target=worker, args=(n,)) for n in range(8)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        assert len(allowed) == 3
        retry = store.try_acquire(key, 3, 900.0)
        assert retry is not None and 1 <= retry <= 900
    finally:
        store.clear()


# ---------- 2. 가입 인증 코드 시도 횟수 (DB) ----------


@pytest.fixture
def code_row(client, db_session):
    """맞는 코드가 `123456` 인 살아 있는 가입 코드 한 장."""
    from app.services import signup_email_code

    email = f"race-code-{uuid4().hex[:8]}@oncare.com"
    purpose = signup_email_code.MEMBER_SIGNUP
    row = models.EmailVerificationCode(
        id=f"evc-{uuid.uuid4().hex[:16]}",
        email=email,
        purpose=purpose,
        code_hash=signup_email_code.hash_code(
            email, purpose, "123456", settings=get_settings()
        ),
        expires_at=clock.now() + timedelta(minutes=10),
    )
    db_session.add(row)
    db_session.commit()
    yield email, purpose, row.id
    db_session.execute(
        delete(models.EmailVerificationCode).where(
            models.EmailVerificationCode.email == email
        )
    )
    db_session.commit()


def _race_consume(email: str, purpose: str, code: str, n: int) -> list[str]:
    """세션을 따로 쥔 n 개 스레드가 같은 코드로 동시에 확인한다. 결과 목록을 돌려준다."""
    from app.db.session import SessionLocal
    from app.services import signup_email_code

    results: list[str] = []
    guard = threading.Lock()
    start = threading.Barrier(n)

    def worker() -> None:
        db = SessionLocal()
        try:
            start.wait()
            try:
                signup_email_code.consume(db, email, purpose, code, now=clock.now())
            except signup_email_code.InvalidEmailCode:
                outcome = "invalid"
            else:
                db.commit()
                outcome = "ok"
        finally:
            db.close()
        with guard:
            results.append(outcome)

    threads = [threading.Thread(target=worker) for _ in range(n)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    return results


def test_racing_wrong_codes_cannot_exceed_the_attempt_cap(
    code_row, db_session, monkeypatch
):
    from app.services import signup_email_code

    monkeypatch.setattr(get_settings(), "signup_email_code_max_attempts", 3)
    compared: list[str] = []
    guard = threading.Lock()
    real_hash = signup_email_code.hash_code

    def counting_hash(*args, **kwargs):
        with guard:
            compared.append("x")
        return real_hash(*args, **kwargs)

    monkeypatch.setattr(signup_email_code, "hash_code", counting_hash)
    email, purpose, row_id = code_row
    results = _race_consume(email, purpose, "000000", 8)
    assert results == ["invalid"] * 8
    # 비교 단계에 들어간 요청은 상한(3)을 넘지 않고, 횟수는 덮어쓰이지 않는다.
    assert len(compared) == 3
    db_session.expire_all()
    assert db_session.get(models.EmailVerificationCode, row_id).attempts == 3


def test_a_code_is_used_once_even_when_requests_race(code_row, db_session):
    email, purpose, row_id = code_row
    results = _race_consume(email, purpose, "123456", 6)
    assert sorted(results) == ["invalid"] * 5 + ["ok"]
    db_session.expire_all()
    assert db_session.get(models.EmailVerificationCode, row_id).used_at is not None


# ---------- 3. 비밀번호 재설정 요청: 메일은 응답 뒤에 (DB) ----------


class _Outbox:
    name = "test"

    def __init__(self) -> None:
        self.sent: list = []

    def send(self, mail) -> None:
        self.sent.append(mail)


@pytest.fixture
def mail_on():
    """개발 설정은 SMTP 가 없어도 log 발송으로 메일을 켜 둔다(`Settings.mail_enabled`)."""
    settings = get_settings()
    assert settings.mail_enabled
    return settings


def test_reset_mail_is_scheduled_not_sent_inline(client, db_session, member, mail_on):
    from app.services import password_reset

    box = _Outbox()
    scheduled: list[tuple] = []
    issued = password_reset.request_reset(
        db_session,
        member,
        now=clock.now(),
        settings=mail_on,
        mailer=box,
        schedule=lambda fn, *args: scheduled.append((fn, args)),
    )
    assert issued is not None
    # 요청이 돌아올 때까지 아무것도 보내지 않는다.
    assert box.sent == []
    assert len(scheduled) == 1
    fn, args = scheduled[0]
    fn(*args)
    assert [m.to for m in box.sent] == [member]


def test_unknown_email_schedules_nothing(client, db_session, mail_on):
    from app.services import password_reset

    scheduled: list[tuple] = []
    issued = password_reset.request_reset(
        db_session,
        f"nobody-{uuid4().hex[:8]}@oncare.com",
        now=clock.now(),
        settings=mail_on,
        mailer=_Outbox(),
        schedule=lambda fn, *args: scheduled.append((fn, args)),
    )
    assert issued is None and scheduled == []


def test_reset_endpoint_hands_mail_to_background_tasks(
    client, member, mail_on, monkeypatch
):
    from app.services import password_reset

    seen: dict[str, object] = {}
    real = password_reset.request_reset

    def spy(*args, **kwargs):
        seen["schedule"] = kwargs.get("schedule")
        return real(*args, **kwargs)

    monkeypatch.setattr(password_reset, "request_reset", spy)
    box = _Outbox()
    monkeypatch.setattr(password_reset, "get_mailer", lambda settings=None: box)
    res = client.post("/v1/auth/password-reset/request", json={"email": member})
    assert res.status_code == 202, res.text
    assert callable(seen["schedule"])
    # TestClient 는 응답 뒤 백그라운드 작업까지 끝내고 돌아온다 — 메일은 실제로 간다.
    assert [m.to for m in box.sent] == [member]


# ---------- 4. 토큰 칸 길이 상한 (DB) ----------


def test_refresh_rejects_an_oversized_token(client):
    res = client.post(
        "/v1/auth/refresh", json={"refresh_token": "t" * (TOKEN_MAX_LENGTH + 1)}
    )
    assert res.status_code == 422


# ---------- 5. 소셜 로그인 (DB) ----------


def _fake_social(monkeypatch, identity: SocialIdentity) -> None:
    import app.api.v1.social as social_mod

    class _FakeVerifier:
        async def verify(self, token):  # noqa: ARG002
            return identity

    monkeypatch.setattr(social_mod, "get_verifier", lambda provider: _FakeVerifier())


def _identity() -> SocialIdentity:
    uid = f"kakao-race-{uuid4().hex[:8]}"
    return SocialIdentity(provider="kakao", provider_user_id=uid, email="", name="소셜")


def _social_user_id(db_session, identity: SocialIdentity) -> str | None:
    return db_session.scalar(
        select(models.SocialAccount.user_id).where(
            models.SocialAccount.provider == identity.provider,
            models.SocialAccount.provider_user_id == identity.provider_user_id,
        )
    )


def _drop_user(db_session, user_id: str | None) -> None:
    if user_id is None:
        return
    db_session.expire_all()
    row = db_session.get(models.User, user_id)
    if row is not None:
        db_session.delete(row)
        db_session.commit()


def test_suspended_account_gets_no_social_tokens(client, db_session, monkeypatch):
    identity = _identity()
    _fake_social(monkeypatch, identity)
    first = client.post("/v1/auth/social/kakao", json={"token": "any"})
    assert first.status_code == 200, first.text
    user_id = _social_user_id(db_session, identity)
    try:
        user = db_session.get(models.User, user_id)
        user.is_active = False
        db_session.commit()

        res = client.post("/v1/auth/social/kakao", json={"token": "any"})
        assert res.status_code == 401
        assert "access_token" not in res.json()
        db_session.expire_all()
        audit = db_session.scalars(
            select(models.AuditLog)
            .where(models.AuditLog.event == "auth.social", models.AuditLog.user_id == user_id)
            .order_by(models.AuditLog.id.desc())
        ).first()
        assert audit is not None and audit.success is False
        assert "inactive" in (audit.detail or "")
    finally:
        _drop_user(db_session, user_id)


def test_racing_first_social_login_lands_on_the_same_account(
    client, db_session, monkeypatch
):
    """먼저 끝난 요청이 연결을 만들고 늦은 요청은 유일 제약에서 만난다 — 500 이 아니라 같은 계정."""
    import app.api.v1.social as social_mod
    from app.db.session import SessionLocal

    identity = _identity()
    _fake_social(monkeypatch, identity)
    real = social_mod._find_or_create_user
    calls: list[str] = []

    def racing(db, ident):
        if not calls:
            calls.append("lost")
            # 다른 요청이 같은 신원으로 먼저 연결을 만들고 커밋했다.
            other = SessionLocal()
            try:
                real(other, ident)
            finally:
                other.close()
            raise IntegrityError("INSERT INTO social_accounts", {}, Exception("uq_social_provider_uid"))
        calls.append("retry")
        return real(db, ident)

    monkeypatch.setattr(social_mod, "_find_or_create_user", racing)
    res = client.post("/v1/auth/social/kakao", json={"token": "any"})
    user_id = _social_user_id(db_session, identity)
    try:
        assert res.status_code == 200, res.text
        assert calls == ["lost", "retry"]
        me = client.get(
            "/v1/users/me", headers={"Authorization": f"Bearer {res.json()['access_token']}"}
        )
        assert me.json()["id"] == user_id
        links = db_session.scalars(
            select(models.SocialAccount).where(
                models.SocialAccount.provider_user_id == identity.provider_user_id
            )
        ).all()
        assert len(links) == 1
    finally:
        _drop_user(db_session, user_id)
