"""PT 관리 신호 판정 공유 사례 파일을 서버 규칙으로 만든다. (#2906)

서버(`client_signals.decide_signals`)는 회원 목록 배지(PT 관리 신호)를 정하고,
트레이너 웹 데모는 시드(`frontend/flutter_trainer/lib/core/storage/
seed_clients.dart`)에 회원마다 신호를 적어 둔다. 판정 로직은 공유할 수 없으므로
이 스크립트가 서버 기준값과 서버 판정 결과를 한 파일로 내고, 서버 pytest 와
트레이너 웹 테스트(사례 대조 + 시드가 규칙으로 나올 수 있는 값인지 검사)가 그
파일과 대조한다. 기준이나 판정을 바꾸면 이 스크립트를 다시 돌려 파일을 고친다.

    cd backend && python scripts/gen_client_signals_cases.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.services import client_signals as svc  # noqa: E402

OUT = (
    Path(__file__).resolve().parents[2]
    / "shared/oncare_rules/vectors/client_signals_cases.json"
)

#: 아무 신호도 없는 회원. 사례는 여기서 바꿀 칸만 적는다.
_BASE: dict = {
    "discomfort": False,
    "link_age_days": 30,
    "record_gap_days": 0,
    "no_show_count": 0,
    "routine_missed_days": 0,
    "weekday": 3,
    "exercise_goal_percent": 80,
    "recent_diet": [[2000, 100.0], [2000, 100.0], [2000, 100.0]],
    "calorie_target": 2000,
    "protein_target": 100.0,
    "focus": ["근력 향상"],
}


def cases() -> list[dict]:
    """(이름, 바꿀 칸). 경계값은 양쪽을 하나씩 둔다."""
    raw: list[tuple[str, dict]] = [
        ("조용한 회원 — 신호 없음", {}),
        ("담당 이틀째 — 통증만 보고 나머지는 유예", {
            "link_age_days": 2, "discomfort": True, "record_gap_days": 10,
        }),
        ("담당 사흘째 — 유예가 끝난다", {"link_age_days": 3, "record_gap_days": 3}),
        ("기록 끊김 사흘", {"record_gap_days": 3}),
        ("기록 끊김 이틀은 신호 아님", {"record_gap_days": 2}),
        ("기록이 끊기면 기록에서 나온 신호를 내리지 않는다", {
            "discomfort": True, "record_gap_days": 5, "no_show_count": 2,
            "routine_missed_days": 3, "exercise_goal_percent": 10,
            "recent_diet": [[3000, 20.0], [3000, 20.0]],
        }),
        ("노쇼·취소 두 번", {"no_show_count": 2}),
        ("노쇼·취소 한 번은 신호 아님", {"no_show_count": 1}),
        ("배정 루틴 미수행 이틀", {"routine_missed_days": 2}),
        ("배정 루틴 미수행 하루는 신호 아님", {"routine_missed_days": 1}),
        ("화요일에는 운동 목표를 보지 않는다", {
            "weekday": 1, "exercise_goal_percent": None,
        }),
        ("수요일 운동 목표 49%", {"weekday": 2, "exercise_goal_percent": 49}),
        ("운동 목표 50% 는 신호 아님", {"exercise_goal_percent": 50}),
        ("식단 기록 하루면 칼로리·단백질을 보지 않는다", {
            "recent_diet": [[3000, 10.0]],
        }),
        ("칼로리 20% 초과", {"recent_diet": [[2400, 100.0], [2400, 100.0]]}),
        ("칼로리 15% 는 허용 폭 안", {"recent_diet": [[2300, 100.0], [2300, 100.0]]}),
        ("칼로리 부족", {"recent_diet": [[1600, 100.0], [1600, 100.0]]}),
        ("칼로리 개인 목표", {
            "calorie_target": 1600, "recent_diet": [[2000, 100.0], [2000, 100.0]],
        }),
        ("칼로리 이탈 폭 반올림", {"recent_diet": [[2345, 100.0], [2345, 100.0]]}),
        ("단백질 부족 — 근력 향상", {"recent_diet": [[2000, 70.0], [2000, 70.0]]}),
        ("단백질 부족 — 체중 감량", {
            "focus": ["체중 감량"], "recent_diet": [[2000, 60.0], [2000, 60.0]],
        }),
        ("단백질 75% 는 신호 아님", {"recent_diet": [[2000, 75.0], [2000, 75.0]]}),
        ("단백질 섭취율 반올림은 짝수 쪽", {
            "recent_diet": [[2000, 74.5], [2000, 74.5]],
        }),
        ("단백질 목표 없으면 보지 않는다", {
            "protein_target": None, "recent_diet": [[2000, 10.0], [2000, 10.0]],
        }),
        ("단백질 중심 목표가 아니면 보지 않는다", {
            "focus": ["혈압 관리"], "recent_diet": [[2000, 10.0], [2000, 10.0]],
        }),
        ("모든 신호 — 급한 순", {
            "discomfort": True, "no_show_count": 3, "routine_missed_days": 3,
            "exercise_goal_percent": 20,
            "recent_diet": [[2600, 40.0], [2600, 40.0], [2600, 40.0]],
        }),
    ]
    return [{"name": name, "facts": {**_BASE, **patch}} for name, patch in raw]


def facts_of(case: dict) -> svc.SignalFacts:
    f = case["facts"]
    return svc.SignalFacts(
        discomfort=f["discomfort"],
        link_age_days=f["link_age_days"],
        record_gap_days=f["record_gap_days"],
        no_show_count=f["no_show_count"],
        routine_missed_days=f["routine_missed_days"],
        weekday=f["weekday"],
        exercise_goal_percent=f["exercise_goal_percent"],
        recent_diet=tuple((int(k), float(p)) for k, p in f["recent_diet"]),
        calorie_target=f["calorie_target"],
        protein_target=f["protein_target"],
        focus=frozenset(f["focus"]),
    )


def run(case: dict) -> list[dict]:
    """서버 판정 — 신호 계약 JSON(빈 칸은 뺀다), 급한 순."""
    return [s.model_dump(exclude_none=True) for s in svc.decide_signals(facts_of(case))]


def thresholds() -> dict:
    """서버 기준값과 신호 순서. 트레이너 웹 테스트의 판정이 이 값을 쓴다."""
    return {
        "signal_order": list(svc.SIGNAL_ORDER),
        "record_derived": sorted(svc._RECORD_DERIVED),
        "new_link_grace_days": svc.NEW_LINK_GRACE_DAYS,
        "record_gap_days": svc.RECORD_GAP_DAYS,
        "record_lookback_days": svc.RECORD_LOOKBACK_DAYS,
        "no_show_min_count": svc.NO_SHOW_MIN_COUNT,
        "routine_min_assigned_days": svc.ROUTINE_MIN_ASSIGNED_DAYS,
        "exercise_goal_low_percent": svc.EXERCISE_GOAL_LOW_PERCENT,
        "exercise_goal_from_weekday": svc.EXERCISE_GOAL_FROM_WEEKDAY,
        "min_recorded_days": svc.MIN_RECORDED_DAYS,
        "calorie_tolerance": svc.CALORIE_TOLERANCE,
        "protein_focus": sorted(svc.PROTEIN_FOCUS),
        "protein_low_ratio": svc.PROTEIN_LOW_RATIO,
        "default_calorie_target_kcal": svc.DEFAULT_CALORIE_TARGET_KCAL,
    }


def build() -> dict:
    all_cases = cases()
    for case in all_cases:
        case["expected"] = run(case)
    return {"thresholds": thresholds(), "cases": all_cases}


if __name__ == "__main__":
    OUT.write_text(
        json.dumps(build(), ensure_ascii=False, indent=1) + "\n", encoding="utf-8", newline="\n"
    )
    print(f"wrote {OUT}")
