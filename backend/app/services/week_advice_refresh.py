"""`이번 주` AI 조언을 다시 만드는 규칙 — 기록이 바뀌면 다시, 하루 최대 5번. (#3549)

식단 `이번 주`(`diet_week_advice`)와 운동 `이번 주`(`exercise_week_ai`) 조언은 홈 코칭
시트가 함께 읽는다. 하루에 한 번만 만들면 점심에 기록한 짬뽕이 저녁까지 시트에 보이지
않고, 기록할 때마다 무제한으로 만들면 호출이 예전(시트가 따로 부르던 때)과 같아진다.

- **기록이 바뀌면 다시 만든다.** 그 회원의 식단(`DietEntry`)·운동(`ExerciseSession`) 행이나
  판정 기준 목표가 flush 되면, 같은 트랜잭션에서 보관한 조언에 "다시 만들 것" 표시를
  한다([_mark_on_change]). 표시는 재시도 시각(`retry_after`)을 아주 옛날로 두는 것이다 —
  보관한 조언을 읽는 쪽(`cached_advice`)은 그 시각이 지났으면 새로 만든다.
- **하루 최대 [MAX_GENERATIONS_PER_DAY]번.** 조언을 만들 때마다 상태 행에 횟수를 적고,
  그 횟수가 차면 표시가 있어도 마지막으로 만든 조언을 그대로 둔다. AI 가 실패한 시도도
  센다 — 이 값은 "회원 한 명이 하루에 몇 번까지 AI 를 부르나" 의 천장이다.

기록을 바꾸는 경로(회원 저장·수정·삭제, 트레이너의 PT 완료 등)가 많아 자리마다 부르지
않고 flush 에서 한 번에 처리한다 — 코칭 시트 캐시(`coach_feedback_service`, #3351)와 같은
방식이다. 상태가 표에 있으므로 백엔드 태스크가 여러 개여도 같은 규칙이 지켜진다.
"""
from __future__ import annotations

import json
from datetime import datetime, timezone

from sqlalchemy import event, inspect, update
from sqlalchemy.orm import Session

from app.models.models import DietAdviceState, DietEntry, ExerciseSession, HealthProfile

#: 식단 `이번 주` 상태 행의 기간 이름(`diet_week_advice.PERIOD_WEEK` 와 같다).
PERIOD_DIET_WEEK = "week"
#: 운동 `이번 주` 상태 행의 기간 이름. 칸 길이(10자) 안이다.
PERIOD_EXERCISE_WEEK = "ex_week"

#: 회원·날짜·종류마다 하루에 조언을 새로 만드는 상한.
MAX_GENERATIONS_PER_DAY = 5

#: "다시 만들 것" 표시로 쓰는 재시도 시각. 어느 `now` 보다도 이르다.
STALE_AT = datetime(2000, 1, 1, tzinfo=timezone.utc)

#: 식단 판정 기준 목표 칸(`diet_coach_inputs.targets_of`).
_DIET_GOAL_FIELDS = ("daily_calories", "daily_protein_g", "daily_sodium_mg", "daily_sugar_g")
#: 운동 판정 기준 목표 칸(`exercise_service.weekly_cardio_goal`).
_EXERCISE_GOAL_FIELDS = ("weekly_cardio_minutes",)


def generations(row: DietAdviceState | None) -> int:
    """그 상태 행(같은 날)에서 지금까지 조언을 만든 횟수."""
    if row is None:
        return 0
    try:
        data = json.loads(row.payload_json or "{}")
        return int(data.get("generations", 1)) if isinstance(data, dict) else 1
    except (TypeError, ValueError):
        return 1


def may_regenerate(row: DietAdviceState | None) -> bool:
    """오늘 한 번 더 만들 수 있는가."""
    return generations(row) < MAX_GENERATIONS_PER_DAY


def mark_stale(session: Session, user_ids: list[str], period: str) -> None:
    """그 회원들의 [period] 조언에 "다시 만들 것" 표시를 한다(커밋 없음)."""
    if not user_ids:
        return
    table = DietAdviceState.__table__
    session.connection().execute(
        update(table)
        .where(table.c.user_id.in_(user_ids), table.c.period == period)
        .values(retry_after=STALE_AT)
    )


@event.listens_for(Session, "after_flush")
def _mark_on_change(session: Session, _flush_context: object) -> None:
    """식단·운동 기록이나 판정 기준 목표가 flush 되면 그 회원의 `이번 주` 조언에 표시한다.

    기록이 롤백되면 이 갱신도 함께 되돌아간다. 보관한 조언이 없는 회원은 아무 일도
    일어나지 않는다.
    """
    diet: set[str] = set()
    exercise: set[str] = set()
    for obj in (*session.new, *session.dirty, *session.deleted):
        if isinstance(obj, DietEntry):
            target = diet
        elif isinstance(obj, ExerciseSession):
            target = exercise
        elif isinstance(obj, HealthProfile):
            owner = _owner(session, obj)
            if owner is None:
                continue
            if _goal_changed(session, obj, _DIET_GOAL_FIELDS):
                diet.add(owner)
            if _goal_changed(session, obj, _EXERCISE_GOAL_FIELDS):
                exercise.add(owner)
            continue
        else:
            continue
        owner = _owner(session, obj)
        if owner is not None:
            target.add(owner)
    mark_stale(session, sorted(diet), PERIOD_DIET_WEEK)
    mark_stale(session, sorted(exercise), PERIOD_EXERCISE_WEEK)


def _goal_changed(session: Session, obj: HealthProfile, fields: tuple[str, ...]) -> bool:
    if obj in session.new or obj in session.deleted:
        return True
    attrs = inspect(obj).attrs
    return any(attrs[name].history.has_changes() for name in fields)


def _owner(session: Session, obj: object) -> str | None:
    """기록 행의 주인. 지운 행은 다시 읽을 수 없어 이미 읽어 둔 값만 쓴다."""
    owner = obj.__dict__.get("user_id")
    if owner is None and obj not in session.deleted:
        owner = getattr(obj, "user_id", None)
    return owner
