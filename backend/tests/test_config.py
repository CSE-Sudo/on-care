"""설정(Settings) 검증 — DB 불필요."""
from __future__ import annotations

import pytest
from pydantic import ValidationError

from app.core.config import (
    DEFAULT_CORS_ALLOW_ORIGINS,
    DEFAULT_JWT_SECRET,
    MIN_PROD_JWT_SECRET_BYTES,
    Settings,
)


def test_dev_defaults(monkeypatch):
    # CI 는 AUTO_CREATE_TABLES=false 로 돈다(#2838). 기본값을 보려면 환경변수를 비운다.
    monkeypatch.delenv("AUTO_CREATE_TABLES", raising=False)
    s = Settings(_env_file=None)
    assert s.env == "dev"
    assert s.is_prod is False
    assert s.auto_create_tables is True
    assert s.api_v1_prefix == "/v1"


def test_prod_blocks_default_secret():
    """운영에서 기본 JWT_SECRET 을 쓰면 기동이 막혀야 한다(fail-fast)."""
    with pytest.raises(ValidationError):
        Settings(_env_file=None, env="prod", jwt_secret=DEFAULT_JWT_SECRET)


def _prod(**kw) -> Settings:
    """운영 정상 설정 헬퍼 — Alembic 이 스키마 소스이므로 auto_create_tables=False 명시."""
    base = dict(
        _env_file=None, env="prod",
        jwt_secret="a-strong-random-secret-value-for-prod-tests",
        cors_allow_origins="https://app.oncare.com",
        seed_demo_data=False,       # 운영은 데모 시드를 켤 수 없다(#2811)
        auto_create_tables=False,   # 운영은 Alembic 이 스키마 소스
        gemini_api_key="test-gemini-key",  # 운영은 사진 인식·임베딩 키 필수(#2812)
        # conftest 가 EMBEDDER=hash 를 환경변수로 심으므로 운영 값을 명시한다.
        recognizer="gemini",
        embedder="gemini",
    )
    base.update(kw)
    return Settings(**base)


def test_prod_ok_with_real_secret():
    s = _prod()
    assert s.is_prod is True
    assert s.auto_create_tables is False


def test_prod_blocks_auto_create_tables():
    """운영에서 AUTO_CREATE_TABLES=true 면 기동 거부(Alembic 만 스키마 소스)."""
    with pytest.raises(ValidationError):
        _prod(auto_create_tables=True)


def test_dev_keeps_auto_create_tables(monkeypatch):
    """개발에서는 create_all 편의 유지(기본 True)."""
    monkeypatch.delenv("AUTO_CREATE_TABLES", raising=False)
    assert Settings(_env_file=None).auto_create_tables is True


def test_auto_create_tables_env_false_is_respected(monkeypatch):
    """CI·운영처럼 AUTO_CREATE_TABLES=false 를 주면 create_all 을 끈다(#2838)."""
    monkeypatch.setenv("AUTO_CREATE_TABLES", "false")
    assert Settings(_env_file=None).auto_create_tables is False


def test_log_level_rejects_invalid():
    """LOG_LEVEL 은 허용값만(임의 문자열 금지)."""
    with pytest.raises(ValidationError):
        Settings(_env_file=None, log_level="LOUD")
    assert Settings(_env_file=None, log_level="DEBUG").log_level == "DEBUG"


def test_demo_fallback_is_off_by_default(monkeypatch):
    """환경변수 없이 뜨면 데모 폴백은 꺼져 있다(#2821)."""
    monkeypatch.delenv("ALLOW_DEMO_FALLBACK", raising=False)
    s = Settings(_env_file=None)
    assert s.allow_demo_fallback is False
    assert s.demo_fallback_enabled is False


def test_demo_fallback_gated_by_env():
    # 개발: 명시적으로 켜야 허용(.env.example 이 켠다)
    assert Settings(_env_file=None, allow_demo_fallback=True).demo_fallback_enabled is True
    # 운영: 설정과 무관하게 비활성(_prod 헬퍼가 seed/auto_create 가드를 모두 만족)
    assert _prod(allow_demo_fallback=True).demo_fallback_enabled is False
    # 명시적으로 끄면 개발에서도 비활성
    assert Settings(_env_file=None, allow_demo_fallback=False).demo_fallback_enabled is False


# --- DB URL 정규화(psycopg v3) 회귀 (#308, CodeRabbit 리뷰 반영) ---


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        # Railway/Heroku 스타일 postgres:// → psycopg v3 로 정규화
        (
            "postgres://u:p@host:5432/db",
            "postgresql+psycopg://u:p@host:5432/db",
        ),
        # 드라이버 없는 bare postgresql:// (Neon/Supabase) → psycopg v3
        (
            "postgresql://u:p@host:5432/db",
            "postgresql+psycopg://u:p@host:5432/db",
        ),
        # 이미 psycopg v3 명시 → 그대로
        (
            "postgresql+psycopg://u:p@host:5432/db",
            "postgresql+psycopg://u:p@host:5432/db",
        ),
        # 비-Postgres URL → 손대지 않음
        ("sqlite:///./local.db", "sqlite:///./local.db"),
    ],
)
def test_sqlalchemy_database_url_normalizes_to_psycopg_v3(raw: str, expected: str):
    s = Settings(_env_file=None, database_url=raw)
    assert s.sqlalchemy_database_url == expected


# --- JWT 시크릿 길이(#3029) ---


def test_prod_blocks_short_jwt_secret():
    with pytest.raises(ValidationError, match="JWT_SECRET"):
        _prod(jwt_secret="x" * (MIN_PROD_JWT_SECRET_BYTES - 1))


def test_prod_accepts_minimum_length_jwt_secret():
    assert _prod(jwt_secret="x" * MIN_PROD_JWT_SECRET_BYTES).is_prod is True


def test_prod_accepts_openssl_hex_secret():
    # 문서·예시의 생성법(openssl rand -hex 32)은 64자다.
    assert _prod(jwt_secret="ab" * 32).is_prod is True


def test_jwt_secret_length_is_counted_in_bytes():
    # 한글 11자 = 33바이트 → 통과, 10자 = 30바이트 → 거부.
    assert _prod(jwt_secret="가" * 11).is_prod is True
    with pytest.raises(ValidationError, match="JWT_SECRET"):
        _prod(jwt_secret="가" * 10)


def test_dev_allows_short_jwt_secret(monkeypatch):
    monkeypatch.delenv("ENV", raising=False)
    s = Settings(_env_file=None, jwt_secret="short")
    assert s.is_prod is False


# --- 운영 CORS 출처(#3029) ---


def test_prod_blocks_default_cors_origins():
    with pytest.raises(ValidationError, match="개발 기본값"):
        _prod(cors_allow_origins=DEFAULT_CORS_ALLOW_ORIGINS)


@pytest.mark.parametrize(
    "origins",
    [
        "https://app.oncare.com,https://localhost:3000",
        "https://127.0.0.1",
        "https://[::1]:8443",
        "https://LOCALHOST",
    ],
)
def test_prod_blocks_local_cors_hosts(origins: str):
    with pytest.raises(ValidationError, match="개발 호스트"):
        _prod(cors_allow_origins=origins)


@pytest.mark.parametrize(
    "origins",
    ["http://app.oncare.com", "app.oncare.com", "https://app.oncare.com,http://trainer.oncare.com"],
)
def test_prod_blocks_non_https_cors_origins(origins: str):
    with pytest.raises(ValidationError, match="https://"):
        _prod(cors_allow_origins=origins)


@pytest.mark.parametrize("origins", ["", " , ,"])
def test_prod_blocks_empty_cors_origins(origins: str):
    with pytest.raises(ValidationError, match="비어"):
        _prod(cors_allow_origins=origins)


def test_prod_accepts_https_origins_after_normalising_blanks():
    s = _prod(cors_allow_origins=" https://app.oncare.com , ,https://trainer.oncare.com ")
    assert s.cors_origin_list == ["https://app.oncare.com", "https://trainer.oncare.com"]
    assert s.cors_prod_problem() is None


def test_prod_accepts_https_origin_with_port():
    assert _prod(cors_allow_origins="https://app.oncare.com:8443").is_prod is True


def test_cors_checks_do_not_apply_outside_prod(monkeypatch):
    monkeypatch.delenv("ENV", raising=False)
    for env in ("dev", "staging"):
        s = Settings(_env_file=None, env=env, cors_allow_origins=DEFAULT_CORS_ALLOW_ORIGINS)
        assert s.is_prod is False


# --- 커밋 SHA(#3029) ---


def test_commit_sha_defaults_to_unknown(monkeypatch):
    monkeypatch.delenv("GIT_SHA", raising=False)
    assert Settings(_env_file=None).commit_sha == "unknown"


def test_commit_sha_reads_git_sha_env(monkeypatch):
    monkeypatch.setenv("GIT_SHA", "0123456789abcdef0123456789abcdef01234567")
    assert Settings(_env_file=None).commit_sha == "0123456789abcdef0123456789abcdef01234567"


def test_blank_commit_sha_is_unknown():
    assert Settings(_env_file=None, git_sha="   ").commit_sha == "unknown"
