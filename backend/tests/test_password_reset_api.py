"""비밀번호 재설정 `POST /auth/password-reset/*`(#2824) — DB 필요(로컬 skip, CI 실행).

메일은 실제로 보내지 않는다. 발송 수단을 모으는 가짜로 바꿔 끼워, 무엇이 누구에게
갔는지(또는 가지 않았는지)를 본다.
"""
from __future__ import annotations

import re
import uuid
from collections.abc import Iterator
from datetime import timedelta
from uuid import uuid4

import pytest

from app.core import clock
from app.core.config import get_settings
from app.models import models
from app.services import password_reset
from app.services.mailer import MailDeliveryError, OutgoingMail

_OLD_PW = "reset-pw-123"
_NEW_PW = "reset-pw-456"
_CODE = re.compile(r"[A-Z2-9]{4}(?:-[A-Z2-9]{4}){3}")


class _Outbox:
    name = "test"

    def __init__(self) -> None:
        self.sent: list[OutgoingMail] = []
        self.fail = False

    def send(self, mail: OutgoingMail) -> None:
        if self.fail:
            raise MailDeliveryError("down")
        self.sent.append(mail)

    def code_for(self, email: str) -> str:
        mails = [m for m in self.sent if m.to == email]
        assert mails, f"{email} 앞으로 보낸 메일이 없다"
        found = _CODE.search(mails[-1].body)
        assert found, mails[-1].body
        return found.group(0)


@pytest.fixture
def outbox(monkeypatch) -> _Outbox:
    box = _Outbox()
    monkeypatch.setattr(password_reset, "get_mailer", lambda settings=None: box)
    return box


def _h(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _login(client, email: str, password: str):
    return client.post("/v1/auth/login", data={"username": email, "password": password})


def _request(client, email: str, **headers):
    return client.post(
        "/v1/auth/password-reset/request", json={"email": email}, headers=headers
    )


def _confirm(client, token: str, new: str = _NEW_PW):
    return client.post(
        "/v1/auth/password-reset/confirm", json={"token": token, "new_password": new}
    )


def _cleanup(db_session, user_id: str) -> None:
    db_session.expire_all()
    row = db_session.get(models.User, user_id)
    if row is not None:
        db_session.delete(row)
        db_session.commit()


@pytest.fixture
def member(client, db_session) -> Iterator[str]:
    email = f"rst-{uuid4().hex[:8]}@oncare.com"
    res = client.post(
        "/v1/auth/register", json={"email": email, "password": _OLD_PW, "name": "재설정"}
    )
    assert res.status_code == 201, res.text
    yield email
    _cleanup(db_session, res.json()["id"])


@pytest.fixture
def trainer(client, db_session) -> Iterator[str]:
    email = f"rst-tr-{uuid4().hex[:8]}@oncare.com"
    res = client.post(
        "/v1/auth/trainer/register",
        json={"email": email, "password": _OLD_PW, "name": "재설정트레이너"},
    )
    assert res.status_code in (200, 201), res.text
    yield email
    db_session.expire_all()
    row = db_session.get(models.User, res.json()["id"])
    if row is not None:
        from app.services.trainer import profile as trainer_profile_service

        trainer_profile_service.delete_trainer_account(db_session, row)


# ---- 요청 ----


def test_request_sends_one_time_code(client, outbox, member):
    res = _request(client, member)
    assert res.status_code == 202, res.text
    assert res.json() == {"status": "requested", "expires_in_minutes": 30}
    assert [m.to for m in outbox.sent] == [member]
    assert outbox.code_for(member)


def test_unknown_email_gets_identical_response_and_no_mail(client, outbox, member):
    """가입되지 않은 이메일도 같은 상태·같은 본문 — 가입 여부가 드러나지 않는다."""
    known = _request(client, member)
    unknown = _request(client, f"nobody-{uuid4().hex[:8]}@oncare.com")
    assert unknown.status_code == known.status_code == 202
    assert unknown.json() == known.json()
    assert [m.to for m in outbox.sent] == [member]


def test_code_is_stored_only_as_hash(client, db_session, outbox, member):
    _request(client, member)
    code = outbox.code_for(member)
    user = db_session.query(models.User).filter(models.User.email == member).one()
    rows = (
        db_session.query(models.PasswordResetToken)
        .filter(models.PasswordResetToken.user_id == user.id)
        .all()
    )
    assert len(rows) == 1
    assert rows[0].token_hash == password_reset.hash_code(code)
    assert password_reset.normalize_code(code) not in rows[0].token_hash


def test_inactive_account_gets_no_mail(client, db_session, outbox, member):
    user = db_session.query(models.User).filter(models.User.email == member).one()
    user.is_active = False
    db_session.commit()
    assert _request(client, member).status_code == 202
    assert outbox.sent == []


def test_social_only_account_gets_no_mail(client, db_session, outbox):
    """비밀번호가 없는 소셜 계정에는 코드를 보내지 않는다 — 응답은 같다."""
    user = models.User(
        id=f"user-{uuid.uuid4().hex[:12]}",
        email=f"kakao_{uuid4().hex[:8]}@social.oncare",
        name="소셜",
        hashed_password="",
    )
    db_session.add(user)
    db_session.commit()
    try:
        res = _request(client, user.email)
        assert res.status_code == 202
        assert outbox.sent == []
    finally:
        _cleanup(db_session, user.id)


def test_mail_failure_does_not_change_response(client, outbox, member):
    """발송 실패가 응답에 드러나면 계정 존재 여부도 함께 드러난다."""
    outbox.fail = True
    res = _request(client, member)
    assert res.status_code == 202
    assert res.json()["status"] == "requested"


def test_english_request_gets_english_mail(client, outbox, member):
    _request(client, member, **{"Accept-Language": "en-US"})
    assert "password reset" in outbox.sent[-1].subject.lower()


def test_link_uses_role_specific_url(client, monkeypatch, outbox, member, trainer):
    s = get_settings()
    monkeypatch.setattr(s, "password_reset_member_url", "https://member.example.com/auth/password-reset")
    monkeypatch.setattr(s, "password_reset_trainer_url", "https://trainer.example.com/auth/password-reset")
    _request(client, member)
    _request(client, trainer)
    member_mail = next(m for m in outbox.sent if m.to == member)
    trainer_mail = next(m for m in outbox.sent if m.to == trainer)
    assert "https://member.example.com/auth/password-reset?token=" in member_mail.body
    assert "https://trainer.example.com/auth/password-reset?token=" in trainer_mail.body


def test_no_link_without_url(client, outbox, member):
    _request(client, member)
    assert "http" not in outbox.sent[-1].body


def test_prod_without_mail_is_503(client, monkeypatch, outbox, member):
    s = get_settings()
    monkeypatch.setattr(s, "env", "prod")
    monkeypatch.setattr(s, "mail_provider", "log")
    res = _request(client, member)
    assert res.status_code == 503
    assert outbox.sent == []


def test_per_email_limit_applies_to_unknown_addresses_too(client, monkeypatch, outbox):
    """이메일 한도는 계정이 없는 주소도 똑같이 센다 — 429 로 가입 여부를 알 수 없다."""
    monkeypatch.setattr(get_settings(), "password_reset_email_per_window", 2)
    ghost = f"ghost-{uuid4().hex[:8]}@oncare.com"
    assert _request(client, ghost).status_code == 202
    assert _request(client, ghost).status_code == 202
    assert _request(client, ghost).status_code == 429


def test_per_email_limit_ignores_case(client, monkeypatch, outbox, member):
    monkeypatch.setattr(get_settings(), "password_reset_email_per_window", 1)
    assert _request(client, member).status_code == 202
    assert _request(client, member.upper()).status_code == 429


def test_ip_bucket_limits_requests(client, outbox):
    limit = get_settings().rate_limit_auth_per_minute
    codes = [
        _request(client, f"ip-{i}-{uuid4().hex[:6]}@oncare.com").status_code
        for i in range(limit + 1)
    ]
    assert codes[:limit] == [202] * limit
    assert codes[-1] == 429


# ---- 확인 ----


def test_confirm_resets_password_and_ends_all_sessions(client, monkeypatch, outbox, member):
    # 프로필 조회의 데모 폴백(개발 환경)을 끄고 지난 세대 토큰이 401 인지 본다.
    monkeypatch.setattr(get_settings(), "allow_demo_fallback", False)
    phone = _login(client, member, _OLD_PW).json()
    _request(client, member)
    res = _confirm(client, outbox.code_for(member))
    assert res.status_code == 200, res.text
    assert res.json() == {"status": "reset"}
    # 토큰은 주지 않는다.
    assert "access_token" not in res.json()

    assert client.get("/v1/users/me/profile", headers=_h(phone["access_token"])).status_code == 401
    assert (
        client.post("/v1/auth/refresh", json={"refresh_token": phone["refresh_token"]})
    ).status_code == 401
    assert _login(client, member, _OLD_PW).status_code == 401
    assert _login(client, member, _NEW_PW).status_code == 200


def test_confirm_accepts_lowercase_without_hyphens(client, outbox, member):
    _request(client, member)
    typed = outbox.code_for(member).replace("-", "").lower()
    assert _confirm(client, typed).status_code == 200


def test_code_cannot_be_reused(client, outbox, member):
    _request(client, member)
    code = outbox.code_for(member)
    assert _confirm(client, code).status_code == 200
    again = _confirm(client, code, new="another-pw-789")
    assert again.status_code == 400
    assert again.json()["detail"]["code"] == "invalid_reset_token"
    assert _login(client, member, _NEW_PW).status_code == 200


def test_expired_code_is_rejected(client, db_session, outbox, member):
    _request(client, member)
    code = outbox.code_for(member)
    row = (
        db_session.query(models.PasswordResetToken)
        .filter(models.PasswordResetToken.token_hash == password_reset.hash_code(code))
        .one()
    )
    row.expires_at = clock.now() - timedelta(seconds=1)
    db_session.commit()
    res = _confirm(client, code)
    assert res.status_code == 400
    assert res.json()["detail"]["code"] == "invalid_reset_token"
    assert _login(client, member, _OLD_PW).status_code == 200


def test_new_request_closes_previous_code(client, outbox, member):
    _request(client, member)
    first = outbox.code_for(member)
    _request(client, member)
    second = outbox.code_for(member)
    assert first != second
    assert _confirm(client, first).status_code == 400
    assert _confirm(client, second).status_code == 200


@pytest.mark.parametrize("token", ["ABCD-EFGH-JKMN-PQRS", "short", "!!!!"])
def test_unknown_or_malformed_code_is_400(client, token):
    res = _confirm(client, token)
    assert res.status_code == 400
    assert res.json()["detail"]["code"] == "invalid_reset_token"


def test_confirm_enforces_password_policy(client, outbox, member):
    _request(client, member)
    code = outbox.code_for(member)
    res = _confirm(client, code, new="12345678")
    assert res.status_code == 422
    assert res.json()["detail"][0]["type"] == "password_weak"
    # 정책에 걸린 요청은 코드를 쓰지 않는다 — 다시 맞는 값으로 바꿀 수 있다.
    assert _confirm(client, code).status_code == 200


def test_trainer_can_reset_too(client, outbox, trainer):
    _request(client, trainer)
    assert _confirm(client, outbox.code_for(trainer)).status_code == 200
    tokens = _login(client, trainer, _NEW_PW).json()
    assert client.get("/v1/trainer/me", headers=_h(tokens["access_token"])).status_code == 200


def test_confirm_is_rate_limited(client):
    limit = get_settings().rate_limit_auth_per_minute
    codes = [_confirm(client, "ABCD-EFGH-JKMN-PQRS").status_code for _ in range(limit + 1)]
    assert codes[:limit] == [400] * limit
    assert codes[-1] == 429


def test_confirm_is_audited(client, db_session, outbox, member):
    _request(client, member)
    _confirm(client, "ABCD-EFGH-JKMN-PQRS")
    _confirm(client, outbox.code_for(member))
    user = db_session.query(models.User).filter(models.User.email == member).one()
    ok = (
        db_session.query(models.AuditLog)
        .filter(
            models.AuditLog.event == "auth.password_reset_confirm",
            models.AuditLog.user_id == user.id,
        )
        .all()
    )
    assert [r.success for r in ok] == [True]
