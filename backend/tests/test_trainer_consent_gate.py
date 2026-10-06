"""필수 동의가 끝나지 않은 트레이너는 트레이너 API 를 쓰지 못한다. (#3155)

트레이너는 회원의 식단·운동·신체 정보·건강상태를 열람하는 쪽이다. 트레이너 웹은
로그인 응답의 `consent_required` 로 동의 화면을 띄웠지만, 서버는 트레이너의 동의를
보지 않아 화면을 거치지 않는 경로(옛 빌드·직접 호출·관리자가 만든 계정)로는 동의
없이 트레이너 API 를 그대로 썼다. 이제 `RequireTrainer` 가 회원과 같은 규칙으로
역할별 필수 항목(약관·개인정보·만 14세)을 확인하고, 남은 항목이 있으면 403
`{"code": "consent_required", "missing": [...]}` 를 준다.

- 앞부분은 DB 없이 라우트 표만 본다.
- 뒷부분은 `client` 픽스처를 쓰므로 DB 가 있는 환경(CI)에서 돈다. 동의하지 않은
  계정을 만들려고 `without_default_consent` 를 쓴다(conftest 참고).
"""
from __future__ import annotations

from uuid import uuid4

import pytest
from sqlalchemy import select

from app.api.deps import CONSENT_EXEMPT_ROUTES, require_trainer
from app.core import clock
from app.models.models import User, UserConsent
from app.services import signup_consent
from tests.route_helpers import api_routes

PASSWORD = "trainer-gate-pw-1234"
TRAINER_REQUIRED = ["age14", "privacy", "terms"]


def _calls(dependant) -> set:
    found = set()
    stack = list(dependant.dependencies)
    while stack:
        dep = stack.pop()
        if dep.call is not None:
            found.add(dep.call)
        stack.extend(dep.dependencies)
    return found


def _trainer_routes() -> list:
    from app.main import app

    return [r for r in api_routes(app) if require_trainer in _calls(r.dependant)]


# ---- 라우트 표 (DB 불필요) ----


def test_trainer_requirements_exclude_health():
    assert sorted(signup_consent.required_for("trainer")) == TRAINER_REQUIRED


def test_only_profile_read_and_withdraw_are_exempt_for_trainers():
    """트레이너 라우트 중 동의 없이 열리는 것은 프로필 읽기와 탈퇴뿐이다."""
    exempt = sorted(
        (method, route.path)
        for route in _trainer_routes()
        for method in route.methods
        if (method, route.path.removeprefix("/v1")) in CONSENT_EXEMPT_ROUTES
    )
    assert exempt == [("DELETE", "/v1/trainer/me"), ("GET", "/v1/trainer/me")]


@pytest.mark.parametrize(
    ("method", "path"),
    [
        ("GET", "/trainer/clients"),
        ("PUT", "/trainer/me"),
        ("GET", "/trainer/me/settings"),
        ("POST", "/trainer/me/password"),
    ],
)
def test_trainer_data_routes_are_not_exempt(method, path):
    assert (method, path) not in CONSENT_EXEMPT_ROUTES


def test_trainer_routes_are_mounted_behind_the_trainer_dependency():
    """`/trainer/*` 라우트가 하나도 빠짐없이 트레이너 의존성을 거친다."""
    from app.main import app

    missing = [
        f"{sorted(r.methods)} {r.path}"
        for r in api_routes(app)
        if r.path.startswith("/v1/trainer/") and require_trainer not in _calls(r.dependant)
    ]
    assert missing == []


# ---- 엔드포인트 (DB) ----


def _auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _register_trainer(client, consents: list[str] | None = None) -> tuple[str, str, dict]:
    """트레이너로 가입하고 로그인한다. (id, 이메일, 로그인 응답)."""
    email = f"tgate-{uuid4().hex[:10]}@oncare.com"
    body: dict = {"email": email, "password": PASSWORD, "name": "트레이너"}
    if consents is not None:
        body["consents"] = consents
    r = client.post("/v1/auth/trainer/register", json=body)
    assert r.status_code == 201, r.text
    login = client.post("/v1/auth/login", data={"username": email, "password": PASSWORD})
    assert login.status_code == 200, login.text
    return r.json()["id"], email, login.json()


def _consent(client, token: str) -> None:
    r = client.post(
        "/v1/users/me/consents",
        json={"consents": TRAINER_REQUIRED},
        headers=_auth(token),
    )
    assert r.status_code == 200, r.text
    assert r.json()["consent_required"] is False


def _assert_consent_required(r, missing=TRAINER_REQUIRED) -> None:
    assert r.status_code == 403, r.text
    assert r.json()["detail"] == {"code": "consent_required", "missing": list(missing)}


def _call_trainer_routes(client, token: str) -> list:
    h = _auth(token)
    return [
        client.get("/v1/trainer/clients", headers=h),
        client.get("/v1/trainer/me/settings", headers=h),
        client.get("/v1/trainer/reservation-slots", headers=h),
        client.get("/v1/trainer/notifications", headers=h),
    ]


def test_trainer_without_consent_is_blocked(client, without_default_consent):
    _, _, login = _register_trainer(client)
    assert login["consent_required"] is True

    for r in _call_trainer_routes(client, login["access_token"]):
        _assert_consent_required(r)


def test_blocked_trainer_sees_only_missing_items(client, db_session, without_default_consent):
    """일부만 남긴 옛 계정에는 빠진 항목만 알린다."""
    user_id, _, login = _register_trainer(client)
    signup_consent.record(db_session, user_id, ["terms"])
    db_session.commit()

    _assert_consent_required(
        client.get("/v1/trainer/clients", headers=_auth(login["access_token"])),
        missing=["age14", "privacy"],
    )


def test_profile_read_and_consent_routes_stay_open(client, without_default_consent):
    """로그인·세션 복구가 읽는 프로필과 동의 저장·인증 경로는 동의 없이 열린다."""
    _, email, login = _register_trainer(client)
    token = login["access_token"]

    me = client.get("/v1/trainer/me", headers=_auth(token))
    assert me.status_code == 200, me.text
    assert me.json()["email"] == email

    refreshed = client.post("/v1/auth/refresh", json={"refresh_token": login["refresh_token"]})
    assert refreshed.status_code == 200, refreshed.text

    _consent(client, token)

    logout = client.post("/v1/auth/logout", json={"refresh_token": login["refresh_token"]})
    assert logout.status_code == 204, logout.text


def test_trainer_without_consent_can_still_withdraw(client, db_session, without_default_consent):
    user_id, _, login = _register_trainer(client)

    r = client.request(
        "DELETE",
        "/v1/trainer/me",
        json={"current_password": PASSWORD},
        headers=_auth(login["access_token"]),
    )

    assert r.status_code == 200, r.text
    db_session.expire_all()
    assert db_session.get(User, user_id) is None


def test_trainer_without_consent_cannot_download_chat_attachments(
    client, without_default_consent
):
    """회원·트레이너 공용 첨부 경로도 트레이너 필수 동의를 본다(#3239).

    파일을 찾기 전에 막으므로 없는 file id 에도 404 가 아니라 403 이다 — 동의가
    남은 계정에 첨부가 있는지 드러나지 않는다. 동의하면 평소처럼 404 다.
    """
    _, _, login = _register_trainer(client)
    token = login["access_token"]
    path = f"/v1/chat/attachments/missing-{uuid4().hex}"

    _assert_consent_required(client.get(path, headers=_auth(token)))

    _consent(client, token)
    r = client.get(path, headers=_auth(token))
    assert r.status_code == 404, r.text


def test_trainer_routes_open_after_consent(client, without_default_consent):
    _, _, login = _register_trainer(client)
    token = login["access_token"]

    _consent(client, token)

    for r in _call_trainer_routes(client, token):
        assert r.status_code == 200, r.text


def test_trainer_registered_with_consents_is_not_blocked(client, without_default_consent):
    _, _, login = _register_trainer(client, consents=TRAINER_REQUIRED)
    assert login["consent_required"] is False

    got = client.get("/v1/trainer/clients", headers=_auth(login["access_token"]))

    assert got.status_code == 200, got.text


def test_document_version_bump_blocks_trainer_until_reconsent(client, monkeypatch):
    """처리방침 버전이 오르면 옛 버전에만 동의한 트레이너도 다시 동의할 때까지 막힌다."""
    _, _, login = _register_trainer(client, consents=TRAINER_REQUIRED)
    token = login["access_token"]
    assert client.get("/v1/trainer/clients", headers=_auth(token)).status_code == 200

    monkeypatch.setitem(signup_consent.CURRENT_VERSIONS, "privacy", "2099-01-01")

    _assert_consent_required(
        client.get("/v1/trainer/clients", headers=_auth(token)), missing=["privacy"]
    )
    # 프로필 읽기는 열려 있어 트레이너 웹이 로그인 상태를 지킨 채 동의 화면으로 간다.
    assert client.get("/v1/trainer/me", headers=_auth(token)).status_code == 200

    _consent(client, token)
    assert client.get("/v1/trainer/clients", headers=_auth(token)).status_code == 200


def test_revoked_trainer_consent_blocks(client, db_session):
    user_id, _, login = _register_trainer(client, consents=TRAINER_REQUIRED)

    row = db_session.scalar(
        select(UserConsent).where(UserConsent.user_id == user_id, UserConsent.kind == "privacy")
    )
    row.revoked_at = clock.now()
    db_session.commit()

    _assert_consent_required(
        client.get("/v1/trainer/clients", headers=_auth(login["access_token"])),
        missing=["privacy"],
    )


def test_member_token_on_trainer_route_is_still_role_forbidden(client):
    """회원 계정은 동의 여부와 상관없이 트레이너 권한 403 이다 — 동의 화면으로 보내지 않는다."""
    email = f"tgate-member-{uuid4().hex[:10]}@oncare.com"
    r = client.post(
        "/v1/auth/register",
        json={"email": email, "password": PASSWORD, "name": "회원"},
    )
    assert r.status_code == 201, r.text
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": PASSWORD}
    ).json()["access_token"]

    got = client.get("/v1/trainer/clients", headers=_auth(token))

    assert got.status_code == 403, got.text
    assert got.json()["detail"] == "트레이너 권한이 필요해요."


def test_seeded_demo_trainer_is_not_blocked(client):
    from app.core.config import get_settings

    login = client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": get_settings().demo_login_password},
    )
    assert login.status_code == 200, login.text
    assert login.json()["consent_required"] is False

    got = client.get("/v1/trainer/clients", headers=_auth(login.json()["access_token"]))

    assert got.status_code == 200, got.text
