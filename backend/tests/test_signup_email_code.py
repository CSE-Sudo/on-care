"""가입 이메일 인증 코드(#3038).

앞부분은 DB 없이 도는 순수 검사(코드 모양·해시·운영 가드·마이그레이션), 뒷부분
(`client` 픽스처)은 CI 의 Postgres 에서 돈다. 메일은 실제로 보내지 않는다 — 발송
수단을 모으는 가짜로 바꿔 끼워 무엇이 누구에게 갔는지 본다.

conftest 가 인증을 꺼 두므로(`_signup_email_verification_off`) 여기서는 `verification_on`
픽스처로 다시 켠다.
"""
from __future__ import annotations

import re
from collections.abc import Iterator
from datetime import timedelta
from pathlib import Path
from uuid import uuid4

import pytest
from sqlalchemy import select

from app.core import clock
from app.core.config import Settings, get_settings
from app.models import models
from app.services import signup_email_code
from app.services.mailer import MailDeliveryError, OutgoingMail

PASSWORD = "signup-code-pw-1234"
PREFIX = "signup-code-"
_CODE = re.compile(r"\b(\d{6})\b")
_MIGRATION = (
    Path(__file__).resolve().parents[1]
    / "migrations"
    / "versions"
    / "0142_email_verification.py"
)


# ---- 순수 검사 (DB 불필요) ----


def test_code_is_six_digits():
    for _ in range(50):
        code = signup_email_code.generate_code()
        assert len(code) == 6 and code.isdigit()


def test_hash_binds_email_and_purpose():
    s = Settings(_env_file=None, jwt_secret="secret-a")
    base = signup_email_code.hash_code("a@x.com", "member_signup", "123456", settings=s)
    assert base == signup_email_code.hash_code("A@X.com", "member_signup", "123 456", settings=s)
    assert base != signup_email_code.hash_code("b@x.com", "member_signup", "123456", settings=s)
    assert base != signup_email_code.hash_code("a@x.com", "trainer_signup", "123456", settings=s)
    assert "123456" not in base


def test_hash_depends_on_server_secret():
    """6자리는 경우의 수가 적다 — 비밀값 없이 만든 해시는 표가 새면 바로 풀린다."""
    a = Settings(_env_file=None, jwt_secret="secret-a")
    b = Settings(_env_file=None, jwt_secret="secret-b")
    assert signup_email_code.hash_code(
        "a@x.com", "member_signup", "123456", settings=a
    ) != signup_email_code.hash_code("a@x.com", "member_signup", "123456", settings=b)


def test_verification_is_on_by_default():
    assert Settings(_env_file=None).signup_email_verification is True


def test_prod_refuses_to_turn_verification_off():
    with pytest.raises(ValueError, match="SIGNUP_EMAIL_VERIFICATION"):
        Settings(
            _env_file=None,
            env="prod",
            jwt_secret="a-strong-random-secret-value",
            cors_allow_origins="https://app.oncare.com",
            seed_demo_data=False,
            auto_create_tables=False,
            gemini_api_key="test-gemini-key",
            recognizer="gemini",
            embedder="gemini",
            signup_email_verification=False,
        )


def test_migration_creates_table_and_column():
    text = _MIGRATION.read_text(encoding="utf-8")
    assert 'down_revision: str | Sequence[str] | None = "0140_program_draft_member"' in text
    assert '"email_verification_codes"' in text
    assert '"email_verified_at"' in text
    # 기존 행을 지우거나 고치지 않는다.
    assert "DELETE" not in text and "UPDATE" not in text


# ---- API (DB) ----


class _Outbox:
    name = "test"

    def __init__(self) -> None:
        self.sent: list[OutgoingMail] = []
        self.fail = False

    def send(self, mail: OutgoingMail) -> None:
        if self.fail:
            raise MailDeliveryError("down")
        self.sent.append(mail)

    def to(self, email: str) -> list[OutgoingMail]:
        return [m for m in self.sent if m.to == email]

    def code_for(self, email: str) -> str:
        mails = self.to(email)
        assert mails, f"{email} 앞으로 보낸 메일이 없다"
        found = _CODE.search(mails[-1].body)
        assert found, mails[-1].body
        return found.group(1)


@pytest.fixture
def outbox(monkeypatch) -> _Outbox:
    box = _Outbox()
    monkeypatch.setattr(signup_email_code, "get_mailer", lambda settings=None: box)
    return box


@pytest.fixture
def verification_on(monkeypatch) -> None:
    monkeypatch.setattr(get_settings(), "signup_email_verification", True)


@pytest.fixture
def cleanup(db_session) -> Iterator[list[str]]:
    emails: list[str] = []
    yield emails
    db_session.expire_all()
    for email in emails:
        db_session.query(models.EmailVerificationCode).filter(
            models.EmailVerificationCode.email == email
        ).delete()
        for user in db_session.scalars(
            select(models.User).where(models.User.email == email)
        ).all():
            if user.role == "trainer":
                from app.services.trainer import profile as trainer_profile_service

                trainer_profile_service.delete_trainer_account(db_session, user)
            else:
                db_session.delete(user)
    db_session.commit()


def _email(cleanup: list[str], tag: str = "m") -> str:
    email = f"{PREFIX}{tag}-{uuid4().hex[:10]}@oncare.com"
    cleanup.append(email)
    return email


def _ask(client, email: str, purpose: str = "member_signup", **headers):
    return client.post(
        "/v1/auth/register/email-code",
        json={"email": email, "purpose": purpose},
        headers=headers,
    )


def _register(client, email: str, code: str | None, path: str = "/v1/auth/register"):
    body = {"email": email, "password": PASSWORD, "name": "인증"}
    if code is not None:
        body["email_code"] = code
    return client.post(path, json=body)


def test_request_sends_a_code(client, outbox, verification_on, cleanup):
    email = _email(cleanup)
    res = _ask(client, email)
    assert res.status_code == 202, res.text
    assert res.json() == {"expires_in_minutes": 10, "resend_after_seconds": 60}
    assert len(outbox.to(email)) == 1
    assert outbox.code_for(email)


def test_registered_address_gets_same_response_and_a_notice(
    client, outbox, verification_on, cleanup, db_session
):
    """가입된 주소도 같은 상태·같은 본문 — 코드 대신 '이미 계정이 있다' 안내만 간다."""
    taken = _email(cleanup, "taken")
    db_session.add(
        models.User(id=f"user-{uuid4().hex[:12]}", email=taken, name="기존", hashed_password="")
    )
    db_session.commit()
    fresh = _email(cleanup, "fresh")

    known = _ask(client, taken)
    unknown = _ask(client, fresh)

    assert known.status_code == unknown.status_code == 202
    assert known.json() == unknown.json()
    (notice,) = outbox.to(taken)
    assert not _CODE.search(notice.body)
    assert db_session.scalar(
        select(models.EmailVerificationCode).where(
            models.EmailVerificationCode.email == taken
        )
    ) is None


def test_code_is_stored_only_as_hash(client, db_session, outbox, verification_on, cleanup):
    email = _email(cleanup)
    _ask(client, email)
    code = outbox.code_for(email)
    (row,) = db_session.scalars(
        select(models.EmailVerificationCode).where(
            models.EmailVerificationCode.email == email
        )
    ).all()
    assert row.purpose == "member_signup"
    assert code not in row.code_hash
    assert row.code_hash == signup_email_code.hash_code(
        email, "member_signup", code, settings=get_settings()
    )


def test_register_with_code_marks_email_verified(
    client, db_session, outbox, verification_on, cleanup
):
    email = _email(cleanup)
    _ask(client, email)
    res = _register(client, email, outbox.code_for(email))
    assert res.status_code == 201, res.text
    db_session.expire_all()
    user = db_session.get(models.User, res.json()["id"])
    assert user.email_verified_at is not None


def test_register_without_code_is_422(client, outbox, verification_on, cleanup):
    email = _email(cleanup)
    for code in (None, "", "   "):
        res = _register(client, email, code)
        assert res.status_code == 422, res.text
        assert res.json()["detail"]["code"] == "email_code_required"


def test_wrong_code_is_400_and_creates_nothing(
    client, db_session, outbox, verification_on, cleanup
):
    email = _email(cleanup)
    _ask(client, email)
    real = outbox.code_for(email)
    wrong = "000000" if real != "000000" else "111111"
    res = _register(client, email, wrong)
    assert res.status_code == 400, res.text
    assert res.json()["detail"]["code"] == "invalid_email_code"
    assert db_session.scalar(select(models.User).where(models.User.email == email)) is None
    # 맞는 코드는 여전히 쓸 수 있다.
    assert _register(client, email, real).status_code == 201


def test_code_works_only_once(client, outbox, verification_on, cleanup, db_session):
    email = _email(cleanup)
    _ask(client, email)
    code = outbox.code_for(email)
    first = _register(client, email, code)
    assert first.status_code == 201, first.text
    # 같은 주소는 이제 409 다(중복 확인이 먼저).
    assert _register(client, email, code).status_code == 409


def test_expired_code_is_rejected(client, db_session, outbox, verification_on, cleanup):
    email = _email(cleanup)
    _ask(client, email)
    code = outbox.code_for(email)
    row = db_session.scalar(
        select(models.EmailVerificationCode).where(
            models.EmailVerificationCode.email == email
        )
    )
    row.expires_at = clock.now() - timedelta(seconds=1)
    db_session.commit()
    res = _register(client, email, code)
    assert res.status_code == 400
    assert res.json()["detail"]["code"] == "invalid_email_code"


def test_too_many_wrong_attempts_lock_the_code(
    client, db_session, outbox, verification_on, cleanup, monkeypatch
):
    """6자리는 경우의 수가 백만이다 — 틀린 횟수 상한이 맞혀 보기를 막는 장치다."""
    monkeypatch.setattr(get_settings(), "signup_email_code_max_attempts", 3)
    email = _email(cleanup)
    _ask(client, email)
    real = outbox.code_for(email)
    wrong = "000000" if real != "000000" else "111111"
    for _ in range(3):
        assert _register(client, email, wrong).status_code == 400
    # 상한에 닿은 뒤에는 맞는 코드도 받지 않는다 — 새 코드를 받아야 한다.
    res = _register(client, email, real)
    assert res.status_code == 400
    db_session.expire_all()
    row = db_session.scalar(
        select(models.EmailVerificationCode).where(
            models.EmailVerificationCode.email == email
        )
    )
    assert row.attempts == 3


def test_new_code_closes_the_previous_one(
    client, outbox, verification_on, cleanup, monkeypatch
):
    monkeypatch.setattr(get_settings(), "signup_email_code_resend_seconds", 0)
    email = _email(cleanup)
    _ask(client, email)
    old = outbox.code_for(email)
    _ask(client, email)
    new = outbox.code_for(email)
    if old != new:
        assert _register(client, email, old).status_code == 400
    assert _register(client, email, new).status_code == 201


def test_member_code_cannot_create_a_trainer(client, outbox, verification_on, cleanup):
    email = _email(cleanup, "tr")
    _ask(client, email, "member_signup")
    code = outbox.code_for(email)
    res = _register(client, email, code, path="/v1/auth/trainer/register")
    assert res.status_code == 400
    assert res.json()["detail"]["code"] == "invalid_email_code"


def test_trainer_register_with_code(client, db_session, outbox, verification_on, cleanup):
    email = _email(cleanup, "tr")
    _ask(client, email, "trainer_signup")
    res = _register(client, email, outbox.code_for(email), path="/v1/auth/trainer/register")
    assert res.status_code == 201, res.text
    db_session.expire_all()
    user = db_session.get(models.User, res.json()["id"])
    assert user.role == "trainer"
    assert user.email_verified_at is not None


def test_code_for_another_address_is_rejected(client, outbox, verification_on, cleanup):
    """화면에서 이메일을 바꾸면 새 코드가 필요하다 — 코드는 주소에 묶인다."""
    first = _email(cleanup, "a")
    second = _email(cleanup, "b")
    _ask(client, first)
    assert _register(client, second, outbox.code_for(first)).status_code == 400


def test_duplicate_email_is_still_409_before_the_code(
    client, outbox, verification_on, cleanup, db_session
):
    taken = _email(cleanup, "dup")
    db_session.add(
        models.User(id=f"user-{uuid4().hex[:12]}", email=taken, name="기존", hashed_password="")
    )
    db_session.commit()
    assert _register(client, taken, "123456").status_code == 409
    assert _register(client, taken.upper(), None).status_code == 409


def test_verification_off_skips_the_code(client, db_session, cleanup):
    """테스트·E2E 서버(설정 꺼짐)는 코드를 보지 않는다. 확인 시각도 비어 있다."""
    email = _email(cleanup)
    res = _register(client, email, None)
    assert res.status_code == 201, res.text
    db_session.expire_all()
    assert db_session.get(models.User, res.json()["id"]).email_verified_at is None


def test_unknown_purpose_is_422(client, outbox, cleanup):
    assert _ask(client, _email(cleanup), "admin_signup").status_code == 422


def test_malformed_email_is_422(client, outbox):
    assert _ask(client, "not-an-email").status_code == 422


def test_resend_waits(client, outbox, verification_on, cleanup):
    email = _email(cleanup)
    assert _ask(client, email).status_code == 202
    again = _ask(client, email)
    assert again.status_code == 429
    assert "Retry-After" in again.headers
    assert len(outbox.to(email)) == 1


def test_per_email_limit_counts_registered_addresses_too(
    client, outbox, verification_on, cleanup, db_session, monkeypatch
):
    """가입된 주소도 똑같이 센다 — 429 로 가입 여부를 알 수 없다."""
    s = get_settings()
    monkeypatch.setattr(s, "signup_email_code_per_window", 2)
    monkeypatch.setattr(s, "signup_email_code_resend_seconds", 0)
    taken = _email(cleanup, "lim-taken")
    db_session.add(
        models.User(id=f"user-{uuid4().hex[:12]}", email=taken, name="기존", hashed_password="")
    )
    db_session.commit()
    fresh = _email(cleanup, "lim-fresh")
    for email in (taken, fresh):
        assert _ask(client, email).status_code == 202
        assert _ask(client, email).status_code == 202
        assert _ask(client, email).status_code == 429


def test_ip_bucket_limits_requests(client, outbox, verification_on, cleanup):
    limit = get_settings().rate_limit_auth_per_minute
    codes = [_ask(client, _email(cleanup, f"ip{i}")).status_code for i in range(limit + 1)]
    assert codes[:limit] == [202] * limit
    assert codes[limit] == 429


def test_mail_failure_does_not_change_response(client, outbox, verification_on, cleanup):
    outbox.fail = True
    res = _ask(client, _email(cleanup))
    assert res.status_code == 202


def test_prod_without_mail_is_503(client, monkeypatch, outbox, cleanup):
    s = get_settings()
    monkeypatch.setattr(s, "env", "prod")
    monkeypatch.setattr(s, "mail_provider", "log")
    res = _ask(client, _email(cleanup))
    assert res.status_code == 503
    assert outbox.sent == []


def test_english_request_gets_english_mail(client, outbox, verification_on, cleanup):
    email = _email(cleanup)
    _ask(client, email, **{"Accept-Language": "en-US"})
    assert "verification code" in outbox.to(email)[-1].subject.lower()


def test_support_contact_is_added_when_set(
    client, outbox, verification_on, cleanup, monkeypatch
):
    monkeypatch.setattr(get_settings(), "mail_support_contact", "help@example.com")
    email = _email(cleanup)
    _ask(client, email)
    assert "help@example.com" in outbox.to(email)[-1].body


def test_failed_verification_is_audited(client, db_session, outbox, verification_on, cleanup):
    email = _email(cleanup)
    _ask(client, email)
    real = outbox.code_for(email)
    _register(client, email, "000000" if real != "000000" else "111111")
    db_session.expire_all()
    rows = db_session.scalars(
        select(models.AuditLog).where(
            models.AuditLog.event == "auth.signup_code_verify",
            models.AuditLog.success.is_(False),
        )
    ).all()
    assert rows
    # 감사 기록에는 이메일 원문을 남기지 않는다.
    assert all(email not in (row.detail or "") for row in rows)
