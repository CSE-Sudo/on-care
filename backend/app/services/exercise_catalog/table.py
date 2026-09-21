"""`exercise_catalog` 참조표 로딩 + 프로세스 캐시.

`nutrition.table` 과 같은 구조다 — 시딩 후 읽기 전용이고 전체가 수백 행이라,
요청마다 다시 읽을 이유가 없다. 운동 이름 미리보기는 폼에서 여러 번 불리므로
식단(사진 한 장에 한 번)보다 오히려 자주 읽힌다.

ORM 인스턴스를 캐시하지 않는 이유도 같다: 세션에 묶인 인스턴스는 커밋 시 만료되고
세션이 닫히면 detached 라, 다음 요청에서 속성을 읽는 순간 터진다. 필요한 값만
복사한 불변 스냅샷을 캐시한다.

무효화도 같다 — `ExerciseCatalogItem` 을 건드린 세션이 커밋/롤백하면 자동으로
비운다. ORM 을 거치지 않는 변경(마이그레이션, 임포트 스크립트의 bulk insert)은
훅이 잡지 못하므로 그런 경로에서는 `invalidate()` 를 직접 부른다.
"""
from __future__ import annotations

import threading
from dataclasses import dataclass, fields

from sqlalchemy import event, select
from sqlalchemy.orm import Session

from app.models.models import ExerciseCatalogItem


@dataclass(frozen=True, slots=True)
class CatalogRow:
    """세션에 묶이지 않은 `exercise_catalog` 한 행."""

    id: int
    name: str
    name_norm: str
    aliases_norm: str
    type: str
    met: float
    #: 버티는 운동인가 — 폼이 `횟수` 대신 `초` 를 묻는 기본값이다. (#1969)
    isometric: bool
    source: str


_lock = threading.Lock()
_cache: tuple[CatalogRow, ...] | None = None
# 로드 중에 들어온 무효화를 놓치지 않기 위한 세대 번호.
_generation = 0

# 조회 순서를 필드에서 파생시켜야 위치 기반 생성이 어긋날 수 없다.
_COLUMNS = tuple(getattr(ExerciseCatalogItem, f.name) for f in fields(CatalogRow))


def load_rows(db: Session) -> tuple[CatalogRow, ...]:
    """참조표 전건. 캐시가 살아 있으면 DB 를 치지 않는다."""
    global _cache

    cached = _cache
    if cached is not None:
        return cached

    with _lock:
        generation = _generation
    rows = tuple(CatalogRow(*r) for r in db.execute(select(*_COLUMNS)))

    with _lock:
        if generation == _generation:
            _cache = rows
    return rows


def invalidate() -> None:
    """캐시를 비운다. ORM 을 거치지 않는 변경 뒤에 직접 부른다."""
    global _cache, _generation
    with _lock:
        _cache = None
        _generation += 1


_DIRTY_KEY = "oncare_exercise_catalog_dirty"


@event.listens_for(Session, "after_flush")
def _mark_dirty(session: Session, flush_context: object) -> None:
    if any(
        isinstance(obj, ExerciseCatalogItem)
        for obj in (*session.new, *session.dirty, *session.deleted)
    ):
        session.info[_DIRTY_KEY] = True


# 커밋뿐 아니라 롤백에서도 비운다 — 커밋 전 같은 세션에서 캐시가 채워졌다면
# 아직 확정되지 않은 행이 들어갔을 수 있다.
@event.listens_for(Session, "after_commit")
@event.listens_for(Session, "after_soft_rollback")
def _invalidate_if_dirty(session: Session, *_: object) -> None:
    if session.info.pop(_DIRTY_KEY, False):
        invalidate()
