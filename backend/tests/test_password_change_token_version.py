"""비밀번호 변경 시 다른 기기 토큰 폐기(#2766) — DB 필요(로컬 skip, CI 실행).

비밀번호를 바꾸는 이유는 대개 "누가 내 계정을 쓰고 있을지 모른다"는 의심이다.
그런데 바꾼 뒤에도 다른 기기의 접근 토큰(기본 60분)과 refresh 토큰(30일)이 살아
있으면 그 목적을 이루지 못한다. 여기서 확인하는 것은 **변경 전에 발급된 토큰이
모두 끊기고, 바꾼 기기만 응답의 새 토큰으로 이어 쓰는가**다.
"""
from __future__ import annotations

from collections.abc import Iterator
from uuid import uuid4

import pytest

from app.models import models

_OLD_PW = "pw!12345"
_NEW_PW = "pw!67890"


def _h(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _login(client, email: str, password: str) -> dict:
    res = client.post("/v1/auth/login", data={"username": email, "password": password})
    assert res.status_code == 200, res.text
    return res.json()


@pytest.fixture
def trainer_email(client, db_session) -> Iterator[str]:
    """테스트마다 새 트레이너를 만들고 끝나면 지운다 — 시드 계정 비밀번호를
    바꾸면 다른 테스트 파일이 그 계정으로 로그인하다 줄줄이 깨진다."""
    email = f"pwtv-{uuid4().hex[:8]}@oncare.com"
    res = client.post(
        "/v1/auth/trainer/register",
        json={"email": email, "password": _OLD_PW, "name": f"세대 {uuid4().hex[:4]}"},
    )
    assert res.status_code in (200, 201), res.text
    trainer_id = res.json()["id"]
    yield email
    db_session.expire_all()
    row = db_session.get(models.User, trainer_id)
    if row is not None:
        from app.services import trainer_service

        trainer_service.delete_trainer_account(db_session, row)


def _change(client, access_token: str):
    return client.post(
        "/v1/trainer/me/password",
        json={"current_password": _OLD_PW, "new_password": _NEW_PW},
        headers=_h(access_token),
    )


def test_change_returns_a_fresh_token_pair(client, trainer_email):
    """바꾼 기기는 로그아웃되지 않는다 — 응답의 새 토큰으로 바로 이어 쓴다."""
    pc1 = _login(client, trainer_email, _OLD_PW)

    res = _change(client, pc1["access_token"])
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["status"] == "changed"
    assert body["token_type"] == "bearer"
    assert body["access_token"] and body["access_token"] != pc1["access_token"]
    assert body["refresh_token"] and body["refresh_token"] != pc1["refresh_token"]

    me = client.get("/v1/trainer/me", headers=_h(body["access_token"]))
    assert me.status_code == 200, me.text
    rotated = client.post("/v1/auth/refresh", json={"refresh_token": body["refresh_token"]})
    assert rotated.status_code == 200, rotated.text
    assert (
        client.get("/v1/trainer/me", headers=_h(rotated.json()["access_token"]))
    ).status_code == 200


def test_other_device_access_token_is_rejected(client, trainer_email):
    """다른 기기에 남은 접근 토큰은 다음 요청에서 401 이다."""
    pc1 = _login(client, trainer_email, _OLD_PW)
    pc2 = _login(client, trainer_email, _OLD_PW)
    assert (client.get("/v1/trainer/me", headers=_h(pc2["access_token"]))).status_code == 200

    assert _change(client, pc1["access_token"]).status_code == 200

    denied = client.get("/v1/trainer/me", headers=_h(pc2["access_token"]))
    assert denied.status_code == 401


def test_requesting_device_old_access_token_is_rejected_too(client, trainer_email):
    """요청에 쓴 토큰도 옛 세대다 — 응답의 새 토큰으로 갈아 끼워야 한다."""
    pc1 = _login(client, trainer_email, _OLD_PW)
    assert _change(client, pc1["access_token"]).status_code == 200

    assert (client.get("/v1/trainer/me", headers=_h(pc1["access_token"]))).status_code == 401


def test_other_device_refresh_token_cannot_rotate(client, trainer_email):
    """다른 기기의 refresh 토큰으로는 회전할 수 없다 — 30일 동안 세션을 되살리면
    비밀번호를 바꾼 의미가 없다."""
    pc1 = _login(client, trainer_email, _OLD_PW)
    pc2 = _login(client, trainer_email, _OLD_PW)

    assert _change(client, pc1["access_token"]).status_code == 200

    denied = client.post("/v1/auth/refresh", json={"refresh_token": pc2["refresh_token"]})
    assert denied.status_code == 401
    # 두 번째도 같다 — 거부한 토큰은 폐기 표에도 적힌다.
    again = client.post("/v1/auth/refresh", json={"refresh_token": pc2["refresh_token"]})
    assert again.status_code == 401


def test_stale_refresh_is_audited(client, db_session, trainer_email):
    """지난 세대 refresh 시도는 감사 로그에 남는다 — 다른 기기에서 누가 계속
    쓰려 한 흔적을 나중에 볼 수 있어야 한다."""
    pc1 = _login(client, trainer_email, _OLD_PW)
    pc2 = _login(client, trainer_email, _OLD_PW)
    assert _change(client, pc1["access_token"]).status_code == 200
    client.post("/v1/auth/refresh", json={"refresh_token": pc2["refresh_token"]})

    trainer_id = (
        client.get("/v1/trainer/me", headers=_h(_login(client, trainer_email, _NEW_PW)["access_token"]))
    ).json()["id"]
    logged = (
        db_session.query(models.AuditLog)
        .filter(
            models.AuditLog.event == "auth.refresh_stale",
            models.AuditLog.user_id == trainer_id,
        )
        .all()
    )
    assert len(logged) == 1
    assert logged[0].success is False


def test_login_after_change_issues_current_generation(client, trainer_email):
    """변경 뒤 새 비밀번호로 로그인한 기기는 정상이다 — 세대를 올린 뒤 발급한
    토큰까지 거부하면 아무도 다시 들어올 수 없다."""
    pc1 = _login(client, trainer_email, _OLD_PW)
    assert _change(client, pc1["access_token"]).status_code == 200

    pc2 = _login(client, trainer_email, _NEW_PW)
    assert (client.get("/v1/trainer/me", headers=_h(pc2["access_token"]))).status_code == 200
    assert (
        client.post("/v1/auth/refresh", json={"refresh_token": pc2["refresh_token"]})
    ).status_code == 200


def test_failed_change_keeps_existing_tokens(client, trainer_email):
    """현재 비밀번호가 틀려 변경이 안 됐으면 아무 세션도 끊기지 않는다."""
    pc1 = _login(client, trainer_email, _OLD_PW)
    pc2 = _login(client, trainer_email, _OLD_PW)

    res = client.post(
        "/v1/trainer/me/password",
        json={"current_password": "not-the-password", "new_password": _NEW_PW},
        headers=_h(pc1["access_token"]),
    )
    assert res.status_code == 400

    assert (client.get("/v1/trainer/me", headers=_h(pc2["access_token"]))).status_code == 200
    assert (
        client.post("/v1/auth/refresh", json={"refresh_token": pc2["refresh_token"]})
    ).status_code == 200


def test_change_does_not_touch_other_accounts(client, trainer_email):
    """세대는 계정마다 따로다 — 한 트레이너의 변경이 다른 계정을 끊으면 안 된다."""
    other_email = f"pwtv-other-{uuid4().hex[:8]}@oncare.com"
    created = client.post(
        "/v1/auth/register",
        json={"email": other_email, "password": _OLD_PW, "name": "다른 계정"},
    )
    assert created.status_code == 201, created.text
    other = _login(client, other_email, _OLD_PW)

    pc1 = _login(client, trainer_email, _OLD_PW)
    assert _change(client, pc1["access_token"]).status_code == 200

    me = client.get("/v1/users/me", headers=_h(other["access_token"]))
    assert me.status_code == 200
    assert me.json()["id"] == created.json()["id"]
    assert (
        client.post("/v1/auth/refresh", json={"refresh_token": other["refresh_token"]})
    ).status_code == 200


def test_member_tokens_follow_the_same_generation_rule(client, db_session):
    """세대 비교는 회원·트레이너 공통이다 — 이후 회원 비밀번호 변경·재설정이 생기면
    세대만 올리면 된다. 회원 토큰도 세대가 다르면 그 사용자로 통하지 않는다."""
    from app.services import auth_tokens

    email = f"pwtv-member-{uuid4().hex[:8]}@oncare.com"
    created = client.post(
        "/v1/auth/register",
        json={"email": email, "password": _OLD_PW, "name": "회원"},
    )
    assert created.status_code == 201, created.text
    member_id = created.json()["id"]
    tokens = _login(client, email, _OLD_PW)

    row = db_session.get(models.User, member_id)
    auth_tokens.bump_version(row)
    db_session.commit()

    # 읽기 API 는 데모 폴백이 켜진 환경에서 데모 사용자로 떨어질 수는 있어도,
    # 옛 토큰의 주인으로는 통하지 않는다(운영은 폴백 없이 401).
    me = client.get("/v1/users/me", headers=_h(tokens["access_token"]))
    assert me.status_code in (200, 401)
    if me.status_code == 200:
        assert me.json()["id"] != member_id
    assert (
        client.post("/v1/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    ).status_code == 401
