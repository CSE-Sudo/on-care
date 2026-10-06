"""DB 커넥션 풀·쿼리 실행 상한·LLM 대기 중 연결 반납. (#2836)

- 설정 → 엔진 인자, 연결 반납 규칙은 순수 테스트(DB 불필요).
- 실행 상한 초과 쿼리, AI 코치가 LLM 을 기다리는 동안의 풀 체크아웃 수, 하루 한도·
  포인트 회귀는 DB 테스트(로컬 skip, CI 실행).
"""
from __future__ import annotations

from types import SimpleNamespace
from uuid import uuid4

import pytest
from sqlalchemy import select

from app.core.config import Settings, get_settings


def _settings(**kw) -> Settings:
    return Settings(_env_file=None, **kw)


# ---------- 설정 → 엔진 인자 ----------


def test_pool_defaults_fail_fast_instead_of_waiting_30s():
    fields = Settings.model_fields
    assert fields["db_pool_size"].default == 5
    assert fields["db_max_overflow"].default == 10
    assert fields["db_pool_timeout_seconds"].default == 10.0
    assert fields["db_pool_recycle_seconds"].default == 300
    assert fields["db_statement_timeout_ms"].default == 10_000


def test_engine_kwargs_carry_every_pool_setting():
    from app.db.session import engine_kwargs_for

    kw = engine_kwargs_for(
        _settings(
            db_pool_size=7,
            db_max_overflow=3,
            db_pool_timeout_seconds=4.5,
            db_pool_recycle_seconds=120,
            db_statement_timeout_ms=2500,
            db_connect_timeout_seconds=6,
        )
    )
    assert kw["pool_pre_ping"] is True
    assert kw["pool_size"] == 7
    assert kw["max_overflow"] == 3
    assert kw["pool_timeout"] == 4.5
    assert kw["pool_recycle"] == 120
    assert kw["connect_args"] == {
        "connect_timeout": 6,
        "options": "-c statement_timeout=2500",
    }


@pytest.mark.parametrize("ms", [0, -1])
def test_statement_timeout_can_be_turned_off(ms):
    from app.db.session import connect_args_for

    args = connect_args_for(_settings(db_statement_timeout_ms=ms))
    assert "options" not in args
    assert "connect_timeout" in args


def test_the_app_engine_uses_the_configured_pool():
    from app.db.session import engine

    s = get_settings()
    pool = engine.pool
    assert pool.size() == s.db_pool_size
    assert pool._max_overflow == s.db_max_overflow
    assert pool._timeout == s.db_pool_timeout_seconds
    assert pool._recycle == s.db_pool_recycle_seconds


def test_pool_status_reports_checkouts():
    from app.db.session import pool_status

    status = pool_status()
    assert {"size", "checked_out", "overflow", "max_overflow"} <= set(status)
    assert status["size"] == get_settings().db_pool_size


# ---------- 연결 반납 규칙 ----------


class _FakeSession:
    def __init__(self, *, pending: str | None = None, in_tx: bool = True):
        self.new = {"x"} if pending == "new" else set()
        self.dirty = {"x"} if pending == "dirty" else set()
        self.deleted = {"x"} if pending == "deleted" else set()
        self._in_tx = in_tx
        self.commits = 0
        self.info: dict = {}

    def in_transaction(self) -> bool:
        return self._in_tx

    def commit(self) -> None:
        self.commits += 1
        self._in_tx = False


def test_release_ends_a_read_only_transaction():
    from app.db.session import release_connection

    db = _FakeSession()
    assert release_connection(db) is True
    assert db.commits == 1


@pytest.mark.parametrize("pending", ["new", "dirty", "deleted"])
def test_release_leaves_pending_writes_alone(pending):
    """호출자의 트랜잭션 경계를 바꾸지 않는다 — 쓰다 만 변경을 커밋하지 않는다."""
    from app.db.session import release_connection

    db = _FakeSession(pending=pending)
    assert release_connection(db) is False
    assert db.commits == 0


def test_release_tolerates_no_session():
    from app.db.session import release_connection

    assert release_connection(None) is False


def test_release_is_a_no_op_without_a_transaction():
    from app.db.session import release_connection

    db = _FakeSession(in_tx=False)
    assert release_connection(db) is True
    assert db.commits == 0


def test_release_leaves_a_marked_write_alone():
    """대기 변경이 비어 있어도 이번 트랜잭션에 쓴 표시가 있으면 커밋하지 않는다(#3253)."""
    from app.db.session import _WROTE_KEY, release_connection

    db = _FakeSession()
    db.info[_WROTE_KEY] = True
    assert release_connection(db) is False
    assert db.commits == 0


# ---------- 연결 반납 규칙: 실제 세션(SQLite 메모리, #3253) ----------


@pytest.fixture
def sqlite_session():
    """이벤트 표시를 실제 `Session` 으로 확인한다. 앱 모델(pgvector)과 무관한 표 하나."""
    from sqlalchemy import Integer, String, create_engine
    from sqlalchemy.orm import DeclarativeBase, Session, mapped_column

    class _Base(DeclarativeBase):
        pass

    class _Row(_Base):
        __tablename__ = "release_probe"
        # 이 파일은 `from __future__ import annotations` 라 지역 클래스의 `Mapped[...]`
        # 주석을 풀지 못한다 — 주석 없이 열을 적는다.
        id = mapped_column(Integer, primary_key=True)
        name = mapped_column(String)

    engine = create_engine("sqlite://")
    _Base.metadata.create_all(engine)
    with Session(engine) as db:
        yield db, _Row
    engine.dispose()


def test_release_does_not_commit_a_flushed_write(sqlite_session):
    from app.db.session import release_connection

    db, Row = sqlite_session
    db.add(Row(id=1, name="a"))
    db.flush()
    assert not (db.new or db.dirty or db.deleted)

    assert release_connection(db) is False
    assert db.in_transaction()
    db.rollback()
    assert db.scalar(select(Row).where(Row.id == 1)) is None


def test_release_does_not_commit_an_executed_delete(sqlite_session):
    """flush 를 거치지 않는 `db.execute(delete(...))` 도 쓰기다."""
    from sqlalchemy import delete

    from app.db.session import release_connection

    db, Row = sqlite_session
    db.add(Row(id=1, name="a"))
    db.commit()

    db.execute(delete(Row).where(Row.id == 1))
    assert release_connection(db) is False
    db.rollback()
    assert db.scalar(select(Row).where(Row.id == 1)) is not None


def test_release_ends_a_real_read_only_transaction(sqlite_session):
    from app.db.session import release_connection

    db, Row = sqlite_session
    db.execute(select(Row))
    assert db.in_transaction()
    assert release_connection(db) is True
    assert not db.in_transaction()


def test_release_works_again_after_the_write_is_committed(sqlite_session):
    """커밋하면 쓰기 표시가 지워져, 그 뒤 읽기만 한 트랜잭션은 다시 반납한다."""
    from app.db.session import release_connection

    db, Row = sqlite_session
    db.add(Row(id=1, name="a"))
    db.flush()
    assert release_connection(db) is False
    db.commit()

    db.execute(select(Row))
    assert release_connection(db) is True
    assert not db.in_transaction()


def test_release_works_again_after_a_rollback(sqlite_session):
    from app.db.session import release_connection

    db, Row = sqlite_session
    db.add(Row(id=1, name="a"))
    db.flush()
    db.rollback()

    db.execute(select(Row))
    assert release_connection(db) is True


def test_a_savepoint_end_keeps_the_outer_write_mark(sqlite_session):
    """세이브포인트가 끝나도 바깥 트랜잭션의 쓰기는 남아 있다."""
    from app.db.session import release_connection

    db, Row = sqlite_session
    db.add(Row(id=1, name="a"))
    db.flush()
    with db.begin_nested():
        db.execute(select(Row))
    assert release_connection(db) is False


# ---------- DB: 실행 상한 ----------


def test_a_query_over_the_statement_timeout_is_cancelled(client):
    """실행 상한을 넘는 쿼리는 연결을 무기한 쥐지 않고 오류로 끝난다."""
    from sqlalchemy import create_engine, text
    from sqlalchemy.exc import OperationalError

    from app.db.session import engine_kwargs_for

    s = get_settings()
    kw = engine_kwargs_for(_settings(db_statement_timeout_ms=200, db_pool_size=1))
    eng = create_engine(s.sqlalchemy_database_url, **kw)
    try:
        with eng.connect() as conn:
            assert conn.execute(text("SHOW statement_timeout")).scalar() == "200ms"
            with pytest.raises(OperationalError, match="statement timeout"):
                conn.execute(text("SELECT pg_sleep(2)"))
    finally:
        eng.dispose()


def test_app_sessions_run_under_the_configured_statement_timeout(client):
    from sqlalchemy import text

    from app.db.session import SessionLocal

    db = SessionLocal()
    try:
        shown = db.execute(text("SHOW statement_timeout")).scalar()
    finally:
        db.close()
    ms = get_settings().db_statement_timeout_ms
    assert shown == (f"{ms // 1000}s" if ms % 1000 == 0 else f"{ms}ms")


# ---------- DB: LLM 대기 중 연결 반납 ----------


def _member(client) -> tuple[str, dict[str, str]]:
    email = f"pool-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register", json={"email": email, "password": "test-pw-1234", "name": "u"}
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "test-pw-1234"}
    ).json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    return client.get("/v1/users/me", headers=headers).json()["id"], headers


@pytest.fixture
def watching_llm(monkeypatch):
    """LLM 을 기다리는 순간의 풀 체크아웃 수를 적어 두는 가짜 LLM."""
    from app.db.session import engine
    from app.services.coach import chat as chat_service
    from app.services.coach.llm_base import LLMResult

    seen: dict[str, int] = {}

    class _WatchingLLM:
        name = "watching"
        model_name = "watching-1"

        def generate(self, system_prompt: str, user_prompt: str) -> LLMResult:
            seen["checked_out"] = engine.pool.checkedout()
            return LLMResult(text="물을 한 컵 더 드세요.", model="watching-1")

    monkeypatch.setattr(chat_service, "get_coach_llm", lambda *a, **k: _WatchingLLM())
    return seen


def test_coach_answer_holds_no_connection_while_waiting_for_the_llm(
    client, db_session, watching_llm
):
    from app.db.session import engine
    from app.models.models import User
    from app.services.coach.chat import answer

    user_id, _ = _member(client)
    db_session.scalar(select(User.id).where(User.id == user_id))  # 연결을 빌린다
    assert db_session.in_transaction()
    holding = engine.pool.checkedout()

    reply, _, generated = answer(db_session, user_id, "물 얼마나 마셔요?")

    assert generated is True
    assert reply
    assert watching_llm["checked_out"] == holding - 1


def test_ai_coach_chat_releases_the_request_connection_during_the_llm(
    client, watching_llm
):
    """요청 세션이 LLM 대기 내내 연결을 쥐지 않는다 — 답 저장·한도 집계는 그대로."""
    from app.db.session import engine

    _, h = _member(client)
    before = engine.pool.checkedout()

    r = client.post("/v1/ai-coach/chat", headers=h, json={"message": "물 얼마나?"})

    assert r.status_code == 200, r.text
    assert watching_llm["checked_out"] == before
    body = r.json()
    assert body["reply"] == "물을 한 컵 더 드세요."
    assert body["points_spent"] == 0
    assert body["quota"]["free_left"] == get_settings().coach_chat_free_per_day - 1


def test_paid_chat_still_spends_points_after_the_connection_is_released(
    client, db_session, watching_llm, monkeypatch
):
    """반납 뒤 새 연결로 저장·차감한다 — 포인트 차감 회귀."""
    from app.models.models import HealthProfile

    s = get_settings()
    monkeypatch.setattr(s, "coach_chat_free_per_day", 0)
    monkeypatch.setattr(s, "coach_chat_paid_per_day", 1)
    monkeypatch.setattr(s, "coach_chat_paid_cost", 50)
    user_id, h = _member(client)
    db_session.expire_all()
    profile = db_session.scalar(select(HealthProfile).where(HealthProfile.user_id == user_id))
    if profile is None:
        db_session.add(HealthProfile(user_id=user_id, activity_points=120))
    else:
        profile.activity_points = 120
    db_session.commit()

    r = client.post(
        "/v1/ai-coach/chat",
        headers=h,
        json={"message": "물 얼마나?", "pay_with_points": True},
    )

    assert r.status_code == 200, r.text
    assert r.json()["points_spent"] == 50
    assert r.json()["balance_after"] == 70
    again = client.post(
        "/v1/ai-coach/chat",
        headers=h,
        json={"message": "또?", "pay_with_points": True},
    )
    assert again.status_code == 429
    assert again.json()["detail"]["code"] == "daily_limit"


def test_domain_coach_releases_before_the_llm(monkeypatch):
    """회원 홈 코칭(RAG)도 LLM 직전에 연결을 돌려준다."""
    from app.schemas.misc_api import CoachSuggestion
    from app.services.coach import domain_coaches

    calls: list[str] = []
    monkeypatch.setattr(domain_coaches, "retrieve_context", lambda *a, **k: "근거")
    monkeypatch.setattr(
        domain_coaches, "release_connection", lambda db: calls.append("release") or True
    )

    class _LLM:
        def generate(self, system_prompt, user_prompt):
            calls.append("generate")
            return SimpleNamespace(text="물을 더 드세요.")

    monkeypatch.setattr(domain_coaches, "get_coach_llm", lambda: _LLM())
    fallback = CoachSuggestion(tag="t", title="제목", body="규칙")

    out = domain_coaches._rag_suggestion(
        object(), "u-1", domain="diet", system_prompt="s", query="q",
        tag="t", title="제목", fallback=fallback,
    )

    assert out.body == "물을 더 드세요."
    assert calls == ["release", "generate"]
