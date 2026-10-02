"""담당 링크의 데이터 공유 동의 — 부여·철회·열람 판단. (#1022, #1631)

**담당 해제 = 동의 철회다.** 회원이 담당을 끊든(`DELETE /me/coach`,
`DELETE /me/coach/trainer`) 트레이너가 끊든(`DELETE /trainer/clients/{id}`)
링크의 `data_consent_at` 을 비우고 `data_consent_revoked_at` 에 그 시각을 적는다.
회원 계정·트레이너 계정 탈퇴는 링크 행이 `CASCADE` 로 함께 지워지므로 따로
적을 곳이 없다.

철회는 **앞으로의 열람**만 막는다. 이미 트레이너에게 전해진 채팅·리포트·일정은
지우지 않는다 — 그 기록은 두 사람이 함께 쓴 것이다. 회원 앱의 코치 화면은 활성
담당 기준이라 해제한 동안은 비고, 같은 트레이너와 다시 연결하면 다시 보인다.

끊긴 링크를 되살릴 때(상담 수락·담당 요청 수락·연결 코드) 그 연결의 새 동의만
적는다. 새 동의가 없으면 옛 동의는 살아나지 않고, 트레이너는 회원 기록을 열 수
없다. 판단 규칙을 여러 곳이 각자 들고 있으면 한쪽만 고쳐지므로 여기에 모은다.

**동의 이력은 감사 로그가 지킨다(#2830).** 링크의 두 칸은 다시 연결하면 덮어써지고
탈퇴하면 행째 지워진다. 그래서 발급(경로별)·철회(주체별)를 바꿀 때마다
`consent.grant`·`consent.revoke` 를 **같은 트랜잭션에** 얹는다 — 커밋되면 둘 다,
롤백되면 둘 다 없다. 감사 기록에는 대상 회원·트레이너·경로/주체만 적는다.
"""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import ColumnElement, or_, select
from sqlalchemy.orm import Session, object_session

from app.core import clock
from app.models.models import TrainerClient, User
from app.services import audit

#: 동의 발급 경로 — 회원이 띄운 6자리 연결 코드, 트레이너 담당 요청 수락, 상담 신청.
VIA_PAIRING = "pairing"
VIA_INVITE = "invite"
VIA_CONSULTATION = "consultation"

#: 철회 주체.
BY_MEMBER = "member"
BY_TRAINER = "trainer"


def stage_grant(db: Session, *, trainer_id: str, member_id: str, via: str) -> None:
    """동의 발급 감사 기록을 얹는다(커밋 없음). 행위자는 동의한 회원이다."""
    audit.stage(
        db,
        event=audit.CONSENT_GRANT,
        user_id=member_id,
        target_user_id=member_id,
        detail=f"via={via} trainer={trainer_id}",
    )


def stage_revoke(
    db: Session, *, trainer_id: str, member_id: str, by: str, reason: str = ""
) -> None:
    """동의 철회 감사 기록을 얹는다(커밋 없음). 행위자는 철회한 쪽이다."""
    detail = f"by={by} trainer={trainer_id}"
    if reason:
        detail += f" reason={reason}"
    audit.stage(
        db,
        event=audit.CONSENT_REVOKE,
        user_id=trainer_id if by == BY_TRAINER else member_id,
        target_user_id=member_id,
        detail=detail,
    )


def revoke(
    link: TrainerClient, *, at: datetime | None = None, by: str = ""
) -> None:
    """링크의 동의를 철회한다(커밋 없음).

    이미 철회된 링크(동의가 비어 있고 철회 시각이 있는 링크)는 건드리지 않는다 —
    두 번 해제해도 처음 철회한 시각이 남는다. 감사 기록도 처음 한 번만 남는다.

    `by` 는 철회 주체(`member`·`trainer`)다. 링크가 세션에 붙어 있으면 같은
    트랜잭션에 `consent.revoke` 를 얹는다(#2830).
    """
    if link.data_consent_at is None and link.data_consent_revoked_at is not None:
        return
    link.data_consent_at = None
    link.data_consent_revoked_at = at or clock.now()
    db = object_session(link)
    if db is not None:
        stage_revoke(
            db, trainer_id=link.trainer_id, member_id=link.member_id, by=by
        )


def grant(link: TrainerClient, at: datetime | None, *, via: str = "") -> None:
    """이번 연결의 동의 시각을 적는다(커밋 없음).

    `None` 이면 새 동의가 없다는 뜻이다 — 옛 값을 살리지 않고 비운다. 철회
    시각은 지우지 않는다(언제 철회했는지는 이력이다).

    새 동의가 있고 링크가 세션에 붙어 있으면 `consent.grant` 를 얹는다(#2830).
    `via` 는 발급 경로(`pairing`·`invite`·`consultation`)다.
    """
    link.data_consent_at = at
    if at is None:
        return
    db = object_session(link)
    if db is not None:
        stage_grant(
            db, trainer_id=link.trainer_id, member_id=link.member_id, via=via
        )


def blocks_access(link: TrainerClient) -> bool:
    """트레이너가 이 링크로 회원 기록을 열 수 없는가.

    철회된 뒤 새 동의가 없는 링크만 막는다. 동의 기능(#1022) 이전에 만들어져
    동의도 철회도 없는 링크는 그대로 둔다 — 소급해서 막으면 멀쩡한 담당이
    어느 날 기록을 못 보게 된다.
    """
    return link.data_consent_at is None and link.data_consent_revoked_at is not None


def allows_access_clause() -> ColumnElement[bool]:
    """[blocks_access] 의 반대를 SQL 조건으로. 쿼리 쪽 가드가 쓴다."""
    return or_(
        TrainerClient.data_consent_at.is_not(None),
        TrainerClient.data_consent_revoked_at.is_(None),
    )


def stage_account_withdrawal(db: Session, user: User, *, ip: str = "") -> None:
    """탈퇴를 감사 기록으로 얹는다(커밋 없음). 계정 삭제와 같은 트랜잭션에 부른다.

    탈퇴하면 담당 링크가 `CASCADE` 로 행째 사라져 동의가 언제 끝났는지 남지
    않는다(#2830). 그래서 지금 살아 있는 동의(활성이고 막히지 않은 링크)마다
    `consent.revoke`(reason=withdraw)를 먼저 얹고, 마지막에 `account.withdraw`
    를 얹는다. 감사 로그에는 FK 가 없어 계정이 지워져도 기록은 남는다.
    """
    is_trainer = user.role == "trainer"
    owner = TrainerClient.trainer_id if is_trainer else TrainerClient.member_id
    links = db.scalars(
        select(TrainerClient)
        .where(owner == user.id, TrainerClient.active.is_(True))
        .order_by(TrainerClient.id)
    ).all()
    for link in links:
        if blocks_access(link):
            continue
        stage_revoke(
            db,
            trainer_id=link.trainer_id,
            member_id=link.member_id,
            by=BY_TRAINER if is_trainer else BY_MEMBER,
            reason="withdraw",
        )
    audit.stage(
        db,
        event=audit.ACCOUNT_WITHDRAW,
        user_id=user.id,
        target_user_id=None if is_trainer else user.id,
        ip=ip,
        detail=f"role={user.role}",
    )
