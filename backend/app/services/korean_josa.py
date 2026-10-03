"""이름 뒤에 붙는 한국어 조사(`을/를`·`은/는`·`이/가`·`으로/로`)를 고르는 규칙. (#1177, #2897)

두 앱의 `oncare_rules` 패키지(`shared/oncare_rules/lib/src/korean_josa.dart`)와 **같은
규칙**이다. 예전에는 받침 판정이 서버·두 앱에 다섯 벌 있었고 규칙이 세 갈래였다 —
괄호로 끝나는 이름(`레그 프레스(머신)`)이 주간 피드백 초안에서는 `는`, 운동 조언에서는
`은` 을 받았고, 영문 이름에는 `을(를)` 처럼 두 꼴이 함께 적혔다. 같은 입력 표
(`shared/oncare_rules/vectors/korean_josa.json`)로 양쪽을 함께 검사한다.

규칙:

1. 끝의 공백과 닫는 괄호(`)`·`]`·`}`)를 벗기고 그 앞 글자로 본다.
2. 한글 음절이면 받침으로 본다.
3. 숫자면 읽는 소리로 본다 — 영·일·삼·육·칠·팔(0·1·3·6·7·8)에 받침이 있다.
4. 그 밖(영문·`%`·단위·빈 문자열)은 받침 없음으로 본다. 화면에 쓰는 단위는 모두
   모음으로 끝나게 읽히고(퍼센트·밀리그램), 틀리더라도 `…를` 이 `…을` 보다 눈에 덜
   걸린다. **두 꼴(`을(를)`)은 쓰지 않는다** — 사람이 쓴 글로 읽히지 않는다(#1177).

`으로/로` 는 받침이 `ㄹ` 이면 `로` 다(`3일로`·`덤벨 컬로`).
"""

from __future__ import annotations

import re

#: 끝에서 벗겨 낼 공백·닫는 괄호.
_TRAILING = re.compile(r"[\s)\]}]+\Z")

#: 읽는 소리에 받침이 있는 숫자(영·일·삼·육·칠·팔).
_DIGITS_WITH_FINAL = frozenset("013678")

#: 읽는 소리의 받침이 `ㄹ` 인 숫자(일·칠·팔).
_DIGITS_WITH_RIEUL = frozenset("178")

#: 받침 `ㄹ` 의 종성 번호.
_RIEUL = 8


def _last(word: str) -> str | None:
    """판정에 쓰는 마지막 글자. 벗기고 나서 비면 None."""
    stripped = _TRAILING.sub("", word)
    return stripped[-1] if stripped else None


def _is_hangul_syllable(ch: str) -> bool:
    return 0xAC00 <= ord(ch) <= 0xD7A3


def ends_with_hangul(word: str) -> bool:
    """공백·닫는 괄호를 벗긴 뒤 한글 음절로 끝나는가.

    "받침을 판정할 수 없다" 가 아니라 "한글 이름이 아니다" 를 뜻한다 — 조언 문장이
    한글 이름이 아닐 때(`Squat`, `플랭크 60`) 조사 없이 읽히는 `_plain` 틀을 고르는
    기준이다.
    """
    last = _last(word)
    return last is not None and _is_hangul_syllable(last)


def has_final_consonant(word: str) -> bool:
    """마지막 글자를 소리 내어 읽었을 때 받침이 있는가. 규칙은 모듈 설명."""
    last = _last(word)
    if last is None:
        return False
    if _is_hangul_syllable(last):
        return (ord(last) - 0xAC00) % 28 != 0
    return last in _DIGITS_WITH_FINAL


def _final_is_rieul(word: str) -> bool:
    last = _last(word)
    if last is None:
        return False
    if _is_hangul_syllable(last):
        return (ord(last) - 0xAC00) % 28 == _RIEUL
    return last in _DIGITS_WITH_RIEUL


def particle(word: str, with_final: str, without_final: str) -> str:
    """`word` 뒤에 올 조사 — 받침이 있으면 `with_final`, 없으면 `without_final`.

    `으로`/`로` 쌍이면 받침이 `ㄹ` 일 때도 `로` 다. 단어는 붙이지 않고 조사만
    돌려준다.
    """
    if not has_final_consonant(word):
        return without_final
    if with_final == "으로" and _final_is_rieul(word):
        return without_final
    return with_final


def with_particle(word: str, with_final: str, without_final: str) -> str:
    """`word` 에 `particle` 로 고른 조사를 붙인다."""
    return f"{word}{particle(word, with_final, without_final)}"
