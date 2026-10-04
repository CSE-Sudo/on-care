"""탈퇴·로그인 이메일 변경 전 본인 확인(#3039) — DB 필요(로컬 skip, CI 실행).

접근 토큰만으로는 계정을 지우거나 로그인 이메일을 바꾸지 못한다. 비밀번호 계정은
현재 비밀번호, 소셜 로그인 전용 계정은 다시 로그인해 받은 provider 토큰(그 사용자에게
연결된 provider 계정이어야 한다)이 필요하다. 실패는 모두 400 이라 앱이 로그아웃으로
오인하지 않는다.
"""
from __future__ import annotations

from collections.abc import Iterator
from uuid import uuid4

import pytest
from sqlalchemy import select

from app.core.config import get_settings
from app.core.security import create_access_token, hash_password
from app.models.models import AuditLog, SocialAccount, TrainerProfile, User
from app.services import account_notice, audit, reauth
from app.services.mailer import OutgoingMail
from app.services.social.base import SocialAuthError, SocialIdentity

PASSWORD = "reauth3039-pw-1234"
PREFIX = "reauth3039-"


class _Outbox:
    name = "test"

    def __init__(self) -> None:
        self.sent: list[OutgoingMail] = []

    def send(self, mail: OutgoingMail) -> None:
        self.sent.append(mail)


@pytest.fixture
def outbox(monkeypatch) -> _Outbox:
    box = _Outbox()
    monkeypatch.setattr(account_notice, "get_mailer", lambda settings=None: box)
    return box


class _FakeVerifier:
    """provider 토큰 `good-<uid>` 를 그 uid 로 확인한다. 나머지는 실패."""

    def __init__(self, provider: str) -> None:
        self.provider = provider

    async def verify(self, token: str) -> SocialIdentity:
        if not token.startswith("good-"):
            raise SocialAuthError("bad token")
        return SocialIdentity(provider=self.provider, provider_user_id=token[5:])


@pytest.fixture
def fake_social(monkeypatch) -> None:
    monkeypatch.setattr(reauth, "get_verifier", lambda provider: _FakeVerifier(provider))


@pytest.fixture
def made(db_session) -> Iterator[list[str]]:
    ids: list[str] = []
    yield ids
    db_session.expire_all()
    for user_id in ids:
        row = db_session.get(User, user_id)
        if row is None:
            continue
        if row.role == "trainer":
            from app.services.trainer import profile as trainer_profile_service

            trainer_profile_service.delete_trainer_account(db_session, row)
        else:
            db_session.delete(row)
            db_session.commit()


def _user(
    db_session,
    made: list[str],
    *,
    role: str = "member",
    password: str | None = PASSWORD,
    social_uid: str | None = None,
) -> User:
    user = User(
        id=f"{role}-{uuid4().hex[:12]}",
        email=f"{PREFIX}{uuid4().hex[:10]}@oncare.com",
        name="본인확인",
        hashed_password=hash_password(password) if password else "",
        role=role,
    )
    db_session.add(user)
    db_session.commit()
    if role == "trainer":
        db_session.add(TrainerProfile(trainer_id=user.id))
    if social_uid:
        db_session.add(
            SocialAccount(user_id=user.id, provider="kakao", provider_user_id=social_uid)
        )
    db_session.commit()
    made.append(user.id)
    return user


def _h(user: User) -> dict[str, str]:
    return {"Authorization": f"Bearer {create_access_token(user.id)}"}


def _delete(client, user: User, path: str = "/v1/users/me", **body):
    return client.request("DELETE", path, json=body or None, headers=_h(user))


def _exists(db_session, user_id: str) -> bool:
    db_session.expire_all()
    return db_session.get(User, user_id) is not None


# ---- 탈퇴 ----


def test_member_delete_without_reauth_is_400(client, db_session, made):
    user = _user(db_session, made)
    res = _delete(client, user)
    assert res.status_code == 400, res.text
    assert res.json()["detail"]["code"] == "reauth_required"
    assert _exists(db_session, user.id)


def test_member_delete_with_reasons_only_is_400(client, db_session, made):
    user = _user(db_session, made)
    res = _delete(client, user, reasons=["privacy"])
    assert res.json()["detail"]["code"] == "reauth_required"
    assert _exists(db_session, user.id)


def test_member_delete_with_wrong_password_is_400(client, db_session, made):
    user = _user(db_session, made)
    res = _delete(client, user, current_password="wrong-pw-0000")
    assert res.status_code == 400
    assert res.json()["detail"]["code"] == "invalid_current_password"
    assert _exists(db_session, user.id)


def test_member_delete_with_password_works(client, db_session, made):
    user = _user(db_session, made)
    res = _delete(client, user, current_password=PASSWORD)
    assert res.status_code == 200, res.text
    assert not _exists(db_session, user.id)


def test_trainer_delete_requires_password(client, db_session, made):
    trainer = _user(db_session, made, role="trainer")
    missing = _delete(client, trainer, "/v1/trainer/me")
    assert missing.status_code == 400
    assert missing.json()["detail"]["code"] == "reauth_required"
    wrong = _delete(client, trainer, "/v1/trainer/me", current_password="nope-0000")
    assert wrong.json()["detail"]["code"] == "invalid_current_password"
    assert _exists(db_session, trainer.id)
    ok = _delete(client, trainer, "/v1/trainer/me", current_password=PASSWORD)
    assert ok.status_code == 200, ok.text
    assert not _exists(db_session, trainer.id)


def test_social_only_member_reauths_with_linked_account(
    client, db_session, made, fake_social
):
    user = _user(db_session, made, password=None, social_uid="kakao-111")
    missing = _delete(client, user)
    assert missing.json()["detail"]["code"] == "reauth_required"
    bad = _delete(client, user, social_provider="kakao", social_token="bad")
    assert bad.status_code == 400
    assert bad.json()["detail"]["code"] == "invalid_reauth"
    ok = _delete(client, user, social_provider="kakao", social_token="good-kakao-111")
    assert ok.status_code == 200, ok.text
    assert not _exists(db_session, user.id)


def test_someone_elses_social_token_is_refused(client, db_session, made, fake_social):
    """검증에 성공한 토큰이라도 이 사용자에게 연결된 provider 계정이어야 한다."""
    user = _user(db_session, made, password=None, social_uid="kakao-222")
    _user(db_session, made, password=None, social_uid="kakao-333")
    res = _delete(client, user, social_provider="kakao", social_token="good-kakao-333")
    assert res.status_code == 400
    assert res.json()["detail"]["code"] == "invalid_reauth"
    assert _exists(db_session, user.id)


def test_social_trainer_reauths_with_linked_account(client, db_session, made, fake_social):
    trainer = _user(db_session, made, role="trainer", password=None, social_uid="kakao-444")
    res = _delete(
        client, trainer, "/v1/trainer/me", social_provider="kakao", social_token="good-kakao-444"
    )
    assert res.status_code == 200, res.text


def test_trainer_me_reports_has_password(client, db_session, made):
    with_pw = _user(db_session, made, role="trainer")
    social = _user(db_session, made, role="trainer", password=None, social_uid="kakao-555")
    assert client.get("/v1/trainer/me", headers=_h(with_pw)).json()["has_password"] is True
    assert client.get("/v1/trainer/me", headers=_h(social)).json()["has_password"] is False


def test_repeated_failures_lock_reauth(client, db_session, made, monkeypatch):
    monkeypatch.setattr(get_settings(), "password_change_max_failures", 2)
    user = _user(db_session, made)
    for _ in range(2):
        assert _delete(client, user, current_password="wrong-0000").status_code == 400
    locked = _delete(client, user, current_password=PASSWORD)
    assert locked.status_code == 429
    assert "Retry-After" in locked.headers
    assert _exists(db_session, user.id)


def test_missing_values_do_not_count_as_failures(client, db_session, made, monkeypatch):
    """본문 없는 옛 빌드 호출은 추측 시도가 아니다 — 잠금에 세지 않는다."""
    monkeypatch.setattr(get_settings(), "password_change_max_failures", 1)
    user = _user(db_session, made)
    for _ in range(3):
        assert _delete(client, user).status_code == 400
    assert _delete(client, user, current_password=PASSWORD).status_code == 200


def test_failures_are_audited(client, db_session, made):
    user = _user(db_session, made)
    _delete(client, user, current_password="wrong-0000")
    db_session.expire_all()
    rows = db_session.scalars(
        select(AuditLog).where(
            AuditLog.event == audit.REAUTH_FAILED, AuditLog.user_id == user.id
        )
    ).all()
    assert len(rows) == 1
    assert rows[0].success is False
    assert "action=delete_account" in rows[0].detail
    assert "wrong-0000" not in rows[0].detail


# ---- 로그인 이메일 변경 ----


def _put(client, user: User, **body):
    return client.put("/v1/users/me", json=body, headers=_h(user))


def test_profile_save_without_email_change_needs_no_password(client, db_session, made):
    user = _user(db_session, made)
    res = _put(client, user, name="새 이름", email=user.email)
    assert res.status_code == 200, res.text
    assert res.json()["access_token"] is None
    assert res.json()["refresh_token"] is None


def test_case_only_email_change_needs_no_password(client, db_session, made):
    """대소문자만 다른 값은 같은 이메일이다(#2816) — 바뀌는 것이 없다."""
    user = _user(db_session, made)
    res = _put(client, user, email=user.email.upper())
    assert res.status_code == 200, res.text
    assert res.json()["access_token"] is None


def test_email_change_without_password_is_400(client, db_session, made):
    user = _user(db_session, made)
    new_email = f"{PREFIX}new-{uuid4().hex[:8]}@oncare.com"
    res = _put(client, user, email=new_email)
    assert res.status_code == 400
    assert res.json()["detail"]["code"] == "reauth_required"
    db_session.expire_all()
    assert db_session.get(User, user.id).email == user.email


def test_email_change_with_wrong_password_is_400(client, db_session, made):
    user = _user(db_session, made)
    res = _put(
        client, user, email=f"{PREFIX}new-{uuid4().hex[:8]}@oncare.com",
        current_password="wrong-0000",
    )
    assert res.json()["detail"]["code"] == "invalid_current_password"


def test_duplicate_check_comes_after_reauth(client, db_session, made):
    """확인 없이 409 를 주면 아무 주소나 넣어 가입 여부를 알아낼 수 있다."""
    user = _user(db_session, made)
    other = _user(db_session, made)
    assert _put(client, user, email=other.email).json()["detail"]["code"] == "reauth_required"
    assert _put(client, user, email=other.email, current_password=PASSWORD).status_code == 409


def test_email_change_rotates_tokens_and_notifies_old_address(
    client, db_session, made, outbox
):
    user = _user(db_session, made)
    old_email = user.email
    old_token = create_access_token(user.id)
    new_email = f"{PREFIX}moved-{uuid4().hex[:8]}@oncare.com"

    res = _put(client, user, email=new_email, current_password=PASSWORD, name="이동")

    assert res.status_code == 200, res.text
    body = res.json()
    assert body["email"] == new_email
    assert body["access_token"] and body["refresh_token"]
    # 새 토큰은 쓰이고, 바꾸기 전 토큰은 끊긴다(세대가 올랐다).
    # 쓰기 API 는 데모 폴백이 없어 끊긴 토큰이 그대로 401 이다.
    fresh = {"Authorization": f"Bearer {body['access_token']}"}
    assert client.put("/v1/users/me", json={"name": "새"}, headers=fresh).status_code == 200
    stale = client.put(
        "/v1/users/me", json={"name": "옛"}, headers={"Authorization": f"Bearer {old_token}"}
    )
    assert stale.status_code == 401
    (notice,) = [m for m in outbox.sent if m.to == old_email]
    assert new_email not in notice.body
    db_session.expire_all()
    rows = db_session.scalars(
        select(AuditLog).where(
            AuditLog.event == audit.EMAIL_CHANGE, AuditLog.user_id == user.id
        )
    ).all()
    assert len(rows) == 1
    assert old_email not in (rows[0].detail or "")


def test_social_only_member_changes_email_with_linked_account(
    client, db_session, made, fake_social, outbox
):
    user = _user(db_session, made, password=None, social_uid="kakao-666")
    new_email = f"{PREFIX}social-{uuid4().hex[:8]}@oncare.com"
    res = _put(
        client, user, email=new_email, social_provider="kakao", social_token="good-kakao-666"
    )
    assert res.status_code == 200, res.text
    assert res.json()["access_token"]
