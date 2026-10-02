"""서버·회원 앱·트레이너 웹이 함께 쓰는 값이 원본 표와 같은가. (#2906)

목표 미설정 기본값처럼 세 쪽이 같은 숫자를 들어야 하는 값은
`shared/oncare_rules/vectors/` 아래 JSON 한 벌이 원본이다. 백엔드 이미지는
`backend/` 만 담으므로 서버는 값을 모듈에 두고, 이 테스트가 원본과 같은지 본다 —
앱 쪽 테스트도 같은 파일을 읽으므로 원본을 바꾸면 어긋난 쪽이 깨진다.

DB 없이 돈다.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from app.api.v1 import dashboard
from app.services import (
    client_signals,
    diet_coach_inputs,
    diet_recommendation_service,
    exercise_service,
    goal_defaults,
    routine_ai,
    trainer_report_summary_service,
    trainer_service,
)

#: 원본 표 위치. 백엔드 이미지에는 없고 저장소에서 테스트할 때만 읽는다.
SOURCES = Path(__file__).resolve().parents[2] / "shared/oncare_rules/vectors"


def _load(name: str) -> dict:
    data = json.loads((SOURCES / f"{name}.json").read_text(encoding="utf-8"))
    data.pop("_comment", None)
    return data


GOAL_DEFAULTS = _load("goal_defaults")


# ── 목표 미설정 기본값 ────────────────────────────────────────────────────


@pytest.mark.parametrize("key", sorted(GOAL_DEFAULTS))
def test_goal_defaults_module_matches_the_shared_original(key: str) -> None:
    """서버 원본 모듈의 값이 공용 표와 같다."""
    assert getattr(goal_defaults, key.upper()) == GOAL_DEFAULTS[key]


def test_goal_defaults_module_has_no_value_missing_from_the_original() -> None:
    """서버에만 있는 기본값이 없다 — 더하면 원본 표에도 더해야 앱이 대조한다."""
    names = {n for n in vars(goal_defaults) if n.isupper()}
    assert names == {k.upper() for k in GOAL_DEFAULTS}


@pytest.mark.parametrize(
    ("value", "key"),
    [
        (dashboard._MAX_CALORIES, "daily_calories"),
        (dashboard._MAX_SODIUM_MG, "daily_sodium_mg"),
        (dashboard._MAX_SUGAR_G, "daily_sugar_g"),
        (diet_coach_inputs.DEFAULT_CALORIES, "daily_calories"),
        (diet_coach_inputs.DEFAULT_SODIUM_MG, "daily_sodium_mg"),
        (diet_coach_inputs.DEFAULT_SUGAR_G, "daily_sugar_g"),
        (diet_coach_inputs.DEFAULT_PROTEIN_G, "daily_protein_g"),
        (diet_coach_inputs.PROTEIN_G_PER_KG, "protein_g_per_kg"),
        (diet_recommendation_service.DEFAULT_CALORIE_LIMIT, "daily_calories"),
        (diet_recommendation_service.DEFAULT_SODIUM_LIMIT_MG, "daily_sodium_mg"),
        (diet_recommendation_service.DEFAULT_SUGAR_LIMIT_G, "daily_sugar_g"),
        (trainer_service.SODIUM_TARGET_MG, "daily_sodium_mg"),
        (routine_ai.SODIUM_TARGET_MG, "daily_sodium_mg"),
        (trainer_report_summary_service.SODIUM_TARGET_MG, "daily_sodium_mg"),
        (trainer_report_summary_service.CALORIE_TARGET_KCAL, "daily_calories"),
        (trainer_report_summary_service.SUGAR_TARGET_G, "daily_sugar_g"),
        (client_signals.DEFAULT_CALORIE_TARGET_KCAL, "daily_calories"),
        (client_signals.DEFAULT_WEEKLY_CARDIO_MINUTES, "weekly_cardio_minutes"),
        (client_signals.DEFAULT_WEEKLY_STRENGTH_SETS, "weekly_strength_sets"),
        (
            client_signals.DEFAULT_WEEKLY_STRETCHING_MINUTES,
            "weekly_flexibility_minutes",
        ),
        (exercise_service.DEFAULT_WEEKLY_MINUTES_GOAL, "weekly_cardio_minutes"),
        (exercise_service.DEFAULT_DAILY_BURN_KCAL, "daily_burn_kcal"),
    ],
)
def test_every_server_default_reads_the_original(value: float, key: str) -> None:
    """모듈마다 남아 있던 기본값 이름이 모두 원본 값을 가리킨다."""
    assert value == GOAL_DEFAULTS[key]
