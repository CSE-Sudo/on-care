"""트레이너 서비스·라우터 영역별 모듈 구조 가드. (#2909)

한 파일이던 `trainer_service.py`·`api/v1/trainer.py` 를 영역별 모듈로 옮겼고, 호환
단계의 예전 경로 재수출도 지웠다. 다음이 지켜져야 한다(모두 DB 없이 돈다).

- 트레이너 라우트의 Method·Path 집합 — 나누기 전 표(아래 스냅숏)와 같다.
- 예전 경로(`app.services.trainer_service`, `app.core.module_reexport`)가 다시 생기지
  않고, 어느 코드도 그 경로를 가져오지 않는다. 라우터 패키지는 마운트 목록만 낸다.
- 이름마다 정의한 영역 모듈이 하나다 — 호출부는 그 모듈에서 가져온다.
- 영역 모듈끼리 서로의 비공개 헬퍼를 가져다 쓰지 않는다 — `_common` 을 거친다.
"""
from __future__ import annotations

import ast
import importlib
import importlib.util
import types
from pathlib import Path

import pytest

from tests.route_helpers import api_routes

_BACKEND = Path(__file__).resolve().parents[1]
_APP = _BACKEND / "app"

#: 나누기 전 `app/api/v1/trainer.py` 가 등록하던 라우트(Method·Path). 라우트를 새로
#: 만들거나 지우는 PR 은 이 표도 함께 고친다 — 이동 PR 은 고치지 않는다.
TRAINER_ROUTES = frozenset({
    "GET /v1/trainer/chat/unread",
    "GET /v1/trainer/client-invites",
    "POST /v1/trainer/client-invites",
    "DELETE /v1/trainer/client-invites/{invite_id}",
    "GET /v1/trainer/clients",
    "DELETE /v1/trainer/clients/{member_id}",
    "GET /v1/trainer/clients/{member_id}/chat",
    "POST /v1/trainer/clients/{member_id}/chat",
    "POST /v1/trainer/clients/{member_id}/chat/image",
    "POST /v1/trainer/clients/{member_id}/chat/read",
    "GET /v1/trainer/clients/{member_id}/deliveries/latest",
    "GET /v1/trainer/clients/{member_id}/diet",
    "GET /v1/trainer/clients/{member_id}/diet-advice",
    "GET /v1/trainer/clients/{member_id}/diet-recommendations",
    "PUT /v1/trainer/clients/{member_id}/diet-recommendations",
    "GET /v1/trainer/clients/{member_id}/diet/days",
    "GET /v1/trainer/clients/{member_id}/diet/photos/{photo_id}",
    "GET /v1/trainer/clients/{member_id}/exercise-advice",
    "GET /v1/trainer/clients/{member_id}/exercise-week",
    "GET /v1/trainer/clients/{member_id}/exercise/weeks",
    "GET /v1/trainer/clients/{member_id}/feedbacks",
    "GET /v1/trainer/clients/{member_id}/follow-ups",
    "POST /v1/trainer/clients/{member_id}/follow-ups",
    "GET /v1/trainer/clients/{member_id}/health-profile",
    "PUT /v1/trainer/clients/{member_id}/health-profile",
    "GET /v1/trainer/clients/{member_id}/history",
    "GET /v1/trainer/clients/{member_id}/memos",
    "POST /v1/trainer/clients/{member_id}/memos",
    "DELETE /v1/trainer/clients/{member_id}/memos/{memo_id}",
    "PUT /v1/trainer/clients/{member_id}/memos/{memo_id}",
    "POST /v1/trainer/clients/{member_id}/program",
    "POST /v1/trainer/clients/{member_id}/program-schedule",
    "GET /v1/trainer/clients/{member_id}/records/span",
    "PUT /v1/trainer/clients/{member_id}/registration",
    "GET /v1/trainer/clients/{member_id}/report",
    "GET /v1/trainer/clients/{member_id}/report/feedback",
    "PUT /v1/trainer/clients/{member_id}/report/feedback",
    "GET /v1/trainer/clients/{member_id}/report/goals",
    "PUT /v1/trainer/clients/{member_id}/report/goals",
    "GET /v1/trainer/clients/{member_id}/report/member-feedback",
    "POST /v1/trainer/clients/{member_id}/report/send",
    "POST /v1/trainer/clients/{member_id}/report/send-pdf",
    "GET /v1/trainer/clients/{member_id}/report/summary",
    "GET /v1/trainer/clients/{member_id}/reports/sent",
    "GET /v1/trainer/clients/{member_id}/routine-days",
    "POST /v1/trainer/clients/{member_id}/routine-options",
    "GET /v1/trainer/clients/{member_id}/routine-suggestions",
    "POST /v1/trainer/clients/{member_id}/routine-suggestions",
    "GET /v1/trainer/clients/{member_id}/routines",
    "POST /v1/trainer/clients/{member_id}/routines",
    "GET /v1/trainer/clients/{member_id}/routines/unsent",
    "DELETE /v1/trainer/clients/{member_id}/routines/{routine_id}",
    "PUT /v1/trainer/clients/{member_id}/routines/{routine_id}",
    "PUT /v1/trainer/clients/{member_id}/status",
    "GET /v1/trainer/consultations",
    "GET /v1/trainer/consultations/pending-count",
    "POST /v1/trainer/consultations/{consultation_id}/accept",
    "POST /v1/trainer/consultations/{consultation_id}/reject",
    "GET /v1/trainer/dashboard/task-progress",
    "PUT /v1/trainer/dashboard/task-progress/{day}",
    "POST /v1/trainer/dashboard/task-progress/{day}/keys",
    "GET /v1/trainer/follow-ups",
    "PUT /v1/trainer/follow-ups/{task_id}",
    "POST /v1/trainer/follow-ups/{task_id}/complete",
    "GET /v1/trainer/gyms/search",
    "DELETE /v1/trainer/me",
    "GET /v1/trainer/me",
    "PUT /v1/trainer/me",
    "DELETE /v1/trainer/me/gym",
    "PUT /v1/trainer/me/gym",
    "PUT /v1/trainer/me/gym/kakao",
    "GET /v1/trainer/me/gym/profile",
    "PUT /v1/trainer/me/gym/profile",
    "POST /v1/trainer/me/password",
    "GET /v1/trainer/me/settings",
    "PUT /v1/trainer/me/settings",
    "GET /v1/trainer/notifications",
    "POST /v1/trainer/notifications/read-all",
    "GET /v1/trainer/notifications/unread-count",
    "POST /v1/trainer/notifications/{notification_id}/read",
    "POST /v1/trainer/pairing-code",
    "POST /v1/trainer/pairing-code/preview",
    "GET /v1/trainer/program-templates",
    "POST /v1/trainer/program-templates",
    "DELETE /v1/trainer/program-templates/{template_id}",
    "PUT /v1/trainer/program-templates/{template_id}",
    "GET /v1/trainer/programs",
    "POST /v1/trainer/programs",
    "DELETE /v1/trainer/programs/{draft_id}",
    "GET /v1/trainer/programs/{draft_id}",
    "PUT /v1/trainer/programs/{draft_id}",
    "GET /v1/trainer/reports/queue",
    "GET /v1/trainer/reports/sent",
    "POST /v1/trainer/routine-suggestions/{suggestion_id}/approve",
    "POST /v1/trainer/routine-suggestions/{suggestion_id}/dismiss",
    "GET /v1/trainer/schedule",
    "POST /v1/trainer/schedule",
    "GET /v1/trainer/schedule/booked-dates",
    "POST /v1/trainer/schedule/recurring",
    "POST /v1/trainer/schedule/recurring/preview",
    "DELETE /v1/trainer/schedule/{session_id}",
    "PUT /v1/trainer/schedule/{session_id}",
    "POST /v1/trainer/schedule/{session_id}/cancel",
    "POST /v1/trainer/schedule/{session_id}/complete",
    "POST /v1/trainer/schedule/{session_id}/no-show",
    "POST /v1/trainer/schedule/{session_id}/program/send",
    "POST /v1/trainer/schedule/{session_id}/reopen",
    "GET /v1/trainer/schedule/{session_id}/routines",
    "PUT /v1/trainer/schedule/{session_id}/routines",
    "POST /v1/trainer/schedule/{session_id}/routines/dismiss",
    "POST /v1/trainer/schedule/{session_id}/routines/send",
})

_SERVICE_AREAS = (
    "_common",
    "roster",
    "chat",
    "client_status",
    "routines",
    "routine_suggestions",
    "memos",
    "follow_ups",
    "programs",
    "schedule",
    "member_mirror",
    "profile",
    "gym",
    "reports",
    "notification_settings",
    "weekly_feedback",
)

_ROUTER_AREAS = (
    "_common",
    "profile",
    "clients",
    "chat",
    "routines",
    "routine_suggestions",
    "memos",
    "follow_ups",
    "programs",
    "task_progress",
    "schedule",
    "reports",
    "client_invites",
    "consultations",
    "notifications",
)


def _is_trainer_router_module(name: str) -> bool:
    # `app.api.v1.trainers`(회원앱 디렉터리)는 다른 라우터다.
    return name == "app.api.v1.trainer" or name.startswith("app.api.v1.trainer.")


def _defined_names(module: types.ModuleType) -> list[str]:
    """[module] 이 직접 정의한 함수·클래스(가져온 이름 제외)."""
    return [
        name
        for name, value in vars(module).items()
        if isinstance(value, (types.FunctionType, type))
        and getattr(value, "__module__", None) == module.__name__
    ]


# ---- 라우트 표 ----


def test_trainer_routes_match_the_snapshot_taken_before_the_split():
    from app.main import app

    found = {
        f"{method} {route.path}"
        for route in api_routes(app)
        if _is_trainer_router_module(route.original_route.endpoint.__module__)
        for method in route.methods
    }
    assert sorted(found - TRAINER_ROUTES) == []
    assert sorted(TRAINER_ROUTES - found) == []


def test_every_area_router_is_mounted_once():
    from app.api.v1 import trainer

    modules = [importlib.import_module(f"app.api.v1.trainer.{n}") for n in _ROUTER_AREAS[1:]]
    assert list(trainer.routers) == [m.router for m in modules]
    assert all(r.routes for r in trainer.routers), "라우트가 없는 영역 라우터가 있다"


# ---- 예전 경로 제거 ----


@pytest.mark.parametrize(
    "module", ["app.services.trainer_service", "app.core.module_reexport"]
)
def test_compat_modules_are_gone(module):
    assert importlib.util.find_spec(module) is None, f"{module} 가 다시 생겼다"


def test_router_package_exposes_only_the_mount_list():
    """라우터 패키지는 영역 라우터 목록만 낸다 — 예전 단일 모듈의 이름을 다시 싣지 않는다."""
    from app.api.v1 import trainer

    for area in _ROUTER_AREAS:
        module = importlib.import_module(f"app.api.v1.trainer.{area}")
        leaked = [name for name in _defined_names(module) if hasattr(trainer, name)]
        assert leaked == [], f"{area}: {leaked}"


def test_cors_headers_come_from_the_notifications_router():
    from app.api.v1.trainer import notifications
    from app.main import app

    cors = next(m for m in app.user_middleware if m.cls.__name__ == "CORSMiddleware")
    exposed = cors.kwargs["expose_headers"]
    assert notifications.NEXT_BEFORE_HEADER in exposed
    assert notifications.NEXT_BEFORE_ID_HEADER in exposed


def test_no_code_imports_the_removed_compat_paths():
    removed = {"app.services.trainer_service", "app.core.module_reexport"}
    hits: list[str] = []
    for folder in ("app", "tests", "scripts", "migrations"):
        for path in sorted((_BACKEND / folder).rglob("*.py")):
            tree = ast.parse(path.read_text(encoding="utf-8"))
            for node in ast.walk(tree):
                if isinstance(node, ast.Import):
                    modules = [alias.name for alias in node.names]
                elif isinstance(node, ast.ImportFrom) and node.module:
                    modules = [node.module] + [
                        f"{node.module}.{alias.name}" for alias in node.names
                    ]
                else:
                    continue
                if removed & set(modules):
                    hits.append(f"{path.relative_to(_BACKEND)}:{node.lineno}")
    assert hits == []


# ---- 정의 위치 ----


@pytest.mark.parametrize(
    ("package", "areas"),
    [("app.services.trainer", _SERVICE_AREAS), ("app.api.v1.trainer", _ROUTER_AREAS)],
)
def test_each_name_is_defined_in_exactly_one_area(package, areas):
    owners: dict[str, list[str]] = {}
    for area in areas:
        module = importlib.import_module(f"{package}.{area}")
        names = _defined_names(module)
        assert names or area == "_common", f"{area} 에 정의된 함수·클래스가 없다"
        for name in names:
            owners.setdefault(name, []).append(area)
    assert {n: a for n, a in owners.items() if len(a) > 1} == {}


# ---- 영역 경계 ----


@pytest.mark.parametrize(
    ("package", "areas"),
    [("app.services.trainer", _SERVICE_AREAS), ("app.api.v1.trainer", _ROUTER_AREAS)],
)
def test_areas_take_private_helpers_only_from_common(package, areas):
    folder = _APP.joinpath(*package.split(".")[1:])
    crossings: list[str] = []
    for area in areas:
        tree = ast.parse((folder / f"{area}.py").read_text(encoding="utf-8"))
        for node in ast.walk(tree):
            if not isinstance(node, ast.ImportFrom) or node.module is None:
                continue
            if not node.module.startswith(f"{package}."):
                continue
            source = node.module.rsplit(".", 1)[1]
            if source == "_common":
                continue
            crossings += [
                f"{area} <- {source}.{alias.name}"
                for alias in node.names
                if alias.name.startswith("_")
            ]
    assert crossings == []


def test_common_does_not_depend_on_any_area():
    for package, areas in (
        ("app.services.trainer", _SERVICE_AREAS),
        ("app.api.v1.trainer", _ROUTER_AREAS),
    ):
        folder = _APP.joinpath(*package.split(".")[1:])
        tree = ast.parse((folder / "_common.py").read_text(encoding="utf-8"))
        imported = {
            node.module
            for node in ast.walk(tree)
            if isinstance(node, ast.ImportFrom) and node.module
        }
        assert not {m for m in imported if m.startswith(f"{package}.")}, package
