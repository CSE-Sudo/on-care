"""기록 그래프 색 — 교환·고르기. (#2076)

기록 그래프(#2075)은 한 가지 색상 계열의 3단계 진하기로 그린다. 그 계열을 포인트로
바꾼다. 헬스장 쿠폰·보호권과 달리 **비용이 들지 않는 꾸밈**이라, 자주 보는 화면을
바꾸는 값싼 사용처다.

규칙:

- **기본 색**(`blue`, 회원앱 파랑)은 누구나 쓴다. 교환하지 않아도 고를 수 있고 표에
  행이 없다. 다른 색으로 갔다가 기본 색으로 되돌리는 것은 고른 행을 푸는 일이다.
- **교환** 한 색에 150P 다. **색 하나씩** 연다 — 한 번에 모두 열면 다시 모을 이유가
  없다. 이미 연 색은 다시 사지 못한다(`AlreadyUnlocked`).
- **기한이 없다.** 한 번 연 색은 계속 쓰고, 언제든 연 색 사이를 오간다. 색을 바꾸는
  데에는 포인트가 들지 않는다.
- 네 색을 모두 열면 사용처 목록에서 항목이 **빠진다** — 더 살 게 없는 카드를 막힌
  채 남겨 두지 않는다(`points_coupon_service.build_shop`).
- 고른 색은 서버에 있다. 기기를 바꿔도 유지된다.
"""
from __future__ import annotations

import uuid

from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core import clock
from app.models.models import GraphColor
from app.schemas.activity_api import GraphColorOut
from app.schemas.points_api import ExchangeOut
from app.services import points_service

#: 포인트 사용처의 항목 id — `points_coupon_service.CATALOG` 에 선다.
ITEM_ID = "graph_color"
#: 한 색의 값.
COST = 150

#: 포인트를 내지 않는 기본 색 — 회원앱 파랑.
BASE_COLOR = "blue"
#: 포인트로 여는 색. 화면 팔레트에 서는 순서 그대로다.
BUYABLE_COLORS: tuple[str, ...] = ("green", "purple", "orange", "pink")
#: 고를 수 있는 색 전부. 기본 색이 늘 첫 칸이다.
PALETTE: tuple[str, ...] = (BASE_COLOR, *BUYABLE_COLORS)

#: 사용·교환 내역의 근거 — 연 그래프 색.
SOURCE_GRAPH_COLOR = "graph_color"


class GraphColorError(Exception):
    """그래프 색 규칙 위반. 라우터가 상태코드로 옮긴다."""


class UnknownColor(GraphColorError):
    """파는 색이 아니다."""


class AlreadyUnlocked(GraphColorError):
    """이미 연 색이다 — 다시 살 필요가 없다."""


class ColorLocked(GraphColorError):
    """아직 열지 않은 색은 고를 수 없다."""


# ---- 조회 ----


def unlocked_colors(db: Session, member_id: str) -> list[str]:
    """고를 수 있는 색 — 기본 색과 포인트로 연 색. 팔레트 순서다."""
    bought = set(
        db.scalars(
            select(GraphColor.color).where(GraphColor.user_id == member_id)
        ).all()
    )
    return [c for c in PALETTE if c == BASE_COLOR or c in bought]


def current_color(db: Session, member_id: str) -> str:
    """지금 기록 그래프를 그리는 색. 고른 행이 없으면 기본 색이다."""
    picked = db.scalar(
        select(GraphColor.color).where(
            GraphColor.user_id == member_id, GraphColor.selected.is_(True)
        )
    )
    return picked or BASE_COLOR


def status(db: Session, member_id: str) -> GraphColorOut:
    """지금 색·연 색·팔레트·값. 기록 그래프 응답과 색 변경 응답이 같은 모양이다."""
    return GraphColorOut(
        current=current_color(db, member_id),
        unlocked=unlocked_colors(db, member_id),
        palette=list(PALETTE),
        cost=COST,
    )


def all_unlocked(db: Session, member_id: str) -> bool:
    """살 수 있는 색을 모두 열었는가. 사용처에서 항목을 뺄지 정한다."""
    bought = set(
        db.scalars(
            select(GraphColor.color).where(
                GraphColor.user_id == member_id,
                GraphColor.color.in_(BUYABLE_COLORS),
            )
        ).all()
    )
    return bought >= set(BUYABLE_COLORS)


# ---- 교환 ----


def exchange(
    db: Session,
    member_id: str,
    color: str | None,
    *,
    client_request_id: str | None = None,
) -> ExchangeOut:
    """포인트를 써서 색 하나를 연다. 연 색을 바로 고른 색으로 만든다. 커밋한다.

    [color] 는 앱이 색 고르기 시트에서 받은 값이다. 열자마자 기록 그래프가 그 색으로
    바뀌어야 "샀는데 아무 일도 없다" 가 되지 않으므로, 여는 것과 고르는 것을 한
    요청에서 끝낸다.

    [client_request_id] 로 이미 연 색이 있으면 새로 쓰지 않고 그 색을 돌려준다.
    기본 색·모르는 색은 [UnknownColor], 이미 연 색은 [AlreadyUnlocked], 잔액이
    모자라면 [points_service.InsufficientPoints] 다.
    """
    if client_request_id:
        existing = _by_request(db, member_id, client_request_id)
        if existing is not None:
            return _exchange_out(db, member_id)

    if color is None or color not in BUYABLE_COLORS:
        # 기본 색은 이미 누구나 쓰므로 살 것이 아니다 — 모르는 색과 같이 막는다.
        raise UnknownColor("고를 수 없는 색이에요.")

    points_service.lock_balance(db, member_id)
    if color in set(
        db.scalars(
            select(GraphColor.color).where(GraphColor.user_id == member_id)
        ).all()
    ):
        db.rollback()
        raise AlreadyUnlocked("이미 가지고 있는 색이에요.")
    current = points_service.balance(db, member_id)
    if current < COST:
        db.rollback()
        raise points_service.InsufficientPoints(COST - current)

    row = GraphColor(
        id=f"grs-{uuid.uuid4().hex[:12]}",
        user_id=member_id,
        color=color,
        cost=COST,
        client_request_id=client_request_id,
        acquired_at=clock.now(),
    )
    try:
        _clear_selection(db, member_id)
        row.selected = True
        db.add(row)
        db.flush()
        points_service.spend(
            db,
            member_id,
            reason=ITEM_ID,
            source_type=SOURCE_GRAPH_COLOR,
            source_id=row.id,
            cost=COST,
        )
        db.commit()
    except IntegrityError:
        db.rollback()
        if client_request_id:
            existing = _by_request(db, member_id, client_request_id)
            if existing is not None:
                return _exchange_out(db, member_id)
        raise
    return _exchange_out(db, member_id)


# ---- 고르기 ----


def select_color(db: Session, member_id: str, color: str) -> GraphColorOut:
    """그래프 색을 [color] 로 바꾼다. 커밋한다.

    포인트가 들지 않는다 — 이미 연 색 사이는 언제든 오간다. 기본 색(`blue`)은 고른
    행을 푸는 일이라 늘 고를 수 있다. 팔레트에 없는 색은 [UnknownColor], 아직 열지
    않은 색은 [ColorLocked] 다.
    """
    if color not in PALETTE:
        raise UnknownColor("없는 색이에요.")
    if color != BASE_COLOR and color not in unlocked_colors(db, member_id):
        raise ColorLocked("아직 열지 않은 색이에요.")
    _clear_selection(db, member_id)
    if color != BASE_COLOR:
        db.execute(
            update(GraphColor)
            .where(GraphColor.user_id == member_id, GraphColor.color == color)
            .values(selected=True)
            .execution_options(synchronize_session=False)
        )
    db.commit()
    return status(db, member_id)


# ---- 내부 ----


def _clear_selection(db: Session, member_id: str) -> None:
    """고른 색을 푼다. 새 색을 고르기 전에 늘 먼저 부른다 — 고른 색은 하나뿐이다."""
    db.execute(
        update(GraphColor)
        .where(GraphColor.user_id == member_id, GraphColor.selected.is_(True))
        .values(selected=False)
        .execution_options(synchronize_session=False)
    )


def _by_request(
    db: Session, member_id: str, client_request_id: str
) -> GraphColor | None:
    return db.scalar(
        select(GraphColor).where(
            GraphColor.user_id == member_id,
            GraphColor.client_request_id == client_request_id,
        )
    )


def _exchange_out(db: Session, member_id: str) -> ExchangeOut:
    return ExchangeOut(
        graph_color=status(db, member_id),
        spent=COST,
        balance=points_service.balance(db, member_id),
    )
