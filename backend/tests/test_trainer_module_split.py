"""트레이너 서비스·라우터 영역별 모듈 분리의 호환 단계 가드. (#2909)

한 파일이던 `trainer_service.py`·`api/v1/trainer.py` 를 영역별 모듈로 옮겼다. 이동만
했으므로 다음이 그대로여야 한다(모두 DB 없이 돈다).

- 트레이너 라우트의 Method·Path 집합 — 나누기 전 표(아래 스냅숏)와 같다.
- 예전 경로(`trainer_service.X`, `trainer.X`)가 영역 모듈의 같은 객체를 가리킨다.
- 예전 경로를 monkeypatch 하면 영역 모듈 안의 호출도 바뀐 값을 본다(한 파일이던
  때와 같은 효과). 되돌리면 원래 객체로 돌아온다.
- 영역 모듈끼리 서로의 비공개 헬퍼를 가져다 쓰지 않는다 — `_common` 을 거친다.
"""
from __future__ import annotations

import ast
import importlib
import sys
import types
from datetime import datetime
from pathlib import Path

import pytest

from tests.route_helpers import api_routes

_APP = Path(__file__).resolve().parents[1] / "app"

#: 나누기 전 `app/api/v1/trainer.py` 가 등록하던 라우트(Method·Path). 라우트를 새로
#: 만들거나 지우는 PR 은 이 표도 함께 고친다 — 이동 PR 은 고치지 않는다.
TRAINER_ROUTES = frozenset({
    "GET /v1/trainer/chat/unread",
    "GET /v1/trainer/client-invites",
    "POST /v1/trainer/client-invites",
    "DELETE /v1/trainer/client-invites/{invite_id}",
    "GET /v1/trainer/clients",
    "DELETE /v1/trainer/clients/{member_id}",
    "GET /v1/trainer/clients/{member_id}/ai-coach",
    "POST /v1/trainer/clients/{member_id}/ai-coach",
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
    "ai_coach",
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


# ---- 예전 경로 재수출 ----


@pytest.mark.parametrize("area", _SERVICE_AREAS)
def test_trainer_service_reexports_the_same_objects(area):
    from app.services import trainer_service

    module = importlib.import_module(f"app.services.trainer.{area}")
    names = _defined_names(module)
    assert names, f"{area} 에 정의된 함수가 없다"
    for name in names:
        assert getattr(trainer_service, name) is getattr(module, name), name


@pytest.mark.parametrize("area", _ROUTER_AREAS)
def test_trainer_router_package_reexports_the_same_objects(area):
    from app.api.v1 import trainer

    module = importlib.import_module(f"app.api.v1.trainer.{area}")
    for name in _defined_names(module):
        assert getattr(trainer, name) is getattr(module, name), name


def test_old_router_names_used_outside_the_package_stay_reachable():
    from app.api.v1 import trainer

    # `app/main.py` 의 CORS expose_headers 가 읽는다.
    assert trainer.NEXT_BEFORE_HEADER == "X-Next-Before"
    assert trainer.NEXT_BEFORE_ID_HEADER == "X-Next-Before-Id"
    assert callable(trainer.trainer_me)


# ---- monkeypatch 전파 ----


def test_patching_the_old_service_path_reaches_the_area_module():
    """`trainer_service._now_kst` 를 고정하면 스케줄 판정(`session_has_started`)이 그 값을 본다.

    conftest 의 자동 픽스처가 이미 같은 이름을 고정해 두므로, 그 값을 기준으로
    바꾸고 되돌린다.
    """
    from app.services import trainer_service
    from app.services.trainer import schedule

    before = trainer_service._now_kst
    with pytest.MonkeyPatch.context() as mp:
        mp.setattr(trainer_service, "_now_kst", lambda: datetime(2026, 1, 1, 10, 0))
        assert schedule.session_has_started("2026-01-01", "09:30")
        assert not schedule.session_has_started("2026-01-01", "10:30")
    assert trainer_service._now_kst is before
    assert schedule._now_kst is before


def test_patching_a_common_helper_reaches_every_area_that_imported_it():
    """`_today` 는 `_common` 에 있고 여러 영역이 가져다 쓴다 — 모두 고정 값을 본다."""
    from app.services import trainer_service

    before = trainer_service._today
    users = [
        importlib.import_module(f"app.services.trainer.{n}") for n in _SERVICE_AREAS
    ]
    users = [m for m in users if vars(m).get("_today") is before]
    assert len(users) > 1

    with pytest.MonkeyPatch.context() as mp:
        mp.setattr(trainer_service, "_today", lambda: "fixed")
        assert all(m._today() == "fixed" for m in users)
    assert all(m._today is before for m in users)


def test_patching_a_shared_import_reaches_every_area_that_uses_it():
    """한 파일이던 때처럼 `trainer_service.select` 하나를 바꾸면 모든 영역이 본다."""
    from app.services import trainer_service

    real = trainer_service.select
    users = [
        importlib.import_module(f"app.services.trainer.{n}") for n in _SERVICE_AREAS
    ]
    users = [m for m in users if vars(m).get("select") is real]
    assert len(users) > 1

    def never(*args, **kwargs):
        return real(*args, **kwargs)

    with pytest.MonkeyPatch.context() as mp:
        mp.setattr(trainer_service, "select", never)
        assert all(m.select is never for m in users)
    assert all(m.select is real for m in users)


def test_patch_leaves_a_different_object_with_the_same_name_alone():
    from app.core.module_reexport import reexport

    a = types.ModuleType("w2909_area_a")
    b = types.ModuleType("w2909_area_b")
    a.helper = lambda: "a"
    b.helper = lambda: "b"
    facade = types.ModuleType("w2909_facade")
    sys.modules["w2909_facade"] = facade
    try:
        with pytest.raises(RuntimeError):
            reexport("w2909_facade", (a, b))
        b.helper = a.helper
        b.other = "b-only"
        reexport("w2909_facade", (a, b))
        facade.helper = "patched"
        assert a.helper == "patched" and b.helper == "patched"
        b.other = "changed"
        facade.other = "set-on-facade"
        # 퍼사드와 다른 객체를 쥔 모듈은 건드리지 않는다.
        assert b.other == "changed"
    finally:
        del sys.modules["w2909_facade"]


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
