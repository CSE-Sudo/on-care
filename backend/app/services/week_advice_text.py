"""`이번 주` AI 조언의 두 문장 — 탭 카드의 짧은 문장과 홈 코칭 시트의 긴 문장. (#3549)

2026-09-22 회의 결정: 화면마다 AI 를 따로 부르면 비용이 커지고 같은 날 화면마다 조언이
달라진다. 그래서 AI 는 식단 탭 `이번 주` 에서 한 번, 운동 탭 `이번 주` 에서 한 번만
부르고, 한 번의 호출로 두 길이의 문장을 함께 받는다.

| 문장 | 쓰는 곳 | 길이 |
| --- | --- | --- |
| `sentence` | 식단·운동 탭 `이번 주` 카드(규칙 한 줄 뒤) | 카드 한도(`CARD_MAX`) 안 |
| `detail` | 홈 코칭 시트 카드(규칙이 쓴 오늘 수치 뒤) | `DETAIL_MIN`~`DETAIL_MAX` |

홈 시트 카드 본문은 "규칙 첫 문장 + detail" 이라, 체험하기 문구(#2706, 약 110~130자)와
비슷한 분량이 되도록 detail 의 길이를 잡았다.

두 문장 모두 **수치를 쓰지 않는다** — 수치는 규칙이 계산한다(회의 결정 3번).
"""
from __future__ import annotations

import json
from collections.abc import Callable
from dataclasses import dataclass

from app.services.diet_advice_copy import plain

#: 프롬프트가 요구하는 긴 문장 길이(공백 포함).
DETAIL_MIN = 50
DETAIL_MAX = 95
#: 검사에서 받아 주는 길이. 모델이 글자 수를 정확히 세지 못해 프롬프트보다 넉넉히 둔다.
DETAIL_ACCEPT_MIN = 35
DETAIL_ACCEPT_MAX = 115
#: 두 문장과 사고 예산이 들어가는 출력 토큰 상한(#3032).
LLM_PAIR_MAX_OUTPUT_TOKENS = 768


@dataclass(frozen=True)
class WeekAdviceText:
    """AI 가 한 번에 준 두 문장. 긴 문장이 검사에 걸렸으면 [detail] 이 None 이다."""

    sentence: str
    detail: str | None


def _strip_fence(raw: str) -> str:
    text = raw.strip()
    if text.startswith("```"):
        text = text.split("\n", 1)[1] if "\n" in text else ""
        text = text.rsplit("```", 1)[0].strip()
    return text


def parse_pair(raw: str) -> tuple[str, str]:
    """응답 JSON → (짧은 문장, 긴 문장). 모양이 다르면 빈 문자열."""
    try:
        data = json.loads(_strip_fence(raw))
    except ValueError:
        return "", ""
    if not isinstance(data, dict):
        return "", ""
    sentence = data.get("sentence")
    detail = data.get("detail")
    return (
        sentence if isinstance(sentence, str) else "",
        clean_detail(detail) if isinstance(detail, str) else "",
    )


def clean_detail(text: str) -> str:
    """긴 문장 정리 — 줄바꿈·따옴표·굵게 표시를 걷는다(시트는 평문이다)."""
    return plain(" ".join(text.split()).strip().strip('"“”\''))


def detail_rejection_reason(
    text: str, has_measure: Callable[[str], bool]
) -> str | None:
    """긴 문장 검사 탈락 사유(`empty`·`too_short`·`too_long`·`measure`). 통과면 None."""
    if not text:
        return "empty"
    if len(text) < DETAIL_ACCEPT_MIN:
        return "too_short"
    if len(text) > DETAIL_ACCEPT_MAX:
        return "too_long"
    if has_measure(text):
        return "measure"
    return None
