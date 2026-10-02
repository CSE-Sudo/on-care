"""스키마와 모델이 같은지 — 마이그레이션·모델 불일치가 테스트 뒤에 숨지 않게(#2838).

CI 는 `AUTO_CREATE_TABLES=false` 로 앱을 띄워, 이 파일이 보는 스키마는 Alembic 이 만든
그대로다. (로컬에서 `create_all` 을 켠 채 돌리면 모델로 만든 표를 보게 되므로 같은 검사가
느슨해진다 — 정확한 판정은 CI 의 `alembic check` 단계가 한다.)
"""
from __future__ import annotations

import inspect as pyinspect
from pathlib import Path

import pytest
from alembic.autogenerate import compare_metadata
from alembic.migration import MigrationContext
from sqlalchemy import inspect

from app.db import init_db as init_db_module
from app.db.session import Base, engine

MIGRATIONS = Path(__file__).resolve().parents[1] / "migrations" / "versions"

#: 0127 이 NOT NULL 로 맞춘 시각 칸 — 모델은 처음부터 NOT NULL 이었다.
NOT_NULL_TIMESTAMPS = (
    ("chat_messages", "created_at"),
    ("routine_history", "created_at"),
    ("trainer_clients", "created_at"),
    ("trainer_profiles", "updated_at"),
    ("trainer_routines", "created_at"),
    ("trainer_schedule", "created_at"),
)


def test_model_declares_coach_document_source_ref_index():
    """0030 이 만든 (user_id, source_ref) 인덱스를 모델도 선언한다."""
    table = Base.metadata.tables["coach_documents"]
    by_name = {ix.name: ix for ix in table.indexes}
    ix = by_name.get("ix_coach_documents_user_source_ref")
    assert ix is not None
    assert [c.name for c in ix.columns] == ["user_id", "source_ref"]


@pytest.mark.parametrize(("table", "column"), NOT_NULL_TIMESTAMPS)
def test_model_timestamp_columns_are_not_null(table, column):
    assert Base.metadata.tables[table].c[column].nullable is False


def test_init_db_has_no_schema_patch_code():
    """스키마 보정은 마이그레이션으로만 한다 — 앱 기동 코드에 ALTER 가 남지 않는다."""
    assert not hasattr(init_db_module, "_relax_points_coupon_cost")
    source = pyinspect.getsource(init_db_module)
    assert "ALTER TABLE" not in source


def test_alignment_migration_backfills_before_not_null():
    """0127 은 남은 NULL 을 채운 뒤 제약을 건다 — 행을 지우지 않는다."""
    text = (MIGRATIONS / "0138_schema_model_alignment.py").read_text(encoding="utf-8")
    assert "IS NULL" in text
    assert text.index("UPDATE") < text.index("nullable=False")
    assert "DELETE" not in text


@pytest.mark.parametrize(("table", "column"), NOT_NULL_TIMESTAMPS)
def test_db_timestamp_columns_are_not_null(client, table, column):
    columns = {c["name"]: c for c in inspect(engine).get_columns(table)}
    assert columns[column]["nullable"] is False


def test_db_has_coach_document_source_ref_index(client):
    names = {ix["name"] for ix in inspect(engine).get_indexes("coach_documents")}
    assert "ix_coach_documents_user_source_ref" in names


def test_db_schema_matches_models(client):
    """DB 스키마와 모델 사이에 자동 생성할 변경이 없다(`alembic check` 와 같은 비교)."""
    with engine.connect() as conn:
        ctx = MigrationContext.configure(conn, opts={"compare_type": True})
        diff = compare_metadata(ctx, Base.metadata)
    assert diff == []
