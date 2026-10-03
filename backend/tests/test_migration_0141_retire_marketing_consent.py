"""0141 마이그레이션 — 마케팅 수신 동의 행에 철회 시각만 채운다. (#3007)"""
from __future__ import annotations

import importlib.util
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import patch
from uuid import uuid4

from sqlalchemy import select, text

from app.models.models import User, UserConsent

_VERSIONS = Path(__file__).resolve().parents[1] / "migrations" / "versions"
_MIGRATION = _VERSIONS / "0141_retire_marketing_consent.py"

AGREED = datetime(2026, 10, 1, 0, 0, tzinfo=timezone.utc)
EARLIER_REVOKE = datetime(2026, 10, 2, 0, 0, tzinfo=timezone.utc)


def _load_migration():
    spec = importlib.util.spec_from_file_location("m0141", _MIGRATION)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def _run(db_session, step: str) -> None:
    migration = _load_migration()
    with patch.object(
        migration.op,
        "execute",
        side_effect=lambda sql: db_session.execute(text(sql)),
    ):
        getattr(migration, step)()
    db_session.commit()


def test_revision_follows_the_previous_head():
    migration = _load_migration()
    assert migration.revision == "0141_retire_marketing_consent"
    assert migration.down_revision == "0140_program_draft_member"


def test_no_other_migration_branches_from_the_previous_head():
    """head 가 하나여야 한다 — 0140 을 부모로 두는 것은 0141 뿐."""
    children = [
        path.name
        for path in _VERSIONS.glob("*.py")
        if '"0140_program_draft_member"' in path.read_text(encoding="utf-8")
        and "down_revision" in path.read_text(encoding="utf-8")
        and path.name != "0140_program_draft_member.py"
    ]
    assert children == ["0141_retire_marketing_consent.py"]


def _user(db_session) -> User:
    user = User(
        id=f"user-m0141-{uuid4().hex[:8]}",
        email=f"m0141-{uuid4().hex[:8]}@example.com",
        name="마이그레이션",
        role="member",
    )
    db_session.add(user)
    db_session.flush()
    return user


def test_upgrade_revokes_marketing_rows_and_keeps_them(client, db_session):
    user = _user(db_session)
    marketing = UserConsent(
        user_id=user.id, kind="marketing", version="2026-10-01", agreed_at=AGREED
    )
    terms = UserConsent(
        user_id=user.id, kind="terms", version="2026-10-01", agreed_at=AGREED
    )
    db_session.add_all([marketing, terms])
    db_session.commit()
    try:
        _run(db_session, "upgrade")
        db_session.expire_all()

        rows = {
            row.kind: row
            for row in db_session.scalars(
                select(UserConsent).where(UserConsent.user_id == user.id)
            )
        }
        # 행은 남고(이력), 철회 시각만 채워진다.
        assert set(rows) == {"marketing", "terms"}
        assert rows["marketing"].revoked_at is not None
        assert rows["marketing"].agreed_at == AGREED
        # 다른 항목은 건드리지 않는다.
        assert rows["terms"].revoked_at is None
    finally:
        db_session.rollback()
        db_session.delete(db_session.get(User, user.id))
        db_session.commit()


def test_upgrade_keeps_an_existing_revoke_time(client, db_session):
    user = _user(db_session)
    db_session.add(
        UserConsent(
            user_id=user.id,
            kind="marketing",
            version="2026-10-01",
            agreed_at=AGREED,
            revoked_at=EARLIER_REVOKE,
        )
    )
    db_session.commit()
    try:
        _run(db_session, "upgrade")
        db_session.expire_all()
        row = db_session.scalar(
            select(UserConsent).where(UserConsent.user_id == user.id)
        )
        assert row.revoked_at == EARLIER_REVOKE
    finally:
        db_session.rollback()
        db_session.delete(db_session.get(User, user.id))
        db_session.commit()


def test_downgrade_clears_the_marketing_revoke_time(client, db_session):
    user = _user(db_session)
    db_session.add(
        UserConsent(
            user_id=user.id, kind="marketing", version="2026-10-01", agreed_at=AGREED
        )
    )
    db_session.commit()
    try:
        _run(db_session, "upgrade")
        _run(db_session, "downgrade")
        db_session.expire_all()
        row = db_session.scalar(
            select(UserConsent).where(UserConsent.user_id == user.id)
        )
        assert row.revoked_at is None
    finally:
        db_session.rollback()
        db_session.delete(db_session.get(User, user.id))
        db_session.commit()
