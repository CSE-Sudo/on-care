"""건강 목표 숫자의 허용 범위 — 회원 경로와 트레이너 경로가 같은가. (#1888)

앞부분(스키마 검사)은 DB 없이 돈다. 뒤의 엔드포인트 검사는 `client` 픽스처를
쓰므로 로컬에서는 skip 되고 CI 에서 돈다.

목표는 **한 벌의 컬럼**이고 회원 앱과 트레이너 웹이 각자의 문으로 그것을
고친다. 전에는 범위 제한이 트레이너 경로에만 있어, 회원이 넣은 값을 트레이너가
고칠 수 없는 자리가 생겼다. 그래서 여기서 확인하는 것은 **두 문이 같은 값을
같게 판정하는가**다.
"""
from __future__ import annotations

import pytest
from pydantic import ValidationError

from app.schemas.health_goal_ranges import MINUTES_PER_WEEK
from app.schemas.trainer_api import MemberHealthProfileUpdate
from app.schemas.user import HealthGoalsUpdate, OnboardingRequest

#: 회원 경로 두 개와 트레이너 경로 하나. 같은 컬럼을 고치는 세 문이다.
#: 온보딩은 옛 주간 목표(`weekly_workout_goal` 등)를 다루지 않아 칸이 조금 적다.
MEMBER_SCHEMAS = (HealthGoalsUpdate, OnboardingRequest)
ALL_SCHEMAS = MEMBER_SCHEMAS + (MemberHealthProfileUpdate,)

#: 이슈에 적힌, 실제로 보내 확인한 세 값. 회원 경로에서 각각 500·200·200 이었다.
REPORTED = (
    {"daily_calories": 99999999999},  # integer out of range → 500
    {"daily_calories": -3000},  # 그대로 저장됐다
    {"weekly_cardio_minutes": 100000},  # 한 주는 10,080분이다
)


def _limits(model, field: str) -> dict:
    """JSON 스키마에서 그 칸의 범위만 추린다.

    `Optional[Annotated[int, Field(...)]]` 이라 제약이 `model_fields[...]`
    가 아니라 주석 안에 있다 — 스키마로 읽는 편이 확실하다.
    """
    prop = model.model_json_schema()["properties"][field]
    shapes = prop.get("anyOf", [prop])
    for shape in shapes:
        if shape.get("type") != "null":
            return {
                key: value
                for key, value in shape.items()
                if key in {"minimum", "maximum", "maxLength"}
            }
    raise AssertionError(f"{model.__name__}.{field} 에 값 자리가 없다")


# ---- 세 문이 같은 기준인가 (DB 불필요) ----


@pytest.mark.parametrize(
    "field",
    [
        "conditions",
        "goals",
        "daily_calories",
        "daily_sodium_mg",
        "daily_sugar_g",
        "daily_carbs_g",
        "daily_protein_g",
        "daily_fat_g",
        "daily_burn_kcal",
        "weekly_cardio_minutes",
        "weekly_strength_sets",
        "weekly_flexibility_minutes",
    ],
)
def test_member_and_trainer_paths_share_one_range(field):
    """같은 칸에 같은 범위. 두 벌로 적어 두면 또 갈라진다."""
    expected = _limits(MemberHealthProfileUpdate, field)
    assert expected, f"{field} 에 범위가 없다"
    for schema in MEMBER_SCHEMAS:
        assert _limits(schema, field) == expected, schema.__name__


@pytest.mark.parametrize(
    "field",
    ["weekly_workout_goal", "weekly_exercise_minutes_goal", "weekly_burn_goal"],
)
def test_legacy_weekly_goals_also_share_the_range(field):
    """옛 주간 목표도 마찬가지다 — `HealthGoalsUpdate` 는 아직 이 칸을 받는다.

    온보딩은 이 칸을 다루지 않아 여기서 뺀다.
    """
    assert _limits(HealthGoalsUpdate, field) == _limits(
        MemberHealthProfileUpdate, field
    )


@pytest.mark.parametrize("schema", ALL_SCHEMAS)
@pytest.mark.parametrize("payload", REPORTED)
def test_reported_values_are_rejected_on_every_path(schema, payload):
    """이슈에 적힌 세 값은 어느 문으로 와도 막힌다."""
    with pytest.raises(ValidationError):
        schema(**payload)


@pytest.mark.parametrize("schema", ALL_SCHEMAS)
def test_calorie_boundary(schema):
    """하한·상한 **바로 안**은 받고 바로 바깥은 막는다."""
    assert schema(daily_calories=500).daily_calories == 500
    assert schema(daily_calories=10000).daily_calories == 10000
    for outside in (499, 10001):
        with pytest.raises(ValidationError):
            schema(daily_calories=outside)


@pytest.mark.parametrize("schema", ALL_SCHEMAS)
def test_weekly_minutes_cannot_exceed_a_week(schema):
    """한 주는 10,080분이다 — 그보다 큰 주간 목표는 셀 수 없는 목표다."""
    assert (
        schema(weekly_cardio_minutes=MINUTES_PER_WEEK).weekly_cardio_minutes
        == MINUTES_PER_WEEK
    )
    with pytest.raises(ValidationError):
        schema(weekly_cardio_minutes=MINUTES_PER_WEEK + 1)


@pytest.mark.parametrize("schema", ALL_SCHEMAS)
def test_clearing_a_goal_still_works(schema):
    """`null` 은 '목표 해제'다 — 범위를 두면서 이 길을 막지 않는다."""
    assert schema(daily_calories=None).daily_calories is None


@pytest.mark.parametrize("schema", ALL_SCHEMAS)
def test_free_text_goals_have_the_same_limit(schema):
    """`conditions`·`goals` 도 같은 모양으로 갈라져 있었다.

    컬럼이 `Text` 라 500 은 아니지만, 회원 경로에는 상한이 없어 20만자가
    200 으로 저장됐다.
    """
    with pytest.raises(ValidationError):
        schema(goals="가" * 200_000)
    with pytest.raises(ValidationError):
        schema(conditions="가" * 1001)


# ---- 엔드포인트 (DB 필요) ----


def _member_token(client) -> str:
    from uuid import uuid4

    email = f"goal-range-{uuid4().hex[:8]}@oncare.com"
    password = "goal-pw-1234"
    r = client.post(
        "/v1/auth/register",
        json={"email": email, "password": password, "name": "목표 범위"},
    )
    assert r.status_code == 201, r.text
    return client.post(
        "/v1/auth/login", data={"username": email, "password": password}
    ).json()["access_token"]


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


@pytest.mark.parametrize("payload", REPORTED)
def test_member_goal_save_rejects_out_of_range(client, payload):
    """전에는 각각 500·200·200 이었다."""
    token = _member_token(client)
    r = client.put("/v1/users/me/health-goals", json=payload, headers=_auth(token))
    assert r.status_code == 422, r.text


@pytest.mark.parametrize("payload", REPORTED)
def test_onboarding_rejects_out_of_range(client, payload):
    """온보딩도 같은 열을 채운다 — 한쪽만 조이면 다른 문으로 같은 값이 들어온다."""
    token = _member_token(client)
    r = client.post("/v1/users/me/onboarding", json=payload, headers=_auth(token))
    assert r.status_code == 422, r.text


def test_member_goal_save_still_accepts_ordinary_values(client):
    """막는 것은 범위 바깥뿐이다 — 평범한 목표는 그대로 저장된다."""
    token = _member_token(client)
    r = client.put(
        "/v1/users/me/health-goals",
        json={"daily_calories": 2100, "weekly_cardio_minutes": 150},
        headers=_auth(token),
    )
    assert r.status_code == 200, r.text
    assert r.json()["daily_calories"] == 2100
    assert r.json()["weekly_cardio_minutes"] == 150


@pytest.mark.parametrize("payload", REPORTED)
def test_trainer_path_answers_the_same(client, payload):
    """같은 값에 두 문이 같은 답을 한다 — 넣는 문과 고치는 문이 갈라지지 않는다."""
    trainer = client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    ).json()["access_token"]
    r = client.put(
        "/v1/trainer/clients/user-jisu/health-profile",
        json=payload,
        headers=_auth(trainer),
    )
    assert r.status_code == 422, r.text
