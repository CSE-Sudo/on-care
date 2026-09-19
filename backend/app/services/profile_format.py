"""이름·생년월일의 서버 형식 기준. (#1887)

연락처(#1780 `contact_format`)와 같은 이유로 여기에 둔다 — 앱의 입력 검사는
보내기 전에 고칠 수 있게 알려 주는 안내일 뿐이고, 앱을 거치지 않은 요청은
아무 값이나 그대로 컬럼에 닿았다. 그 결과가 두 가지로 갈렸다.

* **컬럼 길이를 넘기면 500.** `users.name` 은 `String(100)`,
  `health_profiles.birth_date` 는 `String(10)` 이라 그보다 긴 값은 저장 단계에서
  `value too long` 으로 터졌다 — 무엇이 잘못됐는지 알 수 없는 오류다.
* **들어가는 길이면 무엇이든 200.** `birth_date` 에 `asdfghjkl` 이 저장되면
  트레이너의 담당 요청 확인 화면에서 나이가 조용히 비어 보인다
  (`trainer_client_invite_service._age_on` 이 파싱에 실패한다) — 6자리 코드로
  연결할 때 "이 사람이 맞나" 를 확인하는 근거 하나가 사라진다.

**이름은 비울 수 없다.** 가입 화면이 필수로 받는 값인데 프로필 수정에서 빈 값이
통과하면 그 필수가 무의미해지고, 이름이 빈 회원이 트레이너 로스터·채팅·상담
카드에 공백으로 뜬다. 반대로 **생년월일은 비울 수 있다** — 넣을 자리가 없던
시절에 가입한 회원과 소셜 로그인 가입자에게는 처음부터 없는 값이다.
"""

from __future__ import annotations

import re
from datetime import date

#: 저장 가능한 이름 길이. `users.name` 컬럼(`String(100)`)에 맞춘다 — 넘치면
#: DB 오류로 500 이 되므로, 형식 검사에서 422 로 잡는다.
NAME_MAX_LENGTH = 100

#: `YYYY-MM-DD` 의 길이. `health_profiles.birth_date` 컬럼(`String(10)`)과 같다.
BIRTH_DATE_LENGTH = 10

#: 날짜 표기. 길이만 맞는 값(`9999-99-99`)은 여기를 지나 [date.fromisoformat]
#: 에서 걸린다 — 두 단계로 나눠 보는 이유는 아래 [clean_birth_date] 에 적었다.
_YMD = re.compile(r"^\d{4}-\d{2}-\d{2}$")


class InvalidName(ValueError):
    """이름이 비었거나 저장 가능한 길이를 넘는다."""


class InvalidBirthDate(ValueError):
    """생년월일이 `YYYY-MM-DD` 로 읽히지 않는다."""


def clean_name(value: str) -> str:
    """앞뒤 공백을 자른 이름. 빈 값과 너무 긴 값은 받지 않는다.

    공백만 친 값은 잘라내면 비므로 빈칸과 같이 본다 — 회원앱
    `AppInputRules.name` 도 같은 방식이다.
    """
    name = value.strip()
    if not name:
        raise InvalidName("이름을 입력해 주세요.")
    if len(name) > NAME_MAX_LENGTH:
        raise InvalidName(f"이름은 {NAME_MAX_LENGTH}자까지 입력할 수 있습니다.")
    return name


def name_from_email(email: str) -> str:
    """이름을 보내지 않은 가입에 쓸 기본 이름 — 이메일 로컬 파트.

    **자르는 것이 여기 있는 이유다.** 이메일은 255자까지 받는데(#1780)
    `users.name` 은 100자라, 긴 주소로 가입하면 이름을 안 보냈을 뿐인데 가입이
    500 으로 떨어졌다. 자기가 무엇을 잘못했는지 알 방법이 없는 실패다.

    자른 값이 이름으로 이상해 보일 수는 있지만, 어차피 임시로 채우는 값이고
    회원은 MY 탭에서 언제든 고칠 수 있다 — 가입이 되는 쪽이 낫다.
    """
    local, _, _domain = email.partition("@")
    return local.strip()[:NAME_MAX_LENGTH]


def clean_birth_date(value: str) -> str:
    """저장할 생년월일 표기. 빈 값은 빈 값 그대로 둔다.

    **날짜인지까지 본다.** 표기만 보면 `1990-13-45` 가 통과하는데, 그런 값은
    저장된 뒤에 나이를 세는 쪽에서 조용히 실패한다 — 422 로 지금 막는 편이
    낫다. 그렇다고 [date.fromisoformat] 에만 맡길 수는 없다: 파이썬 3.11 부터는
    `19900101` 이나 `1990-01-01T00:00:00` 같은 표기도 받아들여, 컬럼
    길이(10)를 넘는 값이 형식 검사를 지나 버린다.
    """
    birth_date = value.strip()
    if not birth_date:
        return ""
    if not _YMD.match(birth_date):
        raise InvalidBirthDate("생년월일을 YYYY-MM-DD 형식으로 입력해 주세요.")
    try:
        date.fromisoformat(birth_date)
    except ValueError:
        raise InvalidBirthDate("실제 날짜가 아닙니다.") from None
    return birth_date
