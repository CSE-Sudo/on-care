"""Neon 풀러 엔드포인트 거부(#3146) — DB 불필요.

풀러(`-pooler`)는 PgBouncer 트랜잭션 모드라 기동 마이그레이션의 세션 advisory lock 이
아무것도 직렬화하지 못하고, 연결 시작 옵션(`statement_timeout`)이 거절된다. 운영은
설정 단계와 마이그레이션 러너에서 멈추고, 개발·스테이징은 경고만 남기는지 본다.
"""
from __future__ import annotations

import pytest
from pydantic import ValidationError

from app.core import startup_checks
from app.core.config import Settings
from app.core.db_url import (
    database_host,
    direct_host,
    is_pooler_host,
    pooler_problem,
)
from scripts import migrate

POOLER = (
    "postgresql://app:secret-pw@ep-cool-name-123456-pooler.ap-southeast-1.aws.neon.tech"
    "/oncare?sslmode=require"
)
DIRECT = (
    "postgresql://app:secret-pw@ep-cool-name-123456.ap-southeast-1.aws.neon.tech"
    "/oncare?sslmode=require"
)
LOCAL = "postgresql+psycopg://oncare:oncare@localhost:5432/oncare"

_PROD = dict(
    _env_file=None,
    env="prod",
    jwt_secret="a-strong-random-secret-value-for-prod-tests",
    cors_allow_origins="https://app.oncare.com",
    seed_demo_data=False,
    auto_create_tables=False,
    # conftest 가 EMBEDDER=hash 를 환경변수로 심으므로 운영 값을 명시한다.
    gemini_api_key="test-gemini-key",
    recognizer="gemini",
    embedder="gemini",
    # 운영 메일 필수 가드(#3131)와 함께 병합돼도 이 파일이 깨지지 않게 둔다.
    smtp_host="smtp.example.com",
    mail_from="On-Care <no-reply@example.com>",
)


def _prod(**kw) -> Settings:
    return Settings(**{**_PROD, **kw})


# ---- 호스트 판정 ----


@pytest.mark.parametrize(
    ("url", "host"),
    [
        (POOLER, "ep-cool-name-123456-pooler.ap-southeast-1.aws.neon.tech"),
        (DIRECT, "ep-cool-name-123456.ap-southeast-1.aws.neon.tech"),
        (LOCAL, "localhost"),
        ("postgres://u:p@EP-X-POOLER.us-east-2.aws.neon.tech/db", "ep-x-pooler.us-east-2.aws.neon.tech"),
        ("postgresql+psycopg://u:p@127.0.0.1:5432/db", "127.0.0.1"),
        ("", ""),
        ("not a url", ""),
    ],
)
def test_database_host(url, host):
    assert database_host(url) == host


@pytest.mark.parametrize(
    ("host", "pooler"),
    [
        ("ep-cool-name-123456-pooler.ap-southeast-1.aws.neon.tech", True),
        ("EP-COOL-NAME-POOLER.us-east-2.aws.neon.tech", True),
        ("ep-cool-name-123456.ap-southeast-1.aws.neon.tech", False),
        ("localhost", False),
        ("127.0.0.1", False),
        # 다른 조각에 우연히 들어간 글자는 풀러가 아니다.
        ("db.my-pooler.example.com", False),
        ("pooler.example.com", False),
        ("", False),
    ],
)
def test_is_pooler_host(host, pooler):
    assert is_pooler_host(host) is pooler


def test_direct_host_strips_only_the_endpoint_suffix():
    assert (
        direct_host("ep-cool-name-123456-pooler.ap-southeast-1.aws.neon.tech")
        == "ep-cool-name-123456.ap-southeast-1.aws.neon.tech"
    )
    assert direct_host("localhost") == "localhost"


def test_pooler_problem_names_the_direct_endpoint_without_the_password():
    problem = pooler_problem(POOLER)
    assert problem is not None
    assert "-pooler" in problem
    assert "ep-cool-name-123456.ap-southeast-1.aws.neon.tech" in problem
    assert "직접 엔드포인트" in problem
    # 비밀번호·사용자·쿼리는 문구에 싣지 않는다.
    assert "secret-pw" not in problem
    assert "app:" not in problem


@pytest.mark.parametrize("url", [DIRECT, LOCAL, ""])
def test_no_problem_for_direct_or_local_addresses(url):
    assert pooler_problem(url) is None


# ---- 설정: 운영은 기동 거부 ----


def test_prod_refuses_a_pooler_database_url():
    with pytest.raises(ValidationError) as excinfo:
        _prod(database_url=POOLER)
    message = str(excinfo.value)
    assert "직접 DB 엔드포인트" in message
    assert "-pooler" in message
    assert "secret-pw" not in message


@pytest.mark.parametrize("url", [DIRECT, LOCAL])
def test_prod_accepts_direct_and_local_addresses(url):
    s = _prod(database_url=url)
    assert s.is_prod is True


@pytest.mark.parametrize("env", ["dev", "staging"])
def test_non_prod_boots_with_a_pooler_address(env):
    s = Settings(_env_file=None, env=env, database_url=POOLER)
    assert s.is_prod is False


# ---- 기동 점검: 개발·스테이징은 경고 ----


@pytest.mark.parametrize("env", ["dev", "staging"])
def test_startup_check_warns_outside_prod(env, caplog):
    s = Settings(_env_file=None, env=env, database_url=POOLER)
    with caplog.at_level("WARNING", logger="app.startup"):
        warnings = startup_checks.check(s)
    assert any("-pooler" in w for w in warnings)
    assert "secret-pw" not in caplog.text


def test_startup_check_is_quiet_for_a_direct_address():
    s = Settings(_env_file=None, env="dev", database_url=DIRECT)
    assert not any("-pooler" in w for w in startup_checks.check(s))


# ---- 마이그레이션 러너 ----


class _Connected(Exception):
    """러너가 DB 접속 단계까지 갔다는 표시."""


def _refuse_connect(*args, **kwargs):
    raise _Connected()


@pytest.mark.parametrize("env", ["prod", " PROD ", "production"])
def test_migrate_stops_before_connecting_in_prod(monkeypatch, capsys, env):
    monkeypatch.setenv("ENV", env)
    monkeypatch.setenv("DATABASE_URL", POOLER)
    monkeypatch.setattr(migrate.psycopg, "connect", _refuse_connect)

    assert migrate.main() == 1

    out = capsys.readouterr().out
    assert "[migrate] ERROR" in out
    assert "직접 엔드포인트" in out
    assert "secret-pw" not in out


@pytest.mark.parametrize("env", ["dev", "staging", ""])
def test_migrate_warns_and_continues_outside_prod(monkeypatch, capsys, env):
    monkeypatch.setenv("ENV", env)
    monkeypatch.setenv("DATABASE_URL", POOLER)
    monkeypatch.setattr(migrate.psycopg, "connect", _refuse_connect)

    with pytest.raises(_Connected):
        migrate.main()

    assert "[migrate] WARN" in capsys.readouterr().out


def test_migrate_connects_normally_for_a_direct_address(monkeypatch, capsys):
    monkeypatch.setenv("ENV", "prod")
    monkeypatch.setenv("DATABASE_URL", DIRECT)
    seen: list[str] = []

    def record(url, **kwargs):
        seen.append(url)
        raise _Connected()

    monkeypatch.setattr(migrate.psycopg, "connect", record)

    with pytest.raises(_Connected):
        migrate.main()

    assert seen == [DIRECT]
    assert "-pooler" not in capsys.readouterr().out


def test_migrate_and_settings_share_one_check():
    """러너와 설정 검증이 같은 판정 함수를 쓴다 — 기준이 따로 놀지 않는다."""
    import app.core.config as config

    assert migrate.pooler_problem is pooler_problem
    assert config.pooler_problem is pooler_problem
