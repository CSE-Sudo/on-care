"""가입 동의 — 약관·개인정보 수집·건강정보(민감정보)·만 14세 확인. (#2819)

두 앱의 가입 흐름에는 동의 절차가 없었다. 회원 앱은 링크도 체크도 없이 가입이
끝났고, 트레이너 웹은 "가입하면 동의하는 것으로 봅니다"라는 간주 동의 문구뿐이었다.
분쟁·점검 때 **어느 문서의 어느 버전에 언제 동의했는지** 보일 수 있도록 항목마다
행을 남긴다(`user_consents`).

**문서 버전**은 [CURRENT_VERSIONS] 한 곳에서 정한다. 약관·처리방침 본문을 고치면
(#2820) 그 문서의 버전을 올린다. 그러면 옛 버전에만 동의한 계정은 필수 항목이
비어 있는 것으로 보이고, 다음 로그인 때 앱이 동의 화면을 다시 띄운다.

**필수 항목은 역할마다 다르다.** 건강정보 처리 동의는 식단·운동·신체 정보를
기록하는 회원 앱에만 있다 — 트레이너 계정은 자기 건강정보를 기록하지 않는다.

**동의 목록을 아예 보내지 않은 가입**(옛 앱 빌드·소셜 첫 가입)은 막지 않는다.
계정은 만들되 동의 행이 없으므로 [pending_kinds] 가 필수 항목을 모두 돌려주고,
앱은 로그인 직후 동의 화면을 거치게 한다. 목록을 보냈는데 필수 항목이 빠졌다면
그것은 화면의 잘못이라 422 로 거절한다.

국외 이전 동의는 아직 항목에 없다. 필요 여부는 처리방침 정비(#2820)에서 정해지고,
정해지면 [Kind] 와 역할별 필수 집합에 한 줄씩 더한다.
"""
from __future__ import annotations

from collections.abc import Iterable
from datetime import datetime
from typing import Literal

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core import clock
from app.models.models import User, UserConsent

#: 동의 항목. 앱과 같은 철자다.
Kind = Literal["terms", "privacy", "health", "age14", "marketing"]

TERMS: Kind = "terms"
PRIVACY: Kind = "privacy"
HEALTH: Kind = "health"
AGE14: Kind = "age14"
MARKETING: Kind = "marketing"

ALL_KINDS: tuple[Kind, ...] = (TERMS, PRIVACY, HEALTH, AGE14, MARKETING)

#: 항목마다 지금 동의받는 문서의 버전. 본문을 고치면 그 항목만 올린다.
#: 만 14세 확인·마케팅 수신은 문서가 아니지만, 문구가 바뀌면 같은 방식으로 올린다.
CURRENT_VERSIONS: dict[str, str] = {
    TERMS: "2026-10-01",
    PRIVACY: "2026-10-01",
    HEALTH: "2026-10-01",
    AGE14: "2026-10-01",
    MARKETING: "2026-10-01",
}

#: 역할별 필수 항목. 마케팅 수신은 어느 쪽에서도 선택이다.
REQUIRED_BY_ROLE: dict[str, frozenset[str]] = {
    "member": frozenset({TERMS, PRIVACY, HEALTH, AGE14}),
    "trainer": frozenset({TERMS, PRIVACY, AGE14}),
}


def required_for(role: str) -> frozenset[str]:
    """[role] 계정이 반드시 동의해야 하는 항목. 모르는 역할은 회원으로 본다."""
    return REQUIRED_BY_ROLE.get(role, REQUIRED_BY_ROLE["member"])


def missing_required(role: str, kinds: Iterable[str]) -> list[str]:
    """[kinds] 에 빠진 필수 항목. 정렬해 돌려준다 — 오류 응답이 매번 같도록."""
    return sorted(required_for(role) - set(kinds))


def record(
    db: Session,
    user_id: str,
    kinds: Iterable[str],
    *,
    now: datetime | None = None,
) -> None:
    """[kinds] 를 지금 버전으로 남긴다. 커밋은 부르는 쪽이 한다.

    같은 항목·같은 버전에 이미 철회되지 않은 동의가 있으면 새로 쓰지 않는다 —
    처음 동의한 시각이 그대로 남아야 한다.

    철회했던 동의를 같은 버전으로 다시 받으면 그 줄을 되살린다. 항목·버전마다
    한 줄만 둘 수 있어(`uq_user_consents_user_kind_version`) 새 줄을 쓰면
    고유 제약에 걸린다. 다시 동의한 시각을 새로 적는다.
    """
    at = now or clock.now()
    wanted = {kind for kind in kinds if kind in CURRENT_VERSIONS}
    if not wanted:
        return
    current = {
        row.kind: row
        for row in db.scalars(
            select(UserConsent).where(
                UserConsent.user_id == user_id,
                UserConsent.kind.in_(wanted),
            )
        )
        if row.version == CURRENT_VERSIONS[row.kind]
    }
    for kind in sorted(wanted):
        row = current.get(kind)
        if row is None:
            db.add(
                UserConsent(
                    user_id=user_id,
                    kind=kind,
                    version=CURRENT_VERSIONS[kind],
                    agreed_at=at,
                )
            )
        elif row.revoked_at is not None:
            row.revoked_at = None
            row.agreed_at = at


def agreed_kinds(db: Session, user_id: str) -> set[str]:
    """지금 버전에 철회되지 않은 동의가 남아 있는 항목."""
    rows = db.scalars(
        select(UserConsent).where(
            UserConsent.user_id == user_id,
            UserConsent.revoked_at.is_(None),
        )
    )
    return {row.kind for row in rows if CURRENT_VERSIONS.get(row.kind) == row.version}


def pending_kinds(db: Session, user: User) -> list[str]:
    """아직 동의받지 못한 필수 항목. 비어 있으면 앱을 그대로 쓸 수 있다."""
    return sorted(required_for(user.role) - agreed_kinds(db, user.id))


def is_required(db: Session, user: User) -> bool:
    """이 계정이 동의 화면을 거쳐야 하는가."""
    return bool(pending_kinds(db, user))
