"""이메일 대소문자 정규화. (#2816)

가입·로그인·중복 확인은 대소문자를 구분하고 관리자 승격만 무시하던 불일치를 닫는다.
대문자를 섞어 쳐도 같은 계정으로 로그인돼야 한다. 기동 때 이메일로 관리자를 올리던
동작은 #3037 에서 없앴다 — 관리자 지정의 대소문자 변형 판정은
`test_grant_admin_script` 가 본다.

앞부분은 DB 없이 도는 순수 검사, 뒷부분(`client` 픽스처)은 CI 의 Postgres 에서 돈다.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path
from unittest.mock import patch
from uuid import uuid4

import pytest
from sqlalchemy import select, text

from app.models.models import User
from app.services.contact_format import clean_email, normalize_email

PASSWORD = "email-case-pw-1234"
PREFIX = "email-case-"

_MIGRATION = (
    Path(__file__).resolve().parents[1]
    / "migrations"
    / "versions"
    / "0134_users_email_lower_unique.py"
)


def _load_migration():
    spec = importlib.util.spec_from_file_location("m0120", _MIGRATION)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


# ---- 정규화 규칙 (DB 불필요) ----


@pytest.mark.parametrize(
    ("value", "normalized"),
    [
        ("member@oncare.com", "member@oncare.com"),
        ("Member@ONCARE.com", "member@oncare.com"),
        ("  ADMIN@Example.COM  ", "admin@example.com"),
        ("", ""),
    ],
)
def test_normalize_email(value, normalized):
    assert normalize_email(value) == normalized


def test_clean_email_and_normalize_email_agree():
    """가입이 저장하는 값과 로그인이 찾는 값이 같은 규칙이어야 한다."""
    raw = "  First.Last+Tag@Sub.OnCare.co.KR "
    assert clean_email(raw) == normalize_email(raw)


# ---- 가입·로그인 (DB) ----


def _email(tag: str) -> str:
    return f"{PREFIX}{tag}-{uuid4().hex[:10]}@oncare.com"


def _register(client, email: str, path: str = "/v1/auth/register"):
    return client.post(path, json={"email": email, "password": PASSWORD, "name": "케이스"})


def _login(client, email: str):
    return client.post("/v1/auth/login", data={"username": email, "password": PASSWORD})


def test_register_stores_lowercase(client):
    email = _email("store")
    response = _register(client, email.upper())
    assert response.status_code == 201, response.text
    assert response.json()["email"] == email


def test_case_variant_registration_is_rejected(client):
    email = _email("dup")
    assert _register(client, email).status_code == 201
    again = _register(client, email.replace(PREFIX, PREFIX.upper(), 1))
    assert again.status_code == 409
    assert _register(client, email.upper()).status_code == 409


def test_trainer_registration_rejects_case_variant_of_member(client):
    email = _email("trainer-dup")
    assert _register(client, email).status_code == 201
    trainer = _register(client, email.title(), "/v1/auth/trainer/register")
    assert trainer.status_code == 409


def test_trainer_registration_stores_lowercase(client):
    email = _email("trainer-store")
    response = _register(client, email.upper(), "/v1/auth/trainer/register")
    assert response.status_code == 201, response.text
    assert response.json()["email"] == email


@pytest.mark.parametrize("transform", [str.upper, str.title, lambda e: f"  {e} "])
def test_login_ignores_case_and_spaces(client, transform):
    email = _email("login")
    assert _register(client, email).status_code == 201
    response = _login(client, transform(email))
    assert response.status_code == 200, response.text


def test_login_with_wrong_password_still_401(client):
    email = _email("login-wrong")
    assert _register(client, email).status_code == 201
    response = client.post(
        "/v1/auth/login", data={"username": email.upper(), "password": "wrong-pw-0000"}
    )
    assert response.status_code == 401


def test_profile_email_change_rejects_case_variant_of_other(client):
    taken = _email("taken")
    assert _register(client, taken).status_code == 201
    mine = _email("mine")
    assert _register(client, mine).status_code == 201
    token = _login(client, mine).json()["access_token"]
    response = client.put(
        "/v1/users/me",
        json={"email": taken.upper(), "current_password": PASSWORD},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 409


def test_profile_email_change_stores_lowercase(client, db_session):
    mine = _email("change")
    assert _register(client, mine).status_code == 201
    token = _login(client, mine).json()["access_token"]
    new_email = _email("changed")
    response = client.put(
        "/v1/users/me",
        json={"email": new_email.upper(), "current_password": PASSWORD},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 200, response.text
    assert response.json()["email"] == new_email


def test_social_login_links_existing_account_ignoring_case(client, db_session):
    from app.api.v1.social import _find_or_create_user
    from app.services.social.base import SocialIdentity

    email = _email("social")
    member_id = _register(client, email).json()["id"]
    linked = _find_or_create_user(
        db_session,
        SocialIdentity(
            provider="google",
            provider_user_id=f"g-{uuid4().hex[:10]}",
            email=email.upper(),
        ),
    )
    assert linked.id == member_id


def test_social_login_new_account_stores_lowercase(client, db_session):
    from app.api.v1.social import _find_or_create_user
    from app.services.social.base import SocialIdentity

    email = _email("social-new")
    user = _find_or_create_user(
        db_session,
        SocialIdentity(
            provider="kakao",
            provider_user_id=f"k-{uuid4().hex[:10]}",
            email=email.upper(),
        ),
    )
    assert user.email == email


def test_db_rejects_case_duplicate_insert(client, db_session):
    """앱을 거치지 않은 쓰기도 `lower(email)` 유니크 인덱스가 막는다."""
    from sqlalchemy.exc import IntegrityError

    email = _email("db")
    db_session.add(User(id=f"case-db-{uuid4().hex[:8]}", email=email, name="a"))
    db_session.commit()
    db_session.add(User(id=f"case-db-{uuid4().hex[:8]}", email=email.upper(), name="b"))
    with pytest.raises(IntegrityError):
        db_session.commit()
    db_session.rollback()


# ---- 마이그레이션 0120 (DB) ----


def test_migration_detects_case_duplicates_and_stops(client):
    from app.db.session import engine

    module = _load_migration()
    email = _email("mig-dup")
    with engine.connect() as conn:
        tx = conn.begin()
        try:
            conn.execute(text(f"DROP INDEX IF EXISTS {module.INDEX_NAME}"))
            for i, value in enumerate((email, email.upper())):
                conn.execute(
                    text(
                        "INSERT INTO users (id, email, name, hashed_password, is_active, "
                        "is_admin, role, token_version) VALUES "
                        "(:id, :email, '', '', true, false, 'member', 0)"
                    ),
                    {"id": f"case-mig-{i}-{uuid4().hex[:8]}", "email": value},
                )
            groups = module.find_case_duplicates(conn)
            emails = [g[0] for g in groups]
            assert email in emails
            ids = dict(groups)[email]
            assert len(ids) == 2
            message = module.describe_duplicates(groups)
            assert email in message and all(i in message for i in ids)
            with patch.object(module.op, "get_bind", return_value=conn):
                with pytest.raises(module.CaseDuplicateEmails):
                    module.upgrade()
        finally:
            tx.rollback()


def test_migration_lowercases_existing_rows(client):
    from app.db.session import engine

    module = _load_migration()
    email = _email("mig-lower")
    user_id = f"case-mig-l-{uuid4().hex[:8]}"
    with engine.connect() as conn:
        tx = conn.begin()
        try:
            conn.execute(
                text(
                    "INSERT INTO users (id, email, name, hashed_password, is_active, "
                    "is_admin, role, token_version) VALUES "
                    "(:id, :email, '', '', true, false, 'member', 0)"
                ),
                {"id": user_id, "email": email.upper()},
            )
            assert module.lowercase_emails(conn) >= 1
            stored = conn.execute(
                text("SELECT email FROM users WHERE id = :id"), {"id": user_id}
            ).scalar_one()
            assert stored == email
        finally:
            tx.rollback()
