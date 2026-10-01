"""서버와 두 앱이 같은 입력에 같은 값을 내는지 — 공용 입력 표 검사.

규칙의 앱 쪽 원본은 `shared/oncare_rules` 패키지 하나이고(회원 앱·트레이너 웹이 함께
쓴다), 서버 쪽은 각 모듈이다. 두 쪽이 주석으로만 "같다" 고 가리키면 한쪽만 고쳐지는
순간 화면과 저장값이 갈린다. 그래서 같은 입력 표(`shared/oncare_rules/vectors/*.json`)를
이 테스트와 Dart 테스트가 함께 읽는다 — 표를 바꾸면 양쪽이 같이 움직인다.

DB 없이 돈다.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from app.schemas.exercise_api import ExerciseCalorieRequest, ExerciseSessionCreate
from app.services.exercise_catalog import energy

#: 입력 표 위치. 백엔드 이미지에는 없고 저장소에서 테스트할 때만 읽는다.
VECTORS = Path(__file__).resolve().parents[2] / "shared/oncare_rules/vectors"


def _load(name: str) -> dict:
    return json.loads((VECTORS / f"{name}.json").read_text(encoding="utf-8"))


ROUNDING = _load("rounding")


# ── 반올림 (#2860) ──────────────────────────────────────────────────────


@pytest.mark.parametrize(("x", "expected"), ROUNDING["py_round"])
def test_python_round_matches_shared_vectors(x: float, expected: int) -> None:
    """앱의 `pyRound` 가 맞추는 기준 — 서버 `round` 는 0.5 를 짝수 쪽으로 보낸다."""
    assert round(x) == expected


@pytest.mark.parametrize(
    ("seconds", "minutes"),
    [row for row in ROUNDING["minutes_from_seconds"] if row[0] > 0],
)
def test_session_minutes_from_seconds_match_shared_vectors(
    seconds: int, minutes: int
) -> None:
    """저장 입력의 초 → 분이 앱 입력 시트·데모 서버(`minutesFromSeconds`)와 같다."""
    session = ExerciseSessionCreate(type="cardio", duration_seconds=seconds)
    assert session.minutes == minutes


@pytest.mark.parametrize(
    ("seconds", "minutes"),
    [row for row in ROUNDING["minutes_from_seconds"] if row[0] > 0],
)
def test_calorie_preview_minutes_from_seconds_match_shared_vectors(
    seconds: int, minutes: int
) -> None:
    """미리보기 입력도 저장과 같은 분으로 접는다 — 미리보기 kcal 과 저장 kcal 이 같다."""
    request = ExerciseCalorieRequest(
        type="cardio", name="러닝", duration_seconds=seconds
    )
    assert request.minutes == minutes


def test_half_minute_boundaries_round_to_even() -> None:
    """2분 30초는 2분, 4분 30초는 4분이다 — 앱이 3분·5분으로 보이던 경계."""
    assert ExerciseSessionCreate(type="cardio", duration_seconds=150).minutes == 2
    assert ExerciseSessionCreate(type="cardio", duration_seconds=270).minutes == 4


@pytest.mark.parametrize(
    "case",
    ROUNDING["fallback_calories"],
    ids=lambda c: f"{c['type']}-{c['minutes']}-{c['intensity']}",
)
def test_fallback_calories_match_shared_vectors(case: dict) -> None:
    """유형 평균 kcal 이 두 앱의 폴백 추정·데모 서버와 같은 반올림을 쓴다."""
    result = energy.fallback(case["type"], case["minutes"], case["intensity"])
    assert result.calories == case["calories"]
