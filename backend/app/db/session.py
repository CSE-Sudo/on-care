"""데이터베이스 엔진과 세션 (SQLAlchemy 2.0 동기)."""
from __future__ import annotations

import logging
from collections.abc import Generator
from typing import Any

from sqlalchemy import create_engine, event
from sqlalchemy.orm import DeclarativeBase, ORMExecuteState, Session, SessionTransaction, sessionmaker

from app.core.config import Settings, get_settings

logger = logging.getLogger(__name__)

settings = get_settings()


def connect_args_for(s: Settings) -> dict[str, Any]:
    """드라이버 연결 인자. 연결 수립 상한과 쿼리 실행 상한(#2836)을 싣는다.

    `statement_timeout` 은 연결 시작 옵션으로 걸어 이 엔진의 모든 쿼리에 적용된다.
    마이그레이션(`scripts/migrate.py`·Alembic)은 자기 엔진을 따로 만들므로 긴
    DDL 이 이 상한에 걸리지 않는다. 0 이면 걸지 않는다.
    """
    args: dict[str, Any] = {"connect_timeout": s.db_connect_timeout_seconds}
    if s.db_statement_timeout_ms > 0:
        args["options"] = f"-c statement_timeout={int(s.db_statement_timeout_ms)}"
    return args


def engine_kwargs_for(s: Settings) -> dict[str, Any]:
    """풀 설정(#2836). 기본값에 맡기면 풀 대기가 30초라, 풀이 마르면 가벼운 조회도
    30초 뒤 500 이 된다 — 짧게 실패시켜 클라이언트 재시도로 넘긴다."""
    return {
        "pool_pre_ping": True,
        "pool_size": s.db_pool_size,
        "max_overflow": s.db_max_overflow,
        "pool_timeout": s.db_pool_timeout_seconds,
        "pool_recycle": s.db_pool_recycle_seconds,
        "echo": False,
        "connect_args": connect_args_for(s),
    }


# Use the psycopg-normalized URL for managed Postgres providers, and bound
# connection attempts so readiness probes cannot occupy a worker indefinitely.
engine = create_engine(settings.sqlalchemy_database_url, **engine_kwargs_for(settings))
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)


def pool_status() -> dict[str, int]:
    """풀 지표 — `/system/metrics` 에 싣는다(#2836). 값 조정의 근거다."""
    pool = engine.pool
    out: dict[str, int] = {}
    for key, attr in (
        ("size", "size"),
        ("checked_out", "checkedout"),
        ("checked_in", "checkedin"),
        ("overflow", "overflow"),
    ):
        fn = getattr(pool, attr, None)
        if callable(fn):
            out[key] = int(fn())
    out["max_overflow"] = settings.db_max_overflow
    return out


# 세션이 지금 트랜잭션에서 DB 에 쓴 적이 있는지(#3253). `new`·`dirty`·`deleted` 는
# 아직 flush 하지 않은 변경만 보여 주므로, 이미 flush 했거나 `db.execute(delete(...))`
# 처럼 flush 를 거치지 않고 실행한 쓰기는 따로 표시해 둔다. 루트 트랜잭션이 끝날 때
# (커밋·롤백) 지운다.
_WROTE_KEY = "oncare_wrote_in_transaction"


@event.listens_for(Session, "after_flush")
def _mark_flushed_write(session: Session, _flush_context: Any) -> None:
    session.info[_WROTE_KEY] = True


@event.listens_for(Session, "do_orm_execute")
def _mark_executed_write(state: ORMExecuteState) -> None:
    # SELECT 가 아닌 문장은 쓰기로 본다. `text(...)` 는 내용을 알 수 없고(자문 잠금
    # 같은 트랜잭션 범위 효과도 있다) 커밋하면 되돌릴 수 없으니 보수적으로 표시한다.
    if not state.is_select:
        state.session.info[_WROTE_KEY] = True


@event.listens_for(Session, "after_transaction_end")
def _clear_write_mark(session: Session, transaction: SessionTransaction) -> None:
    if transaction.parent is None:  # 세이브포인트가 아닌 루트 트랜잭션만
        session.info.pop(_WROTE_KEY, None)


def release_connection(db: Session | None) -> bool:
    """외부 호출(LLM 등)을 기다리기 전에 연결을 풀로 돌려준다. (#2836)

    동기 세션은 트랜잭션이 열려 있는 동안 연결을 쥔다. 수 초~수십 초 걸리는 LLM
    응답을 기다리는 내내 쥐고 있으면 동시 요청 몇 개로 풀이 말라, AI 와 무관한 가벼운
    조회까지 풀 대기에 걸린다. 여기까지 **읽기만 했다면** 트랜잭션을 끝내 연결을
    돌려주고, 다음 쿼리 때 새로 빌린다.

    아직 쓰지 않은 변경(new·dirty·deleted)이 있거나, 이번 트랜잭션에서 이미 flush·
    실행한 쓰기가 있으면(#3253) 호출자의 트랜잭션 경계를 바꾸지 않도록 건드리지 않고
    False 를 돌려준다. 끝낸 뒤에는 세션의 객체가 만료되어 다음 접근 때 다시 읽힌다.
    """
    if db is None:  # 세션 없이 부르는 단위 호출(테스트 등)
        return False
    if db.new or db.dirty or db.deleted:
        logger.debug("쓰기 대기 중인 세션 — 연결 반납을 건너뜀")
        return False
    if not db.in_transaction():
        return True
    if db.info.get(_WROTE_KEY):
        logger.debug("이번 트랜잭션에 쓴 세션 — 연결 반납을 건너뜀")
        return False
    db.commit()
    return True


class Base(DeclarativeBase):
    pass


def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
