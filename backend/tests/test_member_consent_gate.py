"""필수 동의가 끝나지 않은 회원은 데이터·AI API 를 쓰지 못한다. (#3088)

동의는 회원 앱이 동의 화면을 먼저 띄우는 것으로만 지켜졌다. 앱을 거치지 않거나
동의 화면이 없는 옛 빌드로 부르면, 동의 없이 사진·건강정보가 저장되고 외부 AI 로
나갔다. 그래서 회원 의존성(`CurrentUser`·`RequireMember`)이 필수 동의를 확인하고,
남은 항목이 있으면 403 `consent_required` 를 준다.

- 앞부분은 DB 없이 라우트 표만 본다 — 동의 확인 밖에서 회원을 받는 라우트가 새로
  생기면 실패한다.
- 뒷부분은 `client` 픽스처를 쓰므로 DB 가 있는 환경(CI)에서 돈다. 동의하지 않은
  계정을 만들려고 `without_default_consent` 를 쓴다(conftest 참고).
"""
from __future__ import annotations

import io
from uuid import uuid4

import pytest
from sqlalchemy import select

from app.api.deps import (
    CONSENT_EXEMPT_ROUTES,
    get_current_user,
    require_admin,
    require_auth,
    require_member,
    require_trainer,
)
from app.core import clock
from app.models.models import User, UserConsent
from app.services import signup_consent
from tests.route_helpers import api_routes

PASSWORD = "consent-gate-pw-1234"
MEMBER_REQUIRED = ["age14", "health", "privacy", "terms"]

#: 회원 의존성 없이 `require_auth` 로만 사용자를 받는 라우트 — 동의 확인 밖이다.
#: 추가할 때는 동의하지 않은 회원이 불러도 되는 이유를 함께 적는다.
AUTH_ONLY_ROUTES: dict[tuple[str, str], str] = {
    ("POST", "/v1/users/me/consents"): "동의를 제출하는 곳이다.",
    ("GET", "/v1/chat/attachments/{file_id}"): "회원·트레이너가 함께 쓰는 첨부 내려받기. "
    "회원의 첨부는 동의 뒤의 채팅에서만 생긴다.",
}


def _calls(dependant) -> set:
    found = set()
    stack = list(dependant.dependencies)
    while stack:
        dep = stack.pop()
        if dep.call is not None:
            found.add(dep.call)
        stack.extend(dep.dependencies)
    return found


def _routes() -> list:
    from app.main import app

    return api_routes(app)


# ---- 라우트 표 (DB 불필요) ----


def test_exempt_routes_exist_and_use_a_member_dependency():
    """예외 목록에 남은 항목이 실제 회원 라우트여야 한다 — 낡은 항목이 남지 않게."""
    for method, path in CONSENT_EXEMPT_ROUTES:
        route = next(
            (r for r in _routes() if r.path == f"/v1{path}" and method in r.methods),
            None,
        )
        assert route is not None, (method, path)
        calls = _calls(route.dependant)
        assert require_member in calls or get_current_user in calls, (method, path)


def test_every_route_that_takes_a_member_goes_through_the_consent_check():
    """사용자를 받는 라우트는 회원 의존성·트레이너·관리자 의존성 중 하나를 거치거나,
    동의 확인 밖에 두는 이유가 적혀 있어야 한다."""
    offenders = []
    for route in _routes():
        calls = _calls(route.dependant)
        if require_auth not in calls and get_current_user not in calls:
            continue
        if calls & {get_current_user, require_member, require_trainer, require_admin}:
            continue
        for method in sorted(route.methods):
            if (method, route.path) not in AUTH_ONLY_ROUTES:
                offenders.append(f"{method} {route.path}")
    assert offenders == [], (
        "require_auth 로만 사용자를 받는 라우트는 필수 동의 확인을 거치지 않는다. "
        "RequireMember 로 바꾸거나 AUTH_ONLY_ROUTES 에 이유와 함께 적을 것: "
        + ", ".join(offenders)
    )


def test_auth_only_allowlist_has_no_stale_entries():
    for method, path in AUTH_ONLY_ROUTES:
        route = next(
            (r for r in _routes() if r.path == path and method in r.methods), None
        )
        assert route is not None, (method, path)
        assert require_auth in _calls(route.dependant), (method, path)


@pytest.mark.parametrize(
    ("method", "path"),
    [
        ("POST", "/v1/diet/analyze"),
        ("POST", "/v1/users/me/onboarding"),
        ("POST", "/v1/ai-coach/chat"),
        ("POST", "/v1/exercise/sessions"),
        ("GET", "/v1/users/me/health"),
        ("GET", "/v1/users/me/profile"),
    ],
)
def test_health_and_ai_routes_are_not_exempt(method, path):
    assert (method, path.removeprefix("/v1")) not in CONSENT_EXEMPT_ROUTES


# ---- 엔드포인트 (DB) ----


def _auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _register_without_consent(client) -> tuple[str, dict]:
    """동의 목록 없이 가입한다(옛 빌드·직접 호출). (id, 로그인 응답)."""
    email = f"gate-{uuid4().hex[:10]}@oncare.com"
    r = client.post(
        "/v1/auth/register",
        json={"email": email, "password": PASSWORD, "name": "동의안함"},
    )
    assert r.status_code == 201, r.text
    login = client.post("/v1/auth/login", data={"username": email, "password": PASSWORD})
    assert login.status_code == 200, login.text
    assert login.json()["consent_required"] is True
    return r.json()["id"], login.json()


def _consent(client, token: str) -> None:
    r = client.post(
        "/v1/users/me/consents",
        json={"consents": MEMBER_REQUIRED},
        headers=_auth(token),
    )
    assert r.status_code == 200, r.text
    assert r.json()["consent_required"] is False


def _assert_consent_required(r, missing=MEMBER_REQUIRED) -> None:
    assert r.status_code == 403, r.text
    assert r.json()["detail"] == {"code": "consent_required", "missing": list(missing)}


@pytest.fixture
def ai_calls(monkeypatch):
    """음식 인식기·코치 LLM 이 불린 횟수. 둘 다 외부 AI 로 나가는 지점이다."""
    from app.api.v1 import diet
    from app.services.coach import chat as chat_service
    from app.services.coach.llm_base import LLMResult

    counts = {"recognizer": 0, "llm": 0}
    real_get_recognizer = diet.get_recognizer

    def counting_recognizer(*args, **kwargs):
        counts["recognizer"] += 1
        return real_get_recognizer(*args, **kwargs)

    class _StubLLM:
        def generate(self, system_prompt: str, user_prompt: str) -> LLMResult:
            return LLMResult(text="물을 한 컵 더 드세요.", model="stub")

    def counting_llm(*args, **kwargs):
        counts["llm"] += 1
        return _StubLLM()

    monkeypatch.setattr(diet, "get_recognizer", counting_recognizer)
    monkeypatch.setattr(chat_service, "get_coach_llm", counting_llm)
    return counts


def _call_data_routes(client, token: str) -> list:
    h = _auth(token)
    return [
        client.post(
            "/v1/diet/analyze",
            files={"image": ("meal.jpg", io.BytesIO(b"\xff\xd8\xff\xe0fake"), "image/jpeg")},
            data={"meal_type": "lunch"},
            headers=h,
        ),
        client.post(
            "/v1/users/me/onboarding",
            json={"height_cm": 170, "weight_kg": 65, "conditions": "고혈압"},
            headers=h,
        ),
        client.post("/v1/ai-coach/chat", json={"message": "오늘 뭐 먹을까요?"}, headers=h),
        client.post(
            "/v1/exercise/sessions",
            json={"type": "other", "minutes": 30, "calories": 120},
            headers=h,
        ),
        client.get("/v1/users/me/profile", headers=h),
        client.get("/v1/users/me/health", headers=h),
    ]


def test_member_without_consent_is_blocked_before_any_ai_call(
    client, without_default_consent, ai_calls
):
    _, login = _register_without_consent(client)

    for r in _call_data_routes(client, login["access_token"]):
        _assert_consent_required(r)

    assert ai_calls == {"recognizer": 0, "llm": 0}


def test_consent_and_account_routes_stay_open(client, without_default_consent):
    _, login = _register_without_consent(client)
    token = login["access_token"]

    me = client.get("/v1/users/me", headers=_auth(token))
    assert me.status_code == 200, me.text
    assert me.json()["consent_required"] is True
    assert me.json()["consent_pending"] == MEMBER_REQUIRED

    refreshed = client.post("/v1/auth/refresh", json={"refresh_token": login["refresh_token"]})
    assert refreshed.status_code == 200, refreshed.text

    logout = client.post("/v1/auth/logout", json={"refresh_token": login["refresh_token"]})
    assert logout.status_code == 204, logout.text


def test_member_without_consent_can_still_withdraw(client, db_session, without_default_consent):
    user_id, login = _register_without_consent(client)

    r = client.delete("/v1/users/me", headers=_auth(login["access_token"]))

    assert r.status_code == 200, r.text
    db_session.expire_all()
    assert db_session.get(User, user_id) is None


def test_data_routes_open_after_consent(client, without_default_consent, ai_calls):
    _, login = _register_without_consent(client)
    token = login["access_token"]

    _consent(client, token)

    h = _auth(token)
    assert client.get("/v1/users/me/profile", headers=h).status_code == 200
    onboarding = client.post(
        "/v1/users/me/onboarding",
        json={"height_cm": 170, "weight_kg": 65},
        headers=h,
    )
    assert onboarding.status_code == 200, onboarding.text
    chat = client.post("/v1/ai-coach/chat", json={"message": "안녕하세요"}, headers=h)
    assert chat.status_code == 200, chat.text


def test_document_version_bump_blocks_until_reconsent(client, monkeypatch):
    """처리방침 버전이 오르면 옛 버전에만 동의한 계정은 다시 동의할 때까지 막힌다."""
    email = f"gate-bump-{uuid4().hex[:10]}@oncare.com"
    r = client.post(
        "/v1/auth/register",
        json={"email": email, "password": PASSWORD, "consents": MEMBER_REQUIRED},
    )
    assert r.status_code == 201, r.text
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": PASSWORD}
    ).json()["access_token"]
    assert client.get("/v1/users/me/profile", headers=_auth(token)).status_code == 200

    monkeypatch.setitem(signup_consent.CURRENT_VERSIONS, "privacy", "2099-01-01")

    _assert_consent_required(
        client.get("/v1/users/me/profile", headers=_auth(token)), missing=["privacy"]
    )

    _consent(client, token)
    assert client.get("/v1/users/me/profile", headers=_auth(token)).status_code == 200


def test_revoked_health_consent_blocks(client, db_session):
    email = f"gate-revoke-{uuid4().hex[:10]}@oncare.com"
    r = client.post(
        "/v1/auth/register",
        json={"email": email, "password": PASSWORD, "consents": MEMBER_REQUIRED},
    )
    assert r.status_code == 201, r.text
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": PASSWORD}
    ).json()["access_token"]

    row = db_session.scalar(
        select(UserConsent).where(
            UserConsent.user_id == r.json()["id"], UserConsent.kind == "health"
        )
    )
    row.revoked_at = clock.now()
    db_session.commit()

    _assert_consent_required(
        client.get("/v1/users/me/profile", headers=_auth(token)), missing=["health"]
    )


def test_trainer_without_consent_is_not_gated(client, without_default_consent):
    """트레이너의 필수 동의 강제는 이 이슈 범위 밖이다 — 트레이너 API 는 그대로."""
    email = f"gate-trainer-{uuid4().hex[:10]}@oncare.com"
    r = client.post(
        "/v1/auth/trainer/register",
        json={"email": email, "password": PASSWORD, "name": "트레이너"},
    )
    assert r.status_code == 201, r.text
    login = client.post("/v1/auth/login", data={"username": email, "password": PASSWORD})
    assert login.json()["consent_required"] is True

    got = client.get("/v1/trainer/clients", headers=_auth(login.json()["access_token"]))

    assert got.status_code == 200, got.text


def test_seeded_demo_member_is_not_blocked(client):
    from app.core.config import get_settings

    login = client.post(
        "/v1/auth/login",
        data={"username": "minsu@oncare.com", "password": get_settings().demo_login_password},
    )
    assert login.status_code == 200, login.text

    got = client.get("/v1/users/me/profile", headers=_auth(login.json()["access_token"]))

    assert got.status_code == 200, got.text


def test_demo_consent_seed_covers_a_demo_member_without_consent(
    client, db_session, without_default_consent
):
    """시드가 데모 도메인 회원에게 필수 동의를 남긴다 — 테스트 기본 동의와 따로 본다."""
    from app.db.init_db import _seed_demo_consents

    user = User(
        id=f"user-gate-{uuid4().hex[:10]}",
        email=f"gate-seed-{uuid4().hex[:8]}@oncare.demo",
        name="시드회원",
        hashed_password="x",
    )
    db_session.add(user)
    db_session.commit()
    assert signup_consent.pending_kinds(db_session, user) == MEMBER_REQUIRED

    _seed_demo_consents()

    db_session.expire_all()
    assert signup_consent.pending_kinds(db_session, user) == []
