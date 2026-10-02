"""추천 개인운동의 효과 한 줄 문구표. (#2570)

회원 앱 추천 개인운동 카드에서 운동 이름 바로 아래 서는 줄이다. 트레이너가
운동마다 효과를 적게 하면 부담이 되므로, **운동 유형 × 회원의 첫 건강 목표** 로
정한 문구를 채우고 트레이너는 바꾸고 싶을 때만 고친다. AI 를 부르지 않는다.

원본은 `shared/routine_effects/routine_effects.json` 이다. 백엔드 이미지는
`backend/` 만 담으므로 여기 사본을 두고, `tests/test_routine_effects.py` 가 원본과
같은지 본다. 트레이너 웹(`routine_effects.dart`)도 같은 표로 입력 칸의
placeholder 를 보여 준다 — 미리 보인 문구와 회원이 받는 문구가 같아야 한다.

근거: 생애주기별 신체활동 지침 — 유산소·근력은 `coach_docs/pa_adult.txt`(만성질환·
비만·고혈압 예방, 근력 운동 권장), 스트레칭은 `coach_docs/pa_safety.txt`(준비운동의
혈액순환·관절 가동 범위·부상 예방, 정리운동의 심박수·혈압 회복).
"""
from __future__ import annotations

import re

#: 유형별 기본 문구. 목표가 없거나 표에 없는 목표면 이것을 쓴다.
ROUTINE_EFFECT_DEFAULTS: dict[str, str] = {
    "유산소": "체력 향상·만성질환 예방",
    "근력": "근력·근지구력 향상",
    "스트레칭": "유연성·부상 예방",
    # 기타는 운동이 무엇인지 알 수 없어 비운다 — 트레이너가 적을 때만 선다.
    "기타": "",
}

#: 유형 → 건강 목표(`health_focus.FOCUS_OPTIONS`) → 문구.
ROUTINE_EFFECTS_BY_GOAL: dict[str, dict[str, str]] = {
    "유산소": {
        "혈압 관리": "혈압 관리에 도움",
        "체중 감량": "체지방 감량에 도움",
        "체력 강화": "심폐 체력 향상",
        "재활": "무리 없는 체력 회복",
    },
    "근력": {
        "체중 감량": "근육량 유지·증가",
        "근력 향상": "근력 향상",
        "자세 교정": "자세 지지 근육 강화",
    },
    "스트레칭": {
        "혈압 관리": "혈압·심박 안정",
        "근력 향상": "근육 회복",
        "자세 교정": "굳은 근육 이완",
        "재활": "관절 가동 범위 회복",
    },
}

def auto_routine_effect(routine_type: str, goals: str | None) -> str:
    """`routine_type` 운동을 `goals` 회원에게 권할 때 채울 효과.

    `goals` 는 건강 목표를 `,`(저장값 `health_profiles.conditions`) 또는 ` · `
    (트레이너 웹 표시값)로 이은 값이다. **첫 목표**만 본다 — 회원이 주 목표로 고른
    것이다.
    """
    first = next(
        (part.strip() for part in re.split(r"[·,]", goals or "") if part.strip()),
        "",
    )
    by_goal = ROUTINE_EFFECTS_BY_GOAL.get(routine_type, {})
    if first in by_goal:
        return by_goal[first]
    return ROUTINE_EFFECT_DEFAULTS.get(routine_type, ROUTINE_EFFECT_DEFAULTS["기타"])
