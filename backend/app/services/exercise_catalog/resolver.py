"""운동 이름 → 참조표 종목. 표 매칭 → 캐시 → AI 순서. (#1312)

세 경로를 이 순서로 두는 이유가 각각 있다.

1. **표 매칭 먼저.** 대부분의 입력은 종목 이름 그대로거나 별칭이라 여기서 붙는다.
   외부 호출도, 캐시 조회도 필요 없다.
2. **그다음 캐시.** 한 번 해석한 이름은 다시 묻지 않는다. 못 붙인 이름도 적어 둔다 —
   실패는 성공보다 자주 일어나므로, 실패를 캐시하지 않으면 해석되지 않는 이름을
   적을 때마다 계속 호출한다.
3. **마지막이 AI.** 여기까지 와야 호출이 일어난다.

## 해석 결과가 무엇을 바꾸나

종목이 붙으면 **유형도 참조표의 값이 맞다.** 회원이 `줄넘기` 를 근력으로 골라도
유산소이고, 집계는 그 유형으로 가야 주간 그래프가 맞는다. 다만 회원이 고른 유형을
덮어쓰지는 않는다 — 저장은 회원이 적은 대로 두고, 계산만 참조표 유형을 쓴다.
화면이 보여 준 적 없는 값으로 기록이 바뀌면 회원이 자기 기록을 못 알아본다.
"""
from __future__ import annotations

from dataclasses import dataclass

from sqlalchemy.orm import Session

from app.models.models import ExerciseNameMatch
from app.services.exercise_catalog import matcher, name_ai
from app.services.exercise_catalog.table import CatalogRow, load_rows


@dataclass(frozen=True, slots=True)
class Resolution:
    """이름 해석 한 건. 못 붙였으면 `row` 가 None 이다."""

    row: CatalogRow | None
    confidence: float
    #: catalog=표 매칭, ai=이름 해석 모델, none=붙이지 못함.
    resolver: str


_UNRESOLVED = Resolution(row=None, confidence=0.0, resolver="none")


def _by_id(rows: tuple[CatalogRow, ...], catalog_id: int) -> CatalogRow | None:
    return next((r for r in rows if r.id == catalog_id), None)


def resolve(db: Session, name: str, *, use_ai: bool = True) -> Resolution:
    """운동 이름을 종목 하나로. 붙지 않으면 `row=None`.

    `use_ai=False` 는 호출을 아예 막는다 — 폼 미리보기처럼 자주 불리는 자리에서
    표 매칭만 쓰고 싶을 때다.
    """
    norm = matcher.normalize(name)
    if not norm:
        return _UNRESOLVED

    rows = load_rows(db)
    if not rows:
        return _UNRESOLVED

    direct = matcher.match_in_rows(rows, name)
    if direct is not None:
        return Resolution(row=direct, confidence=1.0, resolver="catalog")

    cached = db.get(ExerciseNameMatch, norm)
    if cached is not None:
        row = _by_id(rows, cached.catalog_id) if cached.catalog_id else None
        if row is None:
            return _UNRESOLVED
        return Resolution(
            row=row, confidence=cached.confidence, resolver=cached.resolver
        )

    if not use_ai:
        return _UNRESOLVED

    guess = name_ai.resolve_name(name, [r.name for r in rows])
    if guess is None:
        # 못 붙였다는 사실도 적어 둔다. 다음에 같은 이름이 오면 묻지 않는다.
        _remember(db, norm, catalog_id=None, confidence=0.0)
        return _UNRESOLVED

    matched_name, confidence = guess
    row = next((r for r in rows if r.name == matched_name), None)
    if row is None:
        _remember(db, norm, catalog_id=None, confidence=0.0)
        return _UNRESOLVED

    _remember(db, norm, catalog_id=row.id, confidence=confidence)
    return Resolution(row=row, confidence=confidence, resolver="ai")


def _remember(
    db: Session, norm: str, *, catalog_id: int | None, confidence: float
) -> None:
    """해석 결과를 캐시에 적는다. 실패해도 계산은 이미 끝났으므로 삼킨다.

    같은 이름을 두 요청이 동시에 물으면 기본키가 충돌한다. 그때 터뜨릴 이유가
    없다 — 둘 다 같은 값을 쓰려던 참이고, 캐시는 계산의 전제가 아니다.

    **호출자의 세션이 아니라 따로 연 세션에 적는다(#3242).** 이 함수는 PT 완료의
    기록 동기화처럼 "커밋하지 않는다" 를 약속한 흐름 한가운데서도 불린다. 호출자
    세션에서 커밋하면 아직 끝나지 않은 변경이 중간에 확정되고, 키 충돌로 롤백하면
    그 변경이 조용히 버려진다. 별도 세션은 미리보기처럼 커밋하지 않는 요청에서도
    캐시를 남긴다 — savepoint 였다면 바깥이 커밋하지 않을 때 함께 사라진다.
    """
    bind = db.get_bind()
    with Session(getattr(bind, "engine", bind)) as cache_db:
        try:
            cache_db.merge(
                ExerciseNameMatch(
                    name_norm=norm,
                    catalog_id=catalog_id,
                    confidence=confidence,
                    resolver="ai",
                )
            )
            cache_db.commit()
        except Exception:  # noqa: BLE001 — 캐시 실패로 저장을 막지 않는다
            cache_db.rollback()
