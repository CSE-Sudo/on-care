"""트레이너 도메인 — 회원별 트레이너 메모. (#706)"""
from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import date, datetime, timezone

from sqlalchemy import or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core import clock
from app.models.models import (
    ExerciseSession, RoutineHistory,
    TrainerClientMemo,
)
from app.schemas.trainer_api import (
    TrainerMemoOut,
)
from app.services import (
    exercise_activity,
)
from app.services.trainer._common import (
    _iso_day_or_none,
    _today,
    history_kind_code,
)
from app.services.trainer.routines import (
    RoutineNotFound,
)


# ---- 회원별 트레이너 메모 (#706) ----


class MemoNotFound(Exception):
    """그 트레이너·회원 쌍에 그 id 의 메모가 없다(라우터가 404 로 변환)."""


class MemoCategoryLocked(Exception):
    """직접 쓴 메모가 아니라 분류를 바꿀 수 없다(라우터가 400 으로 변환). (#2622)"""


def _memo_out(memo: TrainerClientMemo) -> TrainerMemoOut:
    return TrainerMemoOut(
        id=memo.id,
        body=memo.body,
        source=memo.source,
        insight_id=memo.insight_id,
        insight_kind=memo.insight_kind,
        ref_kind=memo.ref_kind or None,
        ref_id=memo.ref_id,
        ref_date=memo.ref_date,
        ref_name=memo.ref_name or "",
        category=memo.category or "",
        created_at=memo.created_at,
        updated_at=memo.updated_at,
    )


@dataclass(frozen=True)
class _MemoRef:
    """운동 기록 메모가 가리키는 기록 — 서버가 그 기록에서 읽어 채운 값."""

    kind: str
    ref_id: str | None
    day: str | None
    name: str = ""


def _resolve_exercise_memo_ref(
    db: Session,
    trainer_id: str,
    member_id: str,
    *,
    ref_id: str | None,
    ref_date: date | None,
    ref_kind: str | None = None,
) -> _MemoRef:
    """운동 탭 기록 카드가 가리키는 기록을 찾아 출처 표시 값을 채운다. (#2332)

    앱이 보낸 이름·날짜는 믿지 않는다 — 그 기록이 트레이너 화면에 보이는 것
    ([build_client_history] 와 같은 범위: 자율 운동 + 내가 지도한 PT + 내가 배정한
    수행)일 때만 잇고, 이름과 날짜는 기록에서 읽는다. 없거나 남의 기록이면
    [RoutineNotFound] 다(있는지 없는지를 가르지 않는다).
    """
    if ref_date is not None:
        # 날짜로 가리키면 그날의 한 상자(`personal`·`member_log`) 또는 그날
        # 운동 기록 전체(`day`)에 다는 메모다(#2508). 오지 않은 날의 기록은 없다.
        if ref_date > _today():
            raise RoutineNotFound("운동 기록을 찾을 수 없습니다.")
        return _MemoRef(
            kind=ref_kind or "day", ref_id=None, day=ref_date.isoformat()
        )


    history = db.scalar(
        select(RoutineHistory).where(
            RoutineHistory.id == ref_id,
            RoutineHistory.member_id == member_id,
            or_(
                RoutineHistory.trainer_id.is_(None),
                RoutineHistory.trainer_id == trainer_id,
            ),
        )
    )
    if history is not None:
        code = history_kind_code(history.kind_label)
        return _MemoRef(
            kind="pt_session" if code == "pt_session" else "personal",
            ref_id=history.id,
            day=_iso_day_or_none(history.date),
            # 고정 이름(`AI 개인운동` 등)은 앱이 번역하므로 저장하지 않는다.
            name="" if code else (history.kind_label or "").strip()[:100],
        )

    session = db.scalar(
        select(ExerciseSession).where(
            ExerciseSession.id == ref_id,
            ExerciseSession.user_id == member_id,
            ExerciseSession.source == "assigned_routine",
            ExerciseSession.assigned_trainer_id == trainer_id,
        )
    )
    if session is None:
        raise RoutineNotFound("운동 기록을 찾을 수 없습니다.")
    # 날짜는 이력 목록과 같은 규칙이다([_assigned_history_out], #1264) — 둘이
    # 갈리면 같은 기록이 카드와 메모 태그에서 다른 날로 보인다.
    completed_at = session.completed_at or session.created_at
    day = (
        exercise_activity.activity_date_of(session)
        or clock.to_seoul(completed_at).date()
    ).isoformat()
    return _MemoRef(
        kind="personal",
        ref_id=session.id,
        day=day,
        name=(session.assigned_routine_name or "").strip()[:100],
    )


#: 메모 목록이 한 번에 내려주는 최대 건수. 메모는 지워지지 않고 쌓이기만 하는
#: 데이터라, 오래 쓴 계정에서 응답이 무한정 커지는 것을 막는다(알림함과 같은 이유).
_MEMO_LIMIT = 100


def build_memos(db: Session, trainer_id: str, member_id: str) -> list[TrainerMemoOut]:
    """담당 회원에 대해 내가 남긴 메모(최신 먼저, 최대 [_MEMO_LIMIT]건).

    직접 쓴 메모와 채팅 인사이트 메모를 한 목록으로 돌려준다 — 회원 상세가
    출처와 무관하게 "이 회원에 대해 남긴 기록"을 한 곳에서 보여 준다.

    같은 시각에 만들어진 둘의 순서가 흔들리지 않게 id 로 tie-break 한다.
    """
    rows = db.scalars(
        select(TrainerClientMemo)
        .where(
            TrainerClientMemo.trainer_id == trainer_id,
            TrainerClientMemo.member_id == member_id,
        )
        .order_by(TrainerClientMemo.created_at.desc(), TrainerClientMemo.id.desc())
        .limit(_MEMO_LIMIT)
    ).all()
    return [_memo_out(m) for m in rows]


def find_memo_by_insight(
    db: Session, trainer_id: str, member_id: str, insight_id: str
) -> TrainerClientMemo | None:
    return db.scalar(
        select(TrainerClientMemo).where(
            TrainerClientMemo.trainer_id == trainer_id,
            TrainerClientMemo.member_id == member_id,
            TrainerClientMemo.insight_id == insight_id,
        )
    )


def create_memo(
    db: Session, trainer_id: str, member_id: str,
    body: str, source: str = "trainer",
    insight_id: str | None = None, insight_kind: str = "",
    ref_id: str | None = None, ref_date: date | None = None,
    category: str = "", ref_kind: str | None = None,
) -> TrainerMemoOut:
    """회원 메모를 남긴다.

    [insight_id] 가 오면 그 인사이트에 대해 멱등하다 — 채팅에서 같은 신호를 다시
    저장해도 새 메모를 만들지 않고 먼저 저장된 메모를 그대로 돌려준다. 로컬
    저장 시절 `insightId` 로 중복을 막던 의미를 서버에서 그대로 유지한다.

    운동 기록 메모(`exercise_memo`)는 [ref_id]·[ref_date] 로 가리킨 기록을 찾아
    출처 표시 값을 채운다. 한 기록에 메모를 여러 개 남길 수 있다 — 직접 쓴
    메모와 같은 규칙이다.

    분류(#2622)는 직접 쓴 메모가 고른 값을 그대로 두고, 운동 기록 메모는 늘
    `exercise`, 채팅 감지 메모는 비운다 — 출처가 이미 무엇에 대한 메모인지 말한다.
    """
    if insight_id:
        existing = find_memo_by_insight(db, trainer_id, member_id, insight_id)
        if existing is not None:
            return _memo_out(existing)

    ref: _MemoRef | None = None
    if source == "exercise_memo":
        ref = _resolve_exercise_memo_ref(
            db, trainer_id, member_id,
            ref_id=ref_id, ref_date=ref_date, ref_kind=ref_kind,
        )

    now = datetime.now(timezone.utc)
    memo = TrainerClientMemo(
        id=f"memo-{uuid.uuid4().hex[:12]}",
        trainer_id=trainer_id,
        member_id=member_id,
        body=body,
        source=source,
        insight_id=insight_id,
        insight_kind=insight_kind,
        ref_kind=ref.kind if ref else "",
        ref_id=ref.ref_id if ref else None,
        ref_date=ref.day if ref else None,
        ref_name=ref.name if ref else "",
        category=_memo_category(source, category),
        created_at=now,
        updated_at=now,
    )
    db.add(memo)
    # 같은 insight_id 로 동시에 들어온 두 요청이 나란히 위 조회를 통과하면 유니크
    # 제약이 한쪽을 막는다. 그 충돌을 여기서 잡아 먼저 저장된 쪽을 돌려준다 —
    # 클라이언트 입장에서는 어느 쪽이 이겼든 "이미 저장된 그 메모"가 나온다.
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        if insight_id:
            existing = find_memo_by_insight(db, trainer_id, member_id, insight_id)
            if existing is not None:
                return _memo_out(existing)
        raise
    db.commit()
    db.refresh(memo)
    return _memo_out(memo)


def _owned_memo(
    db: Session, trainer_id: str, member_id: str, memo_id: str
) -> TrainerClientMemo:
    """내가 이 회원에 대해 남긴 메모만 집는다.

    남의 메모와 없는 메모를 똑같이 다룬다 — 존재 여부를 드러내면 id 를 훑는 것만
    으로 다른 트레이너가 메모를 남겼다는 사실을 알 수 있다.
    """
    memo = db.scalar(
        select(TrainerClientMemo).where(
            TrainerClientMemo.id == memo_id,
            TrainerClientMemo.trainer_id == trainer_id,
            TrainerClientMemo.member_id == member_id,
        )
    )
    if memo is None:
        raise MemoNotFound("메모를 찾을 수 없습니다.")
    return memo


def _memo_category(source: str, category: str) -> str:
    """저장할 분류 — 출처가 정하는 분류가 있으면 그것을 쓴다. (#2622)"""
    if source == "exercise_memo":
        return "exercise"
    if source == "chat_insight":
        return ""
    return category


def update_memo(
    db: Session, trainer_id: str, member_id: str, memo_id: str, fields: dict
) -> TrainerMemoOut:
    """메모 본문과 분류를 고친다. 출처(`source`/`insight_id`)는 그대로 둔다.

    분류는 직접 쓴 메모만 바꾼다(#2622). 다른 출처는 출처가 분류를 정하므로
    같은 값을 다시 보내는 것만 받는다 — 수정 창이 지금 값을 싣고 와도 된다.
    """
    memo = _owned_memo(db, trainer_id, member_id, memo_id)
    if "category" in fields and fields["category"] != (memo.category or ""):
        if memo.source != "trainer":
            raise MemoCategoryLocked("직접 쓴 메모만 분류를 바꿀 수 있습니다.")
        memo.category = fields["category"]
    if "body" in fields:
        memo.body = fields["body"]
    memo.updated_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(memo)
    return _memo_out(memo)


def delete_memo(db: Session, trainer_id: str, member_id: str, memo_id: str) -> None:
    """메모를 지운다.

    비활성 플래그를 두지 않고 실제로 지운다 — 트레이너 혼자 보는 개인 메모라
    '지웠는데 서버에 남아 있는' 상태가 UX 상 의미가 없다.
    """
    memo = _owned_memo(db, trainer_id, member_id, memo_id)
    db.delete(memo)
    db.commit()
