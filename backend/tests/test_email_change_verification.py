"""로그인 이메일 변경 전 새 주소 확인(#3230) — DB 필요(로컬 skip, CI 실행).

본인 확인(#3039)만으로는 자기 계정의 이메일을 남의 주소로 바꿀 수 있었다. 그 주소의
주인은 가입하려다 409 를 받고, 그 주소의 소셜 로그인은 바꾼 사람의 계정으로 들어왔다.
이제 새 주소로 보낸 코드(`POST /users/me/email/code`)가 맞아야 `PUT /users/me` 가
이메일을 바꾼다.

conftest 가 가입 인증을 꺼 두므로(`_signup_email_verification_off`) 여기서는
`verification_on` 픽스처로 다시 켠다.
"""
from __future__ import annotations

import re
from collections.abc import Iterator
from uuid import uuid4

import pytest
from sqlalchemy import select

from app.core.config import get_settings
from app.core.security import create_access_token, hash_password
from app.models.models import AuditLog, EmailVerificationCode, User
from app.services import account_notice, audit, signup_email_code
from app.services.mailer import OutgoingMail

PASSWORD = "mailchange3230-pw-1234"
PREFIX = "mailchange3230-"
_CODE = re.compile(r"\b(\d{6})\b")


class _Outbox:
    name = "test"

    def __init__(self) -> None:
        self.sent: list[OutgoingMail] = []

    def send(self, mail: OutgoingMail) -> None:
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
    # 바꾼 뒤 옛 주소로 가는 변경 안내도 같은 상자에 모은다.
    monkeypatch.setattr(account_notice, "get_mailer", lambda settings=None: box)
    return box


@pytest.fixture
def verification_on(monkeypatch) -> None:
    monkeypatch.setattr(get_settings(), "signup_email_verification", True)


@pytest.fixture
def made(db_session) -> Iterator[list[str]]:
    ids: list[str] = []
    yield ids
    db_session.expire_all()
    for user_id in ids:
        row = db_session.get(User, user_id)
        if row is not None:
            db_session.query(EmailVerificationCode).filter(
                EmailVerificationCode.email.like(f"{PREFIX}%")
            ).delete(synchronize_session=False)
            db_session.delete(row)
            db_session.commit()


def _user(db_session, made: list[str]) -> User:
    user = User(
        id=f"member-{uuid4().hex[:12]}",
        email=f"{PREFIX}{uuid4().hex[:10]}@oncare.com",
        name="이메일변경",
        hashed_password=hash_password(PASSWORD),
    )
    db_session.add(user)
    db_session.commit()
    made.append(user.id)
    return user


def _new_email() -> str:
    return f"{PREFIX}new-{uuid4().hex[:10]}@oncare.com"


def _h(user: User) -> dict[str, str]:
    return {"Authorization": f"Bearer {create_access_token(user.id)}"}


def _ask(client, user: User, email: str):
    return client.post("/v1/users/me/email/code", json={"email": email}, headers=_h(user))


def _put(client, user: User, **body):
    return client.put("/v1/users/me", json=body, headers=_h(user))


def _reload(db_session, user_id: str) -> User:
    db_session.expire_all()
    return db_session.get(User, user_id)


# ---- 코드 받기 ----


def test_code_goes_to_the_new_address(client, db_session, made, outbox, verification_on):
    user = _user(db_session, made)
    new = _new_email()
    res = _ask(client, user, new)
    assert res.status_code == 202, res.text
    assert res.json() == {
        "expires_in_minutes": get_settings().signup_email_code_minutes,
        "resend_after_seconds": get_settings().signup_email_code_resend_seconds,
    }
    assert outbox.code_for(new)
    # 옛 주소에는 아무것도 가지 않는다 — 코드는 새 주소의 주인만 받는다.
    assert outbox.to(user.email) == []
    body = outbox.to(new)[-1].body
    assert "로그인 이메일" in body


def test_taken_address_gets_the_same_response_but_no_code(
    client, db_session, made, outbox, verification_on
):
    """가입 여부가 응답으로 갈리지 않는다 — 다른 계정이 쓰는 주소에는 코드 대신 안내."""
    user = _user(db_session, made)
    other = _user(db_session, made)
    free = _ask(client, user, _new_email())
    taken = _ask(client, user, other.email)
    assert taken.status_code == free.status_code == 202
    assert taken.json() == free.json()
    mails = outbox.to(other.email)
    assert len(mails) == 1
    assert _CODE.search(mails[0].body) is None
    assert db_session.scalar(
        select(EmailVerificationCode).where(EmailVerificationCode.email == other.email)
    ) is None


def test_code_request_hands_mail_to_background_tasks(
    client, db_session, made, outbox, verification_on, monkeypatch
):
    """메일은 응답 뒤에 보낸다 — 가입 코드·비밀번호 재설정과 같다(#3257)."""
    seen: dict[str, object] = {}
    real = signup_email_code.request_code

    def spy(*args, **kwargs):
        seen["schedule"] = kwargs.get("schedule")
        return real(*args, **kwargs)

    monkeypatch.setattr(signup_email_code, "request_code", spy)
    user = _user(db_session, made)
    new = _new_email()
    res = _ask(client, user, new)
    assert res.status_code == 202, res.text
    assert callable(seen["schedule"])
    # TestClient 는 응답 뒤 백그라운드 작업까지 끝내고 돌아온다.
    assert outbox.code_for(new)


def test_same_address_is_rejected(client, db_session, made, outbox):
    user = _user(db_session, made)
    res = _ask(client, user, user.email.upper())
    assert res.status_code == 422
    assert res.json()["detail"]["code"] == "email_unchanged"
    assert outbox.sent == []


def test_code_request_needs_a_member_token(client):
    res = client.post("/v1/users/me/email/code", json={"email": _new_email()})
    assert res.status_code == 401


def test_code_request_is_audited(client, db_session, made, outbox, verification_on):
    user = _user(db_session, made)
    _ask(client, user, _new_email())
    db_session.expire_all()
    row = db_session.scalars(
        select(AuditLog)
        .where(
            AuditLog.event == audit.EMAIL_CHANGE_CODE_REQUEST, AuditLog.user_id == user.id
        )
        .order_by(AuditLog.id.desc())
    ).first()
    assert row is not None and row.success is True
    # 감사 로그에도 주소 전체는 남기지 않는다.
    assert PREFIX not in row.detail


# ---- 바꾸기 ----


def test_email_does_not_change_without_a_code(
    client, db_session, made, outbox, verification_on
):
    user = _user(db_session, made)
    before = user.email
    new = _new_email()
    _ask(client, user, new)
    res = _put(client, user, email=new, current_password=PASSWORD, name="안 바뀜")
    assert res.status_code == 422
    assert res.json()["detail"]["code"] == "email_code_required"
    row = _reload(db_session, user.id)
    assert row.email == before
    # 함께 보낸 다른 칸도 저장하지 않는다.
    assert row.name == "이메일변경"


def test_wrong_code_does_not_change_the_email(
    client, db_session, made, outbox, verification_on
):
    user = _user(db_session, made)
    before = user.email
    new = _new_email()
    _ask(client, user, new)
    real = outbox.code_for(new)
    wrong = "000000" if real != "000000" else "111111"
    res = _put(client, user, email=new, current_password=PASSWORD, email_code=wrong)
    assert res.status_code == 400
    assert res.json()["detail"]["code"] == "invalid_email_code"
    assert _reload(db_session, user.id).email == before
    db_session.expire_all()
    assert db_session.scalar(
        select(AuditLog.id).where(
            AuditLog.event == audit.EMAIL_CHANGE_CODE_VERIFY, AuditLog.success.is_(False)
        )
    ) is not None


def test_right_code_changes_the_email_and_marks_it_verified(
    client, db_session, made, outbox, verification_on
):
    user = _user(db_session, made)
    old = user.email
    new = _new_email()
    _ask(client, user, new)
    res = _put(
        client, user, email=new, current_password=PASSWORD, email_code=outbox.code_for(new)
    )
    assert res.status_code == 200, res.text
    assert res.json()["email"] == new
    assert res.json()["access_token"]
    row = _reload(db_session, user.id)
    assert row.email == new
    assert row.email_verified_at is not None
    # 옛 주소로 변경 안내가 간다(#3039).
    assert outbox.to(old)


def test_a_code_works_only_once(client, db_session, made, outbox, verification_on):
    user = _user(db_session, made)
    new = _new_email()
    _ask(client, user, new)
    code = outbox.code_for(new)
    assert _put(
        client, user, email=new, current_password=PASSWORD, email_code=code
    ).status_code == 200
    # 같은 코드로 다른 계정을 그 주소로 바꿀 수 없다(이미 쓰는 주소라 409 가 먼저지만,
    # 코드도 닫혀 있다).
    row = db_session.scalar(
        select(EmailVerificationCode).where(EmailVerificationCode.email == new)
    )
    db_session.refresh(row)
    assert row.used_at is not None


def test_code_for_another_address_does_not_work(
    client, db_session, made, outbox, verification_on
):
    """코드는 새 주소에 묶인다 — 내가 받은 주소의 코드로 남의 주소로 바꿀 수 없다."""
    user = _user(db_session, made)
    mine, victim = _new_email(), _new_email()
    _ask(client, user, mine)
    res = _put(
        client,
        user,
        email=victim,
        current_password=PASSWORD,
        email_code=outbox.code_for(mine),
    )
    assert res.status_code == 400
    assert _reload(db_session, user.id).email != victim


def test_signup_code_cannot_change_an_email(
    client, db_session, made, outbox, verification_on
):
    """가입 코드(`member_signup`)는 이메일 변경(`email_change`)에 쓸 수 없다."""
    user = _user(db_session, made)
    new = _new_email()
    asked = client.post(
        "/v1/auth/register/email-code", json={"email": new, "purpose": "member_signup"}
    )
    assert asked.status_code == 202
    res = _put(
        client, user, email=new, current_password=PASSWORD, email_code=outbox.code_for(new)
    )
    assert res.status_code == 400
    assert res.json()["detail"]["code"] == "invalid_email_code"


def test_public_signup_endpoint_does_not_issue_email_change_codes(client):
    res = client.post(
        "/v1/auth/register/email-code", json={"email": _new_email(), "purpose": "email_change"}
    )
    assert res.status_code == 422


def test_taken_address_is_409_before_the_code(
    client, db_session, made, outbox, verification_on
):
    user = _user(db_session, made)
    other = _user(db_session, made)
    res = _put(client, user, email=other.email, current_password=PASSWORD)
    assert res.status_code == 409


def test_reauth_still_comes_first(client, db_session, made, outbox, verification_on):
    user = _user(db_session, made)
    new = _new_email()
    _ask(client, user, new)
    res = _put(
        client, user, email=new, current_password="wrong-pw-0000",
        email_code=outbox.code_for(new),
    )
    assert res.status_code == 400
    assert res.json()["detail"]["code"] == "invalid_current_password"
    # 본인 확인에서 막힌 요청은 코드를 쓰지 않는다 — 비밀번호를 고쳐 다시 보내면 된다.
    ok = _put(
        client, user, email=new, current_password=PASSWORD, email_code=outbox.code_for(new)
    )
    assert ok.status_code == 200, ok.text


def test_name_only_save_needs_no_code(client, db_session, made, verification_on):
    user = _user(db_session, made)
    res = _put(client, user, name="이름만", email=user.email)
    assert res.status_code == 200, res.text


def test_without_verification_the_email_changes_unverified(client, db_session, made):
    """확인을 끈 서버(테스트·E2E)는 코드 없이 바꾸고, 확인하지 않은 주소로 남긴다."""
    user = _user(db_session, made)
    new = _new_email()
    res = _put(client, user, email=new, current_password=PASSWORD)
    assert res.status_code == 200, res.text
    row = _reload(db_session, user.id)
    assert row.email == new
    assert row.email_verified_at is None
