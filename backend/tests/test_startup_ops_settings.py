"""기동 경로의 운영 설정. (#2912)

- 식단 사진 인식 타임아웃은 코드 상수가 아니라 설정(`RECOGNIZER_TIMEOUT_SECONDS`)에서 온다.
- `CREATE EXTENSION` 은 create_all 을 쓰는 개발 환경에서만 보낸다.
- 공개 근거 문서 재적재는 같은 DB 를 쓰는 인스턴스 중 한 곳만 한다(advisory lock).
- 기동 마이그레이션은 DB 연결에 한도(`MIGRATE_CONNECT_TIMEOUT`)를 둔다.

DB 가 필요한 시험은 로컬에서 skip 되고 CI(Postgres) 에서 실행된다.
"""
from __future__ import annotations

import importlib
from types import SimpleNamespace

import pytest

from app.core.config import Settings, get_settings

# --- 설정 ----------------------------------------------------------------------


def test_recognizer_timeout_default_is_sixty_seconds(monkeypatch):
    monkeypatch.delenv("RECOGNIZER_TIMEOUT_SECONDS", raising=False)
    assert Settings(_env_file=None).recognizer_timeout_seconds == 60.0


def test_recognizer_timeout_reads_the_environment(monkeypatch):
    monkeypatch.setenv("RECOGNIZER_TIMEOUT_SECONDS", "25")
    assert Settings(_env_file=None).recognizer_timeout_seconds == 25.0


# --- 인식기 --------------------------------------------------------------------


def test_gemini_recognizer_uses_the_timeout_setting(monkeypatch):
    pytest.importorskip("google.genai")
    from app.services.recognizer import gemini

    settings = get_settings()
    monkeypatch.setattr(settings, "gemini_api_key", "test-key")
    monkeypatch.setattr(settings, "recognizer_timeout_seconds", 12.5)
    captured: dict = {}

    class FakeClient:
        def __init__(self, **kwargs):
            captured.update(kwargs)

    monkeypatch.setattr(gemini.genai, "Client", FakeClient)

    gemini.GeminiVisionRecognizer()

    # google-genai 의 HttpOptions.timeout 은 밀리초다.
    assert captured["http_options"].timeout == 12_500


def test_litellm_recognizer_uses_the_timeout_setting(monkeypatch):
    openai = pytest.importorskip("openai")
    from app.services.recognizer import litellm_vision

    settings = get_settings()
    monkeypatch.setattr(settings, "litellm_api_key", "test-key")
    monkeypatch.setattr(settings, "recognizer_timeout_seconds", 7.0)
    captured: dict = {}

    class FakeOpenAI:
        def __init__(self, **kwargs):
            captured.update(kwargs)

    monkeypatch.setattr(openai, "OpenAI", FakeOpenAI)

    litellm_vision.LiteLLMVisionRecognizer()

    # openai SDK 의 timeout 은 초다.
    assert captured["timeout"] == 7.0


# --- CREATE EXTENSION -----------------------------------------------------------


class _RecordingEngine:
    def __init__(self) -> None:
        self.statements: list[str] = []

    def connect(self):
        engine = self

        class _Conn:
            def __enter__(self):
                return self

            def __exit__(self, *exc):
                return False

            def execute(self, statement, *args):
                engine.statements.append(str(statement))

            def commit(self):
                pass

        return _Conn()


def test_vector_extension_is_not_created_when_alembic_owns_the_schema(monkeypatch):
    from app.db import init_db

    engine = _RecordingEngine()
    monkeypatch.setattr(init_db, "engine", engine)

    init_db._ensure_vector_extension(SimpleNamespace(auto_create_tables=False))

    assert engine.statements == []


def test_vector_extension_is_created_for_create_all_development(monkeypatch):
    from app.db import init_db

    engine = _RecordingEngine()
    monkeypatch.setattr(init_db, "engine", engine)

    init_db._ensure_vector_extension(SimpleNamespace(auto_create_tables=True))

    assert engine.statements == ["CREATE EXTENSION IF NOT EXISTS vector"]


# --- 공개 근거 문서 재적재 잠금 ---------------------------------------------------


def _hold_lock(key: str):
    from sqlalchemy import text

    from app.db.session import engine

    conn = engine.connect()
    acquired = conn.execute(
        text("SELECT pg_try_advisory_lock(hashtext(:key))"), {"key": key}
    ).scalar()
    conn.commit()
    assert acquired
    return conn


def _release_lock(conn, key: str) -> None:
    from sqlalchemy import text

    conn.execute(text("SELECT pg_advisory_unlock(hashtext(:key))"), {"key": key})
    conn.commit()
    conn.close()


def test_session_advisory_lock_is_exclusive_and_released(db_session):
    from app.db import init_db

    key = "test:startup-ops-lock"
    with init_db._session_advisory_lock(key) as first:
        assert first is True
        # 커밋해도 풀리지 않는 세션 잠금이라 다른 연결은 잡지 못한다.
        with init_db._session_advisory_lock(key) as second:
            assert second is False
    # 빠져나오면 풀려 다시 잡힌다.
    with init_db._session_advisory_lock(key) as again:
        assert again is True


def test_public_docs_reload_is_skipped_while_another_instance_holds_the_lock(db_session):
    from sqlalchemy import text

    from app.db import init_db
    from app.models.models import ReferenceDataVersion

    name = init_db._PUBLIC_COACH_DOCS_VERSION
    db_session.execute(
        text("UPDATE reference_data_versions SET fingerprint = 'stale' WHERE name = :n"),
        {"n": name},
    )
    db_session.commit()

    holder = _hold_lock(init_db._PUBLIC_COACH_DOCS_LOCK)
    try:
        init_db._seed_public_coach_docs()
        db_session.expire_all()
        # 다른 인스턴스가 적재 중이므로 이 인스턴스는 손대지 않는다.
        assert db_session.get(ReferenceDataVersion, name).fingerprint == "stale"
    finally:
        _release_lock(holder, init_db._PUBLIC_COACH_DOCS_LOCK)

    # 잠금이 풀린 뒤의 기동은 다시 적재해 지문을 최신으로 맞춘다.
    init_db._seed_public_coach_docs()
    db_session.expire_all()
    assert db_session.get(ReferenceDataVersion, name).fingerprint != "stale"


# --- 기동 마이그레이션 연결 한도 ------------------------------------------------------


def _load_migrate(monkeypatch, timeout: str | None):
    pytest.importorskip("psycopg")
    if timeout is None:
        monkeypatch.delenv("MIGRATE_CONNECT_TIMEOUT", raising=False)
    else:
        monkeypatch.setenv("MIGRATE_CONNECT_TIMEOUT", timeout)
    import scripts.migrate as migrate

    return importlib.reload(migrate)


class _ConnectRefused(Exception):
    pass


def _capture_connect(monkeypatch, migrate) -> dict:
    captured: dict = {}

    def fake_connect(url, **kwargs):
        captured["url"] = url
        captured.update(kwargs)
        raise _ConnectRefused

    monkeypatch.setattr(migrate.psycopg, "connect", fake_connect)
    monkeypatch.setenv("DATABASE_URL", "postgresql+psycopg://u:p@db.invalid:5432/app")
    return captured


def test_migrate_connects_with_a_default_timeout(monkeypatch):
    migrate = _load_migrate(monkeypatch, None)
    captured = _capture_connect(monkeypatch, migrate)

    with pytest.raises(_ConnectRefused):
        migrate.main()

    assert captured["connect_timeout"] == 10
    # psycopg 는 SQLAlchemy 드라이버 접두사를 모른다.
    assert captured["url"].startswith("postgresql://")


def test_migrate_connect_timeout_reads_the_environment(monkeypatch):
    migrate = _load_migrate(monkeypatch, "3")
    captured = _capture_connect(monkeypatch, migrate)

    with pytest.raises(_ConnectRefused):
        migrate.main()

    assert captured["connect_timeout"] == 3
