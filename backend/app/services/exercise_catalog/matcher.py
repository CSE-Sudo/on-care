"""운동 이름 → 종목 참조표 매칭.

`nutrition.matcher` 와 같은 원칙이다 — **오탐보다 폴백.** 틀린 종목으로 계산한
칼로리는 `source="db"` 로 표시돼 회원에게 "참조 데이터 근거" 라는 더 높은 신뢰
신호를 준다. 애매하면 붙이지 않고 유형 표로 떨어뜨리는 편이 낫다.

음식과 다른 점이 둘 있다.

* **별칭이 필수다.** 음식은 `김치찌개` 하나로 대체로 통하지만, 운동은 같은 종목을
  `러닝머신`·`런닝머신`·`트레드밀` 로 부른다. 그래서 이름과 별칭을 같은 자격으로
  본다.
* **포함 매칭의 방향이 하나뿐이다.** 음식은 `점심에 먹은 김치찌개 1인분` 처럼
  질의가 더 긴 경우가 흔해 양방향을 봤다. 운동 이름은 짧게 적히고(`스쿼트`),
  반대 방향(질의가 표 이름의 조각)을 열어 두면 `벤치` 가 `벤치프레스`·`벤치딥스`
  둘 다에 걸려 조용히 아무거나 고른다. 유일할 때만 채택한다.
"""
from __future__ import annotations

import re

_DIGIT = re.compile(r"\d+")
_PUNCT = re.compile(r"[\s()\[\]{}·.,/\\\-_+~!?'\"]+")

#: 종목이 아니라 **수행 방식**을 적은 말. 매칭 전에 떼어 낸다 — `가볍게 스쿼트`
#: 는 `스쿼트` 이고, 강도는 이미 강도 칩이 따로 받는다.
_MODIFIERS = (
    "가볍게",
    "천천히",
    "빠르게",
    "강하게",
    "오늘",
    "아침",
    "저녁",
    "실내",
    "야외",
)


def normalize(name: str) -> str:
    """매칭용 정규화: 소문자화 + 숫자/공백/구두점 제거 + 수행 방식 제거.

    숫자를 지우는 것이 중요하다 — `줄넘기 300개`·`스쿼트 3세트` 처럼 회원이 양을
    이름 칸에 함께 적는 일이 잦다.
    """
    s = (name or "").strip().lower()
    s = _DIGIT.sub("", s)
    s = _PUNCT.sub("", s)
    for modifier in _MODIFIERS:
        if modifier in s and s != modifier:
            s = s.replace(modifier, "")
    return s


def keys_of(row) -> tuple[str, ...]:
    """이 행이 응답하는 정규화 이름 전부 — 대표 이름과 별칭."""
    aliases = tuple(a for a in (row.aliases_norm or "").split("|") if a)
    return ((row.name_norm,) if row.name_norm else ()) + aliases


def match_in_rows(rows, name: str):
    """정규화된 name 을 rows 에 매칭. 붙지 않으면 None.

    1) 정확 일치 — 이름이든 별칭이든
    2) 표 이름이 질의에 포함 → 가장 긴(= 가장 구체적인) 것
       (`아침 러닝머신 유산소` → `러닝머신`)
    3) 질의가 표 이름의 조각 → **유일할 때만** (`랫풀` → `랫풀다운`)
    """
    q = normalize(name)
    if not q:
        return None

    for row in rows:
        if q in keys_of(row):
            return row

    contained = [
        (key, row) for row in rows for key in keys_of(row) if key and key in q
    ]
    if contained:
        return max(contained, key=lambda pair: len(pair[0]))[1]

    containing = {
        id(row): row for row in rows for key in keys_of(row) if key and q in key
    }
    if len(containing) == 1:
        return next(iter(containing.values()))

    return None
