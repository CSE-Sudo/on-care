"""보존 기한 정기 정리(#3144).

감사 로그·읽은 알림 정리가 기동 때 한 번(감사 로그)이나 사람이 스크립트를 돌릴 때(알림)만
일어나서, 재시작 없이 오래 도는 운영 태스크에서는 고지한 보관 기간을 넘겨 기록이 남았다.
정리 진입점 하나(`retention.run_purge`)가 둘을 함께 지우고, 앱이 떠 있는 동안 하루마다
돈다는 것을 본다.

* 기한 경계 — 직전 기록은 지우고 직후 기록은 남긴다(감사 로그 두 종류·알림).
* 실패 격리 — 한 단계가 실패해도 다음 단계는 돌고, 예외가 밖으로 새지 않는다.
* 동시 실행 — 다른 인스턴스가 정리 중이면 건너뛰고, 겹쳐 돌아도 결과가 같다.
* 주기 — lifespan 이 기동 때 한 번 돌리고 백그라운드 루프를 띄웠다가 종료 때 멈춘다.
"""
from __future__ import annotations

import asyncio
import threading
from datetime import timedelta
from uuid import uuid4

import pytest
from sqlalchemy import create_engine, text

from app.core import clock, metrics
from app.core.config import get_settings
from app.models.models import AuditLog, Notification
from app.services import audit, notification_service, retention
from scripts import purge_retention

# ---- DB 없이: 실패 격리 ----


@pytest.fixture()
def sqlite_engine():
    """잠금이 없는 DB(SQLite) — 단계 실행·실패 격리만 본다."""
    engine = create_engine("sqlite://")
    yield engine
    engine.dispose()


def test_a_failing_step_does_not_stop_the_next_one(sqlite_engine):
    metrics.reset()
    calls: list[str] = []

    def broken(db, now):
        calls.append("broken")
        raise RuntimeError("user-123 의 행을 지우다 실패")

    def works(db, now):
        calls.append("works")
        return 3

    report = retention.run_purge(
        engine=sqlite_engine, steps=(("first", broken), ("second", works))
    )

    assert calls == ["broken", "works"]
    assert report.removed == {"second": 3}
    assert report.failed == ["first"]
    assert report.ok is False
    assert report.skipped is False
    counters = metrics.snapshot()["counters"]
    assert counters.get("retention.purge_failures{step=first}") == 1


def test_failure_log_does_not_carry_the_exception_message(sqlite_engine, caplog):
    """예외 문구에는 SQL 매개변수(사용자 id 등)가 실릴 수 있다 — 종류만 남긴다."""

    def broken(db, now):
        raise RuntimeError("user-secret-id-777")

    with caplog.at_level("WARNING", logger="app.services.retention"):
        retention.run_purge(engine=sqlite_engine, steps=(("only", broken),))

    assert "RuntimeError" in caplog.text
    assert "user-secret-id-777" not in caplog.text


def test_unreachable_db_is_reported_not_raised():
    metrics.reset()
    engine = create_engine(
        "postgresql+psycopg://nouser:x@127.0.0.1:1/none",
        connect_args={"connect_timeout": 1},
    )
    try:
        report = retention.run_purge(engine=engine)
    finally:
        engine.dispose()

    assert report.failed == ["connect"]
    assert report.removed == {}
    assert metrics.snapshot()["counters"].get("retention.purge_failures{step=connect}") == 1


def test_all_steps_succeeding_reports_the_total(sqlite_engine):
    report = retention.run_purge(
        engine=sqlite_engine,
        steps=(("a", lambda db, now: 2), ("b", lambda db, now: 0)),
    )
    assert report.ok is True
    assert report.removed == {"a": 2, "b": 0}
    assert report.total == 2


def test_default_steps_cover_audit_logs_and_notifications():
    assert [name for name, _ in retention.STEPS] == ["audit_logs", "notifications"]


def test_steps_receive_the_pinned_time(sqlite_engine):
    pinned = clock.now() - timedelta(days=3)
    seen = []
    retention.run_purge(
        engine=sqlite_engine,
        now=pinned,
        steps=(("a", lambda db, now: seen.append(now) or 0),),
    )
    assert seen == [pinned]


def test_notification_step_leaves_demo_seed_notifications_to_the_seed(monkeypatch):
    """데모 시드 알림은 시드가 관리한다 — 정리 단계가 그 id 를 뺀다."""
    from app.db.seed_notifications import DEMO_AGO_BY_ID

    seen: dict = {}

    def capture(db, **kwargs):
        seen.update(kwargs)
        return 0

    monkeypatch.setattr(notification_service, "purge_expired", capture)
    retention._purge_read_notifications(None, None)

    assert set(seen["exclude_ids"]) == set(DEMO_AGO_BY_ID)
    assert seen["exclude_ids"]


# ---- DB 없이: 주기 실행 ----


def test_daily_interval():
    assert retention.PURGE_INTERVAL == timedelta(hours=24)


def test_periodic_loop_waits_then_purges_repeatedly():
    calls: list[int] = []

    def fake_purge():
        calls.append(1)
        return retention.PurgeReport()

    async def drive():
        task = retention.start_periodic(
            interval=timedelta(milliseconds=10), purge=fake_purge
        )
        # 첫 실행은 기다린 뒤 — 기동 때 정리는 lifespan 이 직접 한다.
        await asyncio.sleep(0)
        assert calls == []
        while len(calls) < 3:
            await asyncio.sleep(0.01)
        await retention.stop_periodic(task)
        assert task.cancelled() or task.done()

    asyncio.run(asyncio.wait_for(drive(), timeout=5))
    assert len(calls) >= 3


def test_periodic_loop_survives_a_raising_purge():
    calls: list[int] = []

    def flaky():
        calls.append(1)
        if len(calls) == 1:
            raise RuntimeError("boom")
        return retention.PurgeReport()

    async def drive():
        task = retention.start_periodic(interval=timedelta(milliseconds=10), purge=flaky)
        while len(calls) < 2:
            await asyncio.sleep(0.01)
        assert not task.done()
        await retention.stop_periodic(task)

    asyncio.run(asyncio.wait_for(drive(), timeout=5))
    assert len(calls) >= 2


def test_stop_periodic_tolerates_none_and_finished_tasks():
    async def drive():
        await retention.stop_periodic(None)
        task = asyncio.create_task(asyncio.sleep(0))
        await task
        await retention.stop_periodic(task)

    asyncio.run(drive())


def test_lifespan_purges_at_boot_and_runs_the_daily_loop(monkeypatch):
    """기동 때 한 번 정리하고 하루 주기 루프를 띄웠다가, 종료 때 루프를 멈춘다."""
    import app.main as main

    boot_calls: list[int] = []
    loop_calls: list[int] = []
    started: list[asyncio.Task] = []
    original_start = retention.start_periodic

    def fake_start(**kwargs):
        def purge():
            loop_calls.append(1)
            return retention.PurgeReport()

        task = original_start(interval=timedelta(milliseconds=10), purge=purge)
        started.append(task)
        return task

    monkeypatch.setattr(main, "init_db", lambda: None)
    monkeypatch.setattr(main.startup_checks, "check", lambda s: None)
    monkeypatch.setattr(
        main.retention, "run_purge", lambda: boot_calls.append(1) or retention.PurgeReport()
    )
    monkeypatch.setattr(main.retention, "start_periodic", fake_start)

    async def drive():
        async with main.lifespan(main.app):
            assert boot_calls == [1]
            while not loop_calls:
                await asyncio.sleep(0.01)
        (task,) = started
        assert task.done()

    asyncio.run(asyncio.wait_for(drive(), timeout=5))


# ---- 명령(scripts.purge_retention) ----


def test_command_prints_counts_and_exits_zero(monkeypatch, capsys):
    monkeypatch.setattr(
        retention,
        "run_purge",
        lambda: retention.PurgeReport(removed={"audit_logs": 4, "notifications": 1}),
    )
    assert purge_retention.main([]) == 0
    out = capsys.readouterr().out
    assert "audit_logs: 4건" in out
    assert "notifications: 1건" in out
    assert "5건" in out


def test_command_exits_one_when_a_step_fails(monkeypatch, capsys):
    monkeypatch.setattr(
        retention,
        "run_purge",
        lambda: retention.PurgeReport(removed={"notifications": 0}, failed=["audit_logs"]),
    )
    assert purge_retention.main([]) == 1
    assert "audit_logs" in capsys.readouterr().err


def test_command_skips_quietly_when_another_instance_is_purging(monkeypatch, capsys):
    monkeypatch.setattr(retention, "run_purge", lambda: retention.PurgeReport(skipped=True))
    assert purge_retention.main([]) == 0
    assert "건너뛰" in capsys.readouterr().out


# ---- DB: 기한 경계 ----


@pytest.fixture()
def engine(client):
    from app.db.session import engine as app_engine

    return app_engine


@pytest.fixture()
def member_id(client) -> str:
    email = f"purge3144-{uuid4().hex[:8]}@oncare.com"
    created = client.post(
        "/v1/auth/register",
        json={"email": email, "password": "pw-12345!", "name": "정리테스터"},
    )
    assert created.status_code == 201, created.text
    return created.json()["id"]


def _audit(db, event: str, at) -> int:
    row = AuditLog(event=event, user_id=f"purge3144-{uuid4().hex[:8]}", created_at=at)
    db.add(row)
    db.commit()
    return row.id


def _notification(db, user_id: str, at, *, read: bool) -> str:
    row = Notification(
        id=f"purge3144-{uuid4().hex[:12]}",
        user_id=user_id,
        title="정리 테스트",
        body="",
        category="reminder",
        read=read,
        created_at=at,
    )
    db.add(row)
    db.commit()
    return row.id


def _audit_alive(db, row_id: int) -> bool:
    db.expire_all()
    return db.get(AuditLog, row_id) is not None


def _notification_alive(db, row_id: str) -> bool:
    db.expire_all()
    return db.get(Notification, row_id) is not None


@pytest.fixture()
def retention_days(monkeypatch):
    settings = get_settings()
    monkeypatch.setattr(settings, "audit_retention_days", 365)
    monkeypatch.setattr(settings, "audit_sensitive_retention_days", 730)
    return settings


def test_purge_deletes_just_past_the_deadline_and_keeps_just_before(
    engine, db_session, member_id, retention_days
):
    now = clock.now()
    minute = timedelta(minutes=1)
    login_cut = now - timedelta(days=365)
    sensitive_cut = now - timedelta(days=730)
    notice_cut = notification_service.retention_cutoff(now=now)

    login_expired = _audit(db_session, "auth.login", login_cut - minute)
    login_kept = _audit(db_session, "auth.login", login_cut + minute)
    read_expired = _audit(db_session, audit.CLIENT_READ, sensitive_cut - minute)
    read_kept = _audit(db_session, audit.CLIENT_READ, sensitive_cut + minute)
    # 민감 기록은 접속 기록 기한(1년)을 넘겨도 2년까지 남는다.
    consent_mid = _audit(db_session, audit.CONSENT_GRANT, login_cut - minute)

    noti_expired = _notification(db_session, member_id, notice_cut - minute, read=True)
    noti_kept = _notification(db_session, member_id, notice_cut + minute, read=True)
    # 미확인 알림은 아무리 오래돼도 남긴다.
    noti_unread = _notification(
        db_session, member_id, notice_cut - timedelta(days=400), read=False
    )

    report = retention.run_purge(engine=engine, now=now)

    assert report.ok, report
    assert report.skipped is False
    assert report.removed["audit_logs"] >= 2
    assert report.removed["notifications"] >= 1

    assert not _audit_alive(db_session, login_expired)
    assert _audit_alive(db_session, login_kept)
    assert not _audit_alive(db_session, read_expired)
    assert _audit_alive(db_session, read_kept)
    assert _audit_alive(db_session, consent_mid)

    assert not _notification_alive(db_session, noti_expired)
    assert _notification_alive(db_session, noti_kept)
    assert _notification_alive(db_session, noti_unread)


def test_excluded_ids_survive_the_purge(engine, db_session, member_id):
    now = clock.now()
    old = now - timedelta(days=200)
    kept = _notification(db_session, member_id, old, read=True)
    gone = _notification(db_session, member_id, old, read=True)

    removed = notification_service.purge_expired(
        db_session, now=now, user_id=member_id, exclude_ids={kept}
    )

    assert removed == 1
    assert _notification_alive(db_session, kept)
    assert not _notification_alive(db_session, gone)


def test_second_run_has_nothing_left(engine, db_session, member_id, retention_days):
    now = clock.now()
    _audit(db_session, "auth.login", now - timedelta(days=500))
    _notification(db_session, member_id, now - timedelta(days=200), read=True)

    first = retention.run_purge(engine=engine, now=now)
    second = retention.run_purge(engine=engine, now=now)

    assert first.total >= 2
    assert second.ok
    assert second.total == 0


def test_audit_failure_still_purges_notifications(
    engine, db_session, member_id, retention_days, monkeypatch
):
    now = clock.now()
    expired = _notification(db_session, member_id, now - timedelta(days=200), read=True)

    def broken(db, *, now=None):
        raise RuntimeError("audit down")

    monkeypatch.setattr(audit, "purge_expired", broken)

    report = retention.run_purge(engine=engine, now=now)

    assert report.failed == ["audit_logs"]
    assert report.removed["notifications"] >= 1
    assert not _notification_alive(db_session, expired)


# ---- DB: 동시 실행 ----


def test_skips_while_another_instance_holds_the_lock(engine, db_session, retention_days):
    old = _audit(db_session, "auth.login", clock.now() - timedelta(days=500))

    with engine.connect() as holder:
        assert holder.execute(
            text("SELECT pg_try_advisory_lock(:k)"), {"k": retention.PURGE_LOCK_KEY}
        ).scalar()
        try:
            report = retention.run_purge(engine=engine)
        finally:
            holder.execute(
                text("SELECT pg_advisory_unlock(:k)"), {"k": retention.PURGE_LOCK_KEY}
            )
            holder.commit()

    assert report.skipped is True
    assert report.removed == {}
    assert _audit_alive(db_session, old)

    # 잠금이 풀리면 다음 차례에 지운다.
    after = retention.run_purge(engine=engine)
    assert after.skipped is False
    assert not _audit_alive(db_session, old)


def test_lock_is_released_after_a_run(engine):
    retention.run_purge(engine=engine)
    with engine.connect() as probe:
        got = probe.execute(
            text("SELECT pg_try_advisory_lock(:k)"), {"k": retention.PURGE_LOCK_KEY}
        ).scalar()
        assert got is True
        probe.execute(text("SELECT pg_advisory_unlock(:k)"), {"k": retention.PURGE_LOCK_KEY})
        probe.commit()


def test_concurrent_runs_are_safe(engine, db_session, member_id, retention_days):
    now = clock.now()
    rows = [
        _audit(db_session, "auth.login", now - timedelta(days=400 + i)) for i in range(6)
    ]
    notes = [
        _notification(db_session, member_id, now - timedelta(days=100 + i), read=True)
        for i in range(4)
    ]

    reports: list[retention.PurgeReport] = []
    errors: list[BaseException] = []
    barrier = threading.Barrier(4)

    def worker():
        try:
            barrier.wait()
            reports.append(retention.run_purge(engine=engine, now=now))
        except BaseException as exc:  # noqa: BLE001
            errors.append(exc)

    threads = [threading.Thread(target=worker) for _ in range(4)]
    for t in threads:
        t.start()
    for t in threads:
        t.join(timeout=30)

    assert errors == []
    assert len(reports) == 4
    assert all(r.ok for r in reports)
    # 잠금을 못 잡은 인스턴스는 건너뛰고, 돈 인스턴스가 대상을 모두 지운다.
    ran = [r for r in reports if not r.skipped]
    assert ran
    assert sum(r.removed.get("audit_logs", 0) for r in ran) >= len(rows)
    for row_id in rows:
        assert not _audit_alive(db_session, row_id)
    for note_id in notes:
        assert not _notification_alive(db_session, note_id)
