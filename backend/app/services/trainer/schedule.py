"""트레이너 도메인 — 스케줄(트레이너 타임라인 + 예약→수업→기록 완료 루프)."""
from __future__ import annotations

import hashlib
import json
import uuid
from collections.abc import Mapping, Sequence
from datetime import date, datetime, timedelta, timezone
from typing import Any

from sqlalchemy import exists, func, or_, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core import clock
from app.models.models import (
    ExerciseSession, RoutineHistory,
    TrainerClient, TrainerReservation, TrainerRoutine, TrainerSchedule, User,
)
from app.schemas.trainer_api import (
    DeliveryOut,
    PersonalRoutineItem,
    ProgramDraftExercise,
    ProgramDraftSession,
    ProgramItem, ProgramScheduleOut, RoutineOut, ScheduleSessionOut,
)
from app.services import (
    data_consent_service,
    exercise_activity,
    exercise_service,
    exercise_types,
    notification_service,
    notification_templates,
    streak_shield_service,
)
from app.services.coach import personal_ingest
from app.services.exercise_duration import format_duration
from app.services.trainer._common import (
    ClientLinkDetached,
    DELIVERY_CANCELLED_ROUTINE_ONLY,
    DELIVERY_PT_WITH_ROUTINE,
    IdempotencyConflict,
    PT_HISTORY_KIND_LABEL,
    ROUTINE_APPROVED,
    ROUTINE_DISMISSED,
    ROUTINE_SCHEDULED,
    SCHEDULE_CANCELLED,
    SCHEDULE_DONE,
    SCHEDULE_GAP,
    SCHEDULE_NO_SHOW,
    SCHEDULE_TERMINAL,
    SCHEDULE_UPCOMING,
    _add_program_routines,
    _clock_minutes,
    _consume_routine_suggestions,
    _done_pt_numbers,
    _ensure_session_member_linked,
    _exercise_seconds,
    _is_consultation_booking,
    _is_reservation_schedule,
    _iso_day_or_none,
    _minutes_of,
    _program_items,
    _program_notification_args,
    _program_routines_for_request,
    _program_row_seconds,
    _release_cancelled_reservation,
    _retire_personal_routines,
    _routine_out,
    _routine_outs,
    _routine_prefetch,
    _schedule_out,
    _today,
    has_active_client_link,
    routine_sent_on,
    today_iso,
)
from app.services.trainer.chat import (
    post_routine_delivery,
)
from app.services.trainer.routines import (
    assign_program,
)


# ---- 스케줄 (트레이너 타임라인 + 예약→수업→기록 완료 루프) ----


#: 취소 주체. 트레이너 사정의 취소를 회원의 미이행으로 읽지 않으려면 남아야 한다.
CANCELLATION_SOURCES = frozenset({"member", "trainer", "other"})


class ScheduleError(ValueError):
    """스케줄 도메인 오류(라우터가 400 으로 변환)."""


class ScheduleConflict(Exception):
    """완료 세션 수정 등 상태 충돌(라우터가 409 로 변환)."""


def _program_item_label(item: ProgramItem) -> str:
    """이력 목록에 적히는 한 줄. 근력은 세트·횟수·중량, 나머지는 시간으로 읽는다.

    유형마다 재는 단위가 다르다(#1276) — 근력을 "30분"으로 적으면 트레이너가
    다음 무게를 정할 근거가 사라지고, 유산소를 "3세트"로 적으면 뜻이 없다.
    """
    if item.type == "근력":
        parts = [f"{item.sets}세트"] if item.sets else []
        # 버티는 운동은 회가 아니라 초로 읽는다 — `플랭크 3세트 60초`. 둘은
        # 배타라 한 줄에 함께 서지 않는다. (#1969)
        if item.hold_seconds:
            parts.append(f"{item.hold_seconds}초")
        elif item.reps:
            parts.append(f"{item.reps}회")
        # 맨몸 운동은 `0kg` 으로 적는다 — 옛 이력 행은 이 문장만 남아 있어, 값은
        # 읽을 때 `parse_history_exercise` 가 이 문장에서 되짚는다. `0kg` 을
        # 빼면 맨몸의 0 이 "적지 않음"(None)으로 바뀐다. 화면은 0 을 적지 않는다
        # (#2533). 값이 아예 없는 것은 규칙 이전의 옛 행뿐이다.
        if item.weight is not None:
            parts.append(f"{item.weight:g}kg")
    else:
        # 초까지 적는다 — `걷기 45초`·`사이클 1시간 30분`(#2546). 이 문장은
        # 되읽지 않는다: 값은 [_program_history_entry] 가 함께 남긴다.
        seconds = item.duration_seconds or 0
        parts = [format_duration(seconds)] if seconds else []
    return " ".join([item.name, *parts])


def _program_history_entry(item: ProgramItem) -> dict[str, Any]:
    """완료한 PT 의 운동 한 종목 → `RoutineHistory.exercises_json` 한 항목. (#2546)

    예전에는 문장([_program_item_label])만 남기고 읽을 때 값으로 되짚었는데, 그
    문장의 `초` 는 버티는 운동의 초로 읽혀 운동 시간 `45초` 를 적을 수 없었다 —
    그래서 분으로 반올림해 적었고 초는 영영 사라졌다. 이제 값을 그대로 남기고
    문장은 `label` 로 곁들인다. 비어 있는 칸은 적지 않는다.
    """
    strength = item.type == "근력"
    entry: dict[str, Any] = {
        "name": item.name,
        "type": item.type,
        "label": _program_item_label(item),
    }
    if strength:
        values = {
            "sets": item.sets,
            # 버티는 운동이면 횟수는 읽지 않는다 — 문장과 같다(#1969).
            "reps": None if item.hold_seconds else item.reps,
            "hold_seconds": item.hold_seconds,
            # 맨몸의 0 도 값이다 — 비워 두면 '적지 않음'이 된다(#2533).
            "weight": item.weight,
        }
    else:
        values = {
            "minutes": item.duration,
            "duration_seconds": item.duration_seconds,
        }
    entry.update({k: v for k, v in values.items() if v is not None})
    return entry


def _program_seconds_and_type(
    items: Sequence[ProgramItem],
) -> tuple[int, str | None]:
    """프로그램 항목들을 (총 초, 가장 많은 유형)으로 요약한다. (#1233, #2221)

    `_session_summary` 와 같은 규칙이다 — 시간은 각 항목 `duration_seconds` 의
    합, 유형은 가장 많은 유형. 항목이 하나도 없으면 유형은 None 이라 호출부가
    기존 폴백(세션 유형 고정값)을 쓸 수 있다.

    근력 항목은 시간을 적지 않으므로 세트에서 환산한다([_exercise_seconds]).
    """
    seconds = 0
    counts: dict[str, int] = {}
    for item in items:
        seconds += _exercise_seconds(item.type, item.duration_seconds, item.sets)
        counts[item.type] = counts.get(item.type, 0) + 1
    type_ = max(counts, key=lambda t: counts[t]) if counts else None
    return seconds, type_


def _personal_row_seconds(row: TrainerRoutine) -> int:
    """개인운동 한 줄의 시간(초). (#3107)

    개인운동 줄은 운동 구성(`exercises_json`) 없이 한 운동을 칸에 담는다 —
    프로그램 줄처럼 읽으면 분으로 떨어져 45초가 1분, 근력은 0분이 된다.
    근력은 세트에서 환산하고([_exercise_seconds]), 둘 다 없는 옛 줄만 분으로 읽는다.
    """
    return _exercise_seconds(
        row.type, row.duration_seconds, row.sets
    ) or row.minutes * 60


def _reservation_schedule_ids(db: Session, session_ids: set[str]) -> set[str]:
    """[session_ids] 중 회원 예약이 소유한 일정. [_is_reservation_schedule] 의 묶음판."""
    if not session_ids:
        return set()
    return set(
        db.scalars(
            select(TrainerReservation.schedule_id).where(
                TrainerReservation.schedule_id.in_(sorted(session_ids))
            )
        ).all()
    )


def _linked_member_ids(
    db: Session, trainer_id: str, member_ids: set[str]
) -> set[str]:
    """[member_ids] 중 이 트레이너와 담당·동의 경계 안인 회원. (#2589)

    [has_active_client_link] 를 여러 회원에 한 번에 묻는 것이다 — 주간 스케줄이
    일정마다 따로 물으면 요청 하나에 쿼리가 일정 수만큼 늘어난다.
    """
    if not member_ids:
        return set()
    return set(
        db.scalars(
            select(TrainerClient.member_id).where(
                TrainerClient.trainer_id == trainer_id,
                TrainerClient.member_id.in_(sorted(member_ids)),
                TrainerClient.active.is_(True),
                data_consent_service.allows_access_clause(),
            )
        ).all()
    )


def _schedule_outs(
    db: Session, trainer_id: str, rows: Sequence[TrainerSchedule]
) -> list[ScheduleSessionOut]:
    """일정 행들을 응답으로 — 담당이 끊긴 회원의 일정은 익명으로. (#2589)"""
    linked = _linked_member_ids(
        db, trainer_id, {s.member_id for s in rows if s.member_id}
    )
    reserved = _reservation_schedule_ids(db, {s.id for s in rows})
    return [
        _schedule_out(
            s,
            detached=bool(s.member_id)
            and s.member_id not in linked
            and not _is_consultation_booking(s),
            is_reservation=s.id in reserved,
        )
        for s in rows
    ]


def build_client_schedule(
    db: Session, trainer_id: str, member_id: str
) -> list[ScheduleSessionOut]:
    """한 고객의 전체 세션(날짜→시간 순), 기간 제한 없이.

    고객 상세의 루틴 이력이 쓴다. 넓은 날짜 구간으로 흉내내면 그 구간보다
    오래된 기록이 조용히 빠지고, 화면은 그걸 '기록 없음'으로 읽는다.
    행 수는 트레이너-고객 한 쌍의 세션 수라 자연히 작다.
    """
    rows = db.scalars(
        select(TrainerSchedule)
        .where(
            TrainerSchedule.trainer_id == trainer_id,
            TrainerSchedule.member_id == member_id,
        )
        .order_by(
            TrainerSchedule.date, TrainerSchedule.time, TrainerSchedule.sort_order
        )
    ).all()
    reserved = _reservation_schedule_ids(db, {s.id for s in rows})
    return [_schedule_out(s, is_reservation=s.id in reserved) for s in rows]


def build_schedule_range(
    db: Session,
    trainer_id: str,
    from_day: str,
    to_day: str,
    member_id: str | None = None,
) -> list[ScheduleSessionOut]:
    """[from_day, to_day] 구간의 슬롯을 날짜→시간 순으로.

    주 캘린더가 7일치를 한 번에 읽기 위한 것 — 하루짜리 조회를 요일마다
    반복하면 요청이 7배가 된다. `YYYY-MM-DD` 는 사전식 정렬이 곧 날짜순이라
    문자열 범위 비교로 충분하다.

    [member_id] 를 주면 그 고객의 세션만 (공백 슬롯은 자연히 빠진다 —
    배정된 회원이 없으므로). 이때는 활성 담당일 때만 준다 — 회원별 조회는 회원
    상세가 쓰는 길이라 해제 회원에게 열리면 안 된다(#2281).

    전체 스케줄에는 담당이 끊긴 회원의 일정도 남긴다(#2589). 트레이너가 참여한
    수업이 달력에서 빠지면 지난 근무를 되짚을 수 없고 그 시간이 빈 시간처럼
    보인다. 회원 식별 정보는 [_schedule_outs] 가 가린다.
    """
    conditions = [
        TrainerSchedule.trainer_id == trainer_id,
        TrainerSchedule.date >= from_day,
        TrainerSchedule.date <= to_day,
    ]
    if member_id is not None:
        conditions.append(TrainerSchedule.member_id == member_id)
        conditions.append(
            exists(
                select(TrainerClient.id).where(
                    TrainerClient.trainer_id == trainer_id,
                    TrainerClient.member_id == member_id,
                    TrainerClient.active.is_(True),
                )
            )
        )
    rows = db.scalars(
        select(TrainerSchedule)
        .where(*conditions)
        .order_by(
            TrainerSchedule.date, TrainerSchedule.time, TrainerSchedule.sort_order
        )
    ).all()
    return _schedule_outs(db, trainer_id, rows)


#: booked_dates 조회 하한(일). 주간 스트립 도트용이라 과거 전체가 필요없다 — 시간이 갈수록
#: 결과가 무한정 커지는 것을 막는다(리뷰 #280). 문자열 날짜(YYYY-MM-DD)는 사전식 비교 가능.
_BOOKED_DATES_WINDOW_DAYS = 90


def booked_dates(db: Session, trainer_id: str) -> list[str]:
    """예약이 있는(공백 아닌) 날짜 목록 — 주간 스트립 도트용(최근 90일 이후).

    담당이 끊긴 회원의 일정도 센다 — 스케줄이 그 일정을 익명으로 보여 주므로
    (#2589) 점과 목록이 어긋나면 안 된다.
    """
    cutoff = (_today() - timedelta(days=_BOOKED_DATES_WINDOW_DAYS)).isoformat()
    rows = db.scalars(
        select(TrainerSchedule.date)
        .where(
            TrainerSchedule.trainer_id == trainer_id,
            TrainerSchedule.status != "공백",
            TrainerSchedule.date >= cutoff,
        )
        .distinct()
    ).all()
    return sorted(rows)


def _get_owned_session(db: Session, trainer_id: str, session_id: str) -> TrainerSchedule | None:
    s = db.get(TrainerSchedule, session_id)
    if s is None or s.trainer_id != trainer_id:
        return None
    return s


def _dump_program(
    program: Sequence[ProgramItem | Mapping[str, object]],
) -> str:
    """Serialize validated program items from create and partial-update paths.

    Schedule creation passes ``ProgramItem`` instances, while
    ``ScheduleUpdateRequest.model_dump()`` recursively converts the same items
    to dictionaries before calling the service.  Supporting both forms keeps
    the service boundary consistent for API and direct service callers.
    """
    items = [
        item.model_dump(mode="json") if isinstance(item, ProgramItem) else dict(item)
        for item in program
    ]
    # `default=str` 은 dict 로 온 쪽의 날짜를 위한 것이다 — 부분 수정 경로는
    # 이미 model_dump() 를 거쳐 date 객체를 담고 오는데, json 은 그걸 모른다.
    return json.dumps(items, ensure_ascii=False, default=str)


def _existing_schedule_out(
    session: TrainerSchedule,
    *,
    date: str,
    time: str,
    client_name: str,
    member_id: str | None,
    type_: str,
    duration_minutes: int,
    note: str,
    program_json: str,
) -> ScheduleSessionOut:
    same_payload = (
        session.date == date
        and session.time == time
        and session.client_name == client_name
        and session.member_id == member_id
        and session.type == type_
        and session.duration_minutes == duration_minutes
        and session.note == note
        and session.program_json == program_json
    )
    if not same_payload:
        raise IdempotencyConflict(
            "같은 client_request_id에 다른 스케줄을 생성할 수 없습니다."
        )
    return _schedule_out(session)


def create_session(
    db: Session, trainer_id: str, *, date: str, time: str, client_name: str,
    member_id: str | None, type_: str, duration_minutes: int, note: str,
    program: list[ProgramItem], client_request_id: str | None = None,
) -> ScheduleSessionOut:
    program_json = _dump_program(program)
    if client_request_id:
        existing = db.scalar(
            select(TrainerSchedule).where(
                TrainerSchedule.trainer_id == trainer_id,
                TrainerSchedule.client_request_id == client_request_id,
            )
        )
        if existing is not None:
            return _existing_schedule_out(
                existing,
                date=date,
                time=time,
                client_name=client_name,
                member_id=member_id,
                type_=type_,
                duration_minutes=duration_minutes,
                note=note,
                program_json=program_json,
            )

    # 재시도 응답(위)보다 뒤에 둔다 — 이미 만든 일정의 재시도가 자기 자신과
    # 겹친다고 거절당하면 안 된다. (#2284)
    ensure_no_overlap(
        db, trainer_id, date=date, time=time, duration_minutes=duration_minutes
    )

    # 같은 키의 동시 요청은 유니크 제약으로 하나만 통과시킨 뒤, 패배한 요청은
    # 승자의 행을 읽어 같은 결과를 반환한다. 알림은 flush 뒤라 중복되지 않는다.
    try:
        s = _add_session(
            db,
            trainer_id,
            date=date,
            time=time,
            client_name=client_name,
            member_id=member_id,
            type_=type_,
            duration_minutes=duration_minutes,
            note=note,
            program_json=program_json,
            client_request_id=client_request_id,
        )
    except IntegrityError:
        db.rollback()
        if client_request_id:
            existing = db.scalar(
                select(TrainerSchedule).where(
                    TrainerSchedule.trainer_id == trainer_id,
                    TrainerSchedule.client_request_id == client_request_id,
                )
            )
            if existing is not None:
                return _existing_schedule_out(
                    existing,
                    date=date,
                    time=time,
                    client_name=client_name,
                    member_id=member_id,
                    type_=type_,
                    duration_minutes=duration_minutes,
                    note=note,
                    program_json=program_json,
                )
        raise
    db.commit()
    db.refresh(s)
    return _schedule_out(s)


def _add_session(
    db: Session, trainer_id: str, *, date: str, time: str, client_name: str,
    member_id: str | None, type_: str, duration_minutes: int, note: str,
    program_json: str, client_request_id: str | None,
) -> TrainerSchedule:
    """예정 일정과 그 알림을 세션에 올리고 flush 한다. 커밋은 호출부 몫이다.

    [_add_program_routines] 와 같은 이유로 커밋하지 않는다(#1580).
    """
    s = TrainerSchedule(
        id=f"sched-{uuid.uuid4().hex[:12]}",
        trainer_id=trainer_id,
        member_id=member_id,
        date=date,
        time=time,
        client_name=client_name,
        type=type_,
        duration_minutes=duration_minutes,
        status="예정",
        note=note,
        program_json=program_json,
        sort_order=0,
        client_request_id=client_request_id,
    )
    db.add(s)
    db.flush()

    # 회원 몫의 일정이 잡혔을 때만 알린다 — 가망 고객('신규 고객 · 상담')처럼
    # member_id 가 없는 슬롯은 알릴 대상 자체가 없다(#489).
    if member_id is not None:
        notification_service.queue(
            db,
            member_id=member_id,
            kind=notification_service.PT_LINK_NOTICE,
            category=notification_service.MEMBER_SCHEDULE,
            template=notification_templates.MEMBER_SCHEDULE_ADDED,
            template_args={"date": date, "time": time, "type": type_},
        )
    return s


#: 한 번의 반복 설정으로 만들 수 있는 최대 회차. 주 2회면 반년, 주 1회면 1년치다.
#: 상한을 두는 까닭은 오입력 때문이다 — 종료일에 연도를 잘못 적으면 수백 건이
#: 조용히 생기고, 그것을 되돌리는 일은 한 건씩 지우는 것뿐이다(#870).
MAX_SERIES_OCCURRENCES = 52


class ScheduleSeriesConflict(Exception):
    """반복 생성이 기존 일정과 겹친다. 겹치는 회차 목록을 들고 다닌다. (#870)

    라우터가 409 로 바꾸고, 화면은 이 목록을 그대로 보여 준다 — "총 8회 중 1개가
    겹칩니다" 는 겹치는 회차를 짚어 줄 수 있어야 트레이너가 판단한다.
    """

    def __init__(self, conflicts: list[ScheduleSessionOut]) -> None:
        super().__init__("겹치는 일정이 있습니다.")
        self.conflicts = conflicts


def _series_id_for(trainer_id: str, client_request_id: str) -> str:
    """생성 시도 하나에 대응하는 결정론적 시리즈 id.

    회차마다 멱등키를 따로 두지 않는 까닭은 유니크 제약이 (trainer, key) 한 쌍
    이기 때문이다. 대신 키에서 시리즈 id 를 만들어, 재시도가 **이미 만든 시리즈를
    다시 찾아** 같은 결과를 돌려주게 한다.
    """
    digest = hashlib.sha256(f"{trainer_id}:{client_request_id}".encode()).hexdigest()
    return f"series-{digest[:20]}"


def series_occurrences(
    start: date, weekdays: Sequence[int], *, count: int | None, until: date | None
) -> list[date]:
    """반복 규칙이 만드는 날짜들.

    [weekdays] 는 ISO 요일(월=1 … 일=7)이다. 시작일이 고른 요일 중 하나면 그 날도
    첫 회차가 된다 — 트레이너가 오늘 잡으며 "매주 화요일" 을 고르면 오늘(화요일)이
    빠지는 편이 더 놀랍다.

    종료는 횟수(`count`) 또는 종료일(`until`) 중 하나다. 둘 다 없으면 빈 목록이라
    호출부가 검증을 건너뛴 채 무한히 만들 수 없다. 어느 쪽이든 [MAX_SERIES_OCCURRENCES]
    를 넘지 않는다.
    """
    picked = {day for day in weekdays if 1 <= day <= 7}
    if not picked or (count is None and until is None):
        return []
    limit = min(count or MAX_SERIES_OCCURRENCES, MAX_SERIES_OCCURRENCES)
    out: list[date] = []
    day = start
    # 종료일이 없으면 회차 수가 멈춰 세운다. 종료일이 있어도 상한을 함께 두어,
    # 먼 미래 날짜 하나가 수백 건을 만들지 않게 한다.
    horizon = until or (start + timedelta(days=7 * MAX_SERIES_OCCURRENCES))
    while day <= horizon and len(out) < limit:
        if day.isoweekday() in picked:
            out.append(day)
        day += timedelta(days=1)
    return out


#: 겹침 409 응답의 `detail.code`. 화면은 문구가 아니라 이 값으로 겹침을 알아보고
#: 자기 언어의 안내를 띄운다 — 서버 문구는 한국어 한 벌뿐이다. (#2284)
SCHEDULE_OVERLAP_CODE = "schedule_overlap"

#: 시간을 차지하는 상태. 취소·노쇼는 그 시간이 비어 있고(#871), 공백 슬롯은
#: "빈 시간" 이라는 표시일 뿐이다.
_OCCUPYING_STATUSES = (SCHEDULE_UPCOMING, SCHEDULE_DONE)


class ScheduleOverlap(Exception):
    """새로 잡거나 옮기려는 시간이 트레이너의 기존 일정과 겹친다. (#2284)

    라우터가 409 `schedule_overlap` 으로 바꾼다. 겹친 세션 목록을 들고 다녀
    트레이너 화면이 "몇 시 누구 일정과 겹치는지" 를 짚어 줄 수 있다 — 회원에게
    가는 응답에는 남의 일정이 섞이지 않게 라우터가 목록을 뺀다.
    """

    def __init__(
        self,
        conflicts: list[ScheduleSessionOut],
        message: str = "같은 시간에 이미 다른 일정이 있습니다.",
    ) -> None:
        super().__init__(message)
        self.conflicts = conflicts


def overlap_detail(exc: ScheduleOverlap, *, include_conflicts: bool = True) -> dict:
    """[ScheduleOverlap] 을 409 응답 본문으로. 모든 경로가 같은 모양을 쓴다."""
    detail: dict = {"code": SCHEDULE_OVERLAP_CODE, "message": str(exc)}
    if include_conflicts:
        detail["conflicts"] = [c.model_dump(mode="json") for c in exc.conflicts]
    return detail


def _interval(day: str, time: str, duration_minutes: int) -> tuple[int, int] | None:
    """(날짜, 시작 시각, 길이) 를 절대 분 단위 반열린 구간 `[시작, 끝)` 으로.

    날짜까지 분으로 펴는 까닭은 자정을 넘는 세션 때문이다 — 23:30 에 90분짜리
    PT 는 다음 날 00:30 의 일정과 겹친다. 길이가 0인 세션은 시작 1분으로 본다
    ([_overlapping_planned_sessions] 와 같은 규칙). 형식이 틀리면 None.
    """
    try:
        start = date.fromisoformat(day).toordinal() * 24 * 60 + _clock_minutes(time)
    except ValueError:
        return None
    return start, start + max(duration_minutes, 1)


def conflicting_sessions(
    db: Session,
    trainer_id: str,
    slots: Sequence[tuple[str, str]],
    *,
    duration_minutes: int = 0,
    exclude_ids: Sequence[str] = (),
) -> list[ScheduleSessionOut]:
    """[slots]((date, time) 쌍, 각각 [duration_minutes] 길이)과 시간이 겹치는 세션.

    겹침은 반열린 구간끼리 본다 — 10:00(60분)과 10:30 은 겹치고, 10:00–11:00 과
    11:00 시작은 이어질 뿐 겹치지 않는다. 예전에는 날짜·시작 시각이 똑같을 때만
    겹침으로 봐 10:00(60분) 위에 10:30 이 조용히 들어갔다(#2284).

    취소·노쇼·공백은 자리를 차지하지 않는다(#871). [exclude_ids] 는 옮기는 세션
    자신처럼 비교에서 뺄 일정이다.

    반복 생성·단건 생성·수정, 회원 예약·슬롯 열기, 상담 승인이 모두 이 판정을
    쓴다 — 경로마다 따로 두면 한 곳만 고쳐지는 사고가 난다.
    """
    wanted = [
        interval
        for day, time in slots
        if (interval := _interval(day, time, duration_minutes)) is not None
    ]
    if not wanted:
        return []
    # 전날 늦게 시작해 자정을 넘긴 세션도 보려면 하루 앞까지 읽는다.
    days: set[str] = set()
    for day, _ in slots:
        try:
            parsed = date.fromisoformat(day)
        except ValueError:
            continue
        days.add(parsed.isoformat())
        days.add((parsed - timedelta(days=1)).isoformat())
    query = select(TrainerSchedule).where(
        TrainerSchedule.trainer_id == trainer_id,
        TrainerSchedule.date.in_(sorted(days)),
        TrainerSchedule.status.in_(_OCCUPYING_STATUSES),
    )
    if exclude_ids:
        query = query.where(TrainerSchedule.id.not_in(list(exclude_ids)))
    rows = db.scalars(
        query.order_by(TrainerSchedule.date, TrainerSchedule.time, TrainerSchedule.id)
    ).all()
    hits: list[TrainerSchedule] = []
    for row in rows:
        existing = _interval(row.date, row.time, row.duration_minutes)
        if existing is None:
            continue
        if any(start < existing[1] and existing[0] < end for start, end in wanted):
            hits.append(row)
    # 겹친 일정은 거절 응답에 실려 나간다 — 담당이 끊긴 회원의 이름이 거기로 새지
    # 않게 스케줄과 같이 가린다(#2589).
    return _schedule_outs(db, trainer_id, hits)


def ensure_no_overlap(
    db: Session,
    trainer_id: str,
    *,
    date: str,
    time: str,
    duration_minutes: int,
    exclude_ids: Sequence[str] = (),
    message: str | None = None,
) -> None:
    """한 자리가 비어 있는지 확인하고, 겹치면 [ScheduleOverlap]. (#2284)"""
    conflicts = conflicting_sessions(
        db,
        trainer_id,
        [(date, time)],
        duration_minutes=duration_minutes,
        exclude_ids=exclude_ids,
    )
    if conflicts:
        if message is None:
            raise ScheduleOverlap(conflicts)
        raise ScheduleOverlap(conflicts, message)


def preview_recurring_sessions(
    db: Session,
    trainer_id: str,
    *,
    start: str,
    time: str,
    weekdays: Sequence[int],
    count: int | None = None,
    until: str | None = None,
    duration_minutes: int = 0,
    client_request_id: str | None = None,
) -> tuple[list[str], list[ScheduleSessionOut], bool]:
    """저장 전에 보여 줄 (생성될 날짜들, 겹치는 기존 세션들, 이미 만들어졌는지).

    만들기 전에 확인시키는 까닭은 반복이 **한 번에 여러 건**을 만들기 때문이다.
    요일이나 종료일을 잘못 골랐을 때 되돌리는 비용이 한 건씩 지우는 일이라,
    그 전에 보여 주는 편이 싸다.

    [client_request_id] 는 만들기와 같은 키다. 그 키의 시리즈가 이미 있으면 —
    만들기는 커밋됐는데 응답만 잃은 재시도 — 그 회차들을 충돌에서 빼고
    `already_created` 를 참으로 돌려준다. 빼지 않으면 방금 만든 자기 회차와
    겹친다고 막혀, 같은 키로 만들기를 다시 불러 결과를 받는 길이 끊긴다(#3102).
    """
    dates = series_occurrences(
        date.fromisoformat(start),
        weekdays,
        count=count,
        until=None if until is None else date.fromisoformat(until),
    )
    iso = [day.isoformat() for day in dates]
    own_ids: list[str] = []
    if client_request_id:
        own_ids = list(
            db.scalars(
                select(TrainerSchedule.id).where(
                    TrainerSchedule.trainer_id == trainer_id,
                    TrainerSchedule.series_id
                    == _series_id_for(trainer_id, client_request_id),
                )
            ).all()
        )
    conflicts = conflicting_sessions(
        db,
        trainer_id,
        [(day, time) for day in iso],
        duration_minutes=duration_minutes,
        exclude_ids=own_ids,
    )
    return iso, conflicts, bool(own_ids)


def create_recurring_sessions(
    db: Session,
    trainer_id: str,
    *,
    start: str,
    time: str,
    weekdays: Sequence[int],
    client_name: str,
    member_id: str | None,
    type_: str,
    duration_minutes: int,
    note: str = "",
    count: int | None = None,
    until: str | None = None,
    client_request_id: str | None = None,
) -> list[ScheduleSessionOut]:
    """반복 규칙대로 PT 회차를 한 번에 만든다. (#870)

    **전부 만들거나 하나도 만들지 않는다.** 겹치는 회차가 있으면
    [ScheduleSeriesConflict] 로 멈춘다 — 겹친 것만 빼고 조용히 나머지를 만들면
    트레이너는 몇 회차가 생겼는지 화면을 세어 봐야 알 수 있고, 빠진 주는 나중에
    발견된다.

    [client_request_id] 를 주면 그 시도에 대해 멱등하다. 응답을 못 받고 재시도한
    등록이 같은 회차를 두 벌 만들면 회원 일정이 두 배가 된다.
    """
    series_id = (
        _series_id_for(trainer_id, client_request_id) if client_request_id else None
    )
    if series_id is not None:
        existing = db.scalars(
            select(TrainerSchedule)
            .where(
                TrainerSchedule.trainer_id == trainer_id,
                TrainerSchedule.series_id == series_id,
            )
            .order_by(TrainerSchedule.date, TrainerSchedule.time)
        ).all()
        if existing:
            return [_schedule_out(row) for row in existing]

    dates = series_occurrences(
        date.fromisoformat(start),
        weekdays,
        count=count,
        until=None if until is None else date.fromisoformat(until),
    )
    if not dates:
        raise ScheduleError("반복할 요일과 종료 기준을 지정해 주세요.")

    iso = [day.isoformat() for day in dates]
    conflicts = conflicting_sessions(
        db,
        trainer_id,
        [(day, time) for day in iso],
        duration_minutes=duration_minutes,
    )
    if conflicts:
        raise ScheduleSeriesConflict(conflicts)

    program_json = _dump_program([])
    created: list[TrainerSchedule] = []
    for day in iso:
        row = TrainerSchedule(
            id=f"sched-{uuid.uuid4().hex[:12]}",
            trainer_id=trainer_id,
            member_id=member_id,
            date=day,
            time=time,
            client_name=client_name,
            type=type_,
            duration_minutes=duration_minutes,
            status=SCHEDULE_UPCOMING,
            note=note,
            program_json=program_json,
            sort_order=0,
            series_id=series_id,
        )
        db.add(row)
        created.append(row)
    try:
        db.flush()
    except IntegrityError:
        # 같은 키의 동시 요청 중 하나만 통과한다. 패배한 쪽은 승자가 만든 회차를
        # 읽어 같은 결과를 돌려준다(단건 생성과 같은 규약).
        db.rollback()
        if series_id is not None:
            existing = db.scalars(
                select(TrainerSchedule)
                .where(
                    TrainerSchedule.trainer_id == trainer_id,
                    TrainerSchedule.series_id == series_id,
                )
                .order_by(TrainerSchedule.date, TrainerSchedule.time)
            ).all()
            if existing:
                return [_schedule_out(row) for row in existing]
        raise

    # 회원에게는 회차마다 알리지 않는다. 8주치를 한 번에 잡으면 알림함이 같은
    # 문구 여덟 줄로 덮이고, 그 뒤의 다른 알림이 밀려난다 — 한 줄로 묶어 보낸다.
    if member_id is not None:
        notification_service.queue(
            db,
            member_id=member_id,
            kind=notification_service.PT_LINK_NOTICE,
            category=notification_service.MEMBER_SCHEDULE,
            template=notification_templates.MEMBER_SCHEDULE_SERIES,
            template_args={
                "first": iso[0], "last": iso[-1], "time": time, "count": len(iso),
            },
        )
    db.commit()
    for row in created:
        db.refresh(row)
    return [_schedule_out(row) for row in created]


def _schedule_program_items(
    sessions: Sequence[ProgramDraftSession],
) -> list[ProgramItem]:
    """프로그램 세션들을 일정 한 건의 평면 항목으로 펼친다. (#709, #1580)

    세션 이름은 항목마다 붙는다 — 일정은 평면 목록이지만 이 값으로 다시 세션별로
    묶어 보여 줄 수 있다. 세션이 하나뿐이면 빈 문자열이라 예전 일정과 같은 모양이다.
    유형에 맞지 않는 칸은 [ProgramItem] 검증이 비운다(#1276).
    """
    multi = len(sessions) > 1
    return [
        ProgramItem(
            name=exercise.name,
            type=exercise.type,
            date=exercise.date,
            duration=exercise.duration,
            duration_seconds=exercise.duration_seconds,
            sets=exercise.sets,
            reps=exercise.reps,
            hold_seconds=exercise.hold_seconds,
            weight=exercise.weight,
            intensity=exercise.intensity,
            session=session.name if multi else "",
        )
        for session in sessions
        for exercise in session.exercises
    ]


class AttachTargetConflict(Exception):
    """프로그램을 붙일 기존 세션을 하나로 정할 수 없다(#1581).

    고른 시간대와 겹치는 예정 세션이 여럿인데 고르지 않았거나, 고른 세션이 더는
    후보가 아니다. 라우터가 409 와 함께 후보를 싣는다.
    """

    #: 409 `detail.code` — 객체 `detail` 은 모두 `code` 를 단다(#2911).
    code = "attach_target_conflict"

    def __init__(self, message: str, candidates: Sequence[TrainerSchedule]):
        super().__init__(message)
        self.candidates = [_schedule_out(s) for s in candidates]


def _overlapping_planned_sessions(
    db: Session, trainer_id: str, member_id: str, *,
    date: str, time: str, duration_minutes: int,
) -> list[TrainerSchedule]:
    """고른 시간대와 겹치는 그 회원·그날의 예정 세션(시작 시각 순). (#1581)

    예전에는 시간과 상관없이 그날 가장 이른 예정 세션에 붙어, 같은 날 PT 가
    여럿이면 의도하지 않은 회차에 프로그램이 들어갔다. 겹침은 반열린 구간
    `[시작, 끝)` 끼리 본다 — 10:00–11:00 과 11:00–12:00 은 이어질 뿐 겹치지
    않는다. 길이가 0인 세션은 시작 1분으로 본다.
    """
    rows = db.scalars(
        select(TrainerSchedule)
        .where(
            TrainerSchedule.trainer_id == trainer_id,
            TrainerSchedule.member_id == member_id,
            TrainerSchedule.date == date,
            TrainerSchedule.status == "예정",
        )
        .order_by(TrainerSchedule.time, TrainerSchedule.id)
        .with_for_update()
    ).all()
    start = _clock_minutes(time)
    end = start + duration_minutes
    overlapping: list[TrainerSchedule] = []
    for row in rows:
        try:
            row_start = _clock_minutes(row.time)
        except ValueError:
            continue
        if start < row_start + max(row.duration_minutes, 1) and row_start < end:
            overlapping.append(row)
    return overlapping


def _schedule_request_key(base: str) -> str:
    """`일정 추가` 가 새로 만든 일정 행의 멱등키. 루틴 키(`#0`…)와 겹치지 않는다."""
    return f"{base}#schedule"


def _personal_request_key(base: str, index: int) -> str:
    """PT 에 붙인 개인운동 행의 멱등키. 세션 루틴(`#0`…)·일정(`#schedule`)과
    겹치지 않는다. (#2223)"""
    return f"{base}#routine{index}"


def _scheduled_routines_for_request(
    db: Session, trainer_id: str, member_id: str, client_request_id: str,
) -> list[TrainerRoutine]:
    """그 멱등키로 이미 붙여 둔 개인운동들(넣은 순서대로). 없으면 빈 목록."""
    return list(
        db.scalars(
            select(TrainerRoutine)
            .where(
                TrainerRoutine.trainer_id == trainer_id,
                TrainerRoutine.member_id == member_id,
                TrainerRoutine.client_request_id.like(
                    f"{client_request_id}#routine%"
                ),
            )
            .order_by(TrainerRoutine.sort_order, TrainerRoutine.id)
        ).all()
    )


def _clear_scheduled_routines(
    db: Session, trainer_id: str, schedule_id: str, *, keep_personal: bool = False
) -> None:
    """그 PT 에 붙어 있던 **아직 보내지 않은** 줄을 지운다. (#2224, #2279)

    프로그램과 개인운동을 함께 걷는다 — 둘 다 `scheduled` 로 붙어 있다가 전송
    때 함께 나간다. 보낸 것(`approved`)·보내지 않기로 한 것(`dismissed`)은
    건드리지 않는다: 회원이 이미 받았거나 트레이너가 이미 답한 것이다.

    [keep_personal] 이면 개인운동은 두고 프로그램 줄만 걷는다(#2280) — 개인운동
    없이 다시 붙인 PT 에서 "없이" 를 "지워라" 로 읽으면, 일정 상세에서 붙여 둔
    개인운동이 말없이 사라진다.
    """
    query = select(TrainerRoutine).where(
        TrainerRoutine.trainer_id == trainer_id,
        TrainerRoutine.schedule_id == schedule_id,
        TrainerRoutine.status == ROUTINE_SCHEDULED,
    )
    if keep_personal:
        query = query.where(TrainerRoutine.delivery_kind.is_(None))
    for row in db.scalars(query).all():
        db.delete(row)
    db.flush()


def _add_scheduled_routines(
    db: Session, trainer_id: str, member_id: str, *,
    items: Sequence[PersonalRoutineItem],
    schedule_id: str,
    exercise_date: str,
    client_request_id: str | None,
) -> list[TrainerRoutine]:
    """PT 일정에 붙는 개인운동을 세션에 올리고 flush 한다. 커밋은 호출부 몫이다. (#2223)

    `status=scheduled` 로 들어가므로 회원 조회(`build_routines`)에도 제안 검토
    목록(`list_routine_suggestions`)에도 잡히지 않는다 — 회원에게 가는 것은 그
    PT 를 완료할 때다(#2224). 그래서 **배정 알림도 여기서 보내지 않는다.**
    지금 알리면 회원은 아직 오지 않은 운동의 알림을 먼저 받는다.
    """
    if not items:
        return []
    max_order = db.scalar(
        select(func.max(TrainerRoutine.sort_order)).where(
            TrainerRoutine.trainer_id == trainer_id,
            TrainerRoutine.member_id == member_id,
        )
    ) or 0
    now = datetime.now(timezone.utc)
    created: list[TrainerRoutine] = []
    for index, item in enumerate(items):
        rt = TrainerRoutine(
            id=f"rt-{uuid.uuid4().hex[:12]}",
            trainer_id=trainer_id,
            member_id=member_id,
            name=item.name,
            minutes=item.minutes,
            duration_seconds=item.duration_seconds,
            type=item.type,
            exercise_date=exercise_date,
            intensity=item.intensity,
            # 세트·횟수·중량·초는 단일 배정과 같은 규칙으로 근력에만 남긴다
            # (#1276, #1310, #1969).
            sets=item.sets if item.type == "근력" else None,
            reps=(
                item.reps
                if item.type == "근력" and item.hold_seconds is None
                else None
            ),
            hold_seconds=item.hold_seconds if item.type == "근력" else None,
            weight=(
                round(item.weight, 1)
                if item.weight is not None and item.type == "근력"
                else None
            ),
            reason=item.reason,
            effect=item.effect.strip(),
            source=item.source,
            status=ROUTINE_SCHEDULED,
            schedule_id=schedule_id,
            delivery_kind=DELIVERY_PT_WITH_ROUTINE,
            sort_order=max_order + index + 1,
            client_request_id=(
                _personal_request_key(client_request_id, index)
                if client_request_id
                else None
            ),
            created_at=now,
        )
        db.add(rt)
        created.append(rt)
    db.flush()
    return created


def _delivery_base_key(client_request_id: str | None) -> str | None:
    """한 번의 전송이 만든 줄들이 함께 쓰는 값. (#2225)

    `일정 추가`·`개인운동만` 은 전송 시도마다 키 하나(`base`)를 만들고, 거기서
    나온 줄에 `{base}#0`(프로그램)·`{base}#routine0`(개인운동)·
    `{base}#schedule`(일정)을 붙인다. 앞부분이 곧 그 전송의 이름이다.
    """
    if not client_request_id:
        return None
    return client_request_id.split("#", 1)[0]


def latest_delivery(
    db: Session, trainer_id: str, member_id: str
) -> DeliveryOut | None:
    """이 회원에게 **가장 최근에 보낸 것** 한 묶음. (#2225)

    전송 이력이 PT 프로그램과 개인운동을 따로 나열하던 동안에는, PT 완료 때 함께
    보낸 개인운동이 어느 PT 와 짝인지 알 수 없었다(#2224).

    묶는 기준은 멱등키의 앞부분이다([_delivery_base_key]). 키가 없는 옛 배정은
    **보낸 날과 종류**로 묶는다 — 그 시절에는 한 날 한 종류가 한 전송이었다.

    아직 보내지 않은 것(`scheduled`)은 보낸 것이 아니므로 빼고, 트레이너가
    물린 것(`dismissed`)도 뺀다.
    """
    newest = db.scalar(
        select(TrainerRoutine)
        .where(
            TrainerRoutine.trainer_id == trainer_id,
            TrainerRoutine.member_id == member_id,
            TrainerRoutine.status == ROUTINE_APPROVED,
            TrainerRoutine.delivery_kind.is_not(None),
            # 미래 시작일로 보냈다가 걸리기 전에 다른 것으로 바꾼 줄은 하루도
            # 뜨지 않았다(#2656) — 가장 최근 전송이 아니다.
            or_(
                TrainerRoutine.ended_on.is_(None),
                TrainerRoutine.ended_on > TrainerRoutine.active_from,
            ),
        )
        # 같은 날 두 번 보내면 `created_at` 이 같은 초에 걸릴 수 있다. 그때
        # `id` 로 가르면 난수라 순서가 뒤집힌다 — `sort_order` 는 이 회원의
        # 배정이 늘 때마다 커지므로 나중 것이 늘 뒤다.
        .order_by(
            TrainerRoutine.active_from.desc(),
            TrainerRoutine.created_at.desc(),
            TrainerRoutine.sort_order.desc(),
        )
        .limit(1)
    )
    if newest is None:
        return None

    base = _delivery_base_key(newest.client_request_id)
    same = [
        TrainerRoutine.trainer_id == trainer_id,
        TrainerRoutine.member_id == member_id,
        TrainerRoutine.status == ROUTINE_APPROVED,
    ]
    if base is not None:
        # `LIKE` 의 와일드카드가 키에 섞여 들면 남의 전송까지 긁는다.
        escaped = base.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
        same.append(
            TrainerRoutine.client_request_id.like(f"{escaped}#%", escape="\\")
        )
    elif newest.schedule_id:
        # 키가 없어도 붙은 PT 가 있으면 그 일정이 곧 이 전송이다.
        same.append(TrainerRoutine.schedule_id == newest.schedule_id)
    else:
        same.extend(
            [
                TrainerRoutine.active_from == newest.active_from,
                TrainerRoutine.delivery_kind == newest.delivery_kind,
                TrainerRoutine.schedule_id.is_(None),
            ]
        )
    rows = db.scalars(
        select(TrainerRoutine)
        .where(*same)
        .order_by(TrainerRoutine.sort_order, TrainerRoutine.id)
    ).all()

    kind = next(
        (r.delivery_kind for r in rows if r.delivery_kind), newest.delivery_kind
    )
    # `delivery_kind` 를 단 줄이 곧 회원이 혼자 할 운동이다. PT 와 함께 간
    # 전송에서는 개인운동 줄이 그 값을 달고 PT 프로그램 줄은 비어 있으며,
    # `개인운동만` 전송은 그 줄 자체가 개인운동이다(#2223).
    personal = [r for r in rows if r.delivery_kind]

    # 일정은 **가장 최근 줄** 이 가리키는 것이다. 묶음의 첫 줄에서 고르면,
    # 키 없는 옛 배정이 한 날에 여럿일 때 엉뚱한 PT 를 가리킨다.
    schedule_id = newest.schedule_id or next(
        (r.schedule_id for r in rows if r.schedule_id), None
    )
    session = db.get(TrainerSchedule, schedule_id) if schedule_id else None
    if session is not None and session.trainer_id != trainer_id:
        session = None

    # 미래 시작일로 보낸 `개인운동만` 은 걸리는 첫날이 보낸 날보다 늦다(#2656).
    sent_on = (
        routine_sent_on(newest)
        if _iso_day_or_none(newest.active_from)
        else None
    )
    return DeliveryOut(
        kind=kind,
        sent_on=sent_on,
        session=_schedule_out(session) if session is not None else None,
        routines=_routine_outs(db, personal),
    )


def unsent_personal_routines(
    db: Session, trainer_id: str, member_id: str
) -> list[RoutineOut]:
    """**끝난 PT 에 남아 있는** 개인운동 — 보낼 수 있는데 아직 안 보낸 것. (#2225)

    프로그램 탭에서도 "보낼 것이 남았다" 를 알리고 거기서 보낼 수 있어야 한다 —
    지금은 그 사실이 스케줄 탭의 그 일정을 열어야만 보인다.

    **예정인 PT 에 붙은 것은 미전송이 아니다.** 그것은 그 PT 를 완료할 때 함께
    나간다(#2224) — `send_scheduled_routines` 도 예정이면 거절한다. 그런 줄까지
    세면 트레이너에게 **누르면 반드시 실패하는 버튼**을 내밀게 된다.

    **PT 프로그램 줄도 뺀다.** 그 줄도 같은 일정에 `scheduled` 로 붙어
    있지만(#2279) `delivery_kind` 가 비어 있다. 개인운동만 그 값을 단다(#2223).
    """
    rows = db.execute(
        select(TrainerRoutine, TrainerSchedule.date)
        .join(TrainerSchedule, TrainerSchedule.id == TrainerRoutine.schedule_id)
        .where(
            TrainerRoutine.trainer_id == trainer_id,
            TrainerRoutine.member_id == member_id,
            TrainerRoutine.status == ROUTINE_SCHEDULED,
            TrainerRoutine.delivery_kind.is_not(None),
            TrainerSchedule.status != SCHEDULE_UPCOMING,
        )
        .order_by(TrainerRoutine.sort_order, TrainerRoutine.id)
    ).all()
    out: list[RoutineOut] = []
    prefetch = _routine_prefetch(db, [row for row, _ in rows])
    for row, schedule_date in rows:
        # 보내는 자리는 스케줄 탭의 그 일정 상세다. 날짜를 함께 줘야 그 주를
        # 열 수 있다 — 일정 id 만으로는 이번 주에서 찾지 못한다. (#2225)
        out.append(
            _routine_out(db, row, prefetch=prefetch).model_copy(
                update={"schedule_date": schedule_date}
            )
        )
    return out


def list_scheduled_routines(
    db: Session, trainer_id: str, schedule_id: str,
) -> list[RoutineOut]:
    """그 PT 일정에 붙어 있는 개인운동 — 보낸 것과 아직 보내지 않은 것. (#2223)

    일정 상세의 `개인운동` 갈래가 이 목록을 그린다(#2224). **보낸 뒤에도
    빠지지 않는다** — 트레이너가 나중에 그 PT 를 열었을 때 "이 회원에게 무엇을
    딸려 보냈나" 를 볼 데가 여기뿐이라, 보내자마자 사라지면 보낸 기록을 어디서도
    확인할 수 없다. 대신 건마다 `pending_send` 로 갈라 놓아 부르는 쪽이 아직
    보낼 것이 남았는지 안다.

    `dismissed`(보내지 않기로 한 것) 는 뺀다 — 트레이너가 이미 아니라고 답한
    것이다.

    **PT 프로그램 줄은 여기 오지 않는다.** 개인운동만 `delivery_kind` 를 달고
    있어(#2223) 그 값으로 가른다.

    담당이 해제됐거나 동의가 철회된 회원의 줄은 남의 일정과 같이 빈 목록이다
    (#3239). 해제하면 일정은 취소되지만 붙은 미전송 줄은 남아, 옛 일정 id 로 읽으면
    그 회원의 지금 목표로 계산한 효과 문구가 나갔다.
    """
    s = _get_owned_session(db, trainer_id, schedule_id)
    if s is None:
        return []
    try:
        _ensure_session_member_linked(db, trainer_id, s)
    except ClientLinkDetached:
        return []
    rows = db.scalars(
        select(TrainerRoutine)
        .where(
            TrainerRoutine.trainer_id == trainer_id,
            TrainerRoutine.schedule_id == schedule_id,
            # 지금 일정의 회원 것만 — 회원을 바꾸기 전에 붙은 줄이 남아 있어도
            # 다른 회원의 운동을 이 일정에 띄우지 않는다(#3232).
            TrainerRoutine.member_id == s.member_id,
            TrainerRoutine.delivery_kind.is_not(None),
            TrainerRoutine.status.in_((ROUTINE_SCHEDULED, ROUTINE_APPROVED)),
        )
        .order_by(TrainerRoutine.sort_order, TrainerRoutine.id)
    ).all()
    # 한 일정의 개인운동은 한 회원의 것이다 — 회원 값은 한 번만 읽는다(#2911).
    return _routine_outs(db, rows)


#: PT 완료로 보낸 개인운동이 회원 목록에 걸려 있는 날 수 — 보낸 날을 1일로 센다.
#:
#: `개인운동만`(#2223) 과 같은 7 일이다. 두 경로가 같은 규칙으로 움직여야 회원이
#: "이번 주에 할 것" 하나만 본다. 끊기는 것이 곧 트레이너에게 "이번 주 것을
#: 보내라" 는 신호다.
PERSONAL_ROUTINE_ACTIVE_DAYS = 7


def _raise_scheduled_program(
    db: Session, trainer_id: str, session: TrainerSchedule
) -> bool:
    """이 PT 에 붙여 둔 프로그램을 회원에게 올린다(커밋 없음). (#2279)

    프로그램 만들기(#1580)로 짠 PT 는 등록 때 배정하지 않고 `scheduled` 로
    붙여만 둔다. 여기서 `approved` 로 올리며 **오늘부터** 건다 — 며칠 전에 짜
    둔 것이라도 회원에게는 오늘 받은 운동이다.

    올린 것이 있으면 참. 붙은 줄이 없으면 거짓이고, 부르는 쪽이 예전처럼 새로
    배정한다.
    """
    rows = db.scalars(
        select(TrainerRoutine)
        .where(
            TrainerRoutine.trainer_id == trainer_id,
            TrainerRoutine.schedule_id == session.id,
            # 프로그램 줄만 — 개인운동은 `delivery_kind` 를 달고 있다(#2223).
            TrainerRoutine.delivery_kind.is_(None),
            TrainerRoutine.status == ROUTINE_SCHEDULED,
        )
        .order_by(TrainerRoutine.sort_order, TrainerRoutine.id)
    ).all()
    if not rows:
        return False
    today_iso = clock.today_iso()
    for row in rows:
        row.status = ROUTINE_APPROVED
        row.active_from = today_iso
        # PT 프로그램은 "오늘 PT 에서 한 것" 이다 — 매일 체크하는 개인운동 목록에
        # 걸지 않는다(#3115). 그날 내용은 PT 기록이 남긴다. 예전에는 `ended_on`
        # 이 비어 철회 전까지 날마다 `추천 개인운동` 에 떠, 조언·미수행 신호·리포트
        # 분모가 개인운동으로 세었다. `ended_on == active_from` 은 하루도 걸리지
        # 않았다는 표시다([_retire_personal_routines] 와 같은 규칙).
        row.ended_on = today_iso
    db.flush()
    # 바로 배정([assign_program])과 같은 틀이다 — 문장이 코드에 박혀 있으면
    # 영어 화면에서도 한국어로 보인다(#2546). 여러 세션이면 프로그램 이름으로 부른다.
    program_name = rows[0].program_name
    notification_service.queue(
        db,
        member_id=session.member_id,
        kind=notification_service.EXERCISE,
        category=notification_service.MEMBER_ROUTINE,
        template=notification_templates.MEMBER_ROUTINE_PROGRAM,
        template_args=_program_notification_args(
            program_name or rows[0].name,
            sessions=len(rows),
            seconds=sum(_program_row_seconds(row) for row in rows),
            multi=bool(program_name),
        ),
    )
    return True


def _send_scheduled_routines(
    db: Session,
    trainer_id: str,
    session: TrainerSchedule,
    *,
    delivery_kind: str,
) -> list[TrainerRoutine]:
    """그 PT 에 붙여 둔 개인운동을 회원에게 보낸다(커밋 없음). (#2224)

    붙일 때는 `scheduled` 로 두어 회원에게 보이지 않았다(#2223). 여기서
    `approved` 로 올리며 **오늘부터** 다시 건다 — 며칠 전에 짜 둔 것이라도
    회원에게는 오늘 받은 운동이다. 그대로 두면 `active_from` 이 짠 날이라
    이미 며칠 지나간 채로 걸린다.

    보낸 것이 없으면 빈 목록이다 — 부르는 쪽이 판단한다.
    """
    rows = db.scalars(
        select(TrainerRoutine)
        .where(
            TrainerRoutine.trainer_id == trainer_id,
            TrainerRoutine.schedule_id == session.id,
            # 개인운동만 — PT 프로그램 줄도 같은 일정에 `scheduled` 로 붙어
            # 있지만(#2279) 그쪽은 `delivery_kind` 가 비어 있다.
            TrainerRoutine.delivery_kind.is_not(None),
            TrainerRoutine.status == ROUTINE_SCHEDULED,
        )
        .order_by(TrainerRoutine.sort_order, TrainerRoutine.id)
    ).all()
    if not rows:
        return []
    today = clock.today()
    _retire_personal_routines(db, trainer_id, session.member_id or "", today=today)
    ended_on = (
        today + timedelta(days=PERSONAL_ROUTINE_ACTIVE_DAYS)
    ).isoformat()
    for row in rows:
        row.status = ROUTINE_APPROVED
        row.delivery_kind = delivery_kind
        row.active_from = today.isoformat()
        row.ended_on = ended_on
        row.exercise_date = today.isoformat()
    db.flush()
    # 프로그램 화면의 `개인운동만` 전송과 같은 틀이다 — 문장이 코드에 박혀
    # 있으면 영어 화면에서도 한국어로 보인다(#2546, #3107).
    notification_service.queue(
        db,
        member_id=session.member_id,
        kind=notification_service.EXERCISE,
        category=notification_service.MEMBER_ROUTINE,
        template=notification_templates.MEMBER_ROUTINE_PROGRAM,
        template_args=_program_notification_args(
            rows[0].name,
            sessions=len(rows),
            seconds=sum(_personal_row_seconds(row) for row in rows),
            multi=len(rows) > 1,
            routine_only=True,
        ),
    )
    return rows


def send_scheduled_routines(
    db: Session,
    trainer_id: str,
    session_id: str,
    *,
    items: Sequence[PersonalRoutineItem] | None = None,
) -> list[RoutineOut] | None:
    """마무리된 PT 에 남아 있던 개인운동을 회원에게 보낸다. (#2224)

    PT 가 취소·노쇼로 끝나면 붙여 둔 개인운동은 갈 곳을 잃는다. 자동으로
    보내지는 않는다 — 아파서 쉬는 회원에게 운동이 저절로 가면 안 된다.
    트레이너가 `개인운동 미전송` 에서 눌렀을 때만 온다.

    [items] 를 주면 그 내용으로 **고쳐서** 보낸다. 개인운동은 "이 PT 다음에
    할 것" 으로 짜였으므로, PT 가 열리지 않았으면 그대로 보내기 어렵다.
    취소된 PT 에는 프로그램 만들기로 다시 붙일 수 없어(`예정` 세션만 찾는다)
    고치는 자리가 여기뿐이다.

    - 소유 슬롯 아님 → None(404).
    - 아직 `예정` → ScheduleError. 완료를 누르면 그때 함께 나간다.
    - 보낼 것이 없음 → ScheduleError.
    """
    s = _get_owned_session(db, trainer_id, session_id)
    if s is None:
        return None
    _ensure_session_member_linked(db, trainer_id, s)
    if s.status == SCHEDULE_UPCOMING:
        raise ScheduleError(
            "아직 예정인 PT 입니다. 완료할 때 개인운동이 함께 나갑니다."
        )
    if not s.member_id:
        raise ScheduleError("회원이 없는 일정입니다.")
    rows = db.scalars(
        select(TrainerRoutine)
        .where(
            TrainerRoutine.trainer_id == trainer_id,
            TrainerRoutine.schedule_id == session_id,
            # 개인운동만 — PT 프로그램 줄도 같은 일정에 붙어 있다(#2279).
            TrainerRoutine.delivery_kind.is_not(None),
            TrainerRoutine.status == ROUTINE_SCHEDULED,
        )
        .order_by(TrainerRoutine.sort_order, TrainerRoutine.id)
    ).all()
    if not rows:
        raise ScheduleError("보낼 개인운동이 없습니다.")
    if items is not None:
        if not items:
            raise ScheduleError("보낼 개인운동이 없습니다.")
        _rewrite_scheduled_routines(db, rows, items)
        rows = db.scalars(
            select(TrainerRoutine)
            .where(
                TrainerRoutine.trainer_id == trainer_id,
                TrainerRoutine.schedule_id == session_id,
                # 개인운동만 — PT 프로그램 줄도 같은 일정에 붙어 있다(#2279).
                TrainerRoutine.delivery_kind.is_not(None),
                TrainerRoutine.status == ROUTINE_SCHEDULED,
            )
            .order_by(TrainerRoutine.sort_order, TrainerRoutine.id)
        ).all()
    kind = (
        DELIVERY_CANCELLED_ROUTINE_ONLY
        if s.status in {SCHEDULE_CANCELLED, SCHEDULE_NO_SHOW}
        else DELIVERY_PT_WITH_ROUTINE
    )
    sent = _send_scheduled_routines(db, trainer_id, s, delivery_kind=kind)
    if s.member_id:
        post_routine_delivery(  # 채팅 안내(#2672)
            db, trainer_id, s.member_id,
            kind=kind, routine_names=[row.name for row in sent],
        )
    db.commit()
    return _routine_outs(db, sent)


def _rewrite_scheduled_routines(
    db: Session,
    rows: Sequence[TrainerRoutine],
    items: Sequence[PersonalRoutineItem],
) -> None:
    """붙어 있던 개인운동을 [items] 로 갈아 끼운다(커밋 없음). (#2224)

    있던 줄을 앞에서부터 고쳐 쓰고, 모자라면 만들고, 남으면 지운다 — 줄을
    전부 지우고 새로 만들면 `client_request_id` 의 멱등 키가 끊겨 재시도가
    같은 운동을 두 번 만든다.

    **손댄 줄은 트레이너 것이 된다.** AI 가 제안한 운동이라도 트레이너가
    고치는 순간 더는 AI 의 추천이 아니다 — 그대로 두면 트레이너가 손본 운동을
    회원이 `AI 추천` 으로 본다. 프로그램 만들기가 이미 같은 규칙으로 움직인다
    (#2223). 여기서도 **서버가** 판단한다: 클라이언트가 보낸 `source` 를 그대로
    믿으면 길마다 규칙이 갈린다.

    세트·횟수·중량·초는 처음 붙일 때([_add_scheduled_routines])와 같은 규칙으로
    근력에만 남긴다(#3232). 고칠 때만 규칙이 빠지면 유산소로 바꾼 운동이 옛 세트를
    들고 회원에게 간다.
    """
    base = rows[0]
    for index, item in enumerate(items):
        if index < len(rows):
            row = rows[index]
        else:
            row = TrainerRoutine(
                id=f"routine-{uuid.uuid4().hex[:12]}",
                trainer_id=base.trainer_id,
                member_id=base.member_id,
                schedule_id=base.schedule_id,
                exercise_date=base.exercise_date,
                status=ROUTINE_SCHEDULED,
                delivery_kind=base.delivery_kind,
                source="trainer",
                # 키 없이 붙인 줄(일정 상세에서 처음 붙인 것, #2280)이면 새 줄도
                # 키를 두지 않는다(#3232). `None` 을 글자로 이어 붙이면 같은
                # 회원의 다른 PT 에서도 `None#routine1` 이 나와 유니크 제약에 걸린다.
                client_request_id=(
                    _personal_request_key(base.client_request_id, index)
                    if base.client_request_id
                    else None
                ),
                created_at=datetime.now(timezone.utc),
            )
            db.add(row)
        strength = item.type == "근력"
        sets = item.sets if strength else None
        reps = item.reps if strength and item.hold_seconds is None else None
        hold_seconds = item.hold_seconds if strength else None
        weight = (
            round(item.weight, 1)
            if item.weight is not None and strength
            else None
        )
        touched = (
            row.name != item.name
            or row.minutes != item.minutes
            or row.duration_seconds != item.duration_seconds
            or row.type != item.type
            or row.intensity != item.intensity
            or row.sets != sets
            or row.reps != reps
            or row.hold_seconds != hold_seconds
            or row.weight != weight
        )
        row.name = item.name
        row.minutes = item.minutes
        row.duration_seconds = item.duration_seconds
        row.type = item.type
        row.intensity = item.intensity
        row.sets = sets
        row.reps = reps
        row.hold_seconds = hold_seconds
        row.weight = weight
        # 사유·효과만 고친 것은 운동을 바꾼 것이 아니라 출처를 건드리지 않는다(#2570).
        row.reason = item.reason
        row.effect = item.effect.strip()
        row.source = "trainer" if touched else item.source
        row.sort_order = base.sort_order + index
    for row in rows[len(items):]:
        db.delete(row)
    db.flush()


def update_scheduled_routines(
    db: Session,
    trainer_id: str,
    session_id: str,
    items: Sequence[PersonalRoutineItem],
    suggestion_ids: Sequence[str] = (),
) -> list[RoutineOut] | None:
    """그 PT 에 붙은 개인운동을 고친다 — 보내지는 않는다. (#2224)

    일정 상세에서 바로 고치는 길이다. 프로그램 만들기로 돌아가지 않고 운동
    하나를 빼거나 시간을 줄일 수 있어야 한다 — PT 직전에 회원 상태를 보고
    손보는 일이 흔하다.

    붙은 것이 하나도 없으면 **처음 붙인다**(#2280). `직접 만들기`·저장한
    프로그램 적용으로 짠 PT 는 개인운동 단계를 지나지 않는다. 일정 상세에서
    코칭 탭의 개인운동 단계(AI 제안)로 가 짠 것을 여기로 붙인다 — 프로그램
    만들기(`일정 추가`)와 같이 출처는 받은 그대로 남긴다: AI 제안을 손대지
    않고 붙였으면 `ai` 다.

    이미 보낸 것은 손댈 수 없다(`scheduled` 만 고친다). 보낸 뒤에 바뀌면
    회원이 어제 본 목록과 오늘 본 목록이 말없이 달라진다.

    - 소유 슬롯 아님 → None(404).
    - 빈 목록으로 비우려 함 → ScheduleError.
    - 처음 붙이는데 붙일 수 없는 PT → ScheduleError(`_ensure_routine_attachable`).
    - 담당이 해제됐거나 동의가 철회된 회원의 일정 → ClientLinkDetached(404).

    [suggestion_ids] 는 이 개인운동을 채운 대기 중 AI 제안이다(#2747) —
    프로그램 만들기와 같이 같은 트랜잭션에서 `consumed` 로 닫는다. 실패하면
    (404·400) 제안은 대기로 남는다.
    """
    s = _get_owned_session(db, trainer_id, session_id)
    if s is None:
        return None
    # 붙은 줄을 고치는 길도 처음 붙이는 길과 같은 담당·동의 경계를 본다(#3239).
    _ensure_session_member_linked(db, trainer_id, s)
    if not items:
        raise ScheduleError("개인운동을 최소 한 개는 남겨 주세요.")
    rows = db.scalars(
        select(TrainerRoutine)
        .where(
            TrainerRoutine.trainer_id == trainer_id,
            TrainerRoutine.schedule_id == session_id,
            # 목록([list_scheduled_routines])과 같이 지금 일정의 회원 것만 고친다.
            TrainerRoutine.member_id == s.member_id,
            # 개인운동만 — PT 프로그램 줄도 같은 일정에 붙어 있다(#2279).
            TrainerRoutine.delivery_kind.is_not(None),
            TrainerRoutine.status == ROUTINE_SCHEDULED,
        )
        .order_by(TrainerRoutine.sort_order, TrainerRoutine.id)
    ).all()
    if not rows:
        _ensure_routine_attachable(db, trainer_id, s)
        _add_scheduled_routines(
            db, trainer_id, s.member_id,
            items=items,
            schedule_id=s.id,
            # 프로그램 만들기와 같다 — 개인운동은 그 PT 가 있는 날의 것이다.
            exercise_date=s.date,
            client_request_id=None,
        )
        _consume_routine_suggestions(db, trainer_id, s.member_id, suggestion_ids)
        db.commit()
        return list_scheduled_routines(db, trainer_id, session_id)
    _rewrite_scheduled_routines(db, rows, items)
    if s.member_id:
        _consume_routine_suggestions(db, trainer_id, s.member_id, suggestion_ids)
    db.commit()
    return list_scheduled_routines(db, trainer_id, session_id)


def _ensure_routine_attachable(
    db: Session, trainer_id: str, s: TrainerSchedule
) -> None:
    """개인운동이 없는 PT 에 처음 붙여도 되는가. 아니면 ScheduleError. (#2280)

    붙인 개인운동은 PT 프로그램과 함께 완료 전송으로 나간다. 그래서 그 전송을
    아직 기다리는 PT 에만 붙인다.

    - 회원이 없는 일정(상담·공백): 받을 사람이 없다.
    - 프로그램이 없는 일정: 나중에 프로그램 만들기로 PT 를 실으면 그때 붙은
      줄을 갈아 끼우므로(`_clear_scheduled_routines`) 여기서 붙인 것이 사라진다.
    - 이미 보낸 PT: 보낸 뒤에 바뀌면 회원이 본 목록이 말없이 달라진다.
    - 취소·노쇼: 열리지 않은 PT 다음에 할 운동을 새로 짜는 자리가 아니다.
    """
    if not s.member_id:
        raise ScheduleError("회원이 연결되지 않은 일정입니다.")
    _ensure_session_member_linked(db, trainer_id, s)
    if not _program_items(s.program_json):
        raise ScheduleError("PT 프로그램이 없는 일정입니다.")
    if s.program_sent_at is not None:
        raise ScheduleError("이미 보낸 PT에는 개인운동을 붙일 수 없습니다.")
    if s.status in {SCHEDULE_CANCELLED, SCHEDULE_NO_SHOW}:
        raise ScheduleError("취소된 PT에는 개인운동을 붙일 수 없습니다.")


def dismiss_scheduled_routines(
    db: Session, trainer_id: str, session_id: str
) -> bool | None:
    """마무리된 PT 의 개인운동을 보내지 않기로 정리한다. (#2224)

    `개인운동 미전송` 표시를 걷어내는 길이다. 보내지 않기로 한 것을 계속
    띄워 두면 트레이너가 매번 다시 판단해야 한다.

    지우지 않고 `dismissed` 로 내린다 — 무엇을 짰다가 안 보냈는지가 남는다.
    """
    s = _get_owned_session(db, trainer_id, session_id)
    if s is None:
        return None
    if s.status == SCHEDULE_UPCOMING:
        raise ScheduleError("아직 예정인 PT 입니다.")
    changed = db.execute(
        update(TrainerRoutine)
        .where(
            TrainerRoutine.trainer_id == trainer_id,
            TrainerRoutine.schedule_id == session_id,
            # 개인운동만 — PT 프로그램 줄도 같은 일정에 붙어 있다(#2279).
            TrainerRoutine.delivery_kind.is_not(None),
            TrainerRoutine.status == ROUTINE_SCHEDULED,
        )
        .values(status=ROUTINE_DISMISSED)
    ).rowcount
    db.commit()
    return changed > 0


def _replayed_program_schedule(
    db: Session, trainer_id: str, member_id: str, *,
    client_request_id: str,
    routines: Sequence[TrainerRoutine],
    date: str,
    program_json: str,
) -> ProgramScheduleOut:  # noqa: D401
    """같은 멱등키로 이미 끝난 `일정 추가` 의 결과를 다시 만든다. (#1580)

    배정과 일정은 한 트랜잭션이라, 루틴이 있으면 일정도 이미 반영돼 있다. 새로
    만든 일정은 멱등키로 찾고, 기존 일정에 붙인 경우는 그 날짜에서 같은 구성을
    가진 일정으로 찾는다. 그 사이 트레이너가 일정을 고쳐 둘 다 없으면 무엇을
    돌려줘야 할지 알 수 없으므로 충돌로 알린다 — 다시 만들면 중복이 된다.
    """
    created = db.scalar(
        select(TrainerSchedule).where(
            TrainerSchedule.trainer_id == trainer_id,
            TrainerSchedule.client_request_id == _schedule_request_key(client_request_id),
        )
    )
    attached: TrainerSchedule | None = None
    if created is None:
        attached = db.scalar(
            select(TrainerSchedule)
            .where(
                TrainerSchedule.trainer_id == trainer_id,
                TrainerSchedule.member_id == member_id,
                TrainerSchedule.date == date,
                TrainerSchedule.program_json == program_json,
            )
            .order_by(TrainerSchedule.time, TrainerSchedule.id)
            .limit(1)
        )
    session = created or attached
    if session is None:
        raise IdempotencyConflict(
            "이미 처리된 요청입니다. 일정을 확인한 뒤 새로 추가해 주세요."
        )
    return ProgramScheduleOut(
        routines=[_routine_out(db, rt) for rt in routines],
        session=_schedule_out(session),
        attached_to_existing=created is None,
        # 개인운동도 같은 트랜잭션에서 저장됐으므로 같은 키로 찾아 함께 돌려준다
        # — 재시도가 개인운동만 빠진 결과를 받으면 화면이 "안 붙었다"고 읽는다.
        personal_routines=[
            _routine_out(db, rt)
            for rt in _scheduled_routines_for_request(
                db, trainer_id, member_id, client_request_id
            )
        ],
    )


def assign_program_with_schedule(
    db: Session,
    trainer_id: str,
    member_id: str,
    *,
    name: str,
    sessions: Sequence[ProgramDraftSession],
    date: str,
    time: str,
    duration_minutes: int,
    client_name: str,
    client_request_id: str | None = None,
    session_id: str | None = None,
    personal_routines: Sequence[PersonalRoutineItem] = (),
    suggestion_ids: Sequence[str] = (),
) -> ProgramScheduleOut | None:
    """프로그램을 회원에게 배정하고 PT 일정에 올린다 — 둘 다 되거나 둘 다 안 된다. (#1580)

    담당 링크 행을 잠가 한 트레이너·회원 쌍의 명령을 줄 세운다. 동시에 들어온
    두 요청이 같은 빈 일정을 보고 각자 일정을 만들지 못하고, 같은 멱등키의 재시도는
    앞 요청이 커밋한 루틴을 보고 결과만 돌려받는다.

    연결 대상은 고른 시간대와 겹치는 그날 예정 세션이다(#1581). 없으면 고른
    시간으로 새 일정을 만들고, 하나면 거기에 붙이며(고른 시간은 쓰지 않는다),
    여럿이면 [session_id] 로 고른 것에만 붙인다 — 고르지 않았거나 고른 것이
    후보가 아니면 [AttachTargetConflict]. 담당 고객이 아니면 None.

    [personal_routines] 는 이 PT 사이에 회원이 혼자 할 개인운동이다(#2223).
    같은 트랜잭션에서 그 일정에 붙여 두기만 하고 회원에게는 보내지 않는다 —
    보내는 것은 PT 완료 때다(#2224). 일정이 정해진 뒤에 넣어야 붙일 id 가
    있으므로 프로그램 루틴보다 나중에 만든다.

    [suggestion_ids] 는 그 개인운동을 채운 대기 중 AI 제안이다(#2747). 같은
    트랜잭션에서 닫는다 — 등록이 실패하면 제안도 대기로 남는다.
    """
    client_link = db.scalar(
        select(TrainerClient)
        .where(
            TrainerClient.trainer_id == trainer_id,
            TrainerClient.member_id == member_id,
        )
        .with_for_update()
    )
    # 해제된 담당(`active=False`)도 없는 담당과 같다 — 배정과 일정 모두 막는다. (#2281)
    # 동의가 철회된 채 살아 있는 링크도 `_require_client` 와 같이 막는다. (#1631)
    if (
        client_link is None
        or not client_link.active
        or data_consent_service.blocks_access(client_link)
    ):
        return None

    program_json = _dump_program(_schedule_program_items(sessions))
    if client_request_id:
        replayed = _program_routines_for_request(
            db, trainer_id, member_id, client_request_id, len(sessions)
        )
        if replayed:
            return _replayed_program_schedule(
                db, trainer_id, member_id,
                client_request_id=client_request_id,
                routines=replayed,
                date=date,
                program_json=program_json,
            )

    candidates = _overlapping_planned_sessions(
        db, trainer_id, member_id,
        date=date, time=time, duration_minutes=duration_minutes,
    )
    target: TrainerSchedule | None
    if session_id is not None:
        target = next((s for s in candidates if s.id == session_id), None)
        if target is None:
            raise AttachTargetConflict(
                "고른 PT 일정이 더는 이 시간대의 예정 PT가 아닙니다. 다시 확인해 주세요.",
                candidates,
            )
    elif len(candidates) > 1:
        raise AttachTargetConflict(
            "고른 시간대와 겹치는 PT 일정이 여러 개입니다. 연결할 회차를 골라 주세요.",
            candidates,
        )
    else:
        target = candidates[0] if candidates else None
    if target is None:
        # 새 일정을 만드는 경우만 본다 — 같은 회원의 겹치는 예정 세션이 있으면
        # 위에서 거기에 붙였다. 다른 회원의 PT 와 겹치는 시간에 새로 잡히면
        # 이중 예약이다. 루틴을 넣기 전에 확인해 반쪽 배정이 남지 않게 한다. (#2284)
        ensure_no_overlap(
            db, trainer_id, date=date, time=time, duration_minutes=duration_minutes
        )
    if target is None:
        session = _add_session(
            db,
            trainer_id,
            date=date,
            time=time,
            client_name=client_name,
            member_id=member_id,
            type_="1:1 PT",
            duration_minutes=duration_minutes,
            note="",
            program_json=program_json,
            client_request_id=(
                _schedule_request_key(client_request_id) if client_request_id else None
            ),
        )
    else:
        target.program_json = program_json
        session = target
    # 이 PT 에 이미 붙어 있던(아직 보내지 않은) 프로그램·개인운동은 걷어낸다.
    # 프로그램을 다시 짜서 보내면 `program_json` 은 덮어쓰는데 붙은 줄만 뒤에
    # 쌓여, 두 번 짠 트레이너가 두 배를 보내게 된다 — 트레이너는 바꾼 것으로
    # 아는데 회원은 더해진 것을 받는다. 아직 보내지 않은 것이라 지워도 회원이
    # 본 것은 없다.
    #
    # 개인운동 없이 붙이면 붙어 있던 개인운동은 그대로 둔다(#2280) — 바꿀 것이
    # 없으니 지울 까닭도 없다. 새로 짠 개인운동으로 바꾸는 것은 트레이너 웹이
    # 한 번 묻고 보낸다.
    _clear_scheduled_routines(
        db, trainer_id, session.id, keep_personal=not personal_routines
    )
    # 프로그램은 **회원에게 보내지 않고 이 PT 에 붙여만 둔다**(#2279). 예전에는
    # 여기서 바로 배정해, 등록만 해도 회원 목록에 떴고 PT 를 마치고 보낼 때
    # 한 벌이 더 생겼다 — 회원은 같은 운동을 두 번 해야 하는 것으로 봤다.
    # 개인운동과 같은 자리에서, 같은 규칙으로 나간다(#2224).
    routines = _add_program_routines(
        db, trainer_id, member_id,
        name=name, sessions=sessions, client_request_id=client_request_id,
        status=ROUTINE_SCHEDULED,
        schedule_id=session.id,
        notify=False,
    )
    personal = _add_scheduled_routines(
        db, trainer_id, member_id,
        items=personal_routines,
        schedule_id=session.id,
        # 개인운동은 그 PT 가 있는 날의 것이다 — 일정에 붙였는데 날짜가 다르면
        # 회원 화면에서 둘이 따로 떨어진다.
        exercise_date=session.date,
        client_request_id=client_request_id,
    )
    _consume_routine_suggestions(db, trainer_id, member_id, suggestion_ids)
    db.commit()
    for rt in routines:
        db.refresh(rt)
    for rt in personal:
        db.refresh(rt)
    db.refresh(session)
    return ProgramScheduleOut(
        routines=[_routine_out(db, rt) for rt in routines],
        session=_schedule_out(session),
        attached_to_existing=target is not None,
        personal_routines=[_routine_out(db, rt) for rt in personal],
    )


def _member_visible_slot(s: TrainerSchedule) -> tuple[str, str, str, int]:
    """회원이 약속을 지키려고 아는 값들. 이 넷 중 하나라도 달라지면 알린다.

    메모(`note`)·프로그램은 트레이너의 준비물이라 빠져 있다 — 그것까지 알리면
    알림함이 같은 일정으로 차고, 정작 시각이 바뀐 알림이 묻힌다. (#664)
    """
    return (s.date, s.time, s.type, s.duration_minutes)


def _slot_args(slot: tuple[str, str, str, int]) -> dict[str, str]:
    """일정 알림 틀의 인자 — 본문 `날짜 시각 · 종류` 를 이룬다(#2302)."""
    date, time, type_, _ = slot
    return {"date": date, "time": time, "type": type_}


def _notify_schedule_changed(
    db: Session,
    *,
    session: TrainerSchedule,
    before_member_id: str | None,
    before_slot: tuple[str, str, str, int],
) -> None:
    """바뀐 일정을 회원에게 알린다. **커밋하지 않는다.**

    등록만 알리고 변경·취소를 알리지 않으면, 회원은 "새 일정이 등록되었어요" 를
    믿고 이미 옮겨진 시간에 나간다. 취소 알림이 등록 알림보다 중요하다. (#664)
    """
    after_slot = _member_visible_slot(session)

    if before_member_id == session.member_id:
        if session.member_id is None or before_slot == after_slot:
            return
        notification_service.queue(
            db,
            member_id=session.member_id,
            kind=notification_service.PT_LINK_NOTICE,
            category=notification_service.MEMBER_SCHEDULE,
            template=notification_templates.MEMBER_SCHEDULE_CHANGED,
            template_args=_slot_args(after_slot),
        )
        return

    # 다른 회원에게 넘긴 일정. 넘겨받은 쪽만 알리면 원래 회원은 약속이 사라진
    # 줄 모른 채 그 시간에 나간다 — 양쪽 모두 알린다.
    if before_member_id is not None:
        notification_service.queue(
            db,
            member_id=before_member_id,
            kind=notification_service.PT_LINK_NOTICE,
            category=notification_service.MEMBER_SCHEDULE,
            template=notification_templates.MEMBER_SCHEDULE_CANCELLED,
            template_args=_slot_args(before_slot),
        )
    if session.member_id is not None:
        notification_service.queue(
            db,
            member_id=session.member_id,
            kind=notification_service.PT_LINK_NOTICE,
            category=notification_service.MEMBER_SCHEDULE,
            template=notification_templates.MEMBER_SCHEDULE_ADDED,
            template_args=_slot_args(after_slot),
        )


def _notify_pt_done(
    db: Session,
    *,
    session: TrainerSchedule,
    trainer_id: str,
    note: str,
    feedback_only: bool,
) -> None:
    """마친 PT 를 회원에게 알린다. **커밋하지 않는다.** (#3027)

    완료 처리는 회원 운동 기록에 PT 를 적재하고 피드백을 운동 탭 PT 카드에 띄우지만,
    알림이 없어 회원이 운동 탭을 열기 전에는 기록도 트레이너의 말도 몰랐다. 수업
    직후가 피드백을 실천할 가장 좋은 때다.

    [feedback_only] 는 완료 뒤 처음 피드백을 적은 경우다 — 완료 알림은 이미 갔다.
    상담 일정·회원 없는 슬롯은 부르는 쪽이 거른다. 회차는 회원 앱 PT 카드와 같은
    번호(`_common._done_pt_numbers`)다.
    """
    if session.member_id is None or session.type == "상담":
        return
    trainer_name = (
        db.scalar(select(User.name).where(User.id == trainer_id)) or ""
    ).strip()
    text = (note or "").strip()
    if feedback_only:
        notification_service.queue(
            db,
            member_id=session.member_id,
            kind=notification_service.EXERCISE,
            category=notification_service.MEMBER_PT_DONE,
            template=notification_templates.MEMBER_PT_FEEDBACK,
            template_args={"trainer_name": trainer_name, "date": session.date},
            body=text,
        )
        return
    number = _done_pt_numbers(db, session.member_id, trainer_id).get(session.id)
    notification_service.queue(
        db,
        member_id=session.member_id,
        kind=notification_service.EXERCISE,
        category=notification_service.MEMBER_PT_DONE,
        template=notification_templates.MEMBER_PT_COMPLETED,
        template_args={
            "trainer_name": trainer_name,
            "session_number": number,
            "has_note": bool(text),
            "date": session.date,
        },
        body=text,
    )


#: 완료·취소·노쇼로 마무리된 세션에서도 고칠 수 있는 필드(#2754). 둘 다 그
#: 약속(시각·회원·종류·길이)을 바꾸지 않는다. 프로그램은 아직 보내지 않았을 때만.
_TERMINAL_EDITABLE_FIELDS = frozenset({"program", "note"})


def update_session(
    db: Session, trainer_id: str, session_id: str, fields: dict
) -> ScheduleSessionOut | None:
    """예약 부분 수정. 소유 슬롯이 아니면 None(라우터 404).

    완료된 세션은 이미 회원 운동기록(RoutineHistory)으로 적재됐다. 이후 시각·
    member_id·종류·길이를 바꾸면 스케줄과 기록이 어긋나므로(리뷰 재-#2) 409 로
    거부한다. 메모와 아직 보내지 않은 프로그램은 마무리된 세션에서도 고칠 수
    있다(#2754). 이미 보낸 프로그램을 바꾸는 요청은 409 다(#1247).
    """
    s = _get_owned_session(db, trainer_id, session_id)
    if s is None:
        return None
    _ensure_session_member_linked(db, trainer_id, s)
    # 회원에게 알릴지 판단하려면 **바꾸기 전** 값을 들고 있어야 한다. 넘긴
    # 일정의 취소 알림에는 옛 시각을 써야 회원이 어느 약속인지 안다.
    before_member_id = s.member_id
    before_slot = _member_visible_slot(s)
    before_program_json = s.program_json
    # 완료 PT 에 피드백이 처음 생기는지(#3027)·파생 기록을 다시 맞출지(#3093) 보려면
    # 바꾸기 전 메모가 필요하다.
    before_note = s.note
    # A reservation owns the booking coordinates and lifecycle, so changing
    # its time/member/type/duration through the general schedule API would
    # desynchronise the slot and remaining count. The trainer may still add
    # the PT plan and memo: those fields do not alter the reservation.
    if _is_reservation_schedule(db, session_id) and not set(fields).issubset(
        {"program", "note"}
    ):
        raise ScheduleConflict(
            "예약으로 생성된 일정은 일반 일정 화면에서 수정할 수 없습니다."
        )
    if s.status in SCHEDULE_TERMINAL and not set(fields).issubset(
        _TERMINAL_EDITABLE_FIELDS
    ):
        # 취소·노쇼도 "그때 무슨 일이 있었나" 를 남긴 기록이라 나중에 시간·회원을
        # 고쳐 쓰면 그 기록이 가리키는 약속이 달라진다(완료 세션과 같은 이유).
        # 메모·아직 보내지 않은 프로그램은 그 약속을 바꾸지 않아 연다 — 수업이
        # 끝난 뒤 기록을 남기는 것이 가장 자연스러운 흐름이다(#2754).
        raise ScheduleConflict(
            "완료·취소·노쇼로 마무리된 PT는 메모·프로그램만 수정할 수 있습니다."
        )
    if (
        "program" in fields
        and fields["program"] is not None
        and s.program_sent_at is not None
        and _program_items(_dump_program(fields["program"]))
        != _program_items(s.program_json)
    ):
        # 회원이 이미 받은 프로그램을 말없이 바꾸지 않는다(#1247). 메모만 고치며
        # 같은 프로그램을 함께 실어 보낸 요청은 막지 않는다.
        raise ScheduleConflict("이미 보낸 프로그램은 수정할 수 없습니다.")
    if {"date", "time", "duration_minutes"} & set(fields):
        # 바꾼 뒤의 시간이 다른 일정과 겹치는지 **바꾸기 전에** 본다. 자기 자신은
        # 빼고 본다 — 길이만 늘려도 원래 자리와 겹친다고 거절하면 안 된다. (#2284)
        ensure_no_overlap(
            db,
            trainer_id,
            date=fields.get("date", s.date),
            time=fields.get("time", s.time),
            duration_minutes=fields.get("duration_minutes", s.duration_minutes),
            exclude_ids=(s.id,),
        )
    # 상담 일정을 다른 시각으로 옮기면 신청 때 잠근 옛 자리를 놓아 준다(#2758).
    # 회원 앱은 이제 일정의 시각을 읽는다.
    if s.consultation_id is not None and (
        fields.get("date", s.date) != s.date or fields.get("time", s.time) != s.time
    ):
        from app.services import consultation_service

        consultation_service.release_slot_for_moved_schedule(db, s.consultation_id)
    if "date" in fields:
        s.date = fields["date"]
        # 붙어 있는 개인운동도 새 날짜로 따라간다(#2224). 아직 보내지 않은
        # 것이라 묻지도 보내지도 않는다 — 옮긴 PT 를 완료할 때 그날 기준으로
        # 나간다. 두고 가면 옛 날짜를 가리킨 채 남는다.
        db.execute(
            update(TrainerRoutine)
            .where(
                TrainerRoutine.schedule_id == s.id,
                TrainerRoutine.status == ROUTINE_SCHEDULED,
            )
            .values(exercise_date=fields["date"])
        )
    if "time" in fields:
        s.time = fields["time"]
    if "client_name" in fields:
        s.client_name = fields["client_name"]
    if "member_id" in fields:
        # 빈 문자열은 '배정 해제'로 해석 → NULL 로 저장(""는 users.id FK 위반이라 500 유발).
        s.member_id = fields["member_id"] or None
        if s.member_id != before_member_id:
            # 붙어 있던 아직 보내지 않은 줄은 이전 회원의 것이다(#3232). 두면 완료
            # 전송이 이전 회원의 줄을 올리면서 알림·개인운동 정리는 새 회원에게
            # 간다. 개인운동은 이전 회원의 목표·상태로 짠 것이라 새 회원에게 옮기지
            # 않고 걷는다. 프로그램은 일정에 그대로 남아, 전송 때 새 회원에게
            # 새로 배정된다(`send_session_program`).
            _clear_scheduled_routines(db, trainer_id, s.id)
    if "type" in fields:
        s.type = fields["type"]
    if "duration_minutes" in fields:
        s.duration_minutes = fields["duration_minutes"]
    if "note" in fields:
        s.note = fields["note"]
    if "program" in fields and fields["program"] is not None:
        s.program_json = _dump_program(fields["program"])
    # 완료 세션의 프로그램·메모를 고치면 완료가 만든 파생 기록도 같은 저장에서
    # 따라간다(#3093). 그대로 두면 회원 운동 탭·주간 집계·트레이너 이력·코치
    # 근거가 완료 시점 값에 머문다 — 회원은 그 기록을 고칠 수 없다.
    program_changed = s.program_json != before_program_json
    note_changed = s.note != before_note
    refresh_derived = False
    if s.status == SCHEDULE_DONE and (program_changed or note_changed):
        refresh_derived = _sync_completed_records(
            db,
            s,
            trainer_id,
            note=s.note if note_changed else None,
            exercise=program_changed,
        )
    _notify_schedule_changed(
        db,
        session=s,
        before_member_id=before_member_id,
        before_slot=before_slot,
    )
    # 수업이 끝난 뒤 피드백을 적는 흐름(#2754)도 회원에게 알린다(#3027). **비어 있다가
    # 처음 채워질 때만** — 이미 있던 피드백을 고칠 때마다 알리면 오타 하나 고친 것도
    # 알림이 된다. 예정 PT 에 미리 적는 메모는 회원에게 보이지 않아 알리지 않는다.
    if (
        "note" in fields
        and s.status == SCHEDULE_DONE
        and not (before_note or "").strip()
        and (s.note or "").strip()
    ):
        _notify_pt_done(
            db, session=s, trainer_id=trainer_id, note=s.note, feedback_only=True
        )
    db.commit()
    db.refresh(s)
    out = _schedule_out(s)
    if refresh_derived:
        # 커밋 뒤 best-effort — 적재 실패가 저장을 되돌리지 않는다(완료와 같다).
        personal_ingest.refresh_exercise(
            db, s.member_id, session_id=_derived_exercise_id(s.id)
        )
    return out


def delete_session(db: Session, trainer_id: str, session_id: str) -> bool:
    s = _get_owned_session(db, trainer_id, session_id)
    if s is None:
        return False
    if _is_reservation_schedule(db, session_id):
        raise ScheduleConflict(
            "예약으로 생성된 일정은 일반 일정 화면에서 삭제할 수 없습니다."
        )
    # 완료 세션은 완료 시 파생된 기록을 갖는다 — 트레이너 이력(sched-hist-{id})과
    # 회원 운동 기록(sched-ex-{id}) 두 개다. 세션을 지우면 둘 다 함께 지워 고아
    # 레코드가 남지 않게 한다(완료 시 적재의 역연산). 회원 쪽을 빠뜨리면 회원의
    # 주간 집계에만 지워진 PT 가 계속 잡힌다.
    derived_owner: str | None = None
    if s.status == "완료":
        hist = db.get(RoutineHistory, f"sched-hist-{s.id}")
        if hist is not None:
            db.delete(hist)
        derived = db.get(ExerciseSession, _derived_exercise_id(s.id))
        if derived is not None:
            derived_owner = derived.user_id
            db.delete(derived)
    # 그 PT 에 붙여 두었을 뿐 아직 회원에게 가지 않은 개인운동은 함께 지운다
    # (#2223). FK 는 `SET NULL` 이라 그냥 두면 일정만 사라지고 `status` 는
    # `scheduled` 인 채 남는데, 그런 행은 회원 목록에도 제안 목록에도 잡히지
    # 않고 붙은 일정으로도 찾을 수 없어 **아무도 못 보고 지우지도 못한다.**
    # 이미 회원에게 간 것(`approved`)은 건드리지 않는다 — 일정이 지워졌다고
    # 회원이 받은 운동이 사라지면 안 된다.
    for pending in db.scalars(
        select(TrainerRoutine).where(
            TrainerRoutine.schedule_id == s.id,
            TrainerRoutine.status == ROUTINE_SCHEDULED,
        )
    ).all():
        db.delete(pending)
    # 아직 진행되지 않은 상담 일정을 지우면 상담 요청도 함께 거둔다(#2758) —
    # 잘못 만든 일정의 삭제라도 회원 쪽 요청이 `수락됨` 으로 남고 자리가 잠긴
    # 채이면 안 된다. 이미 진행된 상담(완료·노쇼)은 그 결말을 그대로 둔다.
    if s.status in (SCHEDULE_UPCOMING, SCHEDULE_CANCELLED):
        _withdraw_consultation(db, s, trainer_id)
    # 아직 오지 않은 약속만 알린다. 이미 끝난 PT 의 기록 정리까지 알리면 회원은
    # 지난 일을 취소 통보로 받는다. (#664)
    if s.member_id is not None and s.status == SCHEDULE_UPCOMING:
        notification_service.queue(
            db,
            member_id=s.member_id,
            kind=notification_service.PT_LINK_NOTICE,
            category=notification_service.MEMBER_SCHEDULE,
            template=notification_templates.MEMBER_SCHEDULE_CANCELLED,
            template_args=_slot_args(_member_visible_slot(s)),
        )
    derived_id = _derived_exercise_id(s.id)
    db.delete(s)
    db.commit()
    if derived_owner is not None:
        # 지운 기록을 코치가 계속 근거로 들지 않게 문서도 지운다(#3093) — 행이
        # 없으므로 refresh 가 문서를 지운다(배정 루틴 되돌리기와 같은 호출).
        personal_ingest.refresh_exercise(db, derived_owner, session_id=derived_id)
    return True


def reopen_session(
    db: Session,
    trainer_id: str,
    session_id: str,
    *,
    new_date: str,
    time: str | None = None,
    duration_minutes: int | None = None,
) -> ScheduleSessionOut | None:
    """완료 세션을 미래 날짜의 예정으로 되돌린다. (#1396)

    수정 화면에서 완료된 회차의 날짜를 앞으로 옮기며 "예정으로 바꿀까요?" 확인을
    거친 저장이 부르는 자리다 — 임의로 완료를 취소하는 일반 수정 경로는 아니다.
    완료가 남긴 파생 기록(트레이너 이력·회원 운동기록)은 [delete_session] 과
    같은 자리(id)를 지운다 — 그대로 두면 되돌린 뒤에도 "이미 했던 운동"으로
    남아 회원 집계가 거짓이 된다.

    옮길 자리의 겹침은 **아무것도 바꾸기 전에** 본다(#2757). 예전에는 되돌리기가
    먼저 커밋되고 겹침 검사는 뒤따르는 일반 수정에서야 돌아, 겹쳐서 거절돼도
    날짜·상태는 이미 바뀌고 파생 기록은 지워져 있었다. [time]·[duration_minutes]
    를 함께 받으면 그 자리로, 없으면 지금 시각·길이로 검사하고 함께 반영한다.
    """
    s = _get_owned_session(db, trainer_id, session_id)
    if s is None:
        return None
    _ensure_session_member_linked(db, trainer_id, s)
    if _is_reservation_schedule(db, session_id):
        raise ScheduleConflict(
            "예약으로 생성된 일정은 일반 일정 화면에서 되돌릴 수 없습니다."
        )
    if s.status != SCHEDULE_DONE:
        raise ScheduleConflict("완료된 PT만 예정으로 되돌릴 수 있습니다.")
    if new_date <= today_iso():
        raise ScheduleConflict("미래 날짜로만 되돌릴 수 있습니다.")
    new_time = time if time is not None else s.time
    new_duration = (
        duration_minutes if duration_minutes is not None else s.duration_minutes
    )
    ensure_no_overlap(
        db,
        trainer_id,
        date=new_date,
        time=new_time,
        duration_minutes=new_duration,
        exclude_ids=(s.id,),
    )

    hist = db.get(RoutineHistory, f"sched-hist-{s.id}")
    if hist is not None:
        db.delete(hist)
    derived = db.get(ExerciseSession, _derived_exercise_id(s.id))
    derived_owner = derived.user_id if derived is not None else None
    if derived is not None:
        db.delete(derived)

    s.date = new_date
    s.time = new_time
    s.duration_minutes = new_duration
    s.status = SCHEDULE_UPCOMING
    db.commit()
    db.refresh(s)
    out = _schedule_out(s)
    if derived_owner is not None:
        # 되돌린 PT 는 아직 하지 않은 운동이다 — 코치 근거도 지운다(#3093).
        personal_ingest.refresh_exercise(
            db, derived_owner, session_id=_derived_exercise_id(s.id)
        )
    return out


#: PT 완료가 파생시키는 회원 운동 기록의 종류. `TrainerSchedule.type` 은 화면용
#: 한국어 라벨('1:1 PT'|'상담')이고 `ExerciseSession.type` 은 계약 값이라 매핑이
#: 필요하다. 여기 없는 종류는 **운동이 아니므로 기록을 만들지 않는다** — 상담
#: 한 시간이 회원 주간 운동량으로 잡히면 집계가 거짓이 된다.
_SESSION_EXERCISE_TYPE = {"1:1 PT": "strength"}

#: 강도를 하나도 적지 않은(예전) 프로그램의 강도. PT 는 트레이너가 붙어서 끌고
#: 가는 시간이라 수기 입력의 '보통'보다 낮게 볼 이유가 없다.
_PT_INTENSITY = "moderate"


def _derived_exercise_id(session_id: str) -> str:
    """PT 완료가 파생시킨 운동 기록의 id — 슬롯 기준 결정론적.

    `sched-hist-{id}` 와 같은 이유다. 동시 완료나 재호출에도 같은 id 가 나와
    중복 행이 생기지 않는다.
    """
    return f"{exercise_service.PT_EXERCISE_ID_PREFIX}{session_id}"


def _schedule_day(day: str) -> date:
    """슬롯의 날짜. 값이 깨졌으면 오늘로 둔다(주차·요일 계산과 같은 폴백)."""
    try:
        return date.fromisoformat(day)
    except (TypeError, ValueError):
        return clock.today()


def _member_exercise_values(db: Session, s: TrainerSchedule) -> dict | None:
    """완료된 PT 세션이 만들 회원 운동 기록의 칸 값. 대상이 아니면 None.

    `RoutineHistory` 는 트레이너 화면 전용이라(`/trainer/clients/{id}/history`)
    회원 앱에서는 읽지 않는다. 회원의 운동 탭·홈 대시보드 주간 집계는 전부
    `ExerciseSession` 에서 나오므로, 두 곳 모두에 남겨야 회원이 받은 PT 가
    자기 기록에 잡힌다. (#499) 완료와 완료 뒤 수정이 같은 값을 쓰도록 계산은
    여기 한 곳에만 둔다(#3093).
    """
    ex_type = _SESSION_EXERCISE_TYPE.get(s.type)
    if s.member_id is None or ex_type is None or s.duration_minutes <= 0:
        return None
    # 프로그램에 적힌 실제 운동 항목의 분·유형을 우선 쓴다 — 분을 하나도
    # 적지 않은(예전) 프로그램만 슬롯 전체 길이·고정 유형으로 되돌아간다(#1233).
    items = _program_items(s.program_json)
    program_seconds, program_type_ko = _program_seconds_and_type(items)
    program_minutes = _minutes_of(program_seconds)
    minutes = program_minutes if program_minutes > 0 else s.duration_minutes
    if program_type_ko is not None:
        ex_type = exercise_types.normalize(program_type_ko)
    # 트레이너가 프로그램에 적어 둔 이름·세트·횟수·중량·강도를 회원 기록에도
    # 남긴다(#1276, #1310). 예전에는 분과 유형만 옮겨서, 회원 화면에는 무슨
    # 운동을 몇 회 몇 kg 로 했는지가 사라졌다.
    strength_items = [i for i in items if i.type == "근력"]
    sets = sum(i.sets for i in strength_items if i.sets) or None
    weights = [i.weight for i in strength_items if i.weight]
    # 횟수는 세트와 달리 더하지 않는다 — 한 세트당 수라 합계는 아무도 한 적 없는
    # 수가 된다. 중량과 같은 규칙으로 가장 많이 한 수를 그날의 기록으로 남긴다.
    rep_counts = [i.reps for i in strength_items if i.reps]
    # 버티는 종목의 홀드도 같은 규칙이다 — 합계는 아무도 버틴 적 없는 시간이라
    # 가장 오래 버틴 값을 그날의 기록으로 남긴다. (#1969)
    hold_counts = [i.hold_seconds for i in strength_items if i.hold_seconds]
    # 항목마다 강도가 다르면 세션 하나로 접을 값이 없다 — 그럴 때만 기본값이다.
    marked = {i.intensity for i in items}
    intensity = marked.pop() if len(marked) == 1 else _PT_INTENSITY
    # 주차·요일·완료 시각 셋 다 완료 시점이 아니라 **세션 날짜** 기준이다.
    # 지난 주 세션을 오늘 완료 처리해도 그 주의 집계로 들어가야 하는데,
    # `completed_at` 만 비워 두면 그 값을 읽는 자리에서는 오늘 한 운동이 된다.
    # 날짜 하나를 먼저 정하고 셋을 거기서 뽑는 이유는 값이 깨졌을 때다 — 따로
    # 계산하면 주차는 이번 주, 요일은 오늘 요일로 각각 흘러 서로 다른 날을
    # 가리킨다. (#1264)
    session_day = _schedule_day(s.date)
    # 한 세션에 여러 종목이면 이름 하나로 접히지 않는다. 그때 이름 해석을 태우면
    # `스쿼트, 데드리프트` 가 둘 중 하나로 붙어, 세션 전체의 칼로리가 한 종목의
    # 계수로 계산된다 — 종목이 하나일 때만 이름을 본다. (#1312)
    pt_estimate = exercise_service.estimate(
        db,
        name=items[0].name if len(items) == 1 else "",
        type_=ex_type,
        minutes=minutes,
        intensity=intensity,
        weight_kg=exercise_service.member_weight_kg(db, s.member_id),
    )
    return {
        "user_id": s.member_id,
        "week_start": exercise_service.monday_of_str(session_day.isoformat()),
        "day_label": exercise_service.weekday_label_of(session_day.isoformat()),
        "type": ex_type,
        "name": ", ".join(i.name for i in items),
        "minutes": minutes,
        # 프로그램에 적힌 시간을 초까지 남긴다(#2221) — 회원 앱이 `45초` 를
        # `1분` 이 아니라 적힌 대로 읽는다. 근력은 세트로 읽고, 프로그램에 시간이
        # 없어 슬롯 길이로 되돌아간 기록은 분뿐이다.
        "duration_seconds": (
            program_seconds
            if program_minutes > 0 and ex_type != exercise_types.STRENGTH
            else None
        ),
        "sets": sets if ex_type == exercise_types.STRENGTH else None,
        "reps": (
            max(rep_counts)
            if rep_counts and not hold_counts
            and ex_type == exercise_types.STRENGTH
            else None
        ),
        "hold_seconds": (
            max(hold_counts)
            if hold_counts and ex_type == exercise_types.STRENGTH
            else None
        ),
        # 여러 운동을 한 세션이면 가장 무거웠던 무게가 그날의 기록이다 —
        # 평균은 실제로 든 적 없는 값이라 다음 무게를 정할 근거가 못 된다.
        "weight": max(weights) if weights and ex_type == exercise_types.STRENGTH else None,
        "calories": pt_estimate.calories,
        "calorie_source": pt_estimate.source,
        "intensity": intensity,
        "source": "trainer_pt",
        "completed_at": exercise_activity.noon(session_day),
    }


def _sync_completed_records(
    db: Session,
    s: TrainerSchedule,
    trainer_id: str,
    *,
    note: str | None,
    exercise: bool = True,
) -> bool:
    """완료 세션의 파생 기록 두 개를 세션의 지금 값으로 맞춘다(커밋 없음). (#3093)

    트레이너 이력(`sched-hist-{id}`)과 회원 운동 기록(`sched-ex-{id}`)을 없으면
    만들고 있으면 고쳐 쓴다. 완료([complete_session])와 완료 뒤 프로그램·메모
    수정([update_session])이 함께 쓴다 — 계산이 두 곳이면 같은 PT 가 언제
    적었느냐에 따라 다른 기록이 된다.

    - [note] 가 None 이면 이력의 메모를 그대로 둔다(프로그램만 고친 수정).
    - [exercise] 가 False 면 회원 운동 기록을 건드리지 않는다 — 메모만 고쳤는데
      그 사이 바뀐 체중으로 칼로리가 다시 계산되면 안 된다.
    - 대상이 아니게 된 회원 운동 기록은 지운다.

    반환: 회원 운동 기록이 있었거나 생겼는가 — 커밋 뒤 코치 근거를 맞출지.
    """
    if not s.member_id:
        return False
    exercises = [
        _program_history_entry(p) for p in _program_items(s.program_json)
    ]
    exercises_json = json.dumps(exercises, ensure_ascii=False)
    hist = db.get(RoutineHistory, f"sched-hist-{s.id}")
    if hist is None:
        db.add(RoutineHistory(
            id=f"sched-hist-{s.id}",
            member_id=s.member_id,
            trainer_id=trainer_id,
            date=s.date,
            kind_label=PT_HISTORY_KIND_LABEL,
            completion_rate=100,
            exercises_json=exercises_json,
            trainer_note=note or "",
        ))
    else:
        hist.exercises_json = exercises_json
        if note is not None:
            hist.trainer_note = note
    if not exercise:
        return False
    row_id = _derived_exercise_id(s.id)
    existing = db.get(ExerciseSession, row_id)
    values = _member_exercise_values(db, s)
    if values is None:
        if existing is not None:
            db.delete(existing)
        return existing is not None
    if existing is not None:
        # 같은 id 를 고쳐 쓴다. 날짜는 바뀌지 않으므로 보호권 환급은 다시 하지
        # 않는다.
        for key, value in values.items():
            setattr(existing, key, value)
        return True
    db.add(ExerciseSession(id=row_id, **values))
    # 보호권으로 이어 붙인 날의 PT 를 완료 처리하면 그날은 운동한 날이다 — 그
    # 보호권을 되돌린다(#1788). 트레이너 화면은 보호한 날을 모른다.
    streak_shield_service.refund_for_record(
        db, s.member_id, _schedule_day(s.date)
    )
    return True


def send_session_program(
    db: Session,
    trainer_id: str,
    session_id: str,
    *,
    client_request_id: str | None = None,
) -> ScheduleSessionOut | None:
    """완료한 세션의 프로그램을 그 회원에게 배정한다. (#822)

    수업을 마친 뒤 "오늘 이걸 했습니다" 를 회원 앱으로 넘기는 자리다. 새 배정
    경로를 만들지 않고 [assign_program] 을 그대로 쓴다 — 회원이 받는 모양이
    트레이너가 코칭 탭에서 보내던 것과 같아야, 회원 화면에 출처마다 다른 루틴이
    생기지 않는다.

    - 소유 슬롯 아님 → None(404).
    - 회원이 없는 슬롯(상담·공백) → ScheduleError(400): 보낼 상대가 없다.
    - 완료 전 → ScheduleError(400): 아직 한 것이 아니라 할 것이다.
    - 프로그램이 비었으면 → ScheduleError(400): 빈 루틴만 간다.
    - 이미 보냈으면 그대로 반환(멱등). 두 번 눌러도 회원 루틴이 겹치지 않는다.
    """
    s = _get_owned_session(db, trainer_id, session_id)
    if s is None:
        return None
    if not s.member_id:
        raise ScheduleError("회원이 연결되지 않은 일정입니다.")
    # 해제 전에 잡아 둔 일정이라도 해제 뒤에는 회원에게 루틴을 보내지 않는다. (#2281)
    if not has_active_client_link(db, trainer_id, s.member_id):
        raise ClientLinkDetached("담당 고객을 찾을 수 없습니다.")
    if s.status != "완료":
        raise ScheduleError("완료한 일정만 보낼 수 있습니다.")
    items = _program_items(s.program_json)
    if not items:
        raise ScheduleError("보낼 프로그램이 없습니다.")
    if s.program_sent_at is not None:
        return _schedule_out(s)  # 멱등 no-op

    # 일정의 프로그램 항목을 배정 계약의 운동으로 옮긴다. 두 계약이 같은 칸을
    # 쓰므로 값을 고쳐 담을 것이 없다(#1276). 세션은 하나다 — 회원 화면에 없던
    # 세션 라벨이 생기지 않는다.
    exercises = [
        ProgramDraftExercise(
            id=f"{s.id}#{index}",
            name=item.name,
            type=item.type,
            date=item.date,
            duration=item.duration,
            duration_seconds=item.duration_seconds,
            sets=item.sets,
            reps=item.reps,
            hold_seconds=item.hold_seconds,
            weight=item.weight,
            intensity=item.intensity,
        )
        for index, item in enumerate(items)
    ]
    # 프로그램 만들기로 짠 PT 는 이미 이 일정에 붙어 있다(#2279) — 올리기만
    # 하면 된다. 여기서 또 배정하면 회원이 같은 운동을 두 벌 받는다.
    #
    # 붙은 것이 없으면 예전처럼 새로 배정한다 — 스케줄에서 연필로 바로 짠
    # 프로그램에는 붙은 줄이 없고, 이 칸이 생기기 전에 만든 일정도 그렇다.
    if not _raise_scheduled_program(db, trainer_id, s):
        assign_program(
            db,
            trainer_id,
            s.member_id,
            name=f"{s.date} {s.type}".strip() or s.date,
            sessions=[ProgramDraftSession(id=s.id, name="", exercises=exercises)],
            client_request_id=client_request_id,
            # 붙여 둔 프로그램을 올릴 때와 같이 매일 목록에 걸지 않는다(#3115).
            active_days=0,
            # 아래에서 개인운동과 함께 카드 하나로 남긴다(#2672).
            chat_card=False,
        )
    # 개인운동은 **이 전송에 함께 실린다**(#2224) — 회원은 "오늘 한 것" 과
    # "혼자 할 것" 을 한 번에 받는다. 프로그램과 같은 트랜잭션이라 둘 다
    # 가거나 둘 다 안 간다: 프로그램만 가고 개인운동이 빠지면 트레이너는
    # 보냈다고 아는데 회원은 혼자 할 것이 없다.
    #
    # **붙은 것이 없어도 막지 않는다.** 개인운동을 필수로 받는 자리는 프로그램
    # 만들기다(#2223) — 스케줄에서 연필로 바로 짠 프로그램에는 붙을 자리가
    # 없어, 여기서 막으면 그 길로 짠 프로그램을 보낼 수 없게 된다.
    routines_sent = _send_scheduled_routines(
        db, trainer_id, s, delivery_kind=DELIVERY_PT_WITH_ROUTINE
    )
    # 프로그램과 함께 간 개인운동을 채팅 안내 하나로 남긴다(#2672).
    post_routine_delivery(
        db, trainer_id, s.member_id,
        kind=DELIVERY_PT_WITH_ROUTINE,
        program_names=[item.name for item in items if item.name],
        routine_names=[row.name for row in routines_sent],
    )
    # 배정이 커밋된 뒤에만 보낸 것으로 남긴다. 반대 순서면 배정에 실패한 세션이
    # 화면에서 '전송됨' 이 되어 다시 보낼 수 없다.
    s.program_sent_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(s)
    return _schedule_out(s)


def _now_kst() -> datetime:
    """시작 판정의 기준 시각(KST). 테스트가 고정할 수 있게 한 자리로 모은다."""
    return clock.now()


def session_has_started(day: str, time: str, *, now: datetime | None = None) -> bool:
    """일정의 시작 시각(KST 날짜+`HH:MM`)이 지났거나 지금인가. (#2760)

    완료·노쇼가 이 판정을 쓴다. 날짜만 보면 오늘 20:00 PT 를 오전에 노쇼·완료로
    처리할 수 있고, 완료는 아직 하지 않은 운동을 회원 기록에 미리 만든다. 완료는
    종료가 아니라 시작 시각부터 연다 — PT 가 일찍 끝나는 경우를 막지 않는다.
    형식이 깨진 값은 날짜만으로 판정한다(예전 규칙).
    """
    current = now or _now_kst()
    today = current.date().isoformat()
    if day != today:
        return day < today
    try:
        return _clock_minutes(time) <= current.hour * 60 + current.minute
    except ValueError:
        return True


def complete_session(
    db: Session, trainer_id: str, session_id: str, note: str
) -> ScheduleSessionOut | None:
    """예정→완료. 매칭된 회원이 있으면 트레이너 쪽 기록(RoutineHistory)과 회원 쪽
    기록(ExerciseSession)으로 함께 적재해 '예약→수업→기록' 루프를 닫는다.

    - 소유 슬롯 아님 → None(404).
    - 공백/시작 전 일정 → ScheduleError(400). 시작 시각(KST) 기준이다(#2760).
    - 이미 완료 → 그대로 반환(멱등, 중복 기록 없음).
    두 기록 모두 id 가 슬롯 기준 결정론적이라 동시/재호출에도 중복되지 않는다.
    """
    s = _get_owned_session(db, trainer_id, session_id)
    if s is None:
        return None
    _ensure_session_member_linked(db, trainer_id, s)
    if s.status == "공백":
        raise ScheduleError("빈 슬롯은 완료할 수 없습니다.")
    if not session_has_started(s.date, s.time):
        raise ScheduleError("시작 전 일정은 완료할 수 없습니다.")
    if s.status == SCHEDULE_DONE:
        return _schedule_out(s)  # 멱등 no-op
    if s.status in SCHEDULE_TERMINAL:
        # 진행되지 않은 것으로 마무리한 세션을 완료로 되돌리면 하지 않은 PT 가
        # 회원 운동 기록으로 적재된다.
        raise ScheduleConflict(
            "취소·노쇼로 마무리된 PT는 완료할 수 없습니다."
        )

    # 조건부 전환(예정 → 완료). rowcount==1 인 호출만 '방금 전환한' 것이므로 그 호출만
    # 운동기록을 쓴다 — 동시 완료 요청이 둘 다 예정을 보고 중복 기록하는 것을 막는다.
    values: dict = {"status": "완료"}
    if note:
        values["note"] = note
    changed = db.execute(
        update(TrainerSchedule)
        .where(TrainerSchedule.id == session_id, TrainerSchedule.status == "예정")
        .values(**values)
    ).rowcount
    if changed != 1:
        db.commit()
        db.refresh(s)
        return _schedule_out(s)  # 동시 호출이 먼저 완료 처리함 — 기록 없이 현재 상태 반환

    # 완료 요청에 메모가 없으면 미리 적어 둔 일정 메모가 그 PT 의 메모다(#3232) —
    # 아래 알림과 같은 값을 이력에도 남긴다.
    has_exercise_log = _sync_completed_records(
        db, s, trainer_id, note=note or (s.note or "")
    )
    if s.member_id:
        # 방금 전환한 이 호출만 알린다(#3027) — 멱등 재호출·동시 호출은 위에서
        # 돌아가 알림도 한 번뿐이다. 완료 요청에 메모가 없으면 미리 적어 둔 메모가
        # 회원에게 보이는 피드백이다(`member_mirror._member_schedule_out`).
        _notify_pt_done(
            db,
            session=s,
            trainer_id=trainer_id,
            note=note or (s.note or ""),
            feedback_only=False,
        )
    db.commit()
    db.refresh(s)
    out = _schedule_out(s)
    if has_exercise_log:
        # 회원 입장에서 PT 도 '내가 한 운동'이라 코치가 검색할 수 있어야 한다(#586).
        # 커밋 뒤에 부르는 이유는 record_chat 과 같다 — 적재 실패의 롤백이 응답을
        # 깨뜨리지 않도록, 값은 미리 뽑아 두고 응답도 이미 만들어 둔다.
        # PT 완료는 멱등하게 재호출될 수 있고 id 도 슬롯 기준 결정론적이라
        # (`_derived_exercise_id`), 교체로 두어야 문서가 겹쳐 쌓이지 않는다.
        personal_ingest.refresh_exercise(
            db, s.member_id, session_id=_derived_exercise_id(s.id)
        )
    return out


def _withdraw_consultation(db: Session, s: TrainerSchedule, trainer_id: str) -> bool:
    """상담 일정을 거두면 그 상담 요청도 취소하고 자리를 돌려준다(커밋 없음). (#2758)

    [_release_cancelled_reservation] 이 회원 예약에 하는 일을 상담 신청에 한다 —
    상담 자리에는 `TrainerReservation` 행이 없어 그 경로로는 풀리지 않는다.
    consultation_service 가 이 모듈을 가져다 쓰므로 함수 안에서 부른다.
    """
    if s.consultation_id is None:
        return False
    from app.services import consultation_service

    return consultation_service.withdraw_for_trainer_schedule(
        db, s.consultation_id, trainer_id
    )


def cancel_session(
    db: Session,
    trainer_id: str,
    session_id: str,
    *,
    source: str = "trainer",
    reason: str = "",
) -> ScheduleSessionOut | None:
    """예정 → 취소. 일정을 지우지 않고 **진행되지 않았다는 기록**으로 남긴다. (#871)

    삭제와 나누는 까닭이 이 함수의 전부다 — 삭제는 잘못 만든 데이터를 없애는 일이고,
    취소는 실제로 있었던 약속이 진행되지 않았다는 사실이다. 지워 버리면 나중에 회원의
    낮은 완료율이 본인의 미이행 때문인지 트레이너 사정 때문인지 구분할 수 없다.

    - 소유 슬롯 아님 → None(404).
    - 공백 슬롯 → ScheduleError(400): 취소할 약속이 없다.
    - 이미 취소 → 그대로 반환(멱등). 중복 클릭·재시도에 409 를 주면 화면은 이미
      취소한 일정에 대해 오류를 띄운다. 취소 시각과 주체는 처음 값을 지킨다.
    - 완료·노쇼 → ScheduleConflict(409): 다른 결말로 이미 마무리된 세션이다.
    """
    s = _get_owned_session(db, trainer_id, session_id)
    if s is None:
        return None
    if s.status == SCHEDULE_GAP:
        raise ScheduleError("빈 슬롯은 취소할 수 없습니다.")
    if s.status == SCHEDULE_CANCELLED:
        # 멱등 no-op. 다만 예약 좌석을 풀지 않던 때(#2283 이전)에 취소된 일정은
        # 예약이 남아 있을 수 있어, 다시 누르면 그 자리만 마저 풀어 준다.
        # 상담 자리도 같다(#2758 이전에 취소된 상담 일정).
        released = _release_cancelled_reservation(db, s)
        withdrawn = _withdraw_consultation(db, s, trainer_id)
        if released or withdrawn:
            db.commit()
            db.refresh(s)
        return _schedule_out(s)
    if s.status in SCHEDULE_TERMINAL:
        raise ScheduleConflict(
            "완료·노쇼로 마무리된 PT는 취소할 수 없습니다."
        )
    if source not in CANCELLATION_SOURCES:
        raise ScheduleError("취소 주체가 올바르지 않습니다.")

    # 조건부 전환(예정 → 취소). 동시에 들어온 취소·완료 요청 중 하나만 이긴다 —
    # rowcount 가 0 이면 그 사이에 다른 전이가 끝난 것이라 현재 상태를 그대로 준다.
    changed = db.execute(
        update(TrainerSchedule)
        .where(
            TrainerSchedule.id == session_id,
            TrainerSchedule.status == SCHEDULE_UPCOMING,
        )
        .values(
            status=SCHEDULE_CANCELLED,
            cancelled_at=datetime.now(timezone.utc),
            cancellation_source=source,
            cancellation_reason=reason[:200],
        )
    ).rowcount
    if changed != 1:
        db.commit()
        db.refresh(s)
        return _schedule_out(s)

    # 회원 앱 예약으로 생긴 일정이면 예약도 함께 거두고 좌석을 돌려준다(#2283).
    # 일정만 `취소` 로 두면 회원 앱에는 '예약됨' 으로 남고 그 시간은 다시 잡을 수
    # 없다. 회원 취소와 같은 경로라 두 쪽 결과가 어긋나지 않는다.
    _release_cancelled_reservation(db, s, source=source)
    # 상담 일정이면 상담 요청을 취소하고 신청 때 잠근 자리를 돌려준다(#2758).
    _withdraw_consultation(db, s, trainer_id)

    # 회원에게는 취소 사실만 간다 — 내부 사유는 트레이너가 보는 기록이다.
    # 삭제 경로와 같은 알림을 쓴다: 회원 입장에서 달라진 것은 "그 시간의 PT 가
    # 없어졌다" 하나뿐이고, 새 알림 종류를 만들 이유가 없다.
    if s.member_id is not None:
        notification_service.queue(
            db,
            member_id=s.member_id,
            kind=notification_service.PT_LINK_NOTICE,
            category=notification_service.MEMBER_SCHEDULE,
            template=notification_templates.MEMBER_SCHEDULE_CANCELLED,
            template_args=_slot_args(_member_visible_slot(s)),
        )
    db.commit()
    db.refresh(s)
    return _schedule_out(s)


def mark_session_no_show(
    db: Session, trainer_id: str, session_id: str
) -> ScheduleSessionOut | None:
    """예정 → 노쇼. 예약된 시간에 회원이 오지 않았다는 기록. (#871)

    취소와 따로 두는 까닭은 두 일이 다르기 때문이다 — 취소는 진행 전에 약속이
    거두어진 것이고, 노쇼는 약속이 그대로 있는데 회원이 오지 않은 것이다.

    회원 알림은 만들지 않는다. 오지 않은 사실을 앱 알림으로 통보하는 것은 이번
    범위의 결정이 아니고, 필요하면 정책을 따로 세운다.

    - 시작 전 일정 → ScheduleError(400): 아직 오지 않은 약속에 불참을 적을 수 없다.
      날짜가 아니라 시작 시각(KST) 기준이다(#2760).
    - 이미 노쇼 → 그대로 반환(멱등). 완료·취소 → ScheduleConflict(409).
    """
    s = _get_owned_session(db, trainer_id, session_id)
    if s is None:
        return None
    if s.status == SCHEDULE_GAP:
        raise ScheduleError("빈 슬롯은 노쇼 처리할 수 없습니다.")
    if not session_has_started(s.date, s.time):
        raise ScheduleError("시작 전 일정은 노쇼 처리할 수 없습니다.")
    if s.status == SCHEDULE_NO_SHOW:
        return _schedule_out(s)  # 멱등 no-op
    if s.status in SCHEDULE_TERMINAL:
        raise ScheduleConflict(
            "완료·취소로 마무리된 PT는 노쇼 처리할 수 없습니다."
        )

    changed = db.execute(
        update(TrainerSchedule)
        .where(
            TrainerSchedule.id == session_id,
            TrainerSchedule.status == SCHEDULE_UPCOMING,
        )
        .values(status=SCHEDULE_NO_SHOW, no_show_at=datetime.now(timezone.utc))
    ).rowcount
    db.commit()
    db.refresh(s)
    if changed != 1:
        return _schedule_out(s)  # 동시 호출이 먼저 전이를 끝냄
    return _schedule_out(s)
