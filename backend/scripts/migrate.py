"""
마이그레이션 직렬화 러너 — App Runner 등 다중 인스턴스가 동시에 기동해도
여러 인스턴스가 같은 DB 를 동시에 마이그레이션하지 않도록 PostgreSQL advisory lock
으로 직렬화한다(리뷰 재-#3).

한 인스턴스가 lock 을 잡고 `alembic upgrade head` 를 수행하는 동안 다른 인스턴스는
lock 획득에서 대기하다가, 앞 인스턴스가 끝나면 lock 을 잡고 alembic 을 실행한다
(이미 head 면 사실상 no-op). alembic 이 실패하면 비정상 종료해 서버 기동을 막는다.
"""
from __future__ import annotations

import os
import subprocess
import sys
import time

import psycopg

# 마이그레이션 전용 고정 advisory lock 키(임의 상수). 다른 용도와 겹치지 않게.
_LOCK_KEY = 4815162342
# lock 획득 총 대기 한도(초)와 재시도 간격. 앞 인스턴스가 lock 을 들고 멈추거나 DB 에
# lock 이 걸려 있어도 무한 대기하지 않고 fail-fast 하도록 한다(리뷰: pg_advisory_lock 무한 대기).
_LOCK_TIMEOUT_SECONDS = float(os.environ.get("MIGRATE_LOCK_TIMEOUT", "120"))
_LOCK_RETRY_INTERVAL = float(os.environ.get("MIGRATE_LOCK_RETRY_INTERVAL", "2"))
# DB 접속 자체의 대기 한도(초, #2912). 잘못된 호스트·막힌 보안 그룹이면 libpq 기본값은
# OS TCP 타임아웃(수 분)까지 기다려 기동이 헬스체크 한도를 넘긴 뒤에야 실패한다.
_CONNECT_TIMEOUT_SECONDS = int(os.environ.get("MIGRATE_CONNECT_TIMEOUT", "10"))


def _try_acquire(conn: psycopg.Connection) -> bool:
    """pg_try_advisory_lock 은 대기 없이 즉시 성공/실패를 반환한다(무한 블로킹 방지)."""
    row = conn.execute("SELECT pg_try_advisory_lock(%s)", (_LOCK_KEY,)).fetchone()
    return bool(row and row[0])


def main() -> int:
    # DATABASE_URL 은 SQLAlchemy 형식(postgresql+psycopg://...) → psycopg 는 순수 postgresql://
    url = os.environ["DATABASE_URL"].replace("postgresql+psycopg://", "postgresql://")
    conn = psycopg.connect(url, autocommit=True, connect_timeout=_CONNECT_TIMEOUT_SECONDS)
    try:
        deadline = time.monotonic() + _LOCK_TIMEOUT_SECONDS
        print(f"[migrate] acquiring advisory lock {_LOCK_KEY} (timeout {_LOCK_TIMEOUT_SECONDS}s)", flush=True)
        while not _try_acquire(conn):
            if time.monotonic() >= deadline:
                print(
                    "[migrate] ERROR: advisory lock 을 시간 내 획득하지 못함 — 다른 인스턴스의 "
                    "마이그레이션이 멈춰있을 수 있음. 기동을 중단한다.",
                    flush=True,
                )
                return 1
            print("[migrate] lock busy, retrying...", flush=True)
            time.sleep(_LOCK_RETRY_INTERVAL)
        print("[migrate] lock acquired -> alembic upgrade head", flush=True)
        try:
            subprocess.run(["alembic", "upgrade", "head"], check=True)
            print("[migrate] alembic upgrade head done", flush=True)
            return 0
        finally:
            # lock 은 우리가 획득한 경우에만 해제한다.
            conn.execute("SELECT pg_advisory_unlock(%s)", (_LOCK_KEY,))
    finally:
        conn.close()


if __name__ == "__main__":
    sys.exit(main())
