"""식단 AI 맞춤 조언의 문장 키·값과 한국어 문장. (#2251)

조언은 **규칙 한 줄 + 다음 할 일 한 문장**이다(회의 결정 3번). 두 문장 모두 로케일과
무관한 키와 값으로도 나간다 — 앱이 자기 번역(ARB)으로 그린다. 운동 조언
(`exercise_advice`, #2210)과 같은 방식이다.

AI 가 만든 문장은 키가 없다. 요청 언어로 받은 문장을 그대로 싣는다.

한국어 문장(`message`)은 두 문장을 이어 계속 함께 나간다. 키를 모르는 옛 앱이 그것을
읽는다. 그 문장은 아래 틀(`_KO`) 하나에서만 만든다 — 앱의 한국어 ARB 가 같은 틀을
옮겨 적는다.

**굵게 보일 곳은 `**` 로 감싼다.** 메뉴 이름과 규칙이 계산한 수치다. 앱은 이 표시를
굵은 글씨로 그리고, `message` 에서는 뗀다.

**두 문장을 합쳐 45자 안팎**이다(#1574 의 한 문장 반). 메뉴 이름은 리스트를 만들 때
12자로 막았다(`diet_menu_plan.NAME_MAX`). 추천 이유 키워드(`저나트륨` 등)는 문장에
싣지 않는다 — 앞의 규칙 한 줄이 이유를 말하고, 키워드는 값(`keyword`)으로만 준다.
"""
from __future__ import annotations

from dataclasses import dataclass, field

#: 끼니 코드 → 한국어. 모두 받침이 있어 "은" 을 붙인다.
SLOT_LABELS_KO = {"breakfast": "아침", "lunch": "점심", "dinner": "저녁"}

_KO: dict[str, str] = {
    # 오늘 — 규칙 한 줄 (#2251)
    "today_empty": "오늘 식단 기록이 아직 없어요.",
    "today_missing_meal": "적지 않은 끼니가 있나요?",
    "today_sodium_over": "나트륨 **{sodium_mg:,}mg**, 권장량 초과예요.",
    "today_calorie_over": "오늘 **{kcal:,}kcal**, 목표 초과예요.",
    "today_protein_left": "단백질 **{protein_g}g** 더 필요해요.",
    "today_balanced": "오늘 **{kcal:,}kcal**, 균형이 좋아요.",
    # 오늘 — 다음 식사 (#2251)
    "next_meal": "{slot_ko}은 **{menu}** 어때요?",
    "next_snack": "간식으로 **{menu}** 어때요?",
    "today_done": "오늘 식단을 잘 마무리했어요!",
    # 빠진 끼니를 묻는 동안은 메뉴를 고르지 않는다 — 기록부터 받는다.
    "today_log_first": "기록하면 다음 메뉴를 골라 드릴게요.",
}

#: 모든 키. 앱의 번역 테스트가 이 목록을 빠짐없이 그리는지 본다.
KEYS: tuple[str, ...] = tuple(_KO)


def _ko_fields(params: dict[str, str | int]) -> dict[str, str | int]:
    fields: dict[str, str | int] = dict(params)
    if "slot" in params:
        fields["slot_ko"] = SLOT_LABELS_KO.get(str(params["slot"]), str(params["slot"]))
    return fields


@dataclass(frozen=True)
class Line:
    """조언 한 문장 — 키·값, 또는 키 없이 받은 문장(AI)."""

    key: str | None
    params: dict[str, str | int] = field(default_factory=dict)
    #: 키가 없을 때의 문장(AI 가 요청 언어로 만든 것).
    raw: str = ""

    @property
    def text(self) -> str:
        """한국어 문장(`**` 표시 포함). AI 문장이면 받은 그대로다."""
        if self.key is None:
            return self.raw
        return _KO[self.key].format(**_ko_fields(self.params))


def line(key: str, **params: str | int) -> Line:
    if key not in _KO:
        raise KeyError(f"모르는 조언 키: {key}")
    return Line(key=key, params=params)


def ai_line(text: str) -> Line:
    return Line(key=None, raw=text)


def plain(text: str) -> str:
    """굵게 표시(`**`)를 뗀 문장."""
    return text.replace("**", "")


def message(analysis: Line, action: Line | None) -> str:
    """옛 앱이 읽는 한국어 평문 — 두 문장을 잇는다."""
    parts = [analysis.text]
    if action is not None and action.text:
        parts.append(action.text)
    return plain(" ".join(parts))
