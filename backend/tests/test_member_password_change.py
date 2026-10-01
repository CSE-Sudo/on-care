"""회원 비밀번호 변경 `POST /users/me/password`(#2824) — DB 필요(로컬 skip, CI 실행).

트레이너 경로(#2766)와 같은 규약인지 본다: 현재 비밀번호 확인, 가입과 같은 새
비밀번호 기준, 세대 증가로 다른 기기 세션 종료, 요청한 기기는 새 토큰으로 이어 쓰기.
"""
from __future__ import annotations

import uuid
from collections.abc import Iterator
from uuid import uuid4

import pytest

from app.models import models
from app.services import auth_tokens

_OLD_PW = "member-pw-123"
_NEW_PW = "member-pw-456"


def _h(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _login(client, email: str, password: str) -> dict:
    res = client.post("/v1/auth/login", data={"username": email, "password": password})
    assert res.status_code == 200, res.text
    return res.json()


def _change(client, token: str, current: str = _OLD_PW, new: str = _NEW_PW):
    return client.post(
        "/v1/users/me/password",
        json={"current_password": current, "new_password": new},
        headers=_h(token),
    )


@pytest.fixture
def member_email(client, db_session) -> Iterator[str]:
    email = f"mpw-{uuid4().hex[:8]}@oncare.com"
    res = client.post(
        "/v1/auth/register",
        json={"email": email, "password": _OLD_PW, "name": "변경회원"},
    )
    assert res.status_code == 201, res.text
    user_id = res.json()["id"]
    yield email
    db_session.expire_all()
    row = db_session.get(models.User, user_id)
    if row is not None:
        db_session.delete(row)
        db_session.commit()


def test_change_returns_fresh_pair_and_keeps_this_device(client, member_email):
    phone = _login(client, member_email, _OLD_PW)
    res = _change(client, phone["access_token"])
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["status"] == "changed"
    assert body["token_type"] == "bearer"
    assert body["access_token"] != phone["access_token"]
    assert body["refresh_token"] and body["refresh_token"] != phone["refresh_token"]
    assert client.get("/v1/users/me/profile", headers=_h(body["access_token"])).status_code == 200
    rotated = client.post("/v1/auth/refresh", json={"refresh_token": body["refresh_token"]})
    assert rotated.status_code == 200, rotated.text


def test_new_password_logs_in_and_old_does_not(client, member_email):
    phone = _login(client, member_email, _OLD_PW)
    assert _change(client, phone["access_token"]).status_code == 200
    assert (
        client.post("/v1/auth/login", data={"username": member_email, "password": _OLD_PW})
    ).status_code == 401
    _login(client, member_email, _NEW_PW)


def test_other_device_sessions_end(client, member_email):
    """다른 기기의 접근 토큰은 401, refresh 도 401 — 만료 안내와 함께 로그인 화면으로 간다."""
    phone = _login(client, member_email, _OLD_PW)
    tablet = _login(client, member_email, _OLD_PW)
    assert _change(client, phone["access_token"]).status_code == 200

    assert client.get("/v1/users/me/profile", headers=_h(tablet["access_token"])).status_code == 401
    assert (
        client.post("/v1/auth/refresh", json={"refresh_token": tablet["refresh_token"]})
    ).status_code == 401
    # 요청에 쓴 옛 토큰도 옛 세대다.
    assert client.get("/v1/users/me/profile", headers=_h(phone["access_token"])).status_code == 401


def test_wrong_current_password_is_400_and_keeps_generation(client, db_session, member_email):
    phone = _login(client, member_email, _OLD_PW)
    res = _change(client, phone["access_token"], current="not-my-pw-1")
    # 401 이 아니다 — 토큰은 유효하므로 앱이 로그아웃으로 오인하면 안 된다.
    assert res.status_code == 400
    assert client.get("/v1/users/me/profile", headers=_h(phone["access_token"])).status_code == 200
    _login(client, member_email, _OLD_PW)


def test_wrong_current_password_is_audited(client, db_session, member_email):
    phone = _login(client, member_email, _OLD_PW)
    _change(client, phone["access_token"], current="not-my-pw-1")
    user = db_session.query(models.User).filter(models.User.email == member_email).one()
    rows = (
        db_session.query(models.AuditLog)
        .filter(
            models.AuditLog.event == "auth.password_change",
            models.AuditLog.user_id == user.id,
        )
        .all()
    )
    assert [r.success for r in rows] == [False]


def test_same_password_is_rejected(client, member_email):
    phone = _login(client, member_email, _OLD_PW)
    assert _change(client, phone["access_token"], new=_OLD_PW).status_code == 400


@pytest.mark.parametrize(
    ("new", "code"),
    [("", "password_empty"), ("12345678", "password_weak"), ("a1" * 40, "password_too_long")],
)
def test_new_password_policy(client, member_email, new, code):
    phone = _login(client, member_email, _OLD_PW)
    res = _change(client, phone["access_token"], new=new)
    assert res.status_code == 422
    assert res.json()["detail"][0]["type"] == code
    # 막힌 요청은 세대를 올리지 않는다.
    assert client.get("/v1/users/me/profile", headers=_h(phone["access_token"])).status_code == 200


def test_requires_token(client):
    res = client.post(
        "/v1/users/me/password",
        json={"current_password": _OLD_PW, "new_password": _NEW_PW},
    )
    assert res.status_code == 401


def test_trainer_token_is_forbidden(client):
    email = f"mpw-tr-{uuid4().hex[:8]}@oncare.com"
    assert client.post(
        "/v1/auth/trainer/register",
        json={"email": email, "password": _OLD_PW, "name": "트레이너"},
    ).status_code in (200, 201)
    tr = _login(client, email, _OLD_PW)
    assert _change(client, tr["access_token"]).status_code == 403


@pytest.fixture
def social_member(client, db_session) -> Iterator[models.User]:
    user = models.User(
        id=f"user-{uuid.uuid4().hex[:12]}",
        email=f"kakao_{uuid4().hex[:8]}@social.oncare",
        name="소셜회원",
        hashed_password="",
    )
    db_session.add(user)
    db_session.commit()
    yield user
    db_session.expire_all()
    row = db_session.get(models.User, user.id)
    if row is not None:
        db_session.delete(row)
        db_session.commit()


def test_social_account_has_no_password_to_change(client, social_member):
    token = auth_tokens.issue_token_pair(social_member).access_token
    res = _change(client, token, current="anything-1")
    assert res.status_code == 409


def test_profile_reports_has_password(client, member_email, social_member):
    phone = _login(client, member_email, _OLD_PW)
    mine = client.get("/v1/users/me/profile", headers=_h(phone["access_token"])).json()
    assert mine["has_password"] is True

    social_token = auth_tokens.issue_token_pair(social_member).access_token
    social = client.get("/v1/users/me/profile", headers=_h(social_token)).json()
    assert social["has_password"] is False
