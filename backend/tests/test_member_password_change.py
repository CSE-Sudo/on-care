"""회원 비밀번호 변경 `POST /users/me/password`(#2824) — DB 필요(로컬 skip, CI 실행).

트레이너 경로(#2766)와 같은 규약인지 본다: 현재 비밀번호 확인, 가입과 같은 새
비밀번호 기준, 세대 증가로 다른 기기 세션 종료, 요청한 기기는 새 토큰으로 이어 쓰기.
"""
from __future__ import annotations

import uuid
from collections.abc import Iterator
from uuid import uuid4

import pytest

from app.core.config import get_settings
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


def test_other_device_sessions_end(client, monkeypatch, member_email):
    """다른 기기의 접근 토큰은 401, refresh 도 401 — 만료 안내와 함께 로그인 화면으로 간다."""
    # 프로필 조회는 개발 환경에서 무효 토큰을 데모 사용자로 받아 준다. 지난 세대 토큰도
    # 무효 토큰과 같으므로, 운영처럼 폴백을 꺼야 401 이 그대로 보인다.
    monkeypatch.setattr(get_settings(), "allow_demo_fallback", False)
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


# ---- 계정 단위 실패 잠금 (#3087) ----
#
# 트레이너 `POST /trainer/me/password`(#2913)와 같은 잠금. 접근 토큰을 손에 넣은 쪽이
# IP 를 바꿔 가며 현재 비밀번호를 맞혀 보지 못하게 사용자 id 로 센다.


def _ip(n: int) -> dict:
    return {"X-Forwarded-For": f"198.51.100.{n % 250 + 1}"}


def _change_from(client, token: str, current: str, n: int, new: str = _NEW_PW):
    """요청마다 다른 IP 로 보낸다 — IP 버킷이 아니라 계정 잠금이 막는지 본다."""
    return client.post(
        "/v1/users/me/password",
        json={"current_password": current, "new_password": new},
        headers={**_h(token), **_ip(n)},
    )


@pytest.fixture
def lock_settings(monkeypatch):
    settings = get_settings()
    monkeypatch.setattr(settings, "rate_limit_enabled", True)
    monkeypatch.setattr(settings, "rate_limit_auth_per_minute", 1000)
    monkeypatch.setattr(settings, "trusted_proxy_hops", 1)
    return settings


def _user_id(db_session, email: str) -> str:
    return db_session.query(models.User).filter(models.User.email == email).one().id


def _fail_until_locked(client, token: str, settings) -> None:
    for n in range(settings.password_change_max_failures):
        r = _change_from(client, token, "not-my-pw-1", n)
        assert r.status_code == 400, r.text


def test_repeated_wrong_current_password_locks_across_ips(
    client, db_session, member_email, lock_settings
):
    """IP 를 바꿔도 정해진 횟수만큼 틀리면 맞는 비밀번호도 429 — 비밀번호는 그대로다."""
    token = _login(client, member_email, _OLD_PW)["access_token"]
    _fail_until_locked(client, token, lock_settings)

    blocked = _change_from(client, token, _OLD_PW, 99)
    assert blocked.status_code == 429, blocked.text
    assert "Retry-After" in blocked.headers
    # 잠긴 동안에는 비밀번호를 확인하지 않는다 — 세대도 그대로라 이 기기는 이어 쓴다.
    assert client.get("/v1/users/me/profile", headers=_h(token)).status_code == 200
    _login(client, member_email, _OLD_PW)


def test_lock_lifts_after_the_window(client, member_email, lock_settings, monkeypatch):
    import app.core.rate_limit as rate_limit_module

    now = [1_000_000.0]
    monkeypatch.setattr(rate_limit_module.time, "monotonic", lambda: now[0])
    rate_limit_module.limiter.clear()
    token = _login(client, member_email, _OLD_PW)["access_token"]
    _fail_until_locked(client, token, lock_settings)
    assert _change_from(client, token, _OLD_PW, 50).status_code == 429

    now[0] += lock_settings.login_lockout_seconds + 1

    assert _change_from(client, token, _OLD_PW, 51).status_code == 200


def test_success_clears_earlier_failures(client, db_session, member_email, lock_settings):
    from app.core.rate_limit import limiter, password_change_fail_key

    token = _login(client, member_email, _OLD_PW)["access_token"]
    limit = lock_settings.password_change_max_failures
    for n in range(limit - 1):
        _change_from(client, token, "not-my-pw-1", n)
    ok = _change_from(client, token, _OLD_PW, 60)
    assert ok.status_code == 200, ok.text

    # 트레이너와 같은 키 규칙이다 — 성공하면 기록이 지워진다.
    key = password_change_fail_key(_user_id(db_session, member_email))
    window = float(lock_settings.login_lockout_seconds)
    assert limiter.retry_after(key, 1, window) is None
    # 다음 실패는 1부터 센다 — 한도 직전까지 다시 틀려도 잠기지 않는다.
    fresh = ok.json()["access_token"]
    for n in range(limit - 1):
        assert _change_from(client, fresh, "not-my-pw-1", 70 + n).status_code == 400
    assert _change_from(client, fresh, _NEW_PW, 80, new=_OLD_PW).status_code == 200


def test_lock_is_per_member(client, db_session, member_email, lock_settings):
    token = _login(client, member_email, _OLD_PW)["access_token"]
    _fail_until_locked(client, token, lock_settings)
    assert _change_from(client, token, "not-my-pw-1", 90).status_code == 429

    other = f"mpw-other-{uuid4().hex[:8]}@oncare.com"
    res = client.post(
        "/v1/auth/register",
        json={"email": other, "password": _OLD_PW, "name": "다른회원"},
    )
    assert res.status_code == 201, res.text
    try:
        other_token = _login(client, other, _OLD_PW)["access_token"]
        assert _change_from(client, other_token, "not-my-pw-1", 91).status_code == 400
    finally:
        db_session.expire_all()
        row = db_session.get(models.User, res.json()["id"])
        if row is not None:
            db_session.delete(row)
            db_session.commit()


def test_wrong_current_password_audit_has_reason(client, db_session, member_email):
    token = _login(client, member_email, _OLD_PW)["access_token"]
    _change(client, token, current="not-my-pw-1")
    row = (
        db_session.query(models.AuditLog)
        .filter(
            models.AuditLog.event == "auth.password_change",
            models.AuditLog.user_id == _user_id(db_session, member_email),
        )
        .one()
    )
    assert row.success is False
    # 입력한 비밀번호가 아니라 사유만 남는다 — 트레이너와 같은 값이다.
    assert row.detail == "current_password_mismatch"


def test_social_account_conflict_is_not_counted(client, social_member, lock_settings):
    from app.core.rate_limit import limiter, password_change_fail_key

    token = auth_tokens.issue_token_pair(social_member).access_token
    for n in range(lock_settings.password_change_max_failures + 1):
        assert _change_from(client, token, "anything-1", n).status_code == 409
    key = password_change_fail_key(social_member.id)
    assert limiter.retry_after(key, 1, float(lock_settings.login_lockout_seconds)) is None
