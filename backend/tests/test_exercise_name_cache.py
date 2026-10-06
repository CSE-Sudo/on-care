"""운동 이름 해석 캐시는 호출자의 트랜잭션을 건드리지 않는다. (#3242)

`resolver._remember` 는 PT 완료의 기록 동기화처럼 "커밋하지 않는다" 를 약속한
흐름 한가운데서도 불린다. 캐시를 적는다고 그 흐름의 변경을 중간에 확정하거나,
캐시가 실패했다고 그 변경을 되돌리면 안 된다.

DB 가 필요하다(로컬 skip, CI 실행).
"""
from __future__ import annotations

from uuid import uuid4

import pytest
from sqlalchemy import delete

from app.db.session import SessionLocal
from app.models.models import ExerciseNameMatch
from app.services.exercise_catalog import resolver


def _key(tag: str) -> str:
    return f"t3242-{tag}-{uuid4().hex[:8]}"


def _exists(norm: str) -> bool:
    with SessionLocal() as s:
        return s.get(ExerciseNameMatch, norm) is not None


@pytest.fixture
def keys(client):
    made: list[str] = []
    yield made
    with SessionLocal() as s:
        s.execute(delete(ExerciseNameMatch).where(ExerciseNameMatch.name_norm.in_(made)))
        s.commit()


def test_cache_write_does_not_commit_the_callers_pending_work(db_session, keys):
    pending, cached = _key("pending"), _key("cached")
    keys.extend([pending, cached])
    db_session.add(ExerciseNameMatch(name_norm=pending, catalog_id=None, confidence=0.0))
    db_session.flush()

    resolver._remember(db_session, cached, catalog_id=None, confidence=0.0)

    # 호출자의 트랜잭션은 그대로 열려 있고, 캐시는 따로 확정됐다.
    assert db_session.in_transaction()
    assert _exists(cached)
    db_session.rollback()
    assert not _exists(pending)


def test_cache_failure_does_not_roll_back_the_callers_pending_work(db_session, keys):
    pending, cached = _key("pending"), _key("broken")
    keys.extend([pending, cached])
    db_session.add(ExerciseNameMatch(name_norm=pending, catalog_id=None, confidence=0.0))
    db_session.flush()

    # 없는 종목 id — 캐시 세션의 커밋이 외래키로 실패한다.
    resolver._remember(db_session, cached, catalog_id=-1, confidence=0.5)

    assert not _exists(cached)
    db_session.commit()
    assert _exists(pending)
