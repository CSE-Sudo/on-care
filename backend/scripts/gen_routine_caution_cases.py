"""루틴 주의 규칙 공유 표·사례 파일을 서버 규칙으로 만든다. (#2906)

서버 규칙형 A/B(`routine_ai`)와 트레이너 웹 데모
(`frontend/flutter_trainer/lib/features/coaching/data/demo_routine_rules.dart`)는
같은 주의 부위 표·전문가 확인 낱말·반복 운동 유형 낱말·라이브러리 운동을 들고
같은 판단을 내려야 한다. 로직은 공유할 수 없으므로 이 스크립트가 서버 표와
서버 판단 결과를 한 파일로 내고, 서버 pytest 와 트레이너 웹 테스트가 그 파일과
대조한다. 표나 판단을 바꾸면 이 스크립트를 다시 돌려 파일을 고친다(어긋난 쪽
테스트가 깨진다).

    cd backend && python scripts/gen_routine_caution_cases.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.services import routine_ai as svc  # noqa: E402

OUT = (
    Path(__file__).resolve().parents[2]
    / "shared/oncare_rules/vectors/routine_caution_cases.json"
)

#: 주의사항·대화 → 조심할 부위·전문가 확인 여부.
_DETECT: list[tuple[str, list[str]]] = [
    ("", ["회원: 허리가 아파요"]),
    ("무릎 수술 이력", []),
    ("어깨 회전근 손상, 발목 염좌", ["회원: 족저근막염도 있어요"]),
    ("혈압 관리", []),
    ("", []),
    ("슬개골 통증", ["회원: 숨이 차요"]),
    ("디스크", ["회원: 가슴 통증이 있어요"]),
    ("반월상 연골", ["회원: 어지럼이 있어요", "회원: 계단이 힘들어요"]),
    # 회원·트레이너가 흔히 적는 `런닝` 표기(#3215).
    ("무릎 통증으로 런닝 자제", []),
]

#: 운동 이름 · 조심할 부위 → 그 운동을 빼는가.
_AVOIDS: list[tuple[str, list[str]]] = [
    ("인터벌 러닝", ["무릎"]),
    ("스쿼트", ["허리"]),
    ("데드리프트", ["허리"]),
    ("오버헤드 프레스", ["어깨"]),
    ("줄넘기", ["발목"]),
    ("저강도 걷기", ["무릎", "허리", "어깨", "발목"]),
    ("코어 스트레칭", ["허리"]),
    ("벤치 프레스", []),
    ("계단 오르기", ["무릎"]),
    # `런닝` 은 `러닝` 과 같은 운동이다(#3215). `러닝` 이 `러닝머신` 에도 걸리듯
    # `런닝` 도 `런닝머신` 에 걸린다 — 두 표기를 같게 다룬다.
    ("런닝 30분", ["무릎"]),
    ("런닝", ["허리"]),
    ("런닝", ["발목"]),
    ("런닝", ["어깨"]),
    ("러닝머신", ["무릎"]),
    ("런닝머신", ["무릎"]),
]

#: 구성 · 조심할 부위 → 저충격 대안으로 바꾼 구성.
_SAFE_PARTS: list[tuple[list[tuple[str, str, int]], list[str]]] = [
    ([("인터벌 러닝", "유산소", 3), ("스쿼트", "근력", 2), ("플랭크", "근력", 1)], ["허리"]),
    ([("인터벌 러닝", "유산소", 3), ("스쿼트", "근력", 2)], ["무릎"]),
    ([("인터벌 러닝", "유산소", 3)], []),
    ([("인터벌 러닝", "유산소", 3), ("스쿼트", "근력", 2), ("플랭크", "근력", 1)], ["어깨"]),
    ([("코어 스트레칭", "스트레칭", 2), ("런지", "근력", 2)], ["무릎"]),
    ([("러닝", "유산소", 2)], ["발목"]),
    ([("런닝 30분", "유산소", 2), ("플랭크", "근력", 1)], ["무릎"]),
]

#: 반복 운동 이름 → 짐작한 유형.
_GUESS_TYPE = [
    "요가 매트 스트레칭",
    "폼롤러",
    "실내 자전거",
    "달리기",
    "런닝",
    "런닝머신",
    "레그프레스",
    "저강도 걷기",
    "플랭크",
]

#: 근거 문장에 붙는 안전 메모.
_SUFFIX: list[tuple[list[str], bool]] = [
    ([], False),
    (["무릎"], False),
    (["허리", "발목"], True),
    ([], True),
]

_LIBRARY = (
    svc._CARDIO_EASY,
    svc._CARDIO_HARD,
    svc._STRENGTH,
    svc._STRENGTH2,
    svc._STRETCH,
    svc._STRETCH2,
)


def tables() -> dict:
    """서버가 들고 있는 표. 트레이너 데모의 같은 이름 상수와 대조한다."""
    return {
        "caution_rules": [
            {"part": part, "keywords": list(keywords), "risky": list(risky)}
            for part, keywords, risky in svc._CAUTION_RULES
        ],
        "escalation_keywords": list(svc._ESCALATION_KEYWORDS),
        "stretch_keywords": list(svc._STRETCH_KEYWORDS),
        "cardio_keywords": list(svc._CARDIO_KEYWORDS),
        "en_caution_parts": dict(svc._EN_CAUTION_PARTS),
        "library": [{"name": name, "type": type_} for name, type_ in _LIBRARY],
        "en_exercise_names": dict(svc._EN_EXERCISE_NAMES),
    }


def cases() -> dict:
    """서버 판단 결과. 같은 입력에 트레이너 데모가 같은 결과를 내야 한다."""
    return {
        "detect": [
            {
                "conditions": conditions,
                "messages": messages,
                "cautions": svc.cautions_in(conditions, messages),
                "needs_professional_check": svc.needs_professional_check(
                    conditions, messages
                ),
            }
            for conditions, messages in _DETECT
        ],
        "avoids": [
            {"name": name, "cautions": cautions, "avoids": svc._avoids(name, cautions)}
            for name, cautions in _AVOIDS
        ],
        "safe_parts": [
            {
                "parts": [list(p) for p in parts],
                "cautions": cautions,
                "result": [list(p) for p in svc._safe_parts(parts, cautions)],
            }
            for parts, cautions in _SAFE_PARTS
        ],
        "guess_type": [
            {"name": name, "type": svc._guess_type(name)} for name in _GUESS_TYPE
        ],
        "caution_suffix": [
            {
                "cautions": cautions,
                "escalate": escalate,
                "ko": svc._caution_suffix(cautions, escalate, "ko"),
                "en": svc._caution_suffix(cautions, escalate, "en"),
            }
            for cautions, escalate in _SUFFIX
        ],
    }


def build() -> dict:
    return {"tables": tables(), "cases": cases()}


if __name__ == "__main__":
    OUT.write_text(
        json.dumps(build(), ensure_ascii=False, indent=1) + "\n", encoding="utf-8", newline="\n"
    )
    print(f"wrote {OUT}")
