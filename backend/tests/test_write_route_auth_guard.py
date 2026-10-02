"""회원 쓰기·삭제 라우트는 데모 폴백 없이 회원 토큰을 요구한다. (#2831)

`CurrentUser` 는 토큰이 없거나 만료되면 (개발·스테이징에서) 데모 사용자를 돌려준다.
쓰기 경로가 그것을 쓰면 만료 토큰으로 보낸 회원의 기록이 데모 계정에 저장되고, 회원
앱은 성공으로 본다. 그래서 쓰기·삭제는 `RequireMember` 로만 받는다.

- 앞부분은 DB 없이 라우트 표만 훑는 가드다 — 새 쓰기 라우트가 `CurrentUser` 를 쓰면 실패한다.
- 뒷부분(`client` 픽스처)은 CI 의 Postgres 에서 데모 폴백을 켠 채 401·403·정상을 본다.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from uuid import uuid4

import jwt
import pytest
from fastapi.routing import APIRoute

from app.api.deps import CurrentUser, get_current_user, require_member
from tests.route_helpers import api_routes

WRITE_METHODS = {"POST", "PUT", "PATCH", "DELETE"}

#: 쓰기 메서드인데도 `CurrentUser` 를 써도 되는 라우트. 지금은 없다.
#: 추가할 때는 `("METHOD", "/v1/경로")` 와 데모 사용자에게 써도 되는 이유를 함께 적는다.
ALLOWED_CURRENT_USER_WRITES: dict[tuple[str, str], str] = {}

#: 이슈에서 짚은 회원 쓰기·삭제 라우트. 가드가 전체를 훑지만, 이 목록은 바꾼 라우트가
#: 실제로 `require_member` 를 거치는지와 401·403 응답을 하나씩 확인하는 데 쓴다.
MEMBER_WRITE_ROUTES: list[tuple[str, str]] = [
    ("POST", "/v1/diet/nutrition"),
    ("POST", "/v1/diet/analyze"),
    ("POST", "/v1/diet/entries"),
    ("PUT", "/v1/diet/entries/{entry_id}"),
    ("DELETE", "/v1/diet/entries/{entry_id}"),
    ("POST", "/v1/exercise/calories"),
    ("POST", "/v1/exercise/sessions"),
    ("PUT", "/v1/exercise/sessions/{session_id}"),
    ("DELETE", "/v1/exercise/sessions/{session_id}"),
    ("POST", "/v1/notifications/read-all"),
    ("POST", "/v1/notifications/{notification_id}/read"),
    ("DELETE", "/v1/notifications/{notification_id}"),
    ("POST", "/v1/ai-coach/chat"),
    ("DELETE", "/v1/ai-coach/insights/{message_id}"),
    ("DELETE", "/v1/me/coach"),
    ("DELETE", "/v1/me/coach/trainer"),
]


def _calls(dependant) -> set:
    """라우트가 거치는 의존성 함수 전부(하위 의존성까지)."""
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


def _route(method: str, path: str):
    for route in _routes():
        if route.path == path and method in route.methods:
            return route
    raise AssertionError(f"{method} {path} 라우트가 없다")


# ---- 라우트 의존성 가드 (DB 불필요) ----


def test_no_write_route_uses_the_demo_fallback_dependency():
    offenders = []
    for route in _routes():
        for method in sorted(route.methods & WRITE_METHODS):
            if (method, route.path) in ALLOWED_CURRENT_USER_WRITES:
                continue
            if get_current_user in _calls(route.dependant):
                offenders.append(f"{method} {route.path}")
    assert offenders == [], (
        "쓰기·삭제 라우트가 데모 폴백 의존성(CurrentUser)을 쓴다. RequireMember 로 바꾸거나 "
        "ALLOWED_CURRENT_USER_WRITES 에 이유와 함께 적을 것: " + ", ".join(offenders)
    )


def test_allowlist_has_no_stale_entries():
    """예외 목록에 남은 항목이 실제로 CurrentUser 를 쓰는 쓰기 라우트여야 한다."""
    for method, path in ALLOWED_CURRENT_USER_WRITES:
        assert get_current_user in _calls(_route(method, path).dependant), (method, path)


@pytest.mark.parametrize(("method", "path"), MEMBER_WRITE_ROUTES)
def test_member_write_route_requires_member(method, path):
    calls = _calls(_route(method, path).dependant)
    assert require_member in calls
    assert get_current_user not in calls


def test_the_guard_notices_a_current_user_write_route():
    """가드 자체가 동작하는지 — CurrentUser 로 받는 쓰기 라우트를 만들면 잡혀야 한다."""
    from fastapi import FastAPI

    # CurrentUser 는 모듈 위에서 가져온다. 이 파일은 `from __future__ import annotations`
    # 라 주석이 문자열로 남고, FastAPI 는 그것을 함수의 모듈 전역에서 풀기 때문이다
    # (함수 안에서 가져오면 풀지 못해 쿼리 인자로 본다).
    probe = FastAPI()

    @probe.post("/v1/probe")
    def _probe(current_user: CurrentUser) -> None:  # noqa: ARG001
        return None

    route = next(r for r in probe.routes if isinstance(r, APIRoute))
    assert get_current_user in _calls(route.dependant)


# ---- 데모 폴백이 켜진 환경에서의 응답 (DB) ----


def _url(path: str) -> str:
    return (
        path.replace("{entry_id}", "diet-nope")
        .replace("{session_id}", "exercise-nope")
        .replace("{notification_id}", "noti-nope")
        .replace("{message_id}", "msg-nope")
    )


def _send(client, method: str, path: str, headers: dict | None = None):
    url = _url(path)
    if path == "/v1/diet/analyze":
        return client.post(
            url,
            files={"image": ("food.jpg", b"\xff\xd8\xff\xe0fake", "image/jpeg")},
            data={"meal_type": "lunch"},
            headers=headers,
        )
    if method == "DELETE":
        return client.delete(url, headers=headers)
    return client.request(method, url, json={}, headers=headers)


@pytest.fixture
def demo_fallback_on(client, monkeypatch):
    """운영 설정이 어긋난 환경을 재현한다 — 토큰이 없으면 데모 사용자로 폴백."""
    from app.core.config import get_settings

    settings = get_settings()
    monkeypatch.setattr(settings, "allow_demo_fallback", True)
    monkeypatch.setattr(settings, "env", "dev")
    assert settings.demo_fallback_enabled is True
    return settings


def _user(db_session, role: str):
    from app.models.models import User

    user_id = f"write-guard-{role}-{uuid4().hex[:10]}"
    user = User(
        id=user_id,
        email=f"{user_id}@oncare.com",
        name="가드",
        hashed_password="",
        role=role,
    )
    db_session.add(user)
    db_session.commit()
    return user


def _bearer(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _expired_token(user_id: str) -> str:
    from app.core.config import get_settings

    settings = get_settings()
    now = datetime.now(timezone.utc)
    payload = {
        "sub": user_id,
        "type": "access",
        "iat": now - timedelta(hours=2),
        "exp": now - timedelta(hours=1),
        "tv": 0,
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


@pytest.mark.parametrize(("method", "path"), MEMBER_WRITE_ROUTES)
def test_missing_token_is_401_even_with_demo_fallback(client, demo_fallback_on, method, path):
    response = _send(client, method, path)
    assert response.status_code == 401, response.text
    assert response.headers.get("www-authenticate") == "Bearer"


@pytest.mark.parametrize(("method", "path"), MEMBER_WRITE_ROUTES)
def test_expired_token_is_401_even_with_demo_fallback(
    client, db_session, demo_fallback_on, method, path
):
    member = _user(db_session, "member")
    response = _send(client, method, path, _bearer(_expired_token(member.id)))
    assert response.status_code == 401, response.text


@pytest.mark.parametrize(("method", "path"), MEMBER_WRITE_ROUTES)
def test_trainer_token_is_403(client, db_session, demo_fallback_on, method, path):
    from app.core.security import create_access_token

    trainer = _user(db_session, "trainer")
    response = _send(client, method, path, _bearer(create_access_token(trainer.id)))
    assert response.status_code == 403, response.text


def test_expired_token_does_not_save_to_the_demo_account(client, db_session, demo_fallback_on):
    """재현 경로: 만료 토큰으로 끼니 저장 → 데모 계정에 행이 생기면 안 된다."""
    from sqlalchemy import func, select

    from app.db.init_db import DEMO_USER_ID
    from app.models.models import DietEntry

    def demo_rows() -> int:
        db_session.expire_all()
        return db_session.scalar(
            select(func.count()).select_from(DietEntry).where(DietEntry.user_id == DEMO_USER_ID)
        )

    before = demo_rows()
    member = _user(db_session, "member")
    response = client.post(
        "/v1/diet/entries",
        json={"meal_type": "lunch", "foods": [{"name": "김밥", "calories": 300}]},
        headers=_bearer(_expired_token(member.id)),
    )
    assert response.status_code == 401
    assert demo_rows() == before


def test_member_token_still_writes(client, db_session, demo_fallback_on):
    """유효한 회원 토큰은 그대로 동작하고, 기록은 그 회원 것으로 남는다."""
    from sqlalchemy import select

    from app.core.security import create_access_token
    from app.models.models import DietEntry

    member = _user(db_session, "member")
    headers = _bearer(create_access_token(member.id))

    created = client.post(
        "/v1/diet/entries",
        json={"meal_type": "lunch", "foods": [{"name": "김밥", "calories": 300}]},
        headers=headers,
    )
    assert created.status_code == 201, created.text
    entry_id = created.json()["id"]
    db_session.expire_all()
    assert db_session.scalar(select(DietEntry.user_id).where(DietEntry.id == entry_id)) == (
        member.id
    )

    assert client.post("/v1/notifications/read-all", headers=headers).status_code == 200
    assert client.delete("/v1/me/coach/trainer", headers=headers).status_code == 204
    deleted = client.delete(f"/v1/diet/entries/{entry_id}", headers=headers)
    assert deleted.status_code == 200, deleted.text


def test_read_routes_keep_the_demo_fallback(client, demo_fallback_on):
    """범위 밖 확인: 읽기 화면은 그대로 데모 사용자로 뜬다."""
    assert client.get("/v1/diet/days/today").status_code == 200
