"""보존 기한이 지난 기록의 정기 정리(#3144).

처리방침은 접속 기록 1년, 트레이너의 건강정보 열람·공유 동의 기록 2년 보관 뒤 "자동으로
삭제" 한다고 고지한다. 예전에는 감사 로그 정리가 **서버가 새로 뜰 때만**(#2830), 알림
정리는 **사람이 스크립트를 돌릴 때만**(#965) 일어나서, 몇 주씩 재시작 없이 도는 운영
태스크에서는 고지한 기간을 넘겨 기록이 남았다.

이 모듈이 정리 진입점 하나다.

* [run_purge] — 감사 로그·읽은 알림을 각자의 보존 기한으로 지운다. 단계마다 따로
  커밋하고, 한 단계가 실패해도 나머지는 돈다. **예외를 밖으로 내지 않는다** — 결과는
  [PurgeReport] 로 돌려준다.
* [run_periodic] — 앱 수명 동안 [PURGE_INTERVAL] 마다 [run_purge] 를 부르는 백그라운드
  루프. `app.main` 의 lifespan 이 띄운다.
* `python -m scripts.purge_retention` — 같은 [run_purge] 를 한 번 돌리는 명령. 배포 담당이
  손으로 돌리거나 외부 스케줄러에 걸 때 쓴다.

태스크·워커가 여럿이면 모두 같은 루프를 돈다. 동시에 돌지 않도록 Postgres 세션 advisory
lock 을 **기다리지 않고** 잡아 보고, 이미 누가 돌고 있으면 이번 차례는 건너뛴다. 삭제는
기한 조건으로만 고르므로 여러 번 돌아도 결과가 같다(멱등).

보존 기한 자체는 바꾸지 않는다 — 감사 로그는 `AUDIT_RETENTION_DAYS`·
`AUDIT_SENSITIVE_RETENTION_DAYS`, 알림은 `notification_service.READ_RETENTION_DAYS`(읽은
알림만, 미확인 알림은 남긴다).
"""
from __future__ import annotations

import asyncio
import logging
from collections.abc import Callable
from dataclasses import dataclass, field
from datetime import datetime, timedelta

from sqlalchemy import text
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session, sessionmaker

from app.core import metrics
from app.services import audit, notification_service

log = logging.getLogger(__name__)

#: 정기 정리 주기. 보존 기한이 년 단위라 하루 한 번이면 넘겨 남는 기간이 하루를 넘지 않는다.
PURGE_INTERVAL = timedelta(hours=24)

#: 정리 실행을 한 곳에서만 하게 하는 advisory lock 키(`pg_try_advisory_lock(bigint)`).
#: 다른 잠금과 겹치지 않게 고정 값을 쓴다 — ASCII "oncare-purge" 앞 8바이트.
PURGE_LOCK_KEY = 0x6F6E_6361_7265_2D70

#: 정리 단계 — (이름, 함수). 이름은 로그·메트릭·명령 출력에 그대로 쓴다.
#: 함수는 세션과 기준 시각을 받아 지운 건수를 돌려주고, 스스로 커밋한다.
PurgeStep = Callable[[Session, datetime | None], int]


def _purge_audit_logs(db: Session, now: datetime | None) -> int:
    return audit.purge_expired(db, now=now)


def _purge_read_notifications(db: Session, now: datetime | None) -> int:
    # 데모 시드 알림(스테이징)은 시드가 관리한다. 목록을 열 때 오늘로 옮겨지지만
    # (`slide_demo_notifications`), 아무도 열지 않은 채 90일이 지나면 읽은 데모 알림만
    # 사라지고 시드는 이미 있다고 보고 다시 넣지 않는다 — 데모 화면이 비지 않게 뺀다.
    from app.db.seed_notifications import DEMO_AGO_BY_ID

    return notification_service.purge_expired(
        db, now=now, exclude_ids=frozenset(DEMO_AGO_BY_ID)
    )


STEPS: tuple[tuple[str, PurgeStep], ...] = (
    ("audit_logs", _purge_audit_logs),
    ("notifications", _purge_read_notifications),
)


@dataclass
class PurgeReport:
    """한 번의 정리 결과."""

    #: 단계 이름 → 지운 건수(성공한 단계만).
    removed: dict[str, int] = field(default_factory=dict)
    #: 실패한 단계 이름.
    failed: list[str] = field(default_factory=list)
    #: 다른 곳에서 이미 정리 중이라 건너뛰었다.
    skipped: bool = False

    @property
    def ok(self) -> bool:
        return not self.failed

    @property
    def total(self) -> int:
        return sum(self.removed.values())


def _default_engine() -> Engine:
    from app.db.session import engine

    return engine


def run_purge(
    *,
    engine: Engine | None = None,
    now: datetime | None = None,
    steps: tuple[tuple[str, PurgeStep], ...] | None = None,
) -> PurgeReport:
    """보존 기한이 지난 기록을 지운다. 예외를 내지 않는다.

    [now] 는 테스트가 기준 시각을 고정하려고 넘긴다. [steps] 도 테스트용이다.
    """
    report = PurgeReport()
    try:
        bind = engine or _default_engine()
        lock_conn = bind.connect()
    except Exception as exc:  # noqa: BLE001 — 정리 실패가 서비스를 멈추면 안 된다
        log.warning("보존 기한 정리: DB 연결 실패(건너뜀): %s", type(exc).__name__)
        metrics.incr("retention.purge_failures", step="connect")
        report.failed.append("connect")
        return report

    try:
        if not _try_lock(lock_conn):
            log.info("보존 기한 정리: 다른 인스턴스가 정리 중이라 건너뜀")
            report.skipped = True
            return report
        try:
            _run_steps(bind, now, steps or STEPS, report)
        finally:
            _unlock(lock_conn)
    finally:
        lock_conn.close()

    if report.removed or report.failed:
        log.info(
            "보존 기한 정리: %s%s",
            ", ".join(f"{name} {count}건" for name, count in report.removed.items()),
            f" · 실패 {', '.join(report.failed)}" if report.failed else "",
        )
    return report


def _run_steps(
    bind: Engine,
    now: datetime | None,
    steps: tuple[tuple[str, PurgeStep], ...],
    report: PurgeReport,
) -> None:
    factory = sessionmaker(bind=bind, autoflush=False, autocommit=False)
    for name, step in steps:
        db = factory()
        try:
            report.removed[name] = int(step(db, now) or 0)
        except Exception as exc:  # noqa: BLE001 — 한 단계 실패가 다음 단계를 막지 않는다
            # 예외 문구에는 SQL 매개변수(사용자 id 등)가 실릴 수 있어 종류만 남긴다.
            log.warning("보존 기한 정리 실패(%s): %s", name, type(exc).__name__)
            metrics.incr("retention.purge_failures", step=name)
            report.failed.append(name)
            try:
                db.rollback()
            except Exception:  # noqa: BLE001
                pass
        finally:
            db.close()


def _is_postgres(conn) -> bool:
    return conn.dialect.name == "postgresql"


def _try_lock(conn) -> bool:
    """기다리지 않고 잠금을 잡아 본다. Postgres 가 아니면(로컬 SQLite 등) 늘 잡은 것으로 본다."""
    if not _is_postgres(conn):
        return True
    got = conn.execute(
        text("SELECT pg_try_advisory_lock(:key)"), {"key": PURGE_LOCK_KEY}
    ).scalar()
    # 세션 잠금은 트랜잭션과 무관하게 유지된다. 조회로 열린 트랜잭션만 닫는다.
    conn.commit()
    return bool(got)


def _unlock(conn) -> None:
    if not _is_postgres(conn):
        return
    try:
        conn.execute(text("SELECT pg_advisory_unlock(:key)"), {"key": PURGE_LOCK_KEY})
        conn.commit()
    except Exception as exc:  # noqa: BLE001 — 연결을 닫으면 잠금도 풀린다
        log.warning("보존 기한 정리 잠금 해제 실패(연결 종료로 해제): %s", type(exc).__name__)


async def run_periodic(
    *,
    interval: timedelta = PURGE_INTERVAL,
    purge: Callable[[], PurgeReport] = run_purge,
) -> None:
    """앱이 떠 있는 동안 [interval] 마다 정리한다. 취소될 때까지 돈다.

    기동 때 한 번은 lifespan 이 직접 [run_purge] 를 부르므로(지금까지의 "기동 시 정리"),
    이 루프는 **먼저 기다린 뒤** 정리한다. 정리는 동기 DB 작업이라 스레드에서 돌려
    이벤트 루프(요청 처리)를 막지 않는다.
    """
    seconds = max(interval.total_seconds(), 0.01)
    while True:
        await asyncio.sleep(seconds)
        try:
            await asyncio.to_thread(purge)
        except asyncio.CancelledError:
            raise
        except Exception as exc:  # noqa: BLE001 — run_purge 는 예외를 내지 않지만 루프는 지킨다
            log.warning("보존 기한 정리 루프 오류(계속): %s", type(exc).__name__)


def start_periodic(**kwargs) -> asyncio.Task[None]:
    """[run_periodic] 을 백그라운드 태스크로 띄운다. lifespan 이 종료 때 취소한다."""
    return asyncio.create_task(run_periodic(**kwargs), name="retention-purge")


async def stop_periodic(task: asyncio.Task[None] | None) -> None:
    """[start_periodic] 이 띄운 태스크를 멈춘다. 이미 끝났어도 괜찮다."""
    if task is None:
        return
    task.cancel()
    try:
        await task
    except asyncio.CancelledError:
        pass
    except Exception as exc:  # noqa: BLE001
        log.warning("보존 기한 정리 태스크 종료 오류(무시): %s", type(exc).__name__)
