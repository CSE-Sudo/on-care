"""음식명 → 공공 식품영양성분 DB 매칭.

정규화(normalize)와 후보 매칭(match_in_rows)은 순수 함수로, 모델/DB 의존이 없어
로컬 유닛 테스트가 가능하다. DB 조회가 필요한 match_food 만 지연 import 한다.

매칭 전략(오탐 < 폴백 원칙: 틀린 영양가보다 추정 유지가 낫다):
  0) 질의 정리       : 끝의 양 표기(`1병`·`2인분`·`한 조각`·`(1개)`)와 괄호 설명을 뗀다
  1) 정확 일치       : 정규화 이름이 표 이름이나 별칭(ALIASES)과 같다
  2) 머리 일치       : 표 이름이 질의의 **끝**에 붙으면 가장 긴 것
     (예: "점심에 먹은 김치찌개 1인분" → "김치찌개", "야채비빔밥" → "비빔밥")
  3) 유일 머리 일치  : 질의가 정확히 한 표 이름의 **끝부분**일 때만(모호하면 폴백)
  4) 표기 변형       : 위에서 못 찾으면 `계란` → `달걀` 로 바꿔 한 번 더

## 왜 "끝" 인가 (#2096)

한국어 음식 이름은 **마지막 말이 무엇인지를 정한다.** `고구마맛탕` 은 맛탕이고
`소금빵` 은 빵이다. 예전에는 표 이름이 질의 **어디에든** 들어 있으면 붙였더니
`소금빵` → `소금`, `보리차` → `보리`, `무 절임(치킨무)` → `치킨` 처럼 앞에 붙은 재료로
갔다. 공공 표준 2,130행을 자기 행을 뺀 표에 하나씩 질의해 보면(DB 에 없는 이름이
들어온 상황) 붙은 매칭 1,325건 중 627건이 칼로리가 50% 넘게 어긋났다. 끝 조건을
걸면 붙는 매칭은 646건으로 줄고, 그중 50% 넘게 어긋나는 것은 203건이다 — 못 붙은
이름은 인식기 추정치를 그대로 둔다.

## 한 글자 이름은 정확 일치로만

`밀`·`무`·`조`·`마`·`파`·`김`·`피` 같은 한 글자 행은 끝 조건으로도 걸러지지 않는다 —
`오트밀` → `밀`(밀가루 값), `커피` → `피`, `튀김` → `김`, `고구마` → `마`. 한 글자 표
이름(과 별칭 `밥`)은 질의가 정확히 그 글자일 때만 붙는다.
"""
from __future__ import annotations

import re

_DIGIT = re.compile(r"\d+")
_PUNCT = re.compile(r"[\s()\[\]{}·.,/\\\-_+~!?'\"]+")

#: 이보다 짧은 이름은 포함 관계(2·3단계)로 붙지 않는다 — 정확 일치만.
_MIN_PARTIAL = 2

# 양을 세는 말. **숫자나 띄어 쓴 수사 뒤에 올 때만** 뗀다 — `된장`·`메추리알` 처럼
# 이름이 이 말로 끝나는 음식이 있어서, 앞에 수가 없으면 이름의 일부로 본다.
_COUNTER = (
    "인분|개|병|잔|컵|그릇|공기|조각|봉지|봉|접시|캔|팩|마리|판|통|송이|줌|입|"
    "숟가락|스푼|스쿱|큰술|작은술|줄|쪽|장|알|g|그램|kg|ml|l"
)
_QUANTITY = re.compile(
    rf"(?:\s*\(?\s*\d+(?:\.\d+)?\s*(?:{_COUNTER})\s*\)?"
    rf"|\s+(?:한|두|세|네|다섯|반)\s*(?:{_COUNTER}))\s*$",
    re.IGNORECASE,
)
# 끝의 괄호 설명(`김치찌개(돼지고기)`). 떼지 않으면 괄호 안이 이름의 끝이 된다.
_TRAILING_NOTE = re.compile(r"\s*\([^()]*\)\s*$")

#: 흔한 표기 → 표에 있는 이름. 키도 값도 사람이 읽는 표기로 적고 비교는 정규화해서 한다.
#: 대상이 표에 없으면 조용히 무시된다(그 DB 에서는 별칭이 없는 것과 같다).
ALIASES: dict[str, str] = {
    # `밥` 은 `쌀밥`·`잡곡밥`·`공기밥` … 여러 행의 끝이라 3단계에서 떨어진다.
    "밥": "공기밥",
    "공깃밥": "공기밥",
    "흰밥": "공기밥",
    "흰쌀밥": "공기밥",
    "백미밥": "공기밥",
    "스크램블 에그": "스크램블드에그",
    "스크램블": "스크램블드에그",
    "에그 스크램블": "스크램블드에그",
    "오트밀 죽": "오트밀",
    "그릭 요구르트": "그릭 요거트",
    # 토핑으로 등록된 그래놀라다. 이름 끝이 `토핑` 이라 3단계로는 붙지 않는다.
    "그래놀라": "그래놀라 토핑",
    # 공공 표준의 `파스타`·`치킨` 은 건면·포장 가공품이라 다른 이름으로 옮겼다
    # (`scripts/import_food_nutrients._RENAMES`). 일상어는 요리로 보낸다. (#2100)
    "파스타": "스파게티",
    "치킨": "후라이드치킨",
    # 공공 표준의 커피는 프랜차이즈 음료와 원두 추출액뿐이다. 그냥 "커피" 는 아메리카노다.
    "커피": "아메리카노",
    # 끝말 규칙으로는 `스테이크`(소고기 부채살)에 붙는다.
    "닭가슴살 스테이크": "닭가슴살",
    "연어 스테이크": "연어",
    # 떠먹는 요구르트는 식품 유형상 농후발효유다(공공 표준 1,628개 제품의 중앙값).
    # 별칭이 없으면 3단계에서 `그릭 요거트` 로 가 단백질이 두 배가 된다.
    "요거트": "농후발효유",
    "떠먹는 요거트": "농후발효유",
    "떠먹는 요구르트": "농후발효유",
}

#: 같은 음식의 다른 표기. 이름 **안의** 한 부분을 바꿔 보는 것이라 별칭과 따로 둔다
#: (`삶은 계란`·`계란국`·`계란말이` 를 하나하나 적지 않아도 된다). 공공 표준은 `달걀`
#: 로 적고, 사람과 인식기는 `계란` 을 더 많이 쓴다.
_SPELLINGS: tuple[tuple[str, str], ...] = (("계란", "달걀"),)


def normalize(name: str) -> str:
    """매칭용 정규화: 소문자화 + 숫자/공백/구두점 제거."""
    s = (name or "").strip().lower()
    s = _DIGIT.sub("", s)
    s = _PUNCT.sub("", s)
    return s


_ALIAS_KEYS: dict[str, str] = {normalize(k): normalize(v) for k, v in ALIASES.items()}
_SPELLING_KEYS: tuple[tuple[str, str], ...] = tuple(
    (normalize(a), normalize(b)) for a, b in _SPELLINGS
)


def _strip(name: str, pattern: re.Pattern[str]) -> str:
    s = (name or "").strip()
    while True:
        t = pattern.sub("", s)
        if t == s or not t.strip():
            return s
        s = t


def _query_forms(name: str) -> tuple[list[str], str]:
    """(정확 일치에 쓸 형태들, 포함 매칭에 쓸 머리).

    정확 일치는 괄호까지 붙은 형태로도 본다 — `달걀부침(달걀후라이)` 처럼 괄호가
    이름의 일부인 행이 있다.
    """
    no_qty = _strip(name, _QUANTITY)
    head = no_qty
    while True:
        t = _strip(_strip(head, _TRAILING_NOTE), _QUANTITY)
        if t == head:
            break
        head = t
    forms = [normalize(name), normalize(no_qty), normalize(head)]
    exact = [f for i, f in enumerate(forms) if f and f not in forms[:i]]
    return exact, normalize(head)


def _keys(rows) -> list[tuple[str, object]]:
    """(키, 행) — 표 이름과, 그 행을 가리키는 별칭."""
    pairs = [(r.name_norm, r) for r in rows if r.name_norm]
    by_norm = dict(pairs)
    for alias, target in _ALIAS_KEYS.items():
        row = by_norm.get(target)
        if row is not None and alias not in by_norm:
            pairs.append((alias, row))
    return pairs


def _match(pairs, exact: list[str], head: str):
    """(행, 정확 일치인가). 못 찾으면 None."""
    # 1) 정확 일치
    for q in exact:
        for key, row in pairs:
            if key == q:
                return row, True

    if len(head) < _MIN_PARTIAL:
        return None

    # 2) 표 이름이 질의의 끝 → 가장 구체적인(긴) 이름
    tails = [
        (key, row)
        for key, row in pairs
        if _MIN_PARTIAL <= len(key) < len(head) and head.endswith(key)
    ]
    if tails:
        return max(tails, key=lambda pair: len(pair[0]))[1], False

    # 3) 질의가 정확히 한 표 이름의 끝부분 → 유일할 때만
    containing = {
        id(row): row for key, row in pairs if len(key) > len(head) and key.endswith(head)
    }
    if len(containing) == 1:
        return next(iter(containing.values())), False

    return None


def find_in_rows(rows, name: str):
    """name 을 rows 에 매칭한 (행, 정확 일치인가). 없으면 None. (#2107)

    **정확 일치**는 같은 음식이다 — 정규화한 이름·양 표기를 뗀 이름·끝 괄호를 뗀
    이름이 표 이름이나 별칭과 같거나, 표기 변형(`계란` → `달걀`)으로 그렇게 된
    경우다. 끝말·끝부분 일치(2·3단계)는 **비슷한 음식**이다: `야채비빔밥` 은
    `비빔밥` 에 붙지만 같은 음식이라고 말할 수는 없다(위 #2096 점검에서 끝말로
    붙은 646건 중 203건이 칼로리 50% 넘게 어긋났다).

    사진 분석은 이 구분 없이 붙은 값을 쓴다 — 확인할 사람이 없어서다. 수정 화면은
    회원이 있으니, 같은 음식이면 곧바로 채우고 비슷한 음식이면 보여 주고 고르게 한다.
    """
    exact, head = _query_forms(name)
    if not exact:
        return None
    pairs = _keys(rows)

    found = _match(pairs, exact, head)
    if found is not None:
        return found

    # 4) 표기 변형으로 한 번 더
    for variant, canonical in _SPELLING_KEYS:
        if variant in head:
            found = _match(
                pairs,
                [q.replace(variant, canonical) for q in exact],
                head.replace(variant, canonical),
            )
            if found is not None:
                return found
    return None


def match_in_rows(rows, name: str):
    """name 을 rows(각 원소는 .name_norm 속성 보유)에 매칭. 없으면 None."""
    found = find_in_rows(rows, name)
    return found[0] if found is not None else None


def match_food(db, name: str):
    """food_nutrients 전건에 매칭(작은 참조표라 전건 로드로 충분 — 로드는 캐시된다)."""
    from app.services.nutrition.table import load_rows

    return match_in_rows(load_rows(db), name)
