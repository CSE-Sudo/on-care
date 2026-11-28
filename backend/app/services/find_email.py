"""아이디(가입 이메일) 찾기(#3337) — 이름과 전화번호로 가려진 이메일을 알려 준다.

번호의 주인을 확인할 수단(문자 인증)이 없으므로, 이름과 번호를 아는 누구나 이
경로를 부를 수 있다고 보고 돌려주는 것을 줄인다.

- **이메일은 가려서만 준다**(`ab***@example.com`). 주인은 이 정도로 어느 주소였는지
  떠올리지만, 남은 그 주소로 로그인·재설정을 시도할 수 없다. 전체 이메일은 어떤
  경우에도 싣지 않는다.
- **찾지 못해도 같은 상태 코드에 빈 목록**이다. 형식만 맞으면 오류가 아니다.
- 전화번호에는 유일성 제약이 없다. 같은 이름·번호의 계정이 여럿이면 모두 가려서
  준다(가입 순).
- 소셜 로그인 전용 계정(비밀번호 없음)은 이메일 대신 가입 수단을 알려 준다. 그
  계정의 이메일은 provider 가 준 것이거나 대체 이메일이라 로그인에 쓰이지 않는다.

회원과 트레이너는 따로 찾는다(#3439). 회원의 번호는 `HealthProfile`, 트레이너의
번호는 `TrainerProfile` 에 있고, 회원 앱은 회원만, 트레이너 웹은 트레이너만 찾는다 —
한쪽 화면에서 다른 역할의 계정이 걸리지 않는다. 가리기·빈 목록·소셜 규칙은 같다.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Literal

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models.models import HealthProfile, SocialAccount, TrainerProfile, User

# 대체 이메일 판정은 공용 규칙 한 곳을 쓴다(#3338). 사람이 받은 주소가 아니라 보여 줄
# 것이 없다.
from app.services.placeholder_email import (
    is_placeholder_email as _is_placeholder_email,
)

#: 가린 자리에 쓰는 글자. 개수는 늘 같다 — 가린 길이로 주소 길이가 드러나지 않는다.
MASK = "***"
#: 로컬 부분에서 보여 주는 글자 수의 상한.
VISIBLE_LOCAL = 2

#: 찾는 계정의 역할. 엔드포인트가 정한다 — 요청 필드로 고르지 않는다(#3439).
Role = Literal["member", "trainer"]

@dataclass(frozen=True)
class FoundAccount:
    """찾은 계정 하나. 전체 이메일은 담지 않는다."""

    #: 가려진 이메일. 소셜 로그인 전용 계정이면 None.
    masked_email: str | None
    #: 연결된 소셜 가입 수단(`kakao`·`google` …), 연결한 순. 없으면 빈 목록.
    providers: tuple[str, ...]


def mask_email(address: str) -> str:
    """응답에 싣는 이메일 가림. 앞 두 글자와 도메인만 남긴다(`ab***@example.com`).

    로컬 부분이 짧으면 덜 보여 준다 — 두 글자 이하인 주소를 두 글자까지 보여 주면
    가린 것이 없다. 한 글자는 반드시 가린다(`a***@…`, 한 글자짜리는 `***@…`).
    """
    local, _, domain = address.partition("@")
    if not domain:
        return MASK
    visible = min(VISIBLE_LOCAL, max(len(local) - 1, 0))
    return f"{local[:visible]}{MASK}@{domain}"


def find_accounts(
    db: Session, *, name: str, phone: str, role: Role = "member"
) -> list[FoundAccount]:
    """이름과 전화번호가 모두 맞는 [role] 계정을 가입 순으로 돌려준다. 없으면 빈 목록.

    번호는 역할의 프로필에서 읽는다 — 회원은 `HealthProfile`, 트레이너는
    `TrainerProfile`(#3439). 역할도 함께 걸러, 프로필 행이 어긋나 있어도 다른 역할의
    계정은 나오지 않는다.

    [phone] 은 저장 표기(`normalize_phone`)여야 한다 — 가입·프로필 수정이 같은 표기로
    저장하므로 그대로 비교한다. 빈 번호로는 찾지 않는다(번호를 넣지 않은 계정이 전부
    걸린다). 이름은 앞뒤 공백과 대소문자를 보지 않는다.

    쉬는 계정은 뺀다 — 로그인할 수 없는 계정의 주소를 알려 줄 이유가 없다.
    """
    wanted = name.strip().lower()
    if not wanted or not phone:
        return []
    if role == "trainer":
        profile, owner, stored_phone = (
            TrainerProfile, TrainerProfile.trainer_id, TrainerProfile.phone
        )
    else:
        profile, owner, stored_phone = (
            HealthProfile, HealthProfile.user_id, HealthProfile.phone
        )
    users = db.scalars(
        select(User)
        .join(profile, owner == User.id)
        .where(
            stored_phone == phone,
            func.lower(func.trim(User.name)) == wanted,
            User.role == role,
            User.is_active.is_(True),
        )
        .order_by(User.created_at, User.id)
    ).all()
    if not users:
        return []
    providers: dict[str, list[str]] = {}
    for user_id, provider in db.execute(
        select(SocialAccount.user_id, SocialAccount.provider)
        .where(SocialAccount.user_id.in_([u.id for u in users]))
        .order_by(SocialAccount.created_at, SocialAccount.id)
    ):
        linked = providers.setdefault(user_id, [])
        if provider not in linked:
            linked.append(provider)

    found: list[FoundAccount] = []
    for user in users:
        linked = tuple(providers.get(user.id, ()))
        social_only = not user.hashed_password or _is_placeholder_email(user.email)
        found.append(
            FoundAccount(
                masked_email=None if social_only else mask_email(user.email),
                providers=linked,
            )
        )
    return found
