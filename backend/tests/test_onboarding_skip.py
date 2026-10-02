"""첫 설정 건너뛰기를 계정에 남긴다 — DB 필요(로컬 skip, CI 실행). (#2855)

건너뛰기가 어디에도 남지 않아, 건너뛴 회원이 로그인·세션 복구 때마다 같은 첫
설정 폼으로 다시 끌려갔다. 앱은 `onboarded` 또는 `onboarding_skipped` 가 참이면
첫 설정으로 보내지 않는다.
"""

from __future__ import annotations

from uuid import uuid4


def _register_and_login(client) -> str:
    email = f"skip-{uuid4().hex[:8]}@oncare.com"
    password = "pw-12345!"
    r = client.post(
        "/v1/auth/register",
        json={"email": email, "password": password, "name": "건너뛴회원"},
    )
    assert r.status_code == 201, r.text
    login = client.post(
        "/v1/auth/login", data={"username": email, "password": password}
    )
    assert login.status_code == 200, login.text
    return login.json()["access_token"]


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def test_new_member_has_neither_onboarded_nor_skipped(client):
    token = _register_and_login(client)

    got = client.get("/v1/users/me/profile", headers=_auth(token))

    assert got.status_code == 200, got.text
    assert got.json()["onboarded"] is False
    assert got.json()["onboarding_skipped"] is False


def test_skip_is_remembered_on_the_account(client):
    token = _register_and_login(client)

    r = client.post("/v1/users/me/onboarding/skip", headers=_auth(token))

    assert r.status_code == 200, r.text
    assert r.json()["onboarding_skipped"] is True
    # 건너뛴 것이지 끝낸 것이 아니다.
    assert r.json()["onboarded"] is False

    # 다른 기기·다음 로그인에서 읽는 프로필에도 남아 있다.
    got = client.get("/v1/users/me/profile", headers=_auth(token))
    assert got.json()["onboarding_skipped"] is True
    assert got.json()["onboarded"] is False


def test_skip_saves_no_profile_values(client):
    token = _register_and_login(client)

    r = client.post("/v1/users/me/onboarding/skip", headers=_auth(token))

    body = r.json()
    assert body["birth_date"] == ""
    assert body["gender"] == ""
    assert body["height_cm"] is None
    assert body["weight_kg"] is None
    assert body["conditions"] == ""
    assert body["name"] == "건너뛴회원"


def test_skip_is_idempotent(client):
    token = _register_and_login(client)

    first = client.post("/v1/users/me/onboarding/skip", headers=_auth(token))
    second = client.post("/v1/users/me/onboarding/skip", headers=_auth(token))

    assert first.status_code == 200
    assert second.status_code == 200
    assert second.json()["onboarding_skipped"] is True


def test_finishing_after_skip_marks_onboarded(client):
    """건너뛴 뒤 MY 에서 첫 설정을 다시 열어 저장하면 끝낸 회원이 된다."""
    token = _register_and_login(client)
    client.post("/v1/users/me/onboarding/skip", headers=_auth(token))

    r = client.post(
        "/v1/users/me/onboarding",
        json={"height_cm": 170.0, "weight_kg": 65.0},
        headers=_auth(token),
    )

    assert r.status_code == 200, r.text
    assert r.json()["onboarded"] is True
    assert r.json()["height_cm"] == 170.0


def test_skip_requires_login(client):
    assert client.post("/v1/users/me/onboarding/skip").status_code == 401
