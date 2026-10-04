"""관리자 지정 스크립트 `scripts/grant_admin.py`(#3037).

예전에는 기동할 때 `ADMIN_EMAILS` 의 주소로 가입된 계정을 관리자로 올려, 그 주소로
**먼저 가입한 사람**이 관리자가 됐다. 이제 관리자는 운영자가 계정 id 를 직접 확인한
뒤 이 스크립트로만 바뀐다.

앞부분은 DB 없이 도는 순수 검사(기동 경고), 뒷부분(`db_session`)은 CI 의 Postgres 에서
돈다. `main()` 은 앱의 `SessionLocal` 을 쓰므로 같은 DB 를 본다.
"""
from __future__ import annotations

import logging
from collections.abc import Iterator
from uuid import uuid4

import pytest
from sqlalchemy import select

from app.core import startup_checks
from app.core.config import Settings
from app.models.models import AuditLog, User
from app.services import audit
from scripts import grant_admin

PREFIX = "grant-admin-"


# ---- 기동 경고 (DB 불필요) ----


def test_leftover_admin_emails_is_warned(caplog):
    settings = Settings(_env_file=None, admin_emails="ops@example.com")
    with caplog.at_level(logging.WARNING, logger="app.startup"):
        warnings = startup_checks.check(settings)
    assert any("ADMIN_EMAILS" in w and "grant_admin" in w for w in warnings)


def test_no_warning_without_admin_emails():
    warnings = startup_checks.check(Settings(_env_file=None, admin_emails=""))
    assert not any("ADMIN_EMAILS" in w for w in warnings)


# ---- 스크립트 (DB) ----


@pytest.fixture
def users(db_session) -> Iterator[list[str]]:
    created: list[str] = []
    yield created
    db_session.expire_all()
    for user_id in created:
        row = db_session.get(User, user_id)
        if row is not None:
            db_session.delete(row)
    db_session.commit()


def _user(db_session, users: list[str], email: str, *, is_admin: bool = False) -> User:
    user = User(
        id=f"user-{uuid4().hex[:12]}",
        email=email,
        name="관리자 후보",
        hashed_password="",
        is_admin=is_admin,
    )
    db_session.add(user)
    db_session.commit()
    users.append(user.id)
    return user


def _email(tag: str) -> str:
    return f"{PREFIX}{tag}-{uuid4().hex[:8]}@oncare.com"


def _audits(db_session, event: str, target: str) -> list[AuditLog]:
    db_session.expire_all()
    return list(
        db_session.scalars(
            select(AuditLog).where(
                AuditLog.event == event, AuditLog.target_user_id == target
            )
        ).all()
    )


def test_lookup_only_changes_nothing(client, db_session, users, capsys):
    email = _email("look")
    user = _user(db_session, users, email)
    assert grant_admin.main(["--email", email]) == grant_admin.EXIT_OK
    out = capsys.readouterr().out
    assert user.id in out
    db_session.expire_all()
    assert db_session.get(User, user.id).is_admin is False
    assert _audits(db_session, audit.ADMIN_GRANT, user.id) == []


def test_grant_needs_matching_id(client, db_session, users):
    email = _email("grant")
    user = _user(db_session, users, email)
    code = grant_admin.main(["--email", email, "--confirm-id", user.id])
    assert code == grant_admin.EXIT_OK
    db_session.expire_all()
    assert db_session.get(User, user.id).is_admin is True
    (row,) = _audits(db_session, audit.ADMIN_GRANT, user.id)
    assert row.success is True


def test_id_of_another_account_is_refused(client, db_session, users):
    email = _email("mismatch")
    target = _user(db_session, users, email)
    other = _user(db_session, users, _email("other"))
    code = grant_admin.main(["--email", email, "--confirm-id", other.id])
    assert code == grant_admin.EXIT_MISMATCH
    db_session.expire_all()
    assert db_session.get(User, target.id).is_admin is False
    assert db_session.get(User, other.id).is_admin is False


def test_unknown_email_is_refused(client, db_session):
    code = grant_admin.main(["--email", _email("ghost"), "--confirm-id", "user-x"])
    assert code == grant_admin.EXIT_NOT_FOUND


def test_legacy_uppercase_row_is_found_but_needs_its_id(client, db_session, users):
    """정규화 전 대문자 표기로 남은 옛 행도 소문자 입력으로 찾는다 — id 가 맞을 때만 바꾼다."""
    from sqlalchemy import text

    email = _email("legacy")
    legacy = _user(db_session, users, email)
    db_session.execute(
        text("UPDATE users SET email = :upper WHERE id = :id"),
        {"upper": email.upper(), "id": legacy.id},
    )
    db_session.commit()
    assert grant_admin.main(["--email", email, "--confirm-id", "user-x"]) == (
        grant_admin.EXIT_MISMATCH
    )
    assert grant_admin.main(["--email", email, "--confirm-id", legacy.id]) == (
        grant_admin.EXIT_OK
    )


def test_find_account_refuses_ambiguous_matches(monkeypatch):
    """여러 계정이 걸리면 [GrantError] — 서버가 주인을 고를 수 없다."""

    class _Rows:
        def all(self):
            return [User(id="u-1", email="a@x.com"), User(id="u-2", email="A@x.com")]

    class _Db:
        def scalars(self, _stmt):
            return _Rows()

    with pytest.raises(grant_admin.GrantError) as caught:
        grant_admin.find_account(_Db(), "a@x.com")  # type: ignore[arg-type]
    assert caught.value.exit_code == grant_admin.EXIT_AMBIGUOUS


def test_startup_never_reads_admin_emails():
    """재현 경로: 운영자 주소로 먼저 가입 → 재배포 → 관리자. 기동 코드가 이 값을 읽지
    않으므로 먼저 가입한 계정이 관리자가 되는 길이 없다."""
    import inspect

    from app.db import init_db

    assert "admin_emails" not in inspect.getsource(init_db)


def test_revoke(client, db_session, users):
    email = _email("revoke")
    user = _user(db_session, users, email, is_admin=True)
    code = grant_admin.main(["--email", email, "--confirm-id", user.id, "--revoke"])
    assert code == grant_admin.EXIT_OK
    db_session.expire_all()
    assert db_session.get(User, user.id).is_admin is False
    assert len(_audits(db_session, audit.ADMIN_REVOKE, user.id)) == 1


def test_other_admins_are_left_alone(client, db_session, users):
    keep = _user(db_session, users, _email("keep"), is_admin=True)
    email = _email("new")
    new = _user(db_session, users, email)
    assert grant_admin.main(["--email", email, "--confirm-id", new.id]) == grant_admin.EXIT_OK
    db_session.expire_all()
    assert db_session.get(User, keep.id).is_admin is True
    assert db_session.get(User, new.id).is_admin is True


def test_granting_twice_is_a_no_op(client, db_session, users):
    email = _email("twice")
    user = _user(db_session, users, email)
    grant_admin.main(["--email", email, "--confirm-id", user.id])
    assert grant_admin.main(["--email", email, "--confirm-id", user.id]) == grant_admin.EXIT_OK
    assert len(_audits(db_session, audit.ADMIN_GRANT, user.id)) == 1
