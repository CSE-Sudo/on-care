"""소모 칼로리 산출 — 참조표·체중에서 나오는 결정적 계산과, 그 근거의 표시. (#1312)

## 값의 출처를 나눠 적는 이유

식단이 이미 하는 것과 같다. 공공 DB 로 환산한 값과 인식기 추정값을 `source` 로
구분해 두지 않으면, 회원은 화면의 숫자를 전부 같은 신뢰도로 읽는다. 운동도 같다 —
`러닝머신 30분` 을 종목표로 계산한 값과, 이름을 못 알아들어 유형 평균으로 때운
값이 같은 굵기로 적혀 있으면 안 된다.

    db       종목이 참조표에 붙었고 체중을 알고 있다. 이름·체중이 반영된 값.
    mixed    수치는 참조표, 이름 해석은 AI. 근거는 같고 붙인 경로만 다르다.
    estimate 폴백 — 이름이 안 붙었거나 체중을 모른다. 유형 평균의 어림값.

## 체중을 모르면 왜 db 가 아닌가

체중이 없으면 기준 체중으로 계산할 수는 있지만, 그 값은 이 회원의 값이 아니다.
식단이 양(g)을 모를 때 임의로 1인분을 가정하지 않는 것과 같은 판단이다 — 틀린
전제로 환산한 값에 더 높은 신뢰 신호를 붙이지 않는다.

## MET 을 화면에 꺼내지 않는다

계수는 여기서만 산다. 응답에도 넣지 않는다 — 집계 축은 칼로리 하나이고(#1276),
중간 단위가 계약에 있으면 두 앱이 그것으로 각자 계산하기 시작한다.
"""
from __future__ import annotations

from dataclasses import dataclass

from app.services import exercise_types

#: 강도 배수(가벼움/보통/높음). 참조표 계수는 "보통" 수행 기준이라 그대로 곱한다.
#: 원본은 `shared/oncare_rules/vectors/exercise_energy.json` 이고 두 앱은 공용
#: 패키지 `oncare_rules` 로 같은 값을 읽는다 — `tests/test_shared_rule_sources.py`
#: 가 대조한다(#2906).
INTENSITY_FACTOR = {"light": 0.85, "moderate": 1.0, "high": 1.2}

#: 이름이 붙지 않았을 때 쓰는 유형별 분당 kcal. #1312 이전에 유일한 계산이었고,
#: 지금은 **폴백**이다. 정확도가 아니라 화면 간 일관성이 목적이라(#1131) 값을
#: 바꾸지 않았다 — 여기를 건드리면 이름이 안 붙는 옛 기록의 값이 통째로 움직인다.
#: 원본 표는 강도 배수와 같은 `exercise_energy.json` 이다(#2906).
FALLBACK_KCAL_PER_MIN = {
    exercise_types.CARDIO: 9.0,
    exercise_types.STRENGTH: 6.0,
    exercise_types.STRETCHING: 3.0,
    exercise_types.OTHER: 5.0,
}

#: 이름 해석을 채택할 최소 확신도. 이보다 낮으면 붙이지 않고 폴백한다 —
#: 매칭기의 "오탐보다 폴백" 원칙과 같다.
MIN_CONFIDENCE = 0.6

SOURCE_DB = "db"
SOURCE_MIXED = "mixed"
SOURCE_ESTIMATE = "estimate"


@dataclass(frozen=True, slots=True)
class Estimate:
    """소모 칼로리 한 건과 그 근거."""

    calories: int
    #: db | mixed | estimate — 위 표 참고.
    source: str
    #: 값을 계산한 종목의 대표 이름. 폴백이면 빈 문자열이다. 회원이 적은 말과
    #: 다를 수 있어("런닝머신" → "러닝머신") 화면이 무엇으로 계산했는지 보여 준다.
    matched_name: str = ""
    #: 이 계산에 반영된 유형. 이름이 붙으면 참조표의 유형이 맞다 —
    #: `줄넘기` 를 근력으로 골라도 유산소다.
    type: str = exercise_types.OTHER


def from_catalog(
    row,
    minutes: int,
    intensity: str,
    weight_kg: float,
    *,
    resolver: str = "catalog",
) -> Estimate:
    """참조표 계수 × 체중 × 시간. 같은 입력이면 늘 같은 값이다.

    `met` 은 체중 1kg·1시간당 kcal 이므로 분으로 쓰려면 60 으로 나눈다.
    """
    factor = INTENSITY_FACTOR.get(intensity, 1.0)
    calories = row.met * factor * weight_kg * (max(minutes, 0) / 60.0)
    return Estimate(
        calories=round(calories),
        source=SOURCE_MIXED if resolver == "ai" else SOURCE_DB,
        matched_name=row.name,
        type=row.type,
    )


def fallback(type_: str, minutes: int, intensity: str) -> Estimate:
    """이름이 안 붙었을 때의 유형 평균. 어림값임을 `source` 로 밝힌다."""
    normalized = exercise_types.normalize(type_)
    per_min = FALLBACK_KCAL_PER_MIN.get(
        normalized, FALLBACK_KCAL_PER_MIN[exercise_types.OTHER]
    )
    factor = INTENSITY_FACTOR.get(intensity, 1.0)
    return Estimate(
        calories=round(per_min * max(minutes, 0) * factor),
        source=SOURCE_ESTIMATE,
        type=normalized,
    )


def estimate(
    row,
    type_: str,
    minutes: int,
    intensity: str,
    weight_kg: float | None,
    *,
    resolver: str = "catalog",
    confidence: float = 1.0,
) -> Estimate:
    """종목·체중이 다 갖춰졌을 때만 참조표로, 아니면 폴백.

    `row` 가 None 이거나 확신도가 낮거나 체중을 모르면 폴백이다. 셋 다 "이 회원의
    이 운동" 이라고 말할 수 없는 상태이고, 그럴 때는 확정된 값처럼 보이지 않는
    편이 낫다.
    """
    if row is None or confidence < MIN_CONFIDENCE or not weight_kg or weight_kg <= 0:
        return fallback(type_, minutes, intensity)
    return from_catalog(row, minutes, intensity, float(weight_kg), resolver=resolver)
