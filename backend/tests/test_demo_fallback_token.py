"""데모 폴백은 토큰이 아예 없는 요청에만(#3160).

스테이징에서 데모 폴백을 켜 두면 만료·무효 토큰도 데모 회원으로 처리돼, 실계정 테스터의
토큰이 만료되는 순간 로그인 화면 대신 데모 회원의 기록이 보였다. 토큰이 있는데 쓸 수
없으면 폴백과 무관하게 401 이어야 앱이 갱신 토큰을 돌리고 로그인 화면으로 간다.

- 앞부분은 `get_current_user` 를 가짜 세션으로 직접 부르는 DB 없는 테스트다.
- 뒷부분(`client` 픽스처)은 CI 의 Postgres 에서 실제 회원 API 로 본다.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from uuid import uuid4

import jwt
import pytest
from fastapi import HTTPException
from starlette.requests import Request

from app.api import deps
from app.core.config import get_settings
from app.core.security import create_access_token
from app.db.init_db import DEMO_USER_ID

# ---- 공용 ----


def _expired_token(user_id: str, *, token_version: int = 0) -> str:
    settings = get_settings()
    now = datetime.now(timezone.utc)
    payload = {
        "sub": user_id,
        "type": "access",
        "iat": now - timedelta(hours=2),
        "exp": now - timedelta(hours=1),
        "tv": token_version,
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def _foreign_signature_token(user_id: str) -> str:
    settings = get_settings()
    now = datetime.now(timezone.utc)
    payload = {
        "sub": user_id,
        "type": "access",
        "iat": now,
        "exp": now + timedelta(hours=1),
        "tv": 0,
    }
    return jwt.encode(
        payload, "another-secret-that-is-long-enough-1234567890", algorithm=settings.jwt_algorithm
    )


@pytest.fixture
def fallback_on(monkeypatch):
    settings = get_settings()
    monkeypatch.setattr(settings, "allow_demo_fallback", True)
    monkeypatch.setattr(settings, "env", "staging")
    assert settings.demo_fallback_enabled is True
    return settings


@pytest.fixture
def fallback_off(monkeypatch):
    settings = get_settings()
    monkeypatch.setattr(settings, "allow_demo_fallback", False)
    assert settings.demo_fallback_enabled is False
    return settings


# ---- DB 없이: get_current_user 직접 호출 ----


class _FakeDb:
    """`db.scalar(select(User)…)` 에 정해 둔 사용자를 돌려준다(id 로 찾음)."""

    def __init__(self, *users):
        self.users = {u.id: u for u in users}
        self.lookups: list[str] = []

    def scalar(self, statement):
        params = statement.compile().params
        user_id = next(iter(params.values()))
        self.lookups.append(user_id)
        return self.users.get(user_id)


def _request(token: str | None = None, *, raw: str | None = None) -> Request:
    headers = []
    if raw is not None:
        headers.append((b"authorization", raw.encode()))
    elif token is not None:
        headers.append((b"authorization", f"Bearer {token}".encode()))
    return Request({"type": "http", "method": "GET", "path": "/v1/users/me", "headers": headers})


def _person(user_id: str, *, role: str = "member", active: bool = True, tv: int = 0):
    return SimpleNamespace(id=user_id, role=role, is_active=active, token_version=tv)


@pytest.fixture
def consent_ok(monkeypatch):
    """동의 확인은 이 테스트의 관심이 아니다(#3088 은 따로 본다)."""
    monkeypatch.setattr(deps, "ensure_consented", lambda request, user, db: None)


def _call(request: Request, db: _FakeDb):
    return deps.get_current_user(request, db)


def _assert_401(request: Request, db: _FakeDb):
    with pytest.raises(HTTPException) as excinfo:
        _call(request, db)
    assert excinfo.value.status_code == 401
    assert excinfo.value.headers == {"WWW-Authenticate": "Bearer"}


def test_no_token_falls_back_to_the_demo_member(fallback_on, consent_ok):
    demo = _person(DEMO_USER_ID)
    db = _FakeDb(demo)
    assert _call(_request(), db) is demo


@pytest.mark.parametrize(
    "raw",
    ["", "Bearer ", "Basic dXNlcjpwYXNz"],
    ids=["no-header-value", "empty-bearer", "not-bearer"],
)
def test_requests_without_a_bearer_token_count_as_no_token(fallback_on, consent_ok, raw):
    demo = _person(DEMO_USER_ID)
    assert _call(_request(raw=raw), _FakeDb(demo)) is demo


def test_expired_token_is_401_with_fallback_on(fallback_on, consent_ok):
    member = _person("member-expired")
    db = _FakeDb(member, _person(DEMO_USER_ID))
    _assert_401(_request(_expired_token(member.id)), db)
    # 데모 사용자를 찾으러 가지도 않는다.
    assert DEMO_USER_ID not in db.lookups


@pytest.mark.parametrize(
    "token_factory",
    [
        lambda uid: "not-a-real-token",
        lambda uid: _foreign_signature_token(uid),
        lambda uid: _expired_token(uid),
    ],
    ids=["garbage", "wrong-signature", "expired"],
)
def test_undecodable_tokens_are_401_with_fallback_on(fallback_on, consent_ok, token_factory):
    member = _person("member-bad-token")
    _assert_401(_request(token_factory(member.id)), _FakeDb(member, _person(DEMO_USER_ID)))


def test_previous_generation_token_is_401_with_fallback_on(fallback_on, consent_ok):
    """비밀번호를 바꾼 뒤(#2766) 남은 옛 세대 토큰."""
    member = _person("member-rotated", tv=2)
    token = create_access_token(member.id, token_version=1)
    _assert_401(_request(token), _FakeDb(member, _person(DEMO_USER_ID)))


def test_token_for_a_missing_user_is_401_with_fallback_on(fallback_on, consent_ok):
    """탈퇴 등으로 사라진 사용자의 토큰."""
    token = create_access_token("member-gone")
    _assert_401(_request(token), _FakeDb(_person(DEMO_USER_ID)))


def test_inactive_user_is_401_with_fallback_on(fallback_on, consent_ok):
    member = _person("member-inactive", active=False)
    _assert_401(_request(create_access_token(member.id)), _FakeDb(member, _person(DEMO_USER_ID)))


def test_trainer_token_is_403_with_fallback_on(fallback_on, consent_ok):
    trainer = _person("trainer-x", role="trainer")
    with pytest.raises(HTTPException) as excinfo:
        _call(_request(create_access_token(trainer.id)), _FakeDb(trainer))
    assert excinfo.value.status_code == 403


def test_valid_member_token_returns_that_member(fallback_on, consent_ok):
    member = _person("member-ok")
    assert _call(_request(create_access_token(member.id)), _FakeDb(member)) is member


@pytest.mark.parametrize(
    "token_factory",
    [
        lambda uid: "not-a-real-token",
        lambda uid: _expired_token(uid),
        lambda uid: create_access_token("member-gone"),
    ],
    ids=["garbage", "expired", "missing-user"],
)
def test_fallback_off_is_unchanged_for_bad_tokens(fallback_off, consent_ok, token_factory):
    member = _person("member-off")
    _assert_401(_request(token_factory(member.id)), _FakeDb(member))


def test_fallback_off_is_unchanged_without_a_token(fallback_off, consent_ok):
    _assert_401(_request(), _FakeDb(_person(DEMO_USER_ID)))


# ---- DB: 실제 회원 API ----


def _member(db_session, *, tv: int = 0):
    from app.models.models import User

    user_id = f"fallback3160-{uuid4().hex[:10]}"
    user = User(
        id=user_id,
        email=f"{user_id}@oncare.com",
        name="폴백",
        hashed_password="",
        role="member",
        token_version=tv,
    )
    db_session.add(user)
    db_session.commit()
    return user


def _get_me(client, token: str | None = None):
    headers = {"Authorization": f"Bearer {token}"} if token else {}
    return client.get("/v1/users/me", headers=headers)


def test_api_without_a_token_still_shows_the_demo_member(client, fallback_on):
    response = _get_me(client)
    assert response.status_code == 200, response.text
    assert response.json()["id"] == DEMO_USER_ID


def test_api_expired_token_is_401_not_the_demo_member(client, db_session, fallback_on):
    member = _member(db_session)
    response = _get_me(client, _expired_token(member.id))
    assert response.status_code == 401, response.text
    assert response.headers.get("www-authenticate") == "Bearer"


@pytest.mark.parametrize("kind", ["garbage", "wrong-signature", "previous-generation", "missing-user"])
def test_api_unusable_tokens_are_401(client, db_session, fallback_on, kind):
    if kind == "garbage":
        token = "not-a-real-token"
    elif kind == "wrong-signature":
        token = _foreign_signature_token(_member(db_session).id)
    elif kind == "previous-generation":
        token = create_access_token(_member(db_session, tv=3).id, token_version=2)
    else:
        token = create_access_token(f"fallback3160-gone-{uuid4().hex[:8]}")
    response = _get_me(client, token)
    assert response.status_code == 401, response.text


def test_api_valid_token_is_that_member(client, db_session, fallback_on):
    member = _member(db_session)
    response = _get_me(client, create_access_token(member.id))
    assert response.status_code == 200, response.text
    assert response.json()["id"] == member.id


def test_api_fallback_off_keeps_401_for_expired_and_missing_tokens(
    client, db_session, fallback_off
):
    member = _member(db_session)
    assert _get_me(client).status_code == 401
    assert _get_me(client, _expired_token(member.id)).status_code == 401
