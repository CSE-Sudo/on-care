"""주간 리포트 요약 판정(주의사항) 공유 사례 파일을 서버 규칙으로 만든다. (#2906)

서버(`trainer_report_summary_service.watchpoints`)와 트레이너 웹 데모
(`frontend/flutter_trainer/lib/features/reports/domain/report_summary.dart`
`summaryWatchpoints`)는 같은 리포트에서 같은 주의사항을 같은 순서로 골라야
한다. 판정 로직은 공유할 수 없으므로 이 스크립트가 서버 기준값과 서버 판정
결과를 한 파일로 내고, 서버 pytest·트레이너 웹 테스트·결과지 패키지 테스트가
그 파일과 대조한다. 기준이나 판정을 바꾸면 이 스크립트를 다시 돌려 파일을
고친다(어긋난 쪽 테스트가 깨진다).

    cd backend && python scripts/gen_report_summary_cases.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.schemas.trainer_api import WeeklyReportOut  # noqa: E402
from app.services import trainer_report_summary_service as svc  # noqa: E402

OUT = (
    Path(__file__).resolve().parents[2]
    / "shared/oncare_rules/vectors/report_summary_cases.json"
)

_BASE: dict = {
    "member_id": "m-1",
    "member_name": "김회원",
    "week_start": "2026-09-21",
    "week_end": "2026-09-27",
    "sessions_booked": 2,
    "sessions_done": 2,
    "completion_avg": 85,
    "sodium_over_days": 0,
    "sodium_avg": 1800,
    "calories_week": [2000, 1950, 2050, 0, 2000, 0, 0],
    "sugar_week": [30, 35, 25, 0, 30, 0, 0],
    "days": [],
    "message": "",
}


def _day(*exercises: str) -> dict:
    return {"completion": 50, "exercises": list(exercises)}


def cases() -> list[dict]:
    """(이름, 기본 리포트에서 바꿀 칸). 경계값은 양쪽을 하나씩 둔다."""
    raw: list[tuple[str, dict]] = [
        ("조용한 주 — 주의 없음", {}),
        ("기록 없는 주 — 판정할 값이 없다", {
            "completion_avg": None, "sodium_avg": None,
            "calories_week": [0] * 7, "sugar_week": [0] * 7,
        }),
        ("이행률 기준 미만", {"completion_avg": 55}),
        ("이행률 기준과 같으면 주의 아님", {"completion_avg": 60}),
        ("나트륨 평균은 목표 안이지만 초과 사흘", {
            "sodium_avg": 1900, "sodium_over_days": 3,
        }),
        ("나트륨 초과 이틀은 주의 아님", {
            "sodium_avg": 1900, "sodium_over_days": 2,
        }),
        ("나트륨 평균이 목표 초과", {"sodium_avg": 2100, "sodium_over_days": 1}),
        ("나트륨 개인 목표", {
            "sodium_avg": 1700, "sodium_over_days": 1, "sodium_target": 1500,
        }),
        ("당류 초과 사흘", {"sugar_week": [60, 55, 52, 10, 10, 0, 0]}),
        ("당류 초과 이틀·평균 목표 안", {"sugar_week": [60, 55, 20, 10, 10, 0, 0]}),
        ("당류 평균만 목표 초과", {"sugar_week": [90, 30, 40, 0, 0, 0, 0]}),
        ("당류 개인 목표", {
            "sugar_week": [35, 34, 20, 0, 0, 0, 0], "sugar_target": 25,
        }),
        ("칼로리 20% 초과", {"calories_week": [2400, 2400, 2400, 0, 0, 0, 0]}),
        ("칼로리 15% 정확히 — 허용 폭 안", {
            "calories_week": [2300, 2300, 0, 0, 0, 0, 0],
        }),
        ("칼로리 부족", {"calories_week": [1200, 1300, 1400, 0, 0, 0, 0]}),
        ("칼로리 개인 목표", {
            "calories_week": [2000, 2000, 2000, 0, 0, 0, 0], "calorie_target": 1600,
        }),
        ("탄수화물 개인 목표 초과", {
            "carbs_week": [320, 300, 310, 0, 0, 0, 0], "carbs_target": 200,
        }),
        ("단백질 개인 목표 부족·지방 허용 폭 안", {
            "protein_week": [40, 50, 45, 0, 0, 0, 0], "protein_target": 100,
            "fat_week": [60, 55, 50, 0, 0, 0, 0], "fat_target": 55,
        }),
        ("탄단지 목표 없으면 보지 않는다", {
            "carbs_week": [500, 500, 0, 0, 0, 0, 0],
            "protein_week": [5, 5, 0, 0, 0, 0, 0],
        }),
        ("건너뛴 운동 — 같은 운동은 한 번", {
            "days": [
                _day("스쿼트 3세트 ✗", "러닝 20분 ✓"),
                _day("스쿼트 3세트 ✗"),
                _day("플랭크 60초 ✗"),
            ],
        }),
        ("건너뛴 운동은 셋까지", {
            "days": [
                _day("스쿼트 3세트 ✗", "런지 2세트 ✗"),
                _day("플랭크 60초 ✗", "버피 10회 ✗"),
            ],
        }),
        ("모든 주의 — 심각도 순", {
            "completion_avg": 40,
            "sodium_avg": 2600, "sodium_over_days": 5,
            "sugar_week": [70, 70, 70, 70, 0, 0, 0],
            "calories_week": [2800, 2800, 2800, 0, 0, 0, 0],
            "carbs_week": [400, 400, 400, 0, 0, 0, 0], "carbs_target": 250,
            "days": [_day("스쿼트 3세트 ✗")],
        }),
    ]
    return [{"name": name, "report": {**_BASE, **patch}} for name, patch in raw]


def run(case: dict) -> dict:
    """서버 판정 — 주의사항 종류·심각도(심각도 순)와 건너뛴 운동 이름.

    문장은 두 쪽이 각자의 번역 틀로 만들므로 여기서는 판정만 담는다.
    """
    report = WeeklyReportOut(**case["report"])
    return {
        "watchpoints": [
            {"kind": w.kind, "severity": w.severity}
            for w in svc.watchpoints(report, "ko")
        ],
        "skipped": svc._skipped_exercises(report),
    }


def thresholds() -> dict:
    """서버 기준값. 트레이너 웹·결과지 패키지의 같은 이름 상수와 대조한다."""
    return {
        "low_completion": svc.LOW_COMPLETION,
        "good_completion": svc.GOOD_COMPLETION,
        "calorie_tolerance": svc.CALORIE_TOLERANCE,
        "sodium_over_days": svc.SODIUM_OVER_DAYS,
        "sugar_over_days": svc.SUGAR_OVER_DAYS,
        "macro_tolerance": svc.MACRO_TOLERANCE,
        "max_points": svc.MAX_POINTS,
        "sodium_target_mg": svc.SODIUM_TARGET_MG,
        "calorie_target_kcal": svc.CALORIE_TARGET_KCAL,
        "sugar_target_g": svc.SUGAR_TARGET_G,
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
