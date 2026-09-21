"""세트·횟수·중량의 상한이 회원·트레이너 스키마에서 **같은가**. (#1904)

같은 값인데 상한이 곳마다 달랐다. 세트는 회원 앱 40·회원 백엔드 100·트레이너
99 로 셋이 다 달랐고 중량은 회원 앱만 500kg 이었다. 그래서 트레이너가 배정할 수
있는 값을 회원이 자기 앱에서 직접 적으려 하면 막혔다 — 화면에 보이는 수를 옮겨
적을 수 없었다.

여기서 지키는 것은 **값 자체가 아니라 같음**이다. 나중에 상한을 올리든 내리든
한 곳만 고치면 세 스키마가 함께 움직여야 한다. 한 곳에 숫자를 직접 적어 두면
그때부터 다시 갈린다.

앱 쪽 같은 값은 `frontend/flutter/.../exercise_limits.dart` 와
`frontend/flutter_trainer/lib/shared/exercise_limits.dart` 에 있다.
"""
from __future__ import annotations

from annotated_types import Le
from pydantic import BaseModel

from app.schemas.exercise_api import (
    AssignedRoutineCompleteRequest,
    ExerciseSessionCreate,
)
from app.schemas.exercise_limits import (
    MAX_EXERCISE_HOLD_SECONDS,
    MAX_EXERCISE_REPS,
    MAX_EXERCISE_SETS,
    MAX_EXERCISE_WEIGHT_KG,
)
from app.schemas.trainer_api import ProgramDraftExercise, ProgramItem

#: 세트·횟수·중량을 함께 받는 스키마들. 회원이 적는 쪽과 트레이너가 적는 쪽이
#: 섞여 있어야 이 시험이 뜻을 가진다.
SCHEMAS: list[type[BaseModel]] = [
    ExerciseSessionCreate,
    AssignedRoutineCompleteRequest,
    ProgramItem,
    ProgramDraftExercise,
]

EXPECTED = {
    "sets": MAX_EXERCISE_SETS,
    "reps": MAX_EXERCISE_REPS,
    # 홀드 초도 두 앱이 주고받는 같은 값이다 — 트레이너가 배정할 수 있는
    # 초를 회원이 자기 앱에서 적을 수 없으면 안 된다. (#1969)
    "hold_seconds": MAX_EXERCISE_HOLD_SECONDS,
    "weight": MAX_EXERCISE_WEIGHT_KG,
}


def _upper_bound(model: type[BaseModel], field: str):
    """`Field(..., le=N)` 의 N. 상한을 걸지 않았으면 None 이다."""
    info = model.model_fields[field]
    for meta in info.metadata:
        if isinstance(meta, Le):
            return meta.le
    return None


def test_every_schema_uses_the_same_upper_bounds():
    """네 스키마가 같은 상한을 쓴다."""
    for model in SCHEMAS:
        for field, expected in EXPECTED.items():
            assert _upper_bound(model, field) == expected, (
                f"{model.__name__}.{field}"
            )


def test_bounds_are_not_left_open():
    """상한이 아예 없는 칸이 없다 — #1903 의 `minutes` 가 그랬다."""
    for model in SCHEMAS:
        for field in EXPECTED:
            assert _upper_bound(model, field) is not None, (
                f"{model.__name__}.{field}"
            )


def test_member_can_log_what_a_trainer_can_assign(client):
    """트레이너가 배정할 수 있는 세트·중량을 회원이 직접 적을 수 있다.

    이 시험의 요점은 상한 값이 아니라 **두 쪽이 같다**는 것이다. 트레이너가 짠
    프로그램을 보고 회원이 같은 수를 옮겨 적는 것이 막히면 안 된다.
    """
    email = "exlimits@oncare.com"
    client.post(
        "/v1/auth/register", json={"email": email, "password": "pw!", "name": "u"}
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "pw!"}
    ).json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 트레이너 스키마가 받아 주는 최댓값 그대로.
    res = client.post(
        "/v1/exercise/sessions",
        json={
            "type": "strength",
            "name": "레그프레스",
            "minutes": 60,
            "sets": _upper_bound(ProgramItem, "sets"),
            "reps": _upper_bound(ProgramItem, "reps"),
            "weight": _upper_bound(ProgramItem, "weight"),
            "intensity": "moderate",
        },
        headers=headers,
    )

    assert res.status_code == 201, res.text
    body = res.json()
    assert body["sets"] == MAX_EXERCISE_SETS
    assert body["reps"] == MAX_EXERCISE_REPS
    assert body["weight"] == MAX_EXERCISE_WEIGHT_KG
