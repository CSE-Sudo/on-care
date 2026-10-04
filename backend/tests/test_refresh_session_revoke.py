"""refresh 토큰 재사용 때 세션 전체 폐기 · 세션 절대 수명 — DB 필요(로컬 skip, CI 실행).

재사용 감지(#966)는 다시 온 토큰 한 장만 거부해, 탈취한 쪽이 먼저 회전해 받은 다음
토큰은 그대로 살았다. 또 회전마다 수명을 새로 받아 로그인 없이 세션을 끝없이 이어 갈
수 있었다. 여기서 확인하는 것은 (1) 유예를 넘긴 재사용이 그 세션의 토큰을 모두 끊고,
(2) 다른 기기와 정상적인 동시 갱신은 끊기지 않으며, (3) 최초 로그인으로부터 절대
수명이 지나면 회전되지 않는가다(#3086).
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from uuid import uuid4

import jwt

from app.core import security
from app.core.security import AUTH_TIME_CLAIM, SESSION_ID_CLAIM, decode_refresh_claims
from app.models.models import AuditLog, RevokedRefreshToken, RevokedSession

PASSWORD = "pw-12345!"


def _sign_up(client) -> tuple[str, str]:
    """새 계정을 만들고 (email, user_id) 를 돌려준다."""
    email = f"session-{uuid4().hex[:8]}@oncare.com"
    created = client.post(
        "/v1/auth/register",
        json={"email": email, "password": PASSWORD, "name": "세션"},
    )
    assert created.status_code == 201, created.text
    return email, created.json()["id"]


def _login(client, email: str) -> str:
    """로그인해 refresh 토큰을 돌려준다 — 로그인마다 새 세션이다."""
    login = client.post("/v1/auth/login", data={"username": email, "password": PASSWORD})
    assert login.status_code == 200, login.text
    return login.json()["refresh_token"]


def _refresh(client, token: str):
    return client.post("/v1/auth/refresh", json={"refresh_token": token})


def _payload(token: str) -> dict:
    return jwt.decode(
        token, security.settings.jwt_secret, algorithms=[security.settings.jwt_algorithm]
    )


def _age_revocation(db_session, token: str, *, seconds: int = 120) -> None:
    """회전으로 폐기된 기록을 유예 밖으로 밀어 둔다."""
    entry = db_session.get(RevokedRefreshToken, decode_refresh_claims(token).jti)
    assert entry is not None
    entry.revoked_at = datetime.now(timezone.utc) - timedelta(seconds=seconds)
    db_session.commit()


def _reuse_audits(db_session, user_id: str) -> list[AuditLog]:
    db_session.expire_all()
    return (
        db_session.query(AuditLog)
        .filter(AuditLog.event == "auth.refresh_reuse", AuditLog.user_id == user_id)
        .all()
    )


def test_login_and_rotation_carry_session(client):
    """로그인은 새 세션을 열고, 회전은 세션 이름·최초 인증 시각을 그대로 잇는다."""
    email, _ = _sign_up(client)
    r1 = _login(client, email)
    first = _payload(r1)
    assert first[SESSION_ID_CLAIM]
    assert isinstance(first[AUTH_TIME_CLAIM], int)

    rotated = _refresh(client, r1)
    assert rotated.status_code == 200, rotated.text
    second = _payload(rotated.json()["refresh_token"])
    assert second[SESSION_ID_CLAIM] == first[SESSION_ID_CLAIM]
    assert second[AUTH_TIME_CLAIM] == first[AUTH_TIME_CLAIM]

    other = _payload(_login(client, email))
    assert other[SESSION_ID_CLAIM] != first[SESSION_ID_CLAIM]


def test_reuse_after_grace_revokes_whole_session(client, db_session):
    """탈취한 쪽이 먼저 회전해도, 유예를 넘긴 재사용이 오면 이어진 토큰까지 끊긴다."""
    email, user_id = _sign_up(client)
    r1 = _login(client, email)
    rotated = _refresh(client, r1)
    assert rotated.status_code == 200, rotated.text
    r2 = rotated.json()["refresh_token"]
    _age_revocation(db_session, r1)

    assert _refresh(client, r1).status_code == 401
    assert _refresh(client, r2).status_code == 401

    sid = decode_refresh_claims(r1).session_id
    db_session.expire_all()
    assert db_session.get(RevokedSession, sid) is not None
    logged = _reuse_audits(db_session, user_id)
    assert len(logged) == 1
    assert logged[0].detail == f"session revoked: {sid}"
    revoked_audits = (
        db_session.query(AuditLog)
        .filter(
            AuditLog.event == "auth.refresh_session_revoked",
            AuditLog.user_id == user_id,
        )
        .count()
    )
    assert revoked_audits == 1


def test_reuse_within_grace_keeps_session(client, db_session):
    """정상적인 동시 갱신(유예 안)은 그 요청만 거부되고 세션은 이어진다."""
    email, user_id = _sign_up(client)
    r1 = _login(client, email)
    rotated = _refresh(client, r1)
    assert rotated.status_code == 200, rotated.text
    r2 = rotated.json()["refresh_token"]

    assert _refresh(client, r1).status_code == 401
    again = _refresh(client, r2)
    assert again.status_code == 200, again.text

    db_session.expire_all()
    assert db_session.get(RevokedSession, decode_refresh_claims(r1).session_id) is None
    assert [a.detail for a in _reuse_audits(db_session, user_id)] == ["within grace"]


def test_other_device_session_survives(client, db_session):
    """같은 계정의 다른 로그인(다른 기기)은 한 세션이 끊겨도 영향이 없다."""
    email, _ = _sign_up(client)
    phone = _login(client, email)
    laptop = _login(client, email)

    rotated = _refresh(client, phone)
    assert rotated.status_code == 200, rotated.text
    _age_revocation(db_session, phone)
    assert _refresh(client, phone).status_code == 401
    assert _refresh(client, rotated.json()["refresh_token"]).status_code == 401

    assert _refresh(client, laptop).status_code == 200


def test_logged_out_token_reuse_does_not_revoke_session(client, db_session):
    """로그아웃된 토큰의 재사용은 이미 끊긴 세션이라 세션을 따로 폐기하지 않는다."""
    email, user_id = _sign_up(client)
    r1 = _login(client, email)
    assert client.post("/v1/auth/logout", json={"refresh_token": r1}).status_code == 204
    _age_revocation(db_session, r1)

    assert _refresh(client, r1).status_code == 401

    db_session.expire_all()
    assert db_session.get(RevokedSession, decode_refresh_claims(r1).session_id) is None
    assert [a.detail for a in _reuse_audits(db_session, user_id)] == [
        "already revoked: logout"
    ]


def _session_token(user_id: str, *, auth_time: datetime) -> str:
    """세션 값을 직접 넣은 refresh 토큰. 만료는 남겨 두고 최초 인증 시각만 옮긴다."""
    return security._encode(
        user_id,
        "refresh",
        timedelta(days=1),
        jti=uuid4().hex,
        extra={
            SESSION_ID_CLAIM: uuid4().hex,
            AUTH_TIME_CLAIM: int(auth_time.timestamp()),
        },
    )


def test_session_past_absolute_lifetime_is_not_rotated(client, db_session):
    """최초 로그인으로부터 절대 수명이 지난 세션은 회전되지 않는다."""
    _, user_id = _sign_up(client)
    max_days = security.settings.session_max_days
    old = _session_token(
        user_id, auth_time=datetime.now(timezone.utc) - timedelta(days=max_days, hours=1)
    )

    assert _refresh(client, old).status_code == 401
    db_session.expire_all()
    expired = (
        db_session.query(AuditLog)
        .filter(
            AuditLog.event == "auth.refresh_session_expired",
            AuditLog.user_id == user_id,
        )
        .count()
    )
    assert expired == 1


def test_session_within_lifetime_rotates_and_caps_expiry(client):
    """상한 안의 세션은 회전되고, 최초 인증 시각은 바뀌지 않으며 만료가 상한을 넘지 않는다."""
    _, user_id = _sign_up(client)
    max_days = security.settings.session_max_days
    started = datetime.now(timezone.utc) - timedelta(days=max_days - 1)
    token = _session_token(user_id, auth_time=started)

    rotated = _refresh(client, token)
    assert rotated.status_code == 200, rotated.text
    payload = _payload(rotated.json()["refresh_token"])
    assert payload[AUTH_TIME_CLAIM] == int(started.timestamp())
    assert payload[SESSION_ID_CLAIM] == _payload(token)[SESSION_ID_CLAIM]
    cap = int(started.timestamp()) + max_days * 86400
    assert payload["exp"] <= cap + 1


def test_legacy_token_without_session_gets_new_session(client):
    """세션 값이 없는 옛 토큰은 끊기지 않고, 첫 회전에서 새 세션을 받는다."""
    _, user_id = _sign_up(client)
    legacy = security._encode(user_id, "refresh", timedelta(days=1), jti=uuid4().hex)
    assert SESSION_ID_CLAIM not in _payload(legacy)

    before = int(datetime.now(timezone.utc).timestamp())
    rotated = _refresh(client, legacy)
    assert rotated.status_code == 200, rotated.text
    payload = _payload(rotated.json()["refresh_token"])
    assert payload[SESSION_ID_CLAIM]
    assert payload[AUTH_TIME_CLAIM] >= before - 1
