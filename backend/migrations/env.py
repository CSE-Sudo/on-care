"""Alembic 환경 설정.

DB URL 과 메타데이터를 app 코드에서 가져와, 마이그레이션과 앱이
같은 스키마 정의를 공유하게 합니다. (URL 은 .env 의 DATABASE_URL)
그래서 `alembic.ini` 에는 DB URL 을 적지 않습니다.

리비전 파일명은 `0001_slug` 형태입니다(`alembic.ini` 의 `file_template`).

**`alembic.ini` 는 ASCII 로만 유지합니다.** Alembic 이 그 파일을 로케일
인코딩으로 읽어서(`ConfigParser.read(..., encoding="locale")`), 한국어
Windows 의 cp949 에서는 한글 한 글자만 있어도 `alembic` 명령이 전부
`UnicodeDecodeError` 로 죽습니다. 리눅스 CI 는 UTF-8 로케일이라 통과해서
드러나지 않고, `PYTHONUTF8=1` 로도 잡히지 않습니다 — PEP 686 상
`encoding="locale"` 은 UTF-8 모드를 무시합니다. 설명이 필요하면 한글로
적을 수 있는 이 파일이나 `README.md` 에 씁니다. (#2004)
"""
from __future__ import annotations

from logging.config import fileConfig

from alembic import context
from sqlalchemy import engine_from_config, pool

from app.core.config import get_settings
from app.db.session import Base

# app 모델을 import 해야 Base.metadata 에 테이블이 등록된다.
from app.models import models  # noqa: F401

config = context.config

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# 실행 시점의 실제 DB URL 주입 (하드코딩 방지).
# sqlalchemy_database_url: 관리형 Postgres(Railway/Neon/Supabase)가 주는
# postgres:// · bare postgresql:// 를 psycopg v3 드라이버로 정규화한 값. Alembic 도
# 앱과 동일한 URL 로 엔진을 만들어야 bare URL 에서 psycopg2 dialect 오류로 마이그레이션이
# 실패하지 않는다(앱 기동 전 단계).
# set_main_option 값은 ConfigParser 를 거치므로 URL 의 '%'(예: 비밀번호의 %40)가
# 보간 문법으로 해석돼 InterpolationSyntaxError 를 낼 수 있다. '%%' 로 이스케이프해
# 앱은 뜨는데 마이그레이션만 깨지는 상황을 방지한다.
sqlalchemy_url = get_settings().sqlalchemy_database_url.replace("%", "%%")
config.set_main_option("sqlalchemy.url", sqlalchemy_url)

target_metadata = Base.metadata


def run_migrations_offline() -> None:
    """오프라인(--sql) 모드: DB 연결 없이 SQL 생성."""
    context.configure(
        url=config.get_main_option("sqlalchemy.url"),
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        compare_type=True,
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    """온라인 모드: 실제 DB 에 연결해 마이그레이션."""
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
            compare_type=True,
        )
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
