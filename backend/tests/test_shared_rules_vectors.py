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
from app.services import exercise_advice, exercise_types, korean_josa
from app.services.trainer import reports as trainer_reports_service
from app.services.exercise_catalog import energy

#: 입력 표 위치. 백엔드 이미지에는 없고 저장소에서 테스트할 때만 읽는다.
VECTORS = Path(__file__).resolve().parents[2] / "shared/oncare_rules/vectors"


def _load(name: str) -> dict:
    return json.loads((VECTORS / f"{name}.json").read_text(encoding="utf-8"))


ROUNDING = _load("rounding")
EXERCISE_TYPES = _load("exercise_types")
KOREAN_JOSA = _load("korean_josa")


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


# ── 운동 유형 정규화 (#2861) ──────────────────────────────────────────────


@pytest.mark.parametrize(("raw", "code", "label"), EXERCISE_TYPES["normalize"])
def test_exercise_type_normalize_matches_shared_vectors(
    raw: str | None, code: str, label: str
) -> None:
    """두 앱의 `normalizeExerciseType`·`normalizeExerciseTypeKo` 와 같은 표다."""
    assert exercise_types.normalize(raw) == code
    assert exercise_types.normalize_ko(raw) == label


def test_shared_vectors_cover_every_server_vocabulary() -> None:
    """서버 표의 어휘가 모두 입력 표에 있다 — 서버에 어휘를 더하면 표도 같이 는다."""
    covered = {row[0] for row in EXERCISE_TYPES["normalize"]}
    assert set(exercise_types._TO_CODE) <= covered


# ── 한국어 조사 (#2897) ──────────────────────────────────────────────────


@pytest.mark.parametrize("case", KOREAN_JOSA["cases"], ids=lambda c: repr(c["word"]))
def test_korean_josa_matches_shared_vectors(case: dict) -> None:
    """두 앱의 `hasFinalConsonant`·`endsWithHangul`·`josa` 와 같은 표다."""
    word = case["word"]
    assert korean_josa.has_final_consonant(word) is case["has_final"]
    assert korean_josa.ends_with_hangul(word) is case["ends_with_hangul"]
    assert korean_josa.particle(word, "을", "를") == case["obj"]
    assert korean_josa.particle(word, "은", "는") == case["topic"]
    assert korean_josa.particle(word, "이", "가") == case["subj"]
    assert korean_josa.particle(word, "으로", "로") == case["dir"]
    assert korean_josa.with_particle(word, "을", "를") == word + case["obj"]


@pytest.mark.parametrize("case", KOREAN_JOSA["cases"], ids=lambda c: repr(c["word"]))
def test_weekly_feedback_topic_uses_shared_rule(case: dict) -> None:
    """주간 피드백 초안의 `은/는` 이 운동 조언·리포트 요약과 같은 판정을 쓴다."""
    word = case["word"]
    expected = word + case["topic"] if word else word
    assert trainer_reports_service._topic(word) == expected


@pytest.mark.parametrize(
    ("name", "expected"),
    [
        ("레그 프레스(머신)", "레그 프레스(머신)을 마쳤어요."),
        ("벤치프레스", "벤치프레스를 마쳤어요."),
        ("플랭크 60", "플랭크 60을 마쳤어요."),
        ("Squat", "Squat를 마쳤어요."),
    ],
)
def test_exercise_advice_never_writes_both_particle_forms(
    name: str, expected: str
) -> None:
    """괄호로 끝나는 이름은 괄호 앞 글자로, 한글이 아닌 이름도 한 꼴만 받는다."""
    text = exercise_advice.advice(
        "routine_today_done_next", done=name, next="런지"
    ).text
    assert text.startswith(expected)
    assert "(를)" not in text and "을(" not in text


def test_parenthesised_name_gets_same_particle_in_advice_and_feedback() -> None:
    """같은 이름이 운동 조언에서는 `을`, 주간 피드백에서는 `는` 으로 갈리던 자리."""
    name = "레그 프레스(머신)"
    advice_text = exercise_advice.advice("routine_all_done_today_name", name=name).text
    assert f"{name}을 " in advice_text
    assert trainer_reports_service._topic(name) == f"{name}은"


def test_direction_particle_uses_ro_after_rieul() -> None:
    """`으로/로` 는 받침 ㄹ 뒤에서 `로` 다 — `3일으로` 가 아니라 `3일로`."""
    assert korean_josa.with_particle("3일", "으로", "로") == "3일로"
    assert korean_josa.with_particle("덤벨 컬", "으로", "로") == "덤벨 컬로"
    assert (
        korean_josa.with_particle("코어 스트레칭", "으로", "로") == "코어 스트레칭으로"
    )
