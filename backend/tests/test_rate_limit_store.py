"""시도 제한 공유 저장소(#3143).

분당 한도·로그인 실패 잠금·가입 한도를 Postgres 표(`rate_limit_hits`)에 센다. 여기서는

- 설정(`RATE_LIMIT_STORE`)이 저장소를 고르는 규칙과 호출이 그 저장소로 가는지(DB 불필요),
- DB 저장소가 메모리 구현과 같은 판정을 하고, 인스턴스를 새로 만들어도·여럿이 동시에 세도
  한도를 지키며, 만료 행을 정리하는지(DB),
- 로그인 잠금이 DB 저장소로도 실제 엔드포인트에서 걸리는지(DB)

를 본다. DB 테스트는 `client` 픽스처로 마이그레이션이 끝난 DB 를 쓰고, 표를 비우고 시작한다.
"""
from __future__ import annotations

import threading
import time
from uuid import uuid4

import pytest
from fastapi import HTTPException
from pydantic import ValidationError
from sqlalchemy import create_engine, text

from app.core import metrics
from app.core import rate_limit
from app.core.config import Settings, get_settings
from app.core.rate_limit import ConfiguredLimiter, DatabaseRateLimiter, RateLimiter

PASSWORD = "rate-store-pw-1234"


# ---------- 설정: 저장소 고르기 (DB 불필요) ----------


def _with(**update) -> Settings:
    # 검증기를 다시 돌리지 않는 복사본 — 운영 가드(JWT·CORS·메일 등)와 무관하게
    # 저장소 선택 규칙만 본다.
    return Settings(_env_file=None).model_copy(update=update)


def test_store_defaults_to_auto():
    assert Settings(_env_file=None).rate_limit_store == "auto"


@pytest.mark.parametrize(
    ("env", "store", "backend"),
    [
        ("dev", "auto", "memory"),
        ("staging", "auto", "memory"),
        ("prod", "auto", "database"),
        ("production", "auto", "database"),
        ("prod", "memory", "memory"),
        ("dev", "database", "database"),
        ("staging", "database", "database"),
    ],
)
def test_backend_resolution(env, store, backend):
    assert _with(env=env, rate_limit_store=store).rate_limit_backend == backend


def test_unknown_store_is_rejected():
    with pytest.raises(ValidationError):
        Settings(_env_file=None, rate_limit_store="redis")


# ---------- 위임: 설정이 고른 저장소로 간다 (DB 불필요) ----------


class _Recorder:
    """DatabaseRateLimiter 자리에 끼워 어떤 호출이 왔는지만 적는다."""

    def __init__(self) -> None:
        self.calls: list[tuple] = []

    def check(self, key, limit, window, *, detail=None):
        self.calls.append(("check", key, limit, window, detail))

    def retry_after(self, key, limit, window):
        self.calls.append(("retry_after", key, limit, window))
        return 7

    def hit(self, key, window):
        self.calls.append(("hit", key, window))

    def reset(self, key):
        self.calls.append(("reset", key))

    def clear(self):
        self.calls.append(("clear",))

    def purge_expired(self):
        self.calls.append(("purge",))
        return 3


@pytest.fixture
def recorder(monkeypatch):
    rec = _Recorder()
    monkeypatch.setattr(rate_limit.limiter, "database", rec)
    monkeypatch.setattr(get_settings(), "rate_limit_enabled", True)
    return rec


def test_database_store_receives_every_call(recorder, monkeypatch):
    monkeypatch.setattr(get_settings(), "rate_limit_store", "database")
    rate_limit.check_key("signup-code-email:a@x.com", 3, 60.0)
    rate_limit.check_user("diet-analyze", "user-1", 5, detail={"code": "x"})
    rate_limit.record_failure("login-fail:a@x.com", 900.0)
    with pytest.raises(HTTPException) as exc:
        rate_limit.ensure_unlocked("login-fail:a@x.com", 5, 900.0)
    assert exc.value.headers["Retry-After"] == "7"
    rate_limit.clear_failures("login-fail:a@x.com")
    rate_limit.limiter.clear()
    assert rate_limit.purge_expired() == 3

    assert recorder.calls == [
        ("check", "signup-code-email:a@x.com", 3, 60.0, None),
        ("check", "diet-analyze:user:user-1", 5, 60.0, {"code": "x"}),
        ("hit", "login-fail:a@x.com", 900.0),
        ("retry_after", "login-fail:a@x.com", 5, 900.0),
        ("reset", "login-fail:a@x.com"),
        ("clear",),
        ("purge",),
    ]
    # 메모리 저장소에는 아무것도 남지 않는다.
    assert rate_limit.limiter.memory._hits == {}


def test_memory_store_never_touches_the_database(recorder, monkeypatch):
    monkeypatch.setattr(get_settings(), "rate_limit_store", "memory")
    rate_limit.check_key("k", 3, 60.0)
    rate_limit.record_failure("f", 60.0)
    rate_limit.limiter.clear()
    assert rate_limit.purge_expired() == 0
    assert recorder.calls == []


def test_disabled_switch_skips_the_store(recorder, monkeypatch):
    monkeypatch.setattr(get_settings(), "rate_limit_store", "database")
    monkeypatch.setattr(get_settings(), "rate_limit_enabled", False)
    rate_limit.check_key("k", 1, 60.0)
    rate_limit.record_failure("f", 60.0)
    rate_limit.ensure_unlocked("f", 1, 60.0)
    assert recorder.calls == []


def test_module_limiter_is_the_configured_proxy():
    assert isinstance(rate_limit.limiter, ConfiguredLimiter)
    assert isinstance(rate_limit.limiter.memory, RateLimiter)
    assert isinstance(rate_limit.limiter.database, DatabaseRateLimiter)


# ---------- DB 저장소: 장애 시 동작 (DB 불필요) ----------


@pytest.fixture
def broken_store():
    # 닫힌 포트 — 연결이 바로 거절된다.
    engine = create_engine(
        "postgresql+psycopg://nobody:nothing@127.0.0.1:1/none",
        connect_args={"connect_timeout": 1},
    )
    yield DatabaseRateLimiter(engine=engine)
    engine.dispose()


def _store_errors() -> int:
    counters = metrics.snapshot()["counters"]
    return sum(v for k, v in counters.items() if k.startswith("rate_limit.store_errors"))


def test_store_failure_lets_the_request_through(broken_store):
    """저장소 장애로 로그인·가입 전체를 막지 않는다 — 통과시키고 메트릭·로그를 남긴다."""
    before = _store_errors()
    broken_store.check("k", 1, 60.0)
    broken_store.check("k", 1, 60.0)
    broken_store.hit("k", 60.0)
    broken_store.reset("k")
    assert broken_store.retry_after("k", 1, 60.0) is None
    assert _store_errors() - before == 5


def test_store_failure_log_hides_the_email(broken_store, caplog):
    with caplog.at_level("ERROR", logger=rate_limit.__name__):
        broken_store.check("login-fail:secret@example.com", 1, 60.0)
    text_ = "\n".join(r.getMessage() for r in caplog.records)
    assert "login-fail" in text_
    assert "secret@example.com" not in text_


def test_zero_limit_blocks_without_touching_the_store(broken_store):
    """한도 0 은 메모리 구현처럼 첫 요청부터 막는다 — DB 에 가지 않는다."""
    before = _store_errors()
    with pytest.raises(HTTPException) as exc:
        broken_store.check("k", 0, 60.0)
    assert exc.value.status_code == 429
    assert _store_errors() == before


# ---------- DB 저장소: 판정 (DB) ----------


def _engine():
    from app.db.session import engine

    return engine


def _rows(key: str | None = None) -> int:
    sql = "SELECT count(*) FROM rate_limit_hits"
    params: dict[str, str] = {}
    if key is not None:
        sql += " WHERE key = :key"
        params["key"] = key
    with _engine().connect() as conn:
        return int(conn.execute(text(sql), params).scalar_one())


@pytest.fixture
def store(client):
    """빈 표에서 시작하는 DB 저장소. 끝나면 다시 비운다(스위트가 DB 를 공유한다)."""
    db_store = DatabaseRateLimiter()
    db_store.clear()
    yield db_store
    db_store.clear()


def _key() -> str:
    return f"rl-store-{uuid4().hex[:12]}"


def test_blocks_over_limit_with_retry_after(store):
    key = _key()
    for _ in range(3):
        store.check(key, 3, 60.0)
    with pytest.raises(HTTPException) as exc:
        store.check(key, 3, 60.0)
    assert exc.value.status_code == 429
    assert exc.value.headers["Retry-After"] == "60"
    # 막힌 시도는 기록하지 않는다 — 행 수는 한도 그대로다.
    assert _rows(key) == 3


def test_coded_detail_is_kept(store):
    key = _key()
    detail = {"code": "rate_limited", "message": "잠시 후"}
    store.check(key, 1, 60.0, detail=detail)
    with pytest.raises(HTTPException) as exc:
        store.check(key, 1, 60.0, detail=detail)
    assert exc.value.detail == detail


def test_keys_do_not_share_counts(store):
    first, second = _key(), _key()
    store.check(first, 1, 60.0)
    store.check(second, 1, 60.0)
    with pytest.raises(HTTPException):
        store.check(first, 1, 60.0)


def test_counts_survive_a_new_instance(store):
    """프로세스를 다시 만든 것과 같다 — 새 인스턴스도 앞의 기록을 본다(재배포·다른 태스크)."""
    key = _key()
    for _ in range(2):
        store.check(key, 2, 60.0)
    with pytest.raises(HTTPException):
        DatabaseRateLimiter().check(key, 2, 60.0)


def test_lockout_survives_a_new_instance(store):
    key = f"login-fail:{_key()}@oncare.com"
    for _ in range(3):
        store.hit(key, 900.0)
    retry = DatabaseRateLimiter().retry_after(key, 3, 900.0)
    assert retry is not None and 1 <= retry <= 900


def test_retry_after_does_not_count(store):
    key = _key()
    for _ in range(10):
        assert store.retry_after(key, 3, 60.0) is None
    assert _rows(key) == 0


def test_reset_clears_one_key_only(store):
    key, other = _key(), _key()
    for _ in range(3):
        store.hit(key, 60.0)
        store.hit(other, 60.0)
    store.reset(key)
    assert store.retry_after(key, 3, 60.0) is None
    assert store.retry_after(other, 3, 60.0) is not None


def test_window_expiry_reopens_and_retry_after_shrinks(store):
    key = _key()
    store.check(key, 1, 0.5)
    with pytest.raises(HTTPException):
        store.check(key, 1, 0.5)
    assert store.retry_after(key, 1, 0.5) == 1  # 1초 미만이 남아도 최소 1
    time.sleep(0.6)
    assert store.retry_after(key, 1, 0.5) is None
    store.check(key, 1, 0.5)  # 창이 지나면 다시 허용
    # 판정할 때 그 키의 만료 행을 지운다 — 방금 것 하나만 남는다.
    assert _rows(key) == 1


def test_purge_expired_removes_only_expired_rows(store):
    stale, live = _key(), _key()
    store.hit(stale, 0.2)
    store.hit(live, 60.0)
    time.sleep(0.3)
    assert store.purge_expired() == 1
    assert _rows(stale) == 0
    assert _rows(live) == 1


def test_periodic_sweep_drops_keys_that_never_come_back(client):
    """다시 오지 않는 키도 다른 키의 요청이 청소해 준다(메모리 구현의 #967 과 같은 성질)."""
    eager = DatabaseRateLimiter(sweep_interval=0.0)
    eager.clear()
    try:
        gone, other = _key(), _key()
        eager.check(gone, 3, 0.2)
        time.sleep(0.3)
        eager.check(other, 3, 60.0)
        assert _rows(gone) == 0
        assert _rows(other) == 1
    finally:
        eager.clear()


def test_module_purge_expired_uses_the_database_store(store, monkeypatch):
    monkeypatch.setattr(get_settings(), "rate_limit_store", "database")
    store.hit(_key(), 0.2)
    time.sleep(0.3)
    assert rate_limit.purge_expired() == 1


# ---------- DB 저장소: 동시성 (DB) ----------


def test_two_instances_racing_on_one_key_never_exceed_the_limit(store):
    """태스크 둘이 같은 키를 동시에 세도 한도만큼만 통과한다."""
    key = _key()
    limit = 5
    instances = [DatabaseRateLimiter(), DatabaseRateLimiter()]
    allowed: list[int] = []
    blocked: list[int] = []
    guard = threading.Lock()
    start = threading.Barrier(8)

    def worker(n: int) -> None:
        start.wait()
        for _ in range(4):
            try:
                instances[n % 2].check(key, limit, 60.0)
            except HTTPException:
                with guard:
                    blocked.append(n)
            else:
                with guard:
                    allowed.append(n)

    threads = [threading.Thread(target=worker, args=(n,)) for n in range(8)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    assert len(allowed) == limit
    assert len(blocked) == 8 * 4 - limit
    assert _rows(key) == limit


def test_racing_failures_lock_exactly_at_the_limit(store):
    """실패 기록(hit)이 동시에 쌓여도 잠금 판정은 실제 실패 수를 본다."""
    key = f"login-fail:{_key()}@oncare.com"
    threads = [
        threading.Thread(target=DatabaseRateLimiter().hit, args=(key, 900.0)) for _ in range(6)
    ]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert _rows(key) == 6
    assert store.retry_after(key, 5, 900.0) is not None
    assert store.retry_after(key, 7, 900.0) is None


# ---------- 엔드포인트: DB 저장소로 로그인 잠금 (DB) ----------


@pytest.fixture
def database_store(client, monkeypatch):
    """앱의 `limiter` 가 DB 저장소를 쓰게 한다."""
    settings = get_settings()
    monkeypatch.setattr(settings, "rate_limit_store", "database")
    monkeypatch.setattr(settings, "rate_limit_enabled", True)
    rate_limit.limiter.clear()
    yield settings
    rate_limit.limiter.clear()


def _register(client, email: str) -> None:
    response = client.post(
        "/v1/auth/register", json={"email": email, "password": PASSWORD, "name": "rl"}
    )
    assert response.status_code == 201, response.text


def _login(client, email: str, password: str):
    return client.post("/v1/auth/login", data={"username": email, "password": password})


def test_login_lockout_is_stored_in_the_database(client, database_store):
    email = f"rl-store-{uuid4().hex[:10]}@oncare.com"
    _register(client, email)
    for _ in range(database_store.login_max_failures):
        assert _login(client, email, "wrong-pw-0000").status_code == 401
    assert _rows() > 0

    # 메모리 상태를 버려도(재배포·다른 태스크) 잠금이 남는다.
    rate_limit.limiter.memory.clear()
    locked = _login(client, email, PASSWORD)
    assert locked.status_code == 429
    assert int(locked.headers["Retry-After"]) >= 1


def test_successful_login_clears_the_database_failures(client, database_store):
    email = f"rl-store-ok-{uuid4().hex[:10]}@oncare.com"
    _register(client, email)
    for _ in range(database_store.login_max_failures - 1):
        assert _login(client, email, "wrong-pw-0000").status_code == 401
    assert _login(client, email, PASSWORD).status_code == 200
    # 실패 기록이 지워졌다 — 앞의 실패와 합쳐 한도를 넘을 만큼 더 틀려도 잠기지 않는다.
    for _ in range(2):
        assert _login(client, email, "wrong-pw-0000").status_code == 401
    assert _login(client, email, PASSWORD).status_code == 200


def test_migration_creates_the_table_and_indexes():
    from pathlib import Path

    text_ = (
        Path(__file__).resolve().parents[1]
        / "migrations"
        / "versions"
        / "0150_rate_limit_hits.py"
    ).read_text(encoding="utf-8")
    assert 'revision: str = "0150_rate_limit_hits"' in text_
    assert 'down_revision: str | Sequence[str] | None = "0149_pt_program_off_daily_list"' in text_
    assert '"rate_limit_hits"' in text_
    assert "ix_rate_limit_hits_key_hit_at" in text_
    assert "ix_rate_limit_hits_expires_at" in text_
