"""보안 감사 로그 기록 (best-effort).

인증/관리자 이벤트를 audit_logs 에 남긴다. 감사 기록 실패가 요청을 깨뜨리면 안 되므로
best-effort(실패 시 rollback 후 무시)로 처리한다.
"""
from __future__ import annotations

import logging

from sqlalchemy.orm import Session

# 감사 로그 IP 는 rate limit 과 **같은 함수**로 읽는다(#2815). 예전에는 여기서
# `X-Forwarded-For` 첫 값(요청자가 쓴 값)을 그대로 적어 로그인 기록 IP 를 위조할 수
# 있었다. 호출부가 `audit.client_ip` 로 부르므로 이름을 그대로 내보낸다.
from app.core.client_ip import client_ip  # noqa: F401
from app.models.models import AuditLog

log = logging.getLogger(__name__)


def record(
    db: Session, *, event: str, user_id: str | None = None,
    ip: str = "", success: bool = True, detail: str = "",
) -> None:
    try:
        db.add(AuditLog(
            event=event, user_id=user_id, ip=ip, success=success, detail=detail[:2000],
        ))
        db.commit()
    except Exception as e:  # noqa: BLE001 — 감사 실패가 요청을 깨면 안 됨
        log.warning("감사 로그 기록 실패(무시): %s", e)
        try:
            db.rollback()
        except Exception:  # noqa: BLE001
            pass
