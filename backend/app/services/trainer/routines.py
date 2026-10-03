"""트레이너 도메인 — 루틴 배정(트레이너/AI → 회원, 양쪽에서 보이는 공유 데이터)."""
from __future__ import annotations

import uuid
from collections.abc import Sequence
from datetime import date, datetime, timezone

from sqlalchemy import func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core import clock
from app.models.models import (
    ExerciseSession, TrainerRoutine,
)
from app.schemas.trainer_api import (
    ProgramDraftSession,
    RoutineCompleteOut,
    RoutineOut,
)
from app.services import (
    exercise_activity,
    exercise_service,
    exercise_types,
    notification_service,
    notification_templates,
    points_service,
    streak_shield_service,
)
from app.schemas.points_api import PointsOut
from app.services.coach import personal_ingest
from app.services.trainer._common import (
    DELIVERY_ROUTINE_ONLY,
    ROUTINE_APPROVED,
    RoutineDayInFuture,
    _add_program_routines,
    _apply_routine_duration,
    _consume_routine_suggestions,
    _program_routines_for_request,
    _retire_personal_routines,
    _routine_notification_args,
    _routine_out,
    _routine_prefetch,
    get_member_trainer_id,
)
from app.services.trainer.chat import (
    post_routine_delivery,
)


# ---- 루틴 배정 (트레이너/AI → 회원, 양쪽에서 보이는 공유 데이터) ----


def routine_active_on(day: date):
    """[day] 에 회원 목록에 걸려 있던 개인운동을 고르는 조건. (#2161)

    추천 개인운동은 매일 새로 체크하는 목록이다. 트레이너가 바꾸기 전까지 같은
    목록이 날마다 되풀이되므로, 어느 날의 목록은 "그날 걸려 있던 배정" 이다 —
    `active_from` 은 그날을 포함하고 `ended_on` 은 그날부터 없다.
    """
    iso = day.isoformat()
    return (
        TrainerRoutine.active_from <= iso,
        or_(TrainerRoutine.ended_on.is_(None), TrainerRoutine.ended_on > iso),
    )


def _completion_on(day: date):
    """[day] 하루의 배정 완료 기록을 고르는 조건. (#2161)

    운동 기록의 날짜는 `(week_start, day_label)` 이다. 완료는 배정 하나당 하루
    한 번이라(`uq_exercise_sessions_routine_day`) 이 조건과 배정 id 가 곧 한 행을
    가리킨다.
    """
    iso = day.isoformat()
    return (
        ExerciseSession.week_start == exercise_service.monday_of_str(iso),
        ExerciseSession.day_label == exercise_service.weekday_label_of(iso),
    )


def build_routines(
    db: Session,
    member_id: str,
    trainer_id: str | None,
    *,
    for_member: bool = False,
    day: date | None = None,
) -> list[RoutineOut]:
    """이 트레이너가 회원에게 배정한 루틴(정렬순) — [day] 에 걸려 있던 것과 그날 완료.

    [day] 를 주지 않으면 오늘이다. 추천 개인운동은 매일 미완료로 다시 시작하므로
    `completed` 는 **그날** 완료했는가다(#2161). 어제 한 운동이 오늘 체크된 채로
    보이지 않는다.

    [trainer_id] 가 None 이면 트레이너 없이 만들어진 자동 추천을 읽는다 —
    SQLAlchemy 가 `== None` 을 `IS NULL` 로 옮기므로 조건은 그대로 쓴다.

    [for_member] 는 이 목록이 회원에게 가는지를 말한다. 회원용이면 제안의 근거를
    싣지 않는다 — 트레이너의 판단 재료이기 때문이다(#790).

    한 프로그램의 세션들은 `sort_order` 를 연속으로 받으므로 이 정렬만으로
    세션 순서가 지켜진다 — 별도 그룹핑 없이 배열 순서가 곧 프로그램 순서다.
    """
    day = day or clock.today()
    rows = db.scalars(
        select(TrainerRoutine)
        .where(
            TrainerRoutine.trainer_id == trainer_id,
            TrainerRoutine.member_id == member_id,
            # 검토를 기다리는 후보와 거절된 후보는 '배정된 루틴'이 아니다.
            # 회원 화면은 물론 트레이너의 배정 목록에도 섞이면 안 된다 —
            # 검토는 전용 목록(list_routine_suggestions)에서 한다(#790).
            TrainerRoutine.status == ROUTINE_APPROVED,
            *routine_active_on(day),
        )
        .order_by(TrainerRoutine.sort_order, TrainerRoutine.created_at)
    ).all()
    routine_ids = [row.id for row in rows]
    completed = {}
    if routine_ids:
        completed = {
            row.assigned_routine_id: row
            for row in db.scalars(
                select(ExerciseSession).where(
                    ExerciseSession.assigned_routine_id.in_(routine_ids),
                    *_completion_on(day),
                )
            ).all()
        }
    prefetch = _routine_prefetch(db, rows)
    return [
        _routine_out(
            db,
            row,
            completed.get(row.id),
            include_evidence=not for_member,
            prefetch=prefetch,
        )
        for row in rows
    ]


class RoutineNotFound(Exception):
    """루틴이 없거나 이 트레이너·회원의 것이 아니다."""


def _owned_routine(
    db: Session,
    trainer_id: str | None,
    member_id: str,
    routine_id: str,
    *,
    include_ended: bool = False,
) -> TrainerRoutine:
    """이 트레이너가 이 회원에게 배정한 루틴. 아니면 [RoutineNotFound]. (#504)

    trainer_id 까지 조건에 넣는 이유: 한 회원이 여러 트레이너를 거쳐 왔을 수 있고,
    그때 남의 배정을 고칠 수 있으면 안 된다. 없는 것과 남의 것을 구분하지 않는
    것도 의도다 — 라우터가 둘 다 404 로 돌려 존재 여부를 드러내지 않는다.

    철회해 목록에서 내려온 배정(`ended_on`)도 없는 것으로 본다(#2161). 예전에는
    철회가 행을 지웠으니 같은 답이다. [include_ended] 는 오늘 이미 끝낸 완료를
    되돌릴 때처럼, 내려온 배정에 남은 기록을 다뤄야 하는 경우에만 켠다.
    """
    routine = db.scalar(
        select(TrainerRoutine).where(
            TrainerRoutine.id == routine_id,
            TrainerRoutine.trainer_id == trainer_id,
            TrainerRoutine.member_id == member_id,
        )
    )
    if routine is None or (not include_ended and _has_ended(routine)):
        raise RoutineNotFound("루틴을 찾을 수 없습니다.")
    return routine


def _routine_day(day: date | None) -> date:
    """완료·되돌리기가 다룰 날. 비우면 오늘, 아직 오지 않은 날은 거절한다. (#2506)"""
    today = clock.today()
    if day is None:
        return today
    if day > today:
        raise RoutineDayInFuture("아직 오지 않은 날입니다.")
    return day


def _active_on(routine: TrainerRoutine, day: date) -> bool:
    """[routine] 이 [day] 에 회원 목록에 걸려 있었나 — [routine_active_on] 과 같은
    규칙을 행 하나에 적용한다. (#2161, #2506)"""
    iso = day.isoformat()
    return routine.active_from <= iso and (
        routine.ended_on is None or routine.ended_on > iso
    )


def _has_ended(routine: TrainerRoutine) -> bool:
    """오늘 목록에 이미 없는 배정인가. (#2161)"""
    return routine.ended_on is not None and routine.ended_on <= clock.today_iso()


def _end_routine(db: Session, routine: TrainerRoutine) -> None:
    """배정을 오늘부터 목록에서 내린다 — 행은 지우지 않는다. (#2161)

    지난 날짜 화면은 그날 걸려 있던 목록과 완료 여부를 그대로 보여 준다. 행을
    지우면 그 목록이 통째로 사라져, 회원이 했던 날도 "아무것도 없었던 날" 이 된다.

    승인 전 후보·거절한 후보는 회원 목록에 걸린 적이 없으니 남길 날이 없다 —
    예전처럼 행째 지운다. 남겨 두면 검토 대기 목록에 철회한 후보가 섞인다.
    """
    if routine.status != ROUTINE_APPROVED:
        db.delete(routine)
        return
    routine.ended_on = max(clock.today_iso(), routine.active_from)


def update_routine(
    db: Session, trainer_id: str, member_id: str, routine_id: str,
    fields: dict,
) -> RoutineOut:
    """배정한 루틴을 고친다. 보낸 필드만 반영한다. (#504)

    **알림을 보내지 않는다.** 배정 알림이 오간 뒤 정정 알림까지 겹치면 회원
    알림함이 같은 루틴으로 채워진다. 회원 앱은 목록을 다시 읽을 때 고쳐진 값을
    본다.

    `sort_order` 는 건드리지 않는다 — 순서 변경은 별도 기능이고(범위 밖),
    수정하다 순서가 밀리면 회원이 보는 목록이 이유 없이 흔들린다.
    """
    routine = _owned_routine(db, trainer_id, member_id, routine_id)
    for field in ("name", "type", "reason"):
        if field in fields:
            setattr(routine, field, fields[field])
    _apply_routine_duration(
        routine,
        minutes=fields.get("minutes"),
        duration_seconds=fields.get("duration_seconds"),
    )
    db.commit()
    db.refresh(routine)
    completion = db.scalar(
        select(ExerciseSession).where(
            ExerciseSession.assigned_routine_id == routine.id,
            *_completion_on(clock.today()),
        )
    )
    return _routine_out(db, routine, completion)


def delete_routine(
    db: Session, trainer_id: str, member_id: str, routine_id: str
) -> None:
    """배정한 루틴을 철회한다. 회원 앱에서도 사라진다. (#504)

    남은 루틴의 `sort_order` 는 다시 매기지 않는다. 정렬은 값의 크기 순서만
    쓰므로 중간이 비어도 순서가 유지되고, 다시 매기면 그 회원의 모든 루틴 행을
    건드려 동시에 배정 중인 요청과 부딪힌다.

    지난 기록(`routine_history`)은 건드리지 않는다 — 이미 수행한 운동의 이력이지
    배정의 일부가 아니다.

    행을 지우지 않고 오늘부터 목록에서 내린다(#2161). 회원의 지난 날짜 화면이
    그날 걸려 있던 목록을 되살려야 하기 때문이다. 두 번 철회하면 두 번째는
    404 다 — 예전처럼 이미 없는 배정이다.
    """
    routine = _owned_routine(db, trainer_id, member_id, routine_id)
    _end_routine(db, routine)
    db.commit()


class RoutineNotCancellable(Exception):
    """담당 트레이너가 배정한 루틴을 회원이 직접 지우려 했다. (#1020)"""


def delete_own_routine(db: Session, member_id: str, routine_id: str) -> None:
    """회원이 자기 개인 운동을 지운다. **담당 트레이너가 없을 때만.** (#1020)

    트레이너가 배정한 것을 회원이 조용히 없애면, 다음 상담에서 둘이 서로 다른
    기록을 보게 된다. 담당이 있는 회원에게는 취소가 트레이너의 일이다.

    담당 없이 AI 가 직접 추천한 개인운동(#782)은 승인할 사람이 없으므로 회원이
    스스로 물릴 수 있어야 한다 — 그러지 않으면 한 번 뜬 추천을 지울 방법이 없다.

    이미 수행한 기록은 남는다. 지우는 것은 **배정**이지 한 일이 아니다.
    """
    if get_member_trainer_id(db, member_id) is not None:
        raise RoutineNotCancellable(
            "담당 트레이너가 배정한 개인운동은 회원이 직접 취소할 수 없습니다."
        )
    routine = db.scalar(
        select(TrainerRoutine).where(
            TrainerRoutine.id == routine_id,
            TrainerRoutine.member_id == member_id,
        )
    )
    if routine is None or _has_ended(routine):
        raise RoutineNotFound("루틴을 찾을 수 없습니다.")
    # 트레이너 철회와 같다 — 지난 날짜에 걸려 있던 목록은 남긴다(#2161).
    _end_routine(db, routine)
    db.commit()


#: 루틴의 한글 유형 → 운동 기록의 영문 코드. 옛 값도 함께 접힌다. (#996)
_ROUTINE_EXERCISE_TYPES = exercise_types.normalize


def complete_assigned_routine(
    db: Session,
    trainer_id: str | None,
    member_id: str,
    routine_id: str,
    *,
    minutes: int,
    sets: int | None = None,
    reps: int | None = None,
    hold_seconds: int | None = None,
    weight: float | None = None,
    intensity: str,
    duration_seconds: int | None = None,
    day: date | None = None,
) -> RoutineCompleteOut:
    """배정 하나를 [day](없으면 오늘)의 회원 운동 기록 한 건으로 완료한다.

    추천 개인운동은 매일 새로 체크하는 목록이라 같은 배정을 날마다 한 번씩
    완료한다(#2161). `(배정, 그날)` 유일 제약이 더블 탭·재전송을 같은 기록으로
    모은다. 이름은 스냅샷이라 이후 배정 수정·철회에 흔들리지 않는다.

    **지난 날짜도 완료할 수 있다**(#2506) — 식단·직접 기록한 운동처럼 빠뜨린
    체크를 나중에 한다. 그날 회원 목록에 걸려 있던 배정만 되고, 기록은 그날
    정오에 놓인다. 실제로 누른 시각은 행의 `created_at` 에 남아 트레이너가
    "다음 날 이후 체크" 를 가른다. 아직 오지 않은 날은 [RoutineDayInFuture] 다.

    포인트를 적립하고 그 결과를 응답에 싣는다(#1786). 재전송은
    새로 적립하지 않고 처음 완료할 때 받은 값을 돌려준다. 하루 한도는 **적립하는
    날** 기준이라 지난 날짜를 몰아 체크해도 오늘 한 번만 받는다.
    """
    target = _routine_day(day)
    past = target != clock.today()
    # 지난 날짜의 배정은 그 뒤에 내려왔을 수 있다 — 그날 걸려 있었는지로 본다.
    routine = _owned_routine(
        db, trainer_id, member_id, routine_id, include_ended=past
    )
    # 승인되지 않은 후보는 회원에게 보이지도 않는다. id 를 알아내 직접 호출해도
    # 완료로 넘어가지 않게 여기서 막는다 — 조회만 거르면 경로가 하나 남는다(#790).
    if routine.status != ROUTINE_APPROVED:
        raise RoutineNotFound("루틴을 찾을 수 없습니다.")
    if past and not _active_on(routine, target):
        raise RoutineNotFound("루틴을 찾을 수 없습니다.")
    completed_at = exercise_activity.noon(target) if past else clock.now()
    existing = db.scalar(
        select(ExerciseSession).where(
            ExerciseSession.assigned_routine_id == routine_id,
            *_completion_on(target),
        )
    )
    if existing is not None:
        return _completion_out(
            db, routine, existing,
            _completion_points(db, routine, member_id, existing.id, award=False),
        )

    exercise_type = _ROUTINE_EXERCISE_TYPES(routine.type)
    # 회원이 실제로 한 수를 적지 않았으면 트레이너가 배정한 값이 남는다 —
    # 근력 배정에서 세트·횟수·중량이 통째로 비면, 그래프가 분에서 세트를 되짚어
    # 트레이너도 회원도 적은 적 없는 수를 그린다. (#1276, #1310)
    sets = sets if sets is not None else getattr(routine, "sets", None)
    reps = reps if reps is not None else getattr(routine, "reps", None)
    hold_seconds = (
        hold_seconds if hold_seconds is not None
        else getattr(routine, "hold_seconds", None)
    )
    weight = weight if weight is not None else getattr(routine, "weight", None)
    # 회원이 초로 적었으면 횟수는 뜻이 없다 — 배정에 남아 있던 옛 횟수가
    # 함께 따라오면 한 세트가 두 단위로 적힌다. (#1969)
    if hold_seconds is not None:
        reps = None
    assigned_estimate = exercise_service.estimate(
        db,
        name=routine.name,
        type_=exercise_type,
        minutes=minutes,
        intensity=intensity,
        weight_kg=exercise_service.member_weight_kg(db, member_id),
    )
    row = ExerciseSession(
        id=f"assigned-ex-{uuid.uuid4().hex[:12]}",
        user_id=member_id,
        week_start=exercise_service.monday_of_str(target.isoformat()),
        day_label=exercise_service.weekday_label_of(target.isoformat()),
        type=exercise_type,
        # 배정 이름이 곧 이 운동의 이름이다 — 회원이 따로 적지 않는다.
        name=routine.name,
        minutes=minutes,
        # 초로 적어 온 시간은 초까지 남긴다(#2221) — 근력은 세트로 읽는다.
        duration_seconds=(
            duration_seconds if exercise_type != exercise_types.STRENGTH else None
        ),
        # 세트·횟수·중량은 근력에서만 남긴다. 수기 기록과 같은 규칙이라야
        # 그래프가 두 기록을 같은 축으로 읽는다. (#1276, #1310)
        sets=sets if exercise_type == exercise_types.STRENGTH else None,
        reps=reps if exercise_type == exercise_types.STRENGTH else None,
        hold_seconds=(
            hold_seconds if exercise_type == exercise_types.STRENGTH else None
        ),
        weight=(
            round(weight, 1)
            if weight is not None and exercise_type == exercise_types.STRENGTH
            else None
        ),
        # 이름·체중이 반영된 값이다. 회원이 수기로 적은 기록과 같은 계산을 써야
        # 같은 운동이 두 경로에서 다른 칼로리로 적히지 않는다(#1312).
        calories=assigned_estimate.calories,
        calorie_source=assigned_estimate.source,
        intensity=intensity,
        source="assigned_routine",
        assigned_routine_id=routine.id,
        assigned_trainer_id=trainer_id,
        assigned_routine_name=routine.name,
        completed_at=completed_at,
        # 실제로 누른 때 — 지난 날짜 체크면 `completed_at`(그날 정오)과 날이
        # 갈린다(#2506). DB 시계가 아니라 서버 시계로 적어 `completed_at` 과
        # 같은 기준으로 비교한다.
        created_at=clock.now(),
    )
    db.add(row)
    try:
        # 적립은 기록과 같은 트랜잭션이다(#1786). 먼저 flush 해, 더블 탭이 유니크
        # 제약에 걸리는 자리를 적립보다 앞에 둔다.
        db.flush()
        points = _completion_points(db, routine, member_id, row.id, award=True)
        # 완료 기록이 보호권으로 이어 붙인 날에 떨어지면(자정 무렵 보호와 겹친 완료)
        # 그 보호권을 되돌린다(#1788).
        streak_shield_service.refund_for_record(
            db, member_id, clock.to_seoul(completed_at).date()
        )
        db.commit()
    except IntegrityError:
        db.rollback()
        existing = db.scalar(
            select(ExerciseSession).where(
                ExerciseSession.assigned_routine_id == routine_id,
                *_completion_on(target),
            )
        )
        if existing is None:
            raise
        return _completion_out(
            db, routine, existing,
            _completion_points(db, routine, member_id, existing.id, award=False),
        )
    db.refresh(row)
    personal_ingest.refresh_exercise(db, member_id, session_id=row.id)
    return _completion_out(db, routine, row, points)


def _completion_points(
    db: Session,
    routine: TrainerRoutine,
    member_id: str,
    session_id: str,
    *,
    award: bool,
) -> points_service.PointsResult:
    """배정 완료로 받는 포인트. (#1786)

    AI 추천 루틴이든 트레이너 배정 루틴이든 `추천·배정 운동 완료` 한 규칙으로
    적립하고, 하루 한도를 함께 쓴다 — 그래서 [routine] 의 출처를 보지 않는다.
    [award] 가 거짓이면 이미 저장된 완료가 받은 값을 읽기만 한다(재전송 응답).
    """
    rule = points_service.ROUTINE_COMPLETE
    if award:
        return points_service.award(db, member_id, rule, session_id)
    return points_service.awarded_for(db, member_id, rule, session_id)


def _completion_out(
    db: Session,
    routine: TrainerRoutine,
    completion: ExerciseSession,
    points: points_service.PointsResult,
) -> RoutineCompleteOut:
    """완료 응답 — 루틴 한 건에 이번 적립 결과를 더한다."""
    return RoutineCompleteOut(
        **_routine_out(db, routine, completion).model_dump(),
        points=PointsOut.of(points),
    )


def uncomplete_assigned_routine(
    db: Session,
    trainer_id: str | None,
    member_id: str,
    routine_id: str,
    *,
    day: date | None = None,
) -> RoutineOut:
    """[day](없으면 오늘)의 완료 표시를 되돌린다 — 그날 그 배정으로 만든 운동
    기록을 지운다. (#1131)

    회원이 체크를 잘못 눌렀을 때 되돌릴 방법이 없으면, 하지 않은 운동이 주간
    시간·칼로리에 영원히 남는다. 완료는 배정 하나당 하루 기록 하나라(#2161)
    지울 대상도 하나다. 지난 날짜도 완료처럼 되돌릴 수 있다(#2506).

    아직 완료하지 않은 배정에 대해서는 아무 일도 하지 않고 현재 상태를 돌려준다 —
    같은 요청을 두 번 보내도 결과가 같다.
    """
    target = _routine_day(day)
    # 오늘 철회된 배정이라도 오늘 남긴 완료는 되돌릴 수 있어야 한다.
    routine = _owned_routine(
        db, trainer_id, member_id, routine_id, include_ended=True
    )
    row = db.scalar(
        select(ExerciseSession).where(
            ExerciseSession.assigned_routine_id == routine_id,
            ExerciseSession.user_id == member_id,
            *_completion_on(target),
        )
    )
    if row is None:
        return _routine_out(db, routine, None)
    session_id = row.id
    # 이 완료로 받은 포인트를 회수한다 — 기록 삭제와 같은 트랜잭션이다(#1786).
    points_service.revoke(
        db, member_id, points_service.SOURCE_EXERCISE_SESSION, session_id
    )
    db.delete(row)
    db.commit()
    # 근거 문서도 함께 지운다 — 행이 사라지면 `_load` 가 None 을 돌려준다.
    personal_ingest.refresh_exercise(db, member_id, session_id=session_id)
    return _routine_out(db, routine, None)


def find_routine_by_client_request(
    db: Session, trainer_id: str, member_id: str, client_request_id: str
) -> TrainerRoutine | None:
    return db.scalar(
        select(TrainerRoutine).where(
            TrainerRoutine.trainer_id == trainer_id,
            TrainerRoutine.member_id == member_id,
            TrainerRoutine.client_request_id == client_request_id,
        )
    )


def assign_routine(
    db: Session, trainer_id: str, member_id: str,
    name: str, minutes: int, type_: str, reason: str, source: str,
    client_request_id: str | None = None,
    duration_seconds: int | None = None,
    exercise_date: date | None = None,
    intensity: str = "moderate",
    sets: int | None = None,
    reps: int | None = None,
    hold_seconds: int | None = None,
    weight: float | None = None,
) -> RoutineOut:
    """회원에게 루틴 배정. 로스터 last_routine 은 build_roster 가 최신 루틴을 읽어 반영.

    [client_request_id] 가 오면 그 전송 시도에 대해 멱등하다. 같은 키로 다시
    호출하면 새로 만들지 않고 먼저 저장된 배정을 그대로 돌려준다 — 전송 도중
    끊겨 클라이언트가 재시도해도 회원에게 루틴이 두 번 배정되지 않는다(#581).
    """
    if client_request_id:
        existing = find_routine_by_client_request(
            db, trainer_id, member_id, client_request_id
        )
        if existing is not None:
            return _routine_out(db, existing)

    # 이 회원 루틴들의 현재 최대 sort_order + 1 로 끝에 붙인다. timestamp 방식은 시드(0..n)와
    # 의미가 섞이고, 같은 초에 배정된 둘은 순서가 비결정적이었다(리뷰 #279).
    max_order = db.scalar(
        select(func.max(TrainerRoutine.sort_order))
        .where(TrainerRoutine.trainer_id == trainer_id, TrainerRoutine.member_id == member_id)
    )
    rt = TrainerRoutine(
        id=f"rt-{uuid.uuid4().hex[:12]}",
        trainer_id=trainer_id,
        member_id=member_id,
        name=name,
        minutes=minutes,
        # 시·분·초로 적은 시간(#2547). 근력은 세트로 잰다.
        duration_seconds=duration_seconds if type_ != "근력" else None,
        type=type_,
        exercise_date=exercise_date.isoformat() if exercise_date else None,
        intensity=intensity,
        # 세트·횟수·중량은 근력에만 남긴다 — 운동 기록과 같은 규칙이다.
        # (#1276, #1310)
        sets=sets if type_ == "근력" else None,
        # 버티는 운동이면 초가 맞고 횟수는 비운다 — 한 세트를 두 단위로 적지
        # 않는다(#1969).
        reps=reps if type_ == "근력" and hold_seconds is None else None,
        hold_seconds=hold_seconds if type_ == "근력" else None,
        weight=round(weight, 1) if weight is not None and type_ == "근력" else None,
        reason=reason,
        source=source,
        sort_order=(max_order or 0) + 1,
        client_request_id=client_request_id,
        created_at=datetime.now(timezone.utc),
    )
    db.add(rt)
    # 알림을 붙이기 **전에** 삽입을 flush 한다. 같은 키의 동시 요청 둘이 나란히 위
    # 조회를 통과하면 유니크 제약이 한쪽을 막는데, 그 충돌을 여기서 잡아야 진 쪽이
    # 알림까지 중복으로 쌓지 않는다(회원이 같은 배정 알림을 두 번 받지 않는다).
    # queue() 는 내부 조회를 하므로 그때 autoflush 로 터지면 이 지점을 지나친다.
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        if client_request_id:
            existing = find_routine_by_client_request(
                db, trainer_id, member_id, client_request_id
            )
            if existing is not None:
                return _routine_out(db, existing)
        raise

    # 배정은 회원이 앱을 열기 전에는 알 수 없는 변화다(#489).
    notification_service.queue(
        db,
        member_id=member_id,
        kind=notification_service.EXERCISE,
        category=notification_service.MEMBER_ROUTINE,
        template=notification_templates.MEMBER_ROUTINE_ASSIGNED,
        template_args=_routine_notification_args(
            name, type_, minutes=minutes, sets=sets, reps=reps,
            hold_seconds=hold_seconds, weight=weight,
            duration_seconds=rt.duration_seconds,
        ),
    )
    post_routine_delivery(  # 채팅 안내(#2672)
        db, trainer_id, member_id, kind="routine", routine_names=[rt.name]
    )
    db.commit()
    db.refresh(rt)
    return _routine_out(db, rt)


def assign_program(
    db: Session, trainer_id: str, member_id: str, *,
    name: str,
    sessions: Sequence[ProgramDraftSession],
    client_request_id: str | None = None,
    delivery_kind: str | None = None,
    trainer_message: str = "",
    start_date: date | None = None,
    active_days: int | None = None,
    suggestion_ids: Sequence[str] = (),
    chat_card: bool = True,
) -> list[RoutineOut]:
    """다중 세션 프로그램을 회원에게 배정한다. 세션 하나가 루틴 한 건이 된다. (#709)

    보낸 일은 채팅에도 안내로 남긴다(#2672). [chat_card] 를 끄는 것은 이
    배정을 더 큰 전송의 일부로 쓰는 호출자다 — PT 프로그램 보내기는 프로그램과
    개인운동을 카드 하나로 남긴다.

    세션이 하나뿐이면 예전 단일 배정과 같은 모양이다 — 루틴 이름은 프로그램
    이름이고 `session_name` 이 비어 회원 화면에 없던 세션 라벨이 생기지 않는다.
    세션이 여럿이면 루틴 이름이 세션 이름이 되고 `program_name` 이 묶는다.

    [client_request_id] 가 오면 **프로그램 전체**에 대해 멱등하다. 재시도에 같은
    키를 다시 보내면 먼저 배정된 세션들을 그대로 돌려준다 — 중간까지 저장된
    상태에서 재시도해 세션이 반쯤 겹치는 일이 없다.

    알림은 프로그램당 한 번이다. 세션마다 보내면 회원 알림함이 한 번의 배정으로
    가득 찬다.

    [delivery_kind]·[trainer_message]·[start_date] 는 프로그램 만들기의
    `개인운동만` 전송이 쓴다(#2223) — PT 없이 한 주 분량을 한 묶음으로 보내고,
    이력이 그 전송을 `개인운동만` 으로 알아볼 수 있게 종류와 한마디를 남긴다.

    [active_days] 는 **이 배정이 회원 목록에 며칠간 걸려 있는가**다. 추천
    개인운동은 매일 새로 체크하는 목록이고 그 기간은 `active_from`~`ended_on`
    이 정하므로(#2161), `개인운동만` 은 7 을 보내 보낸 날부터 한 주만 걸어
    둔다. 비우면 트레이너가 철회할 때까지 걸려 있는 기존 배정이다.

    [suggestion_ids] 는 이 전송의 개인운동을 채운 대기 중 AI 제안이다(#2747).
    배정과 같은 트랜잭션에서 닫아, 보낸 제안이 다음 위저드에 다시 뜨거나 대기
    백로그를 차지해 새 제안을 막지 않게 한다.
    """
    if client_request_id:
        existing = _program_routines_for_request(
            db, trainer_id, member_id, client_request_id, len(sessions)
        )
        if existing:
            return [_routine_out(db, rt) for rt in existing]

    # 단일 배정과 같은 이유로 알림보다 먼저 flush 한다 — 동시 요청이 유니크
    # 제약에 걸리면 진 쪽이 알림까지 쌓지 않아야 한다.
    try:
        # `개인운동만` 도 새로 보내는 개인운동이다 — PT 와 함께 보낼 때처럼
        # 이전 개인운동을 먼저 내린다(#2514). 내리지 않으면 지난 주 것과 이번
        # 주 것이 함께 걸려 회원이 두 벌을 받는다. 같은 트랜잭션이라 배정이
        # 실패하면 내린 것도 되돌아간다. 재시도는 위에서 이미 돌려보냈으므로
        # 방금 보낸 한 주를 내리는 일은 없다.
        if delivery_kind is not None:
            _retire_personal_routines(
                db, trainer_id, member_id, today=clock.today()
            )
        created = _add_program_routines(
            db, trainer_id, member_id,
            name=name, sessions=sessions, client_request_id=client_request_id,
            delivery_kind=delivery_kind,
            trainer_message=trainer_message,
            start_date=start_date,
            active_days=active_days,
        )
        _consume_routine_suggestions(db, trainer_id, member_id, suggestion_ids)
    except IntegrityError:
        db.rollback()
        if client_request_id:
            existing = _program_routines_for_request(
                db, trainer_id, member_id, client_request_id, len(sessions)
            )
            if existing:
                return [_routine_out(db, rt) for rt in existing]
        raise
    if chat_card:
        exercise_names = [
            exercise.name
            for session in sessions
            for exercise in session.exercises
            if exercise.name
        ]
        if delivery_kind == DELIVERY_ROUTINE_ONLY:
            post_routine_delivery(
                db, trainer_id, member_id,
                kind=DELIVERY_ROUTINE_ONLY, routine_names=exercise_names,
            )
        else:
            post_routine_delivery(
                db, trainer_id, member_id,
                kind=delivery_kind or "program", program_names=exercise_names,
            )
    db.commit()
    for rt in created:
        db.refresh(rt)
    return [_routine_out(db, rt) for rt in created]
