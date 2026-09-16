"""가입 연락처(이메일·전화번호)의 서버 형식 기준. (#1780)

두 앱의 가입 화면은 `oncare_ui` 의 `AppInputRules` 로 형식을 미리 걸러 주지만,
그건 사용자가 보내기 전에 고칠 수 있게 하는 안내일 뿐이다. 앱을 거치지 않은
요청(직접 호출·옛 빌드)은 아무 값이나 그대로 저장됐다. 여기 규칙이 저장되는
값의 기준이고, 앱 규칙은 같은 것을 미리 보여 주는 쪽이다.

**이메일은 형식만 보고 값은 바꾸지 않는다.** `email-validator` 가 돌려주는
정규화 형태(도메인 소문자화)로 저장하면, 로그인 조회
(`select(User).where(User.email == form.username)`)와 중복 확인이 대소문자를
그대로 비교하므로 대문자 도메인으로 가입한 사람이 자기가 친 주소로 로그인하지
못한다. 정규화는 그 조회까지 함께 옮겨야 하는 별개의 일이다(#1551).

**전화번호는 한 가지 표기로 정리해 저장한다** — 숫자만 추려 `010-1234-5678`
꼴로 되돌린다. 시드와 기존 프로필이 이미 이 표기라 따로 정리할 데이터가 없고,
트레이너 앱이 회원 연락처를 그대로 그리므로 표기가 섞이면 화면에서 보인다.
"""

from __future__ import annotations

import re

from email_validator import EmailNotValidError, validate_email

#: 휴대전화 숫자 개수(3 + 4 + 4). 회원앱 `AppInputRules.phoneDigits` 와 같다.
PHONE_DIGITS = 11

#: 숫자를 끊는 자리. `010-1234-5678`.
_PHONE_GROUPS = (3, 4, 4)

_NON_DIGIT = re.compile(r"\D")


class InvalidEmail(ValueError):
    """이메일이 형식에 맞지 않는다."""


class InvalidPhone(ValueError):
    """전화번호가 숫자 11자리로 읽히지 않는다."""


def clean_email(value: str) -> str:
    """앞뒤 공백을 자르고 형식을 확인한 이메일. 값 자체는 바꾸지 않는다.

    `check_deliverability=False` 인 이유는 가입 요청이 DNS 조회를 기다리게
    되기 때문이다. 받는 주소가 실제로 살아 있는지는 형식 검사의 일이 아니다.
    """
    email = value.strip()
    if not email:
        raise InvalidEmail("이메일을 입력해 주세요.")
    try:
        validate_email(email, check_deliverability=False)
    except EmailNotValidError as exc:
        raise InvalidEmail("이메일 형식이 올바르지 않습니다.") from exc
    return email


def normalize_phone(value: str) -> str:
    """저장할 전화번호 표기. 빈 값은 빈 값 그대로 둔다.

    빈 값을 통과시키는 것은 전화번호가 선택이기 때문이다 — 트레이너 가입은 이
    값을 쓰지 않고, 회원도 MY 탭에서 나중에 넣을 수 있다.

    숫자만 세므로 `01012345678` 처럼 하이픈 없이 보내도 받는다. 앱보다 느슨한
    쪽이라 앱을 통과한 값이 서버에서 막히는 일은 생기지 않는다.
    """
    phone = value.strip()
    if not phone:
        return ""
    digits = _NON_DIGIT.sub("", phone)
    if len(digits) != PHONE_DIGITS:
        raise InvalidPhone("전화번호를 000-0000-0000 형식으로 입력해 주세요.")
    parts: list[str] = []
    start = 0
    for size in _PHONE_GROUPS:
        parts.append(digits[start : start + size])
        start += size
    return "-".join(parts)
