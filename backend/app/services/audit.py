"""보안 감사 로그 기록 (best-effort).

인증/관리자 이벤트와, 트레이너의 회원 건강정보 열람·데이터 공유 동의 발급/철회·
탈퇴·비밀번호 변경(#2830)을 audit_logs 에 남긴다.

두 가지 쓰는 법이 있다.

* [record] — 그 자리에서 커밋하는 best-effort 기록. 감사 기록 실패가 요청을
  깨뜨리면 안 되므로 실패하면 rollback 후 무시한다. **세션을 커밋하므로** 본 작업이
  끝나(커밋된) 뒤나 본 작업이 시작되기 전에만 부른다.
* [stage] — 커밋하지 않고 세션에 얹기만 한다. 동의·탈퇴처럼 본 작업과 **같은
  트랜잭션으로** 남아야 하는 기록에 쓴다 — 동의는 바뀌었는데 기록이 없거나, 기록은
  있는데 동의는 그대로인 상태가 생기지 않는다. 호출자가 커밋한다.

어느 쪽이든 식단 내용·메시지 같은 개인정보 본문은 기록하지 않는다. `detail` 에는
경로(`via=pairing`)·주체(`by=member`) 같은 짧은 분류만 적는다.
"""
from __future__ import annotations

import logging
from datetime import datetime, timedelta

from fastapi import Request
from sqlalchemy import and_, delete, or_, select
from sqlalchemy.orm import Session

from app.core import clock
from app.core.config import get_settings
from app.models.models import AuditLog

log = logging.getLogger(__name__)

#: 트레이너가 담당 회원의 기록을 열람했다(`resource` 에 기록 종류).
CLIENT_READ = "trainer.client_read"
#: 데이터 공유 동의 발급(`detail` 의 `via=` 에 경로: pairing·invite·consultation).
CONSENT_GRANT = "consent.grant"
#: 데이터 공유 동의 철회(`detail` 의 `by=` 에 주체: member·trainer).
CONSENT_REVOKE = "consent.revoke"
#: 회원·트레이너 탈퇴(`detail` 의 `role=`).
ACCOUNT_WITHDRAW = "account.withdraw"
#: 비밀번호 변경.
PASSWORD_CHANGE = "auth.password_change"

#: 민감정보(건강정보) 처리 기록 — [audit_sensitive_retention_days] 동안 보관한다.
#: 나머지 이벤트(로그인 등 접속 기록)는 [audit_retention_days].
SENSITIVE_EVENTS: frozenset[str] = frozenset(
    {CLIENT_READ, CONSENT_GRANT, CONSENT_REVOKE, ACCOUNT_WITHDRAW}
)


def client_ip(request: Request) -> str:
    """클라이언트 IP. 프록시 뒤면 X-Forwarded-For 첫 IP 사용."""
    xff = request.headers.get("x-forwarded-for")
    if xff:
        return xff.split(",")[0].strip()[:64]
    return (request.client.host if request.client else "")[:64]


def _entry(
    *, event: str, user_id: str | None, target_user_id: str | None,
    resource: str, ip: str, success: bool, detail: str,
) -> AuditLog:
    return AuditLog(
        event=event,
        user_id=user_id,
        target_user_id=target_user_id,
        resource=resource[:30],
        ip=ip[:64],
        success=success,
        detail=detail[:2000],
        created_at=clock.now(),
    )


def stage(
    db: Session, *, event: str, user_id: str | None = None,
    target_user_id: str | None = None, resource: str = "", ip: str = "",
    success: bool = True, detail: str = "",
) -> None:
    """커밋 없이 세션에 감사 기록을 얹는다 — 호출자의 트랜잭션과 함께 커밋된다."""
    db.add(_entry(
        event=event, user_id=user_id, target_user_id=target_user_id,
        resource=resource, ip=ip, success=success, detail=detail,
    ))


def record(
    db: Session, *, event: str, user_id: str | None = None,
    ip: str = "", success: bool = True, detail: str = "",
    target_user_id: str | None = None, resource: str = "",
) -> None:
    try:
        stage(
            db, event=event, user_id=user_id, target_user_id=target_user_id,
            resource=resource, ip=ip, success=success, detail=detail,
        )
        db.commit()
    except Exception as e:  # noqa: BLE001 — 감사 실패가 요청을 깨면 안 됨
        log.warning("감사 로그 기록 실패(무시): %s", e)
        try:
            db.rollback()
        except Exception:  # noqa: BLE001
            pass


def record_client_read(
    db: Session, *, trainer_id: str, member_id: str, resource: str, ip: str = "",
) -> bool:
    """트레이너의 회원 기록 열람을 남긴다. 실제로 남겼으면 True.

    같은 (트레이너, 회원, 자원) 조합은 [audit_read_dedupe_minutes] 안에 한 번만
    남긴다 — 한 화면이 같은 기록을 여러 번 부르거나 기간을 넘길 때마다 쌓이면
    정작 필요한 이력을 찾기 어렵다. 0 이면 묶지 않고 매번 남긴다.
    """
    try:
        window = get_settings().audit_read_dedupe_minutes
        if window > 0:
            since = clock.now() - timedelta(minutes=window)
            recent = db.scalar(
                select(AuditLog.id)
                .where(
                    AuditLog.event == CLIENT_READ,
                    AuditLog.target_user_id == member_id,
                    AuditLog.user_id == trainer_id,
                    AuditLog.resource == resource,
                    AuditLog.created_at >= since,
                )
                .limit(1)
            )
            if recent is not None:
                return False
    except Exception as e:  # noqa: BLE001 — 감사 실패가 요청을 깨면 안 됨
        log.warning("감사 로그 조회 실패(무시): %s", e)
        try:
            db.rollback()
        except Exception:  # noqa: BLE001
            pass
        return False
    record(
        db, event=CLIENT_READ, user_id=trainer_id, target_user_id=member_id,
        resource=resource, ip=ip,
    )
    return True


def purge_expired(db: Session, *, now: datetime | None = None) -> int:
    """보존 기간이 지난 감사 기록을 지운다. 지운 건수를 돌려준다(커밋 포함).

    민감정보 처리 기록([SENSITIVE_EVENTS])과 그 밖의 접속 기록은 기간이 다르다.
    기간이 0 이하인 쪽은 지우지 않는다.
    """
    settings = get_settings()
    now = now or clock.now()
    conditions = []
    if settings.audit_retention_days > 0:
        conditions.append(and_(
            AuditLog.event.not_in(sorted(SENSITIVE_EVENTS)),
            AuditLog.created_at < now - timedelta(days=settings.audit_retention_days),
        ))
    if settings.audit_sensitive_retention_days > 0:
        conditions.append(and_(
            AuditLog.event.in_(sorted(SENSITIVE_EVENTS)),
            AuditLog.created_at
            < now - timedelta(days=settings.audit_sensitive_retention_days),
        ))
    if not conditions:
        return 0
    result = db.execute(
        delete(AuditLog).where(or_(*conditions)).execution_options(
            synchronize_session=False
        )
    )
    db.commit()
    return result.rowcount or 0


def purge_expired_best_effort() -> None:
    """기동 시 정리 — 실패해도 서버 기동을 막지 않는다."""
    from app.db.session import SessionLocal

    db = SessionLocal()
    try:
        removed = purge_expired(db)
        if removed:
            log.info("보존 기간 지난 감사 기록 %d건 정리", removed)
    except Exception as e:  # noqa: BLE001
        log.warning("감사 기록 정리 실패(무시): %s", e)
        try:
            db.rollback()
        except Exception:  # noqa: BLE001
            pass
    finally:
        db.close()
