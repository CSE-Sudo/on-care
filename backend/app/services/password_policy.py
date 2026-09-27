"""새 비밀번호의 서버 기준. (#1555)

가입 스키마의 비밀번호가 그냥 문자열이라, 앱을 거치지 않은 요청(직접 호출·옛
빌드)은 빈 문자열이나 한 글자짜리 비밀번호로도 계정을 만들 수 있었다. 두 앱의
가입 화면은 `oncare_ui` 의 `AppInputRules.signUpPassword` 로 미리 걸러 주지만,
그건 보내기 전에 고칠 수 있게 하는 안내일 뿐이다. 여기 규칙이 저장되는 값의
기준이고, 앱 규칙은 같은 것을 미리 보여 주는 쪽이다.

**기준은 앱 가입 화면과 같다.** 8자 이상, 영문과 숫자를 각각 1자 이상. 서버가
더 엄격하면 "화면에서는 괜찮다는데 가입이 안 된다" 가 되고, 더 느슨하면 앱을
거치지 않은 요청만 약한 비밀번호를 쓸 수 있다.

**상한은 두 가지다.**

* **64자.** 문장형 비밀번호(passphrase)를 쓰기에 넉넉하고, 그 이상은 입력 실수나
  비정상 요청일 가능성이 크다.
* **UTF-8 72바이트.** 비밀번호는 bcrypt 로 저장하는데, bcrypt 는 앞 72바이트만
  본다. 그보다 긴 값을 받으면 73바이트째부터는 아무렇게나 쳐도 로그인이 되는,
  사용자가 모르는 약점이 생기고, 지금 쓰는 bcrypt 5 는 아예 ValueError 를 던져
  가입·변경이 500 으로 떨어진다. 영문·숫자만 쓰면 64자가 먼저 걸리지만 한글은
  한 글자에 3바이트, 이모지는 4바이트라 64자 안에서도 72바이트를 넘을 수 있다.

**글자 수는 코드 포인트로 센다.** 앱(Dart)도 `runes` 로 세도록 맞췄다 — 기본
`String.length` 는 UTF-16 단위라 이모지 한 개를 두 글자로 세어, 같은 값을 두
쪽이 다르게 판정했다.

**공백은 비밀번호의 일부다.** 앞뒤 공백을 잘라내지 않는다 — 앱이 친 그대로 보내고
로그인도 그대로 비교하므로, 여기서만 자르면 가입한 비밀번호로 로그인하지 못한다.
공백만 친 값은 영문·숫자가 없어 규칙에서 걸린다.

**기존 계정의 로그인은 막지 않는다.** 이 기준은 새로 정하는 비밀번호(가입·변경)에만
적용한다. 규칙 이전에 만든 계정은 비밀번호가 기준에 못 미쳐도 그대로 로그인된다.

오류는 `PydanticCustomError` 로 던져 422 응답의 `detail[].type` 에 코드가 실린다
(`password_empty`·`password_weak`·`password_too_long`). 앱은 문장이 아니라 이
코드로 자기 로케일의 문구를 고른다.
"""

from __future__ import annotations

import re

from pydantic_core import PydanticCustomError

from app.core.security import BCRYPT_MAX_BYTES

#: 최소 글자 수. `AppInputRules.passwordMinLength` 와 같다.
PASSWORD_MIN_LENGTH = 8

#: 최대 글자 수(코드 포인트). `AppInputRules.passwordMaxLength` 와 같다.
PASSWORD_MAX_LENGTH = 64

#: 최대 UTF-8 바이트. bcrypt 가 보는 길이(`security.BCRYPT_MAX_BYTES`)다.
#: `AppInputRules.passwordMaxBytes` 와 같다.
PASSWORD_MAX_BYTES = BCRYPT_MAX_BYTES

#: 422 `detail[].type` 에 실리는 코드. 앱이 이 값으로 문구를 고른다.
CODE_EMPTY = "password_empty"
CODE_WEAK = "password_weak"
CODE_TOO_LONG = "password_too_long"

# 앱(`AppInputRules._letter`·`_digit`)과 같은 범위. 파이썬 `\d` 는 전각·아라비아
# 숫자까지 받으므로 ASCII 로 못박는다 — Dart `\d` 는 ASCII 만 본다.
_LETTER = re.compile(r"[A-Za-z]")
_DIGIT = re.compile(r"[0-9]")


def check_new_password(value: str) -> str:
    """새로 정하는 비밀번호가 기준에 맞는지 본다. 값은 바꾸지 않고 그대로 돌려준다."""
    if value == "":
        raise PydanticCustomError(CODE_EMPTY, "비밀번호를 입력해 주세요.")
    if (
        len(value) > PASSWORD_MAX_LENGTH
        or len(value.encode("utf-8")) > PASSWORD_MAX_BYTES
    ):
        raise PydanticCustomError(
            CODE_TOO_LONG,
            "비밀번호는 {max_length}자(UTF-8 {max_bytes}바이트)까지 입력할 수 있습니다.",
            {"max_length": PASSWORD_MAX_LENGTH, "max_bytes": PASSWORD_MAX_BYTES},
        )
    if (
        len(value) < PASSWORD_MIN_LENGTH
        or not _LETTER.search(value)
        or not _DIGIT.search(value)
    ):
        raise PydanticCustomError(
            CODE_WEAK,
            "비밀번호는 영문과 숫자를 포함해 {min_length}자 이상이어야 합니다.",
            {"min_length": PASSWORD_MIN_LENGTH},
        )
    return value

