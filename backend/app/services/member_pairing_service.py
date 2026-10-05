"""회원-트레이너 연결용 6자리 일회용 동기화 코드. (#1634)

회원이 자기 앱에서 코드를 띄우고, 트레이너가 그 6자리를 입력하면 담당이
성립한다. 에어드랍이 기기를 잇기 전에 여섯 자리를 맞춰 보게 하는 것과 같은
모양이고, 실제 근접 탐지는 하지 않는다 — 코드를 주고받는 것은 사람이다.

**왜 영구 식별자가 아닌가.** 예전에는 `User.id` 를 "내 회원 ID"로 보여 주고
트레이너가 그것을 입력했다. 사람이 읽을 수 있는 값(이름+전화번호 뒤 4자리
같은 것)으로 바꾸는 안도 있었지만 셋이 걸렸다 — 영구적이라 한 번 새면 계속
유효하고, 조합이 적어 추측할 수 있고, 식별자에 개인정보가 들어간다. 일회용
코드는 셋을 한 번에 푼다.

**발급이 곧 동의다.** 담당 관계는 상대의 식단·건강 기록을 여는 권한이라
데이터 공유 동의가 필요한데(#1022), 회원이 코드를 띄운 화면이 공유 범위를
말하고 그 코드를 직접 불러 준다. 그래서 발급 시각이 동의 시각이 되고,
트레이너가 코드를 쓰는 순간 담당이 바로 성립한다 — 회원에게 한 번 더
수락받을 이유가 없다.

**쓰기 전에 한 번 확인시킨다.** 여섯 자리를 잘못 누르면 남의 식단·건강 기록이
열린다 — 되돌릴 수 없는 사고다. 그래서 [peek] 으로 누구인지 보여 준 뒤
[consume] 으로 잇는다. 확인만으로 코드를 태우지 않는 이유는, 확인하고 그만두는
것이 정상 흐름이기 때문이다.

그 대가로 확인 자리가 열거에 열린다. 다만 100만 가지에 5분 만료, 분당 10회
제한이면 한 코드가 살아 있는 동안 시도할 수 있는 것은 쉰 번 남짓이라, 오입력
쪽이 훨씬 무겁다.
"""

from __future__ import annotations

import secrets
from datetime import datetime, timedelta
from typing import NamedTuple

from sqlalchemy import delete, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.models.models import MemberPairingCode

#: 코드 길이. 사람이 한 번에 부르고 받아 적을 수 있는 자릿수이고, 100만 가지라
#: 만료 안에 훑을 수 없다.
CODE_LENGTH = 6

#: 유효 시간. 60초는 트레이너가 앱을 열고 화면을 찾는 사이에 끝나고, 30분은
#: 어깨너머로 본 코드가 쓸모 있게 남는 창이 된다.
TTL = timedelta(minutes=5)

#: 코드가 겹쳤을 때 다시 뽑아 보는 횟수. 살아 있는 코드는 많아야 수천 개라
#: 한 번에 걸릴 일이 거의 없다 — 무한 루프만 막으면 된다.
_MAX_ATTEMPTS = 8


class PairingError(Exception):
    """이 모듈이 화면에 그대로 전할 수 있는 실패."""


class CodeNotFound(PairingError):
    """그 코드가 없거나 이미 쓰였거나 만료됐다.

    셋을 구분해 알려 주지 않는다 — "만료됐어요" 와 "없어요" 가 갈리면 어떤
    코드가 존재하기는 했는지를 알려 주는 셈이다.
    """


def _now() -> datetime:
    from app.core import clock

    return clock.now()


def purge_expired(db: Session) -> None:
    """만료된 코드를 지운다(커밋 없음).

    발급·사용 앞에서 부른다. 만료된 행이 코드 문자열을 붙들고 있으면 새 발급이
    쓸데없이 재추첨하게 되고, 무엇보다 지난 코드가 DB 에 남아 있을 이유가 없다.
    """
    db.execute(
        delete(MemberPairingCode).where(MemberPairingCode.expires_at <= _now())
    )


def _new_code() -> str:
    """앞자리 0 을 포함한 무작위 6자리.

    `secrets` 를 쓰는 것은 이 값이 담당 관계를 여는 열쇠이기 때문이다 —
    `random` 은 예측 가능한 수열이라 이 자리에 쓸 수 없다.
    """
    return f"{secrets.randbelow(10**CODE_LENGTH):0{CODE_LENGTH}d}"


def issue(db: Session, member_id: str) -> MemberPairingCode:
    """회원의 동기화 코드를 발급한다. 커밋까지 한다.

    **유효한 코드가 남아 있으면 그것을 그대로 돌려준다.** 시트를 다시 열 때마다
    새로 뽑으면, 트레이너가 이미 받아 적은 값이 말없이 무효가 된다.
    """
    purge_expired(db)

    existing = db.get(MemberPairingCode, member_id)
    if existing is not None:
        db.commit()
        return existing

    for _ in range(_MAX_ATTEMPTS):
        row = MemberPairingCode(
            member_id=member_id,
            code=_new_code(),
            expires_at=_now() + TTL,
        )
        db.add(row)
        try:
            db.commit()
        except IntegrityError:
            # 남의 살아 있는 코드와 겹쳤다. 다시 뽑는다.
            db.rollback()
            continue
        db.refresh(row)
        return row

    raise PairingError("연결 코드를 만들지 못했어요. 잠시 후 다시 시도해 주세요.")


def revoke(db: Session, member_id: str) -> None:
    """회원이 코드 화면을 닫았다. 남은 코드를 버린다(커밋한다).

    만료를 기다리지 않는 이유는 회원이 "그만두겠다"고 표시한 것이기 때문이다 —
    발급이 동의였으니 취소도 즉시 반영돼야 한다.
    """
    db.execute(
        delete(MemberPairingCode).where(MemberPairingCode.member_id == member_id)
    )
    db.commit()


class ConsumedCode(NamedTuple):
    """쓰인 코드가 남긴 것 — 누구의 코드였고, 언제 동의한 것인가."""

    member_id: str
    #: 발급 시각 = 데이터 공유 동의 시각. 담당 링크에 그대로 실린다 (#1022).
    consented_at: datetime


def _find(db: Session, code: str) -> MemberPairingCode:
    """유효한 코드 행. 없으면 [CodeNotFound]."""
    normalized = "".join(ch for ch in code if ch.isdigit())
    if len(normalized) != CODE_LENGTH:
        raise CodeNotFound("연결 코드가 맞지 않아요. 회원 화면의 6자리를 확인해 주세요.")

    row = db.scalar(
        select(MemberPairingCode).where(
            MemberPairingCode.code == normalized,
            MemberPairingCode.expires_at > _now(),
        )
    )
    if row is None:
        raise CodeNotFound("연결 코드가 맞지 않아요. 회원 화면의 6자리를 확인해 주세요.")
    return row


def peek(db: Session, code: str) -> ConsumedCode:
    """코드가 누구의 것인지 보되 **쓰지 않는다.** 커밋하지 않는다.

    트레이너가 연결 전에 "이 고객이 맞나요?" 를 확인하는 자리다. 확인만으로
    코드가 사라지면, 확인하고 그만둔 회원이 아무 잘못 없이 다시 띄워야 한다.
    """
    purge_expired(db)
    row = _find(db, code)
    return ConsumedCode(member_id=row.member_id, consented_at=row.created_at)


def consume(db: Session, code: str) -> ConsumedCode:
    """코드를 쓰고 누구의 것이었는지 돌려준다. **커밋하지 않는다.**

    커밋을 부르는 쪽에 맡기는 것은 담당 링크 생성과 같은 트랜잭션이어야 하기
    때문이다. 코드만 지워지고 링크는 안 생긴 상태가 되면 회원은 코드를 다시
    받아야 하고, 그 사이 트레이너에게는 성공한 것처럼 보인다.
    """
    purge_expired(db)
    row = _find(db, code)
    used = ConsumedCode(member_id=row.member_id, consented_at=row.created_at)
    db.delete(row)
    return used
