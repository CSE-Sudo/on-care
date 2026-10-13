"""코칭 시트 피드백의 회원별 캐시와 하루 상한. (#3351)

`GET /ai-coach/feedback` 은 호출 한 번에 모델을 최대 두 번(식단·운동) 부른다. 회원 앱은
식단·운동 기록이 바뀌거나 날이 바뀔 때마다 이 응답을 다시 받으므로, 그대로 두면 기록
횟수만큼 모델을 부르고 직접 반복 호출하면 끝이 없다.

- **캐시** — 만든 카드를 회원별로 `coach_feedback_cache_seconds` 동안 들고 있다가, 같은
  날(KST)의 요청에 그대로 돌려준다. 인사말은 시각에 따라 달라지고 모델을 쓰지
  않으므로 담지 않고 매번 만든다.
- **무효화** — 그 회원의 식단(`DietEntry`)·운동(`ExerciseSession`) 기록이 바뀌면 카드를
  버린다. 기록을 바꾸는 경로(회원 저장·수정·삭제, 트레이너의 PT 완료·루틴 완료 등)가
  많아 자리마다 부르지 않고, 세션이 그 행을 flush 할 때 같은 트랜잭션에서 버린다
  ([_drop_on_record_change]). 버릴 때 `revision` 을 올려, 그 사이에 만들던 응답이 옛
  기록으로 캐시를 다시 채우지 못하게 한다([_store]). 카드의 판정 기준인 회원 목표
  (하루 나트륨·주간 유산소, #3350)가 바뀌어도 같은 자리에서 버린다 — 목표를 낮춘
  회원에게 옛 기준의 "충분해요" 카드가 캐시 시간 내내 남지 않게.
- **하루 상한** — 카드를 새로 만들 때마다 한 번 센다(`coach_feedback_per_day`, KST 하루).
  넘으면 오류가 아니라 규칙 기반 카드로 답한다. 모델을 부르기 **전에** 한 문장으로 잡아
  ([_reserve]) 동시에 온 요청이 상한을 넘지 못한다. 키가 없어 규칙 문구로 떨어진
  생성도 센다 — 이 값은 "하루에 몇 번까지 새로 만드나" 의 천장이다.

캐시와 횟수는 프로세스 메모리가 아니라 표(`coach_feedback_states`)에 둔다. 운영 백엔드는
태스크를 1~4개까지 늘릴 수 있어(`infra/backend-service.yml`), 메모리에 두면 기록을 저장한
태스크와 시트를 여는 태스크가 달라 옛 카드가 남고 상한도 태스크 수만큼 느슨해진다.
"""
from __future__ import annotations

import json
import logging
from datetime import timedelta
from typing import Any

from sqlalchemy import case, event, func, inspect, or_, update
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session

from app.core import clock
from app.core.config import get_settings
from app.models.models import (
    CoachFeedbackState,
    DietEntry,
    ExerciseSession,
    HealthProfile,
)
from app.schemas.misc_api import AiCoachFeedback, CoachSuggestion
from app.services import coach_service

logger = logging.getLogger(__name__)

#: 캐시 행의 `locale` 칸에 적는 값. 카드는 한국어로만 만든다 — 칸은 예전에 영어로
#: 만든 카드를 가려 쓰지 않는 데만 쓴다.
CACHE_LOCALE = "ko"


def cache_seconds() -> int:
    """카드를 들고 있는 시간(초). 0 이면 캐시하지 않는다."""
    return max(get_settings().coach_feedback_cache_seconds, 0)


def daily_limit() -> int:
    """회원 한 명이 하루에 카드를 새로 만드는 상한. 0 이거나 한도를 끈 환경이면 0(상한 없음)."""
    s = get_settings()
    if not s.rate_limit_enabled:
        return 0
    return max(s.coach_feedback_per_day, 0)


def feedback(db: Session, user_id: str, user_name: str) -> AiCoachFeedback:
    """코칭 시트 응답. 캐시가 살아 있으면 그 카드를, 아니면 새로 만들어 돌려준다."""
    greeting = coach_service.build_greeting(user_name)
    today = clock.today_iso()

    cached = _cached(db, user_id, today=today)
    if cached is not None:
        return AiCoachFeedback(greeting=greeting, suggestions=cached)

    revision = _reserve(db, user_id, today=today)
    if revision is None:
        logger.info("코칭 피드백 회원 하루 상한 도달 (user_id=%s) → 규칙 기반 카드", user_id)
        # 규칙 카드는 기록을 바로 읽어 만든다 — 캐시에 넣지 않아 늘 지금 기록을 말한다.
        return AiCoachFeedback(
            greeting=greeting,
            suggestions=coach_service.build_suggestions(db, user_id, use_model=False),
        )

    suggestions = coach_service.build_suggestions(db, user_id)
    _store(db, user_id, revision=revision, today=today, cards=suggestions)
    return AiCoachFeedback(greeting=greeting, suggestions=suggestions)


def invalidate(db: Session, user_id: str) -> None:
    """그 회원의 카드를 버린다(커밋 없음 — 부른 쪽 트랜잭션에 실린다)."""
    db.execute(_drop_statement([user_id]))


def used_today(db: Session, user_id: str) -> int:
    """오늘(KST) 그 회원이 카드를 새로 만든 횟수. 운영 확인·테스트용."""
    row = db.get(CoachFeedbackState, user_id)
    if row is None or row.kst_date != clock.today_iso():
        return 0
    return int(row.generations)


def _cached(
    db: Session, user_id: str, *, today: str
) -> list[CoachSuggestion] | None:
    """살아 있는 카드. 없거나 날이 다르거나 오래됐으면 None."""
    ttl = cache_seconds()
    if ttl <= 0:
        return None
    row = db.get(CoachFeedbackState, user_id)
    if (
        row is None
        or row.payload_json is None
        or row.generated_at is None
        or row.kst_date != today
        or row.locale != CACHE_LOCALE
    ):
        return None
    if clock.to_seoul(row.generated_at) + timedelta(seconds=ttl) <= clock.now():
        return None
    try:
        return [CoachSuggestion(**card) for card in json.loads(row.payload_json)]
    except (TypeError, ValueError):
        # 읽지 못하는 값은 없는 것으로 보고 새로 만든다.
        return None


def _reserve(db: Session, user_id: str, *, today: str) -> int | None:
    """이번 생성의 몫을 잡는다. 지금 `revision` 을 돌려주고, 상한이면 None. 커밋한다.

    행이 없으면 만들고, 지난 날의 행이면 횟수를 1 로 되돌리며 옛 카드를 비운다.
    충돌한 행이 "날이 바뀌었거나 아직 상한 아래" 일 때만 갱신하므로, 동시에 들어온
    요청이 모두 "한 자리 남음" 을 보고 상한을 넘기는 일이 없다(행 잠금 안에서 판정한다).
    """
    limit = daily_limit()
    same_day = CoachFeedbackState.kst_date == today
    stmt = insert(CoachFeedbackState).values(
        user_id=user_id, kst_date=today, generations=1, revision=0
    )
    stmt = stmt.on_conflict_do_update(
        index_elements=[CoachFeedbackState.user_id],
        set_={
            "kst_date": today,
            "generations": case(
                (same_day, CoachFeedbackState.generations + 1), else_=1
            ),
            # 어제 만든 카드가 오늘 날짜를 달고 남지 않게 한다.
            "payload_json": case((same_day, CoachFeedbackState.payload_json), else_=None),
            "updated_at": func.now(),
        },
        where=(
            or_(~same_day, CoachFeedbackState.generations < limit)
            if limit > 0
            else None
        ),
    ).returning(CoachFeedbackState.revision)
    taken = db.execute(stmt).first()
    db.commit()
    return int(taken[0]) if taken is not None else None


def _store(
    db: Session,
    user_id: str,
    *,
    revision: int,
    today: str,
    cards: list[CoachSuggestion],
) -> None:
    """만든 카드를 캐시에 남긴다. 커밋한다.

    만들기 시작한 뒤 기록이 바뀌었으면(`revision` 이 다름) 남기지 않는다 — 옛 기록으로
    만든 카드라, 남기면 방금 저장한 기록이 캐시가 끝날 때까지 시트에 보이지 않는다.
    저장 실패는 응답을 막지 않는다. 이미 만든 카드는 그대로 돌려준다.
    """
    if cache_seconds() <= 0:
        return
    try:
        db.execute(
            update(CoachFeedbackState)
            .where(
                CoachFeedbackState.user_id == user_id,
                CoachFeedbackState.revision == revision,
                CoachFeedbackState.kst_date == today,
            )
            .values(
                payload_json=json.dumps(
                    [card.model_dump() for card in cards], ensure_ascii=False
                ),
                locale=CACHE_LOCALE,
                generated_at=clock.now(),
                updated_at=func.now(),
            )
        )
        db.commit()
    except Exception:  # noqa: BLE001
        db.rollback()
        logger.warning("코칭 피드백 캐시 저장 실패 (user_id=%s)", user_id, exc_info=True)


def _drop_statement(user_ids: list[str]) -> Any:
    # flush 중에는 세션이 아니라 그 트랜잭션의 연결로 바로 실행하므로 표로 쓴다.
    table = CoachFeedbackState.__table__
    return (
        update(table)
        .where(table.c.user_id.in_(user_ids))
        .values(
            payload_json=None,
            revision=table.c.revision + 1,
            updated_at=func.now(),
        )
    )


@event.listens_for(Session, "after_flush")
def _drop_on_record_change(session: Session, _flush_context: object) -> None:
    """식단·운동 기록 행이나 코칭 기준 목표가 flush 되면 그 회원의 카드를 같은
    트랜잭션에서 버린다.

    기록이 롤백되면 이 갱신도 함께 되돌아간다. 행이 없는 회원(시트를 연 적 없음)은
    버릴 카드가 없어 아무 일도 일어나지 않는다.
    """
    user_ids = sorted(
        {
            owner
            for obj in (*session.new, *session.dirty, *session.deleted)
            if _affects_cards(session, obj) and (owner := _owner(session, obj))
        }
    )
    if user_ids:
        session.connection().execute(_drop_statement(user_ids))


#: 카드의 판정 기준으로 쓰이는 프로필 칸(#3350) — `coach_service` 가 읽는 것만.
_GOAL_FIELDS = ("daily_sodium_mg", "weekly_cardio_minutes")


def _affects_cards(session: Session, obj: object) -> bool:
    """이 행의 변경이 코칭 카드를 바꾸는가.

    기록 행은 언제나 그렇다. 프로필은 포인트 적립처럼 카드와 무관한 일로도 자주
    바뀌므로, 판정 기준인 목표 칸이 바뀐 때(새 프로필·삭제 포함)만 본다.
    """
    if isinstance(obj, (DietEntry, ExerciseSession)):
        return True
    if not isinstance(obj, HealthProfile):
        return False
    if obj in session.new or obj in session.deleted:
        return True
    attrs = inspect(obj).attrs
    return any(attrs[name].history.has_changes() for name in _GOAL_FIELDS)


def _owner(
    session: Session, obj: DietEntry | ExerciseSession | HealthProfile
) -> str | None:
    """기록 행의 주인. 지운 행은 다시 읽을 수 없어 이미 읽어 둔 값만 쓴다."""
    owner = obj.__dict__.get("user_id")
    if owner is None and obj not in session.deleted:
        owner = obj.user_id
    return owner
