"""회원 건강 목표(`HealthProfile.conditions`) 어휘. (#1814)

온보딩 2단계와 MY `건강 목표` 가 고르는 값이다. 예전에는 질환명(고혈압·당뇨)을
골랐지만, 타깃이 PT 회원으로 바뀌어 **운동을 시작하는 이유**를 고르게 했다.
회원앱 `health_focus.dart` 와 같은 목록·같은 순서여야 한다.

같은 칸에 트레이너가 적은 건강상태·주의사항(예: "무릎 통증으로 러닝 자제")도
들어간다. 그래서 정리는 **옛 질환 이름만** 새 목표로 바꾸거나 지우고, 그 밖의
글은 건드리지 않는다.
"""
from __future__ import annotations

#: 고를 수 있는 건강 목표. 저장·정렬 순서다.
FOCUS_WEIGHT_LOSS = "체중 감량"
FOCUS_STRENGTH = "근력 향상"
FOCUS_FITNESS = "체력 강화"
FOCUS_POSTURE = "자세 교정"
FOCUS_REHAB = "재활"
FOCUS_EATING = "식습관 개선"
FOCUS_EXERCISE_HABIT = "운동 습관"
FOCUS_BLOOD_PRESSURE = "혈압 관리"

FOCUS_OPTIONS: tuple[str, ...] = (
    FOCUS_WEIGHT_LOSS,
    FOCUS_STRENGTH,
    FOCUS_FITNESS,
    FOCUS_POSTURE,
    FOCUS_REHAB,
    FOCUS_EATING,
    FOCUS_EXERCISE_HABIT,
    FOCUS_BLOOD_PRESSURE,
)

#: 한 회원이 고를 수 있는 건강 목표 수. 주 목표 + 보조 목표로 읽히는 선이다 — 더
#: 고르면 목표가 흐려지고 목표별 권장치 규칙이 서로 부딪힌다. 회원앱과 같다.
MAX_FOCUS = 2

#: 옛 질환 선택지 → 새 목표. `None` 은 이어받을 목표가 없어 지운다.
LEGACY_FOCUS: dict[str, str | None] = {
    "고혈압": FOCUS_BLOOD_PRESSURE,
    "비만": FOCUS_WEIGHT_LOSS,
    "당뇨": None,
    "당뇨 전단계": None,
    "고지혈증": None,
}


def normalize_conditions(raw: str | None) -> str | None:
    """저장할 `conditions` 로 정리한다. `None` 은 '보내지 않음' 이라 그대로 둔다.

    옛 질환 이름은 새 목표로 바꾸거나 지우고, 겹치는 값은 하나로 합친다. 건강
    목표는 [FOCUS_OPTIONS] 순서로 앞에, 그 밖의 글은 적힌 순서대로 뒤에 둔다.
    건강 목표는 [MAX_FOCUS] 개까지만 남긴다 — 옛 값을 정리하다 늘어난 경우도 같다.
    """
    if raw is None:
        return None
    tokens: list[str] = []
    for part in raw.split(","):
        token = part.strip()
        if not token:
            continue
        if token in LEGACY_FOCUS:
            replacement = LEGACY_FOCUS[token]
            if replacement is None:
                continue
            token = replacement
        if token not in tokens:
            tokens.append(token)
    focus = [f for f in FOCUS_OPTIONS if f in tokens][:MAX_FOCUS]
    others = [t for t in tokens if t not in FOCUS_OPTIONS]
    return ", ".join(focus + others)


def focus_in(raw: str | None) -> list[str]:
    """`conditions` 에 들어 있는 건강 목표만 [FOCUS_OPTIONS] 순서로."""
    tokens = {t.strip() for t in (normalize_conditions(raw) or "").split(",")}
    return [f for f in FOCUS_OPTIONS if f in tokens]


#: 트레이너 화면이 건강 목표를 한 줄로 이을 때 쓰는 구분자. (#1818)
FOCUS_LABEL_SEPARATOR = " · "

#: 상담 신청의 운동 목표(`ConsultationRequest.exercise_goal`) → 건강 목표. (#1992)
#:
#: 상담 폼이 [FOCUS_OPTIONS] 를 그대로 선택지로 쓰게 되면서 여덟 목표와 **1:1** 이
#: 됐다 — 예전에는 `체력 향상`·`건강 관리` 처럼 옮길 곳이 없는 값이 있어 넷만 이었고,
#: 그 회원은 상담이 수락돼도 건강 목표가 비어 있었다.
#:
#: 남은 예외는 `other`(기타)뿐이다. 여덟 중 무엇인지 알려주는 바가 없어 옮길 곳이
#: 없고, 없앤 선택지로 이미 저장된 `health`(건강 관리)도 같은 이유로 잇지 않는다.
EXERCISE_GOAL_FOCUS: dict[str, str] = {
    "weight_loss": FOCUS_WEIGHT_LOSS,
    "strength": FOCUS_STRENGTH,
    # 예전 `체력 향상` 으로 저장된 값이다 — 이름만 `체력 강화` 로 바뀌었고 뜻은
    # 같아 백필 없이 그대로 읽는다.
    "fitness": FOCUS_FITNESS,
    "posture": FOCUS_POSTURE,
    "rehab": FOCUS_REHAB,
    "eating": FOCUS_EATING,
    "exercise_habit": FOCUS_EXERCISE_HABIT,
    "blood_pressure": FOCUS_BLOOD_PRESSURE,
}


def focus_label(raw: str | None) -> str:
    """`conditions` 의 건강 목표를 트레이너 화면 한 줄로(`체중 감량 · 혈압 관리`).

    트레이너 로스터·회원 코치 요약·AI 추천이 회원 목표를 말하는 자리다. 예전에는
    트레이너가 따로 적은 자유 문장(`TrainerClient.goal`)이었는데, 회원이 고른 목표와
    따로 놀아 같은 사람을 두 화면이 다르게 말했다(#1818). 목표가 없으면 빈 값이다.
    """
    return FOCUS_LABEL_SEPARATOR.join(focus_in(raw))


def with_focus_if_missing(raw: str | None, focus: str) -> str:
    """건강 목표가 하나도 없을 때만 [focus] 를 채운다. 이미 고른 목표는 덮지 않는다.

    상담 수락·데모 시드처럼 **회원이 고르지 않은 자리에서** 목표를 채울 때 쓴다 —
    회원이나 트레이너가 이미 고른 목표를 시스템이 바꾸면 고친 사람이 모른다.
    """
    if focus_in(raw):
        return normalize_conditions(raw) or ""
    return normalize_conditions(f"{focus}, {raw or ''}") or ""
