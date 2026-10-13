"""소셜 가입 계정의 대체 이메일 판정과 프로필 응답(#3338).

이메일을 주지 않는 소셜 계정으로 가입하면 계정 이메일 자리에
`{provider}_{id}@social.oncare` 가 들어간다. 회원에게는 낯선 주소라 응답이
`email_is_placeholder` 로 알려 앱이 가리게 하고, 그 주소로는 변경 안내 메일을 보내지
않는다.

앞부분은 DB 없이 도는 판정·스키마·발송 검사, 뒤의 엔드포인트 검사는 `client` 픽스처를
쓰므로 DB 가 있는 환경(CI)에서 돈다.
"""
from __future__ import annotations

from collections.abc import Iterator
from uuid import uuid4

import pytest

from app.api.v1 import social as social_api
from app.core.config import get_settings
from app.core.security import create_access_token, hash_password
from app.models.models import EmailVerificationCode, User
from app.schemas.user import HealthProfileBrief, ProfileView, UserMe
from app.services import account_notice, signup_email_code
from app.services.mailer import OutgoingMail
from app.services.placeholder_email import (
    PLACEHOLDER_EMAIL_DOMAIN,
    is_placeholder_email,
    placeholder_email,
    placeholder_provider,
)
from app.services.social.base import SocialIdentity

PASSWORD = "placeholder3338-pw-1234"
PREFIX = "placeholder3338-"


class _Outbox:
    name = "test"

    def __init__(self) -> None:
        self.sent: list[OutgoingMail] = []

    def send(self, mail: OutgoingMail) -> None:
        self.sent.append(mail)

    def to(self, email: str) -> list[OutgoingMail]:
        return [m for m in self.sent if m.to == email]


# ---- 판정 (DB 불필요) ----


def test_placeholder_email_is_built_from_the_provider_identity():
    assert placeholder_email("kakao", "12345") == "kakao_12345@social.oncare"
    assert placeholder_email("google", "AbC").endswith(f"@{PLACEHOLDER_EMAIL_DOMAIN}")


def test_social_signup_uses_the_same_rule():
    identity = SocialIdentity(provider="Google", provider_user_id="Sub-9")
    made = social_api._placeholder_email(identity)
    assert made == placeholder_email("Google", "Sub-9")
    assert is_placeholder_email(made)


@pytest.mark.parametrize(
    "email",
    [
        "kakao_12345@social.oncare",
        "google_abc@social.oncare",
        "KAKAO_12345@SOCIAL.ONCARE",
        "  kakao_1@social.oncare  ",
    ],
)
def test_placeholder_addresses_are_recognized(email):
    assert is_placeholder_email(email) is True


@pytest.mark.parametrize(
    "email",
    [
        "member@oncare.com",
        "kakao_1@social.oncare.com",
        "social.oncare@gmail.com",
        "kakao_1@oncare.com",
        "",
        None,
    ],
)
def test_real_addresses_are_not_placeholders(email):
    assert is_placeholder_email(email) is False
    assert placeholder_provider(email) is None


@pytest.mark.parametrize(
    ("email", "provider"),
    [
        ("kakao_12345@social.oncare", "kakao"),
        ("google_a_b_c@social.oncare", "google"),
        ("KAKAO_1@SOCIAL.ONCARE", "kakao"),
        # provider 자리가 규칙과 다르면 가입 수단을 말하지 않는다.
        ("nounderscore@social.oncare", None),
        ("_12345@social.oncare", None),
    ],
)
def test_placeholder_provider(email, provider):
    assert placeholder_provider(email) == provider


# ---- 스키마 (DB 불필요) ----


@pytest.mark.parametrize("schema", [UserMe, HealthProfileBrief, ProfileView])
def test_profile_schemas_default_to_a_real_email(schema):
    body = schema(id="u1", name="회원", email="m@oncare.com").model_dump()
    assert body["email_is_placeholder"] is False
    assert body["email_placeholder_provider"] is None


# ---- 변경 안내 메일 (DB 불필요) ----


def test_change_notice_is_not_sent_to_a_placeholder_address():
    box = _Outbox()
    sent = account_notice.send_email_changed(
        "kakao_1@social.oncare", "real@oncare.com", mailer=box
    )
    assert sent is False
    assert box.sent == []


def test_change_notice_still_goes_to_a_real_old_address():
    settings = get_settings()
    if not settings.mail_enabled:
        pytest.skip("이 설정에서는 발송 수단이 꺼져 있다")
    box = _Outbox()
    sent = account_notice.send_email_changed(
        "old@oncare.com", "new@oncare.com", settings=settings, mailer=box
    )
    assert sent is True
    assert [m.to for m in box.sent] == ["old@oncare.com"]


# ---- 엔드포인트 (DB 필요) ----


@pytest.fixture
def outbox(monkeypatch) -> _Outbox:
    box = _Outbox()
    monkeypatch.setattr(signup_email_code, "get_mailer", lambda settings=None: box)
    monkeypatch.setattr(account_notice, "get_mailer", lambda settings=None: box)
    return box


@pytest.fixture
def made(db_session) -> Iterator[list[str]]:
    ids: list[str] = []
    yield ids
    db_session.expire_all()
    db_session.query(EmailVerificationCode).filter(
        EmailVerificationCode.email.like(f"{PREFIX}%")
    ).delete(synchronize_session=False)
    for user_id in ids:
        row = db_session.get(User, user_id)
        if row is not None:
            db_session.delete(row)
    db_session.commit()


def _user(db_session, made: list[str], email: str) -> User:
    # 판정은 주소만 본다. 본인 확인을 비밀번호로 하려고 비밀번호를 둔다.
    user = User(
        id=f"member-{uuid4().hex[:12]}",
        email=email,
        name="소셜가입",
        hashed_password=hash_password(PASSWORD),
    )
    db_session.add(user)
    db_session.commit()
    made.append(user.id)
    return user


def _social_user(db_session, made: list[str], provider: str = "kakao") -> User:
    return _user(db_session, made, placeholder_email(provider, f"{PREFIX}{uuid4().hex[:10]}"))


def _h(user: User) -> dict[str, str]:
    return {"Authorization": f"Bearer {create_access_token(user.id)}"}


@pytest.mark.parametrize("provider", ["kakao", "google"])
def test_profile_responses_flag_the_placeholder(client, db_session, made, provider):
    user = _social_user(db_session, made, provider)

    me = client.get("/v1/users/me", headers=_h(user)).json()
    profile = client.get("/v1/users/me/profile", headers=_h(user)).json()
    health = client.get("/v1/users/me/health", headers=_h(user)).json()["profile"]

    for body in (me, profile, health):
        assert body["email_is_placeholder"] is True
        assert body["email_placeholder_provider"] == provider
        # 주소 자체는 예전처럼 싣는다 — 옛 버전 앱이 읽는 자리다.
        assert body["email"] == user.email


def test_profile_responses_leave_a_real_email_alone(client, db_session, made):
    user = _user(db_session, made, f"{PREFIX}{uuid4().hex[:10]}@oncare.com")

    me = client.get("/v1/users/me", headers=_h(user)).json()
    profile = client.get("/v1/users/me/profile", headers=_h(user)).json()
    health = client.get("/v1/users/me/health", headers=_h(user)).json()["profile"]

    for body in (me, profile, health):
        assert body["email_is_placeholder"] is False
        assert body["email_placeholder_provider"] is None
        assert body["email"] == user.email


def test_first_real_email_clears_the_flag_and_sends_no_notice(
    client, db_session, made, outbox
):
    user = _social_user(db_session, made)
    old = user.email
    new = f"{PREFIX}new-{uuid4().hex[:10]}@oncare.com"

    res = client.put(
        "/v1/users/me",
        json={"email": new, "current_password": PASSWORD},
        headers=_h(user),
    )

    assert res.status_code == 200, res.text
    body = res.json()
    assert body["email"] == new
    assert body["email_is_placeholder"] is False
    assert body["email_placeholder_provider"] is None
    # 받는 사람이 없는 내부용 주소로는 변경 안내를 보내지 않는다.
    assert outbox.to(old) == []


def test_real_to_real_change_still_notifies_the_old_address(
    client, db_session, made, outbox
):
    user = _user(db_session, made, f"{PREFIX}{uuid4().hex[:10]}@oncare.com")
    old = user.email
    new = f"{PREFIX}new-{uuid4().hex[:10]}@oncare.com"

    res = client.put(
        "/v1/users/me",
        json={"email": new, "current_password": PASSWORD},
        headers=_h(user),
    )

    assert res.status_code == 200, res.text
    assert outbox.to(old)
