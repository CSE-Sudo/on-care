"""
시스템 엔드포인트 — 프론트 LocalApiInterceptor 의 _ping/_healthz/_version 과 정확히 일치.

프론트 기대 응답:
  GET /ping     -> { "message": "pong (...)" }
  GET /healthz  -> { "status": "ok", "backend": "..." }
  GET /version  -> { "api_version": "v1", "app_version": "..." }
"""
from __future__ import annotations

import logging
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.api.deps import RequireAdmin
from app.core import metrics
from app.core.config import get_settings
from app.db.session import get_db, pool_status

router = APIRouter(tags=["system"])
settings = get_settings()
logger = logging.getLogger("app.system")


@router.get("/ping")
def ping() -> dict[str, str]:
    return {"message": "pong"}


@router.get("/healthz")
def healthz() -> dict[str, str]:
    """Liveness — 프로세스 생존만 확인(DB 무관). App Runner liveness 용."""
    return {"status": "ok", "backend": "fastapi"}


@router.get("/readyz")
def readyz(db: Annotated[Session, Depends(get_db)]) -> dict[str, str]:
    """Readiness — DB 연결 가능 여부까지 확인. 실패 시 내부 상세를 숨긴 503.

    배포 검증/로드밸런서가 '트래픽 받을 준비'를 판정하는 데 쓴다(liveness 와 분리).
    """
    try:
        # established-but-slow 커넥션에서도 프로브가 무한 대기하지 않게 짧은 statement_timeout
        # 을 트랜잭션 로컬로 건다(connect_timeout 은 연결 수립만 커버 — 리뷰 #291).
        db.execute(text("SET LOCAL statement_timeout = '3s'"))
        db.execute(text("SELECT 1"))
    except Exception:
        # 실패/타임아웃 트랜잭션 상태를 롤백해 정리한다 — 같은 세션/커넥션이 이후 재사용될 때
        # 'aborted transaction' 이 남지 않도록(리뷰 #291).
        db.rollback()
        # 원인(접속 문자열 등)은 서버 로그에만. 클라이언트엔 일반화된 503.
        logger.exception("readiness check failed — DB unavailable")
        raise HTTPException(status_code=503, detail="서비스가 아직 준비되지 않았습니다.")
    return {"status": "ready"}


@router.get("/version")
def version() -> dict[str, str]:
    return {"api_version": "v1", "app_version": settings.app_version}


@router.get("/system/metrics")
def system_metrics(admin: RequireAdmin) -> dict[str, object]:
    """AI 경로 성공/폴백 카운터(#583). 관리자 전용.

    폴백은 조용하다 — 사용자는 그럴듯한 규칙형 결과를 계속 받으므로 아무도 신고하지
    않는다. 여기서 `routine_options.generated{by=ai}` 가 0 이면 AI 가 죽은 것이다.

    인증을 거는 이유: 어떤 공급자가 얼마나 실패하는지는 운영 정보다. 공개 헬스
    체크(/healthz, /readyz)와 달리 LB 가 볼 필요도 없다.

    `db_pool` 은 DB 커넥션 풀 상태(#2836) — 크기·빌려 간 연결·여분 연결 수다. 풀
    크기·대기 시간을 조정할 근거로 쓴다. 워커가 여럿이면 이 요청을 받은 워커의
    값이다(docs/DEPLOY.md).
    """
    return {**metrics.snapshot(), "db_pool": pool_status()}
