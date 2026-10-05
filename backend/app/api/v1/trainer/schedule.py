"""트레이너 라우터 — 스케줄(트레이너 타임라인 + 예약→수업→기록 완료 루프)."""
from __future__ import annotations

from typing import Annotated

from fastapi import (
    APIRouter,
    Depends,
    HTTPException,
    Query,
)
from sqlalchemy.orm import Session

from app.api.deps import RequireTrainer
from app.db.session import get_db
from app.schemas.trainer_api import (
    RoutineOut, ProgramScheduleOut, ProgramScheduleRequest,
    ScheduleCancelRequest, ScheduleCompleteRequest,
    ScheduleRoutineSendRequest,
    ScheduleRoutineUpdateRequest,
    ScheduleProgramSendRequest, ScheduleCreateRequest,
    ScheduleRecurringPreviewOut, ScheduleRecurringRequest, ScheduleReopenRequest,
    ScheduleSessionOut, ScheduleUpdateRequest,
)
from app.services.trainer import _common as trainer_common_service
from app.services.trainer import schedule as trainer_schedule_service
from app.api.v1.trainer._common import (
    _is_ymd,
    _require_client,
)


router = APIRouter(tags=["trainer"])


# ---- 스케줄 (트레이너 타임라인 + 예약→수업→기록 완료 루프) ----


@router.get("/trainer/schedule/booked-dates", response_model=list[str])
def trainer_booked_dates(
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> list[str]:
    """예약이 있는(공백 아닌) 날짜 목록 — 주간 스트립 도트용."""
    return trainer_schedule_service.booked_dates(db, trainer.id)


@router.get("/trainer/schedule", response_model=list[ScheduleSessionOut])
def trainer_schedule(
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
    date: str | None = Query(None, description="YYYY-MM-DD (기본: 오늘)"),
    from_: str | None = Query(
        None, alias="from", description="구간 시작 YYYY-MM-DD (to 와 함께)"
    ),
    to: str | None = Query(None, description="구간 끝 YYYY-MM-DD (from 과 함께)"),
    member_id: str | None = Query(None, description="담당 고객의 세션만"),
) -> list[ScheduleSessionOut]:
    """타임라인. 기본은 하루(`date`), `from`/`to` 를 주면 그 구간 전체.

    주 캘린더가 7일치를 한 번에 읽기 위해 구간 조회를 지원한다 — 하루짜리
    요청을 요일마다 반복하면 요청이 7배가 된다.

    `member_id` 만 주면 날짜 제한 없이 그 고객의 전체 세션을 준다. 고객
    상세의 루틴 이력이 필요로 하는 것이고, 구간으로 흉내내면 그 구간보다
    오래된 기록이 조용히 사라진다.
    """
    if member_id is not None:
        _require_client(db, trainer.id, member_id)

    if from_ is not None or to is not None:
        # 한쪽만 오면 어느 구간인지 알 수 없다 — 조용히 하루로 떨어뜨리면
        # 클라이언트는 구간을 받았다고 믿는다.
        if from_ is None or to is None:
            raise HTTPException(
                status_code=422, detail="from 과 to 는 함께 지정해야 해요."
            )
        if not _is_ymd(from_) or not _is_ymd(to):
            raise HTTPException(
                status_code=422, detail="from/to 는 YYYY-MM-DD 형식이어야 해요."
            )
        if from_ > to:
            raise HTTPException(status_code=422, detail="from 은 to 보다 늦을 수 없어요.")
        return trainer_schedule_service.build_schedule_range(
            db, trainer.id, from_, to, member_id=member_id
        )

    if member_id is not None and date is None:
        return trainer_schedule_service.build_client_schedule(db, trainer.id, member_id)

    day = date or trainer_common_service.today_iso()
    if not _is_ymd(day):
        raise HTTPException(status_code=422, detail="date 는 YYYY-MM-DD 형식이어야 해요.")
    return trainer_schedule_service.build_schedule_range(
        db, trainer.id, day, day, member_id=member_id
    )


@router.post("/trainer/schedule", response_model=ScheduleSessionOut, status_code=201)
def trainer_create_session(
    payload: ScheduleCreateRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> ScheduleSessionOut:
    """예약 추가(status 예정). member_id 를 주면 담당 고객이어야 한다(아니면 404)."""
    if payload.member_id:
        _require_client(db, trainer.id, payload.member_id)
    try:
        return trainer_schedule_service.create_session(
            db,
            trainer.id,
            date=payload.date,
            time=payload.time,
            client_name=payload.client_name,
            member_id=payload.member_id,
            type_=payload.type,
            duration_minutes=payload.duration_minutes,
            note=payload.note,
            program=payload.program,
            client_request_id=payload.client_request_id,
        )
    except trainer_common_service.IdempotencyConflict as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    except trainer_schedule_service.ScheduleOverlap as exc:
        # 겹친 세션을 함께 실어 화면이 어느 일정과 겹치는지 짚게 한다. (#2284)
        raise HTTPException(
            status_code=409, detail=trainer_schedule_service.overlap_detail(exc)
        ) from exc


@router.post(
    "/trainer/schedule/recurring/preview",
    response_model=ScheduleRecurringPreviewOut,
)
def trainer_preview_recurring_sessions(
    payload: ScheduleRecurringRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> ScheduleRecurringPreviewOut:
    """반복 설정이 만들 회차와, 그 자리에 이미 있는 일정. (#870)

    저장 전에 보여 주기 위한 경로다 — 반복은 한 번에 여러 건을 만들고, 요일이나
    종료일을 잘못 골랐을 때 되돌리는 비용이 한 건씩 지우는 일이다.
    """
    if payload.member_id:
        _require_client(db, trainer.id, payload.member_id)
    dates, conflicts, already_created = (
        trainer_schedule_service.preview_recurring_sessions(
            db,
            trainer.id,
            start=payload.date,
            time=payload.time,
            weekdays=payload.weekdays,
            count=payload.count,
            until=payload.until,
            duration_minutes=payload.duration_minutes,
            client_request_id=payload.client_request_id,
        )
    )
    return ScheduleRecurringPreviewOut(
        dates=dates, conflicts=conflicts, already_created=already_created
    )


@router.post(
    "/trainer/schedule/recurring",
    response_model=list[ScheduleSessionOut],
    status_code=201,
)
def trainer_create_recurring_sessions(
    payload: ScheduleRecurringRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> list[ScheduleSessionOut]:
    """주간 반복으로 PT 회차를 한 번에 등록한다. (#870)

    전부 만들거나 하나도 만들지 않는다 — 겹치는 회차가 있으면 409 로 멈추고, 응답
    본문에 겹친 세션을 실어 화면이 어느 주가 문제인지 짚어 줄 수 있게 한다.
    """
    if payload.member_id:
        _require_client(db, trainer.id, payload.member_id)
    try:
        return trainer_schedule_service.create_recurring_sessions(
            db,
            trainer.id,
            start=payload.date,
            time=payload.time,
            weekdays=payload.weekdays,
            client_name=payload.client_name,
            member_id=payload.member_id,
            type_=payload.type,
            duration_minutes=payload.duration_minutes,
            note=payload.note,
            count=payload.count,
            until=payload.until,
            client_request_id=payload.client_request_id,
        )
    except trainer_schedule_service.ScheduleSeriesConflict as exc:
        raise HTTPException(
            status_code=409,
            detail={
                # 단건 겹침과 같은 코드 — 화면이 한 가지 규칙으로 알아본다. (#2284)
                "code": trainer_schedule_service.SCHEDULE_OVERLAP_CODE,
                "message": str(exc),
                "conflicts": [
                    conflict.model_dump(mode="json") for conflict in exc.conflicts
                ],
            },
        ) from exc
    except trainer_schedule_service.ScheduleError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.post(
    "/trainer/clients/{member_id}/program-schedule",
    response_model=ProgramScheduleOut,
    status_code=201,
)
def trainer_assign_program_with_schedule(
    member_id: str,
    payload: ProgramScheduleRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> ProgramScheduleOut:
    """프로그램 탭 `일정 추가` — 배정과 PT 일정 등록을 한 트랜잭션으로. (#1580)

    둘 중 하나만 반영되는 경우가 없다. `client_request_id` 는 명령 전체에 대해
    멱등하다 — 응답을 잃고 같은 키로 다시 보내면 먼저 처리한 결과가 돌아온다.
    """
    name = payload.name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="프로그램 이름이 필요해요.")
    if not any(session.exercises for session in payload.sessions):
        raise HTTPException(status_code=400, detail="운동이 하나 이상 필요해요.")
    try:
        result = trainer_schedule_service.assign_program_with_schedule(
            db,
            trainer.id,
            member_id,
            name=name,
            sessions=payload.sessions,
            date=payload.date,
            time=payload.time,
            duration_minutes=payload.duration_minutes,
            client_name=payload.client_name,
            client_request_id=payload.client_request_id,
            session_id=payload.session_id,
            personal_routines=payload.personal_routines,
            suggestion_ids=payload.suggestion_ids,
        )
    except trainer_common_service.IdempotencyConflict as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    except trainer_schedule_service.ScheduleOverlap as exc:
        raise HTTPException(
            status_code=409, detail=trainer_schedule_service.overlap_detail(exc)
        ) from exc
    except trainer_schedule_service.AttachTargetConflict as exc:
        # 겹치는 후보를 함께 실어 화면이 어느 회차를 고를지 다시 물을 수 있게 한다.
        raise HTTPException(
            status_code=409,
            detail={
                "code": exc.code,
                "message": str(exc),
                "candidates": [
                    candidate.model_dump(mode="json") for candidate in exc.candidates
                ],
            },
        ) from exc
    if result is None:
        raise HTTPException(status_code=404, detail="담당 회원을 찾을 수 없어요.")
    return result


@router.get(
    "/trainer/schedule/{session_id}/routines", response_model=list[RoutineOut]
)
def trainer_schedule_routines(
    session_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> list[RoutineOut]:
    """그 PT 일정에 붙어 있는(아직 회원에게 가지 않은) 개인운동. (#2223)

    일정 상세가 "이 PT 와 함께 갈 개인운동"을 보여 주는 데 쓴다(#2224). 보낸
    뒤에는 배정 목록(`GET .../routines`)으로 옮겨 가므로 여기서는 빠진다. 남의
    일정은 조건에서 걸러져 빈 목록이 된다 — 없는 일정과 같은 답이라 어느 id 가
    실재하는지 알려 주지 않는다.
    """
    return trainer_schedule_service.list_scheduled_routines(db, trainer.id, session_id)


@router.put(
    "/trainer/schedule/{session_id}/routines", response_model=list[RoutineOut]
)
def trainer_update_schedule_routines(
    session_id: str,
    payload: ScheduleRoutineUpdateRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> list[RoutineOut]:
    """그 PT 에 붙은 개인운동을 고친다 — 보내지는 않는다. (#2224)

    일정 상세에서 바로 고친다. 이미 보낸 것은 손댈 수 없다. 붙은 것이 없으면
    처음 붙인다(#2280) — 개인운동 단계를 지나지 않은 PT 를 구제하는 자리다.
    """
    try:
        rows = trainer_schedule_service.update_scheduled_routines(
            db,
            trainer.id,
            session_id,
            payload.personal_routines,
            suggestion_ids=payload.suggestion_ids,
        )
    except trainer_common_service.ClientLinkDetached as exc:
        # 해제·동의 철회된 회원의 일정 — 남의 회원과 같은 404. (#2281, #1631)
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except trainer_schedule_service.ScheduleError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    if rows is None:
        raise HTTPException(status_code=404, detail="일정을 찾을 수 없어요.")
    return rows


@router.post(
    "/trainer/schedule/{session_id}/routines/send",
    response_model=list[RoutineOut],
)
def trainer_send_schedule_routines(
    session_id: str,
    payload: ScheduleRoutineSendRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> list[RoutineOut]:
    """마무리된 PT 에 남은 개인운동을 회원에게 보낸다. (#2224)

    취소·노쇼로 끝난 PT 의 개인운동은 자동으로 가지 않는다 — 아파서 쉬는
    회원에게 운동이 저절로 가면 안 된다. 트레이너가 누를 때만 온다.
    `personal_routines` 를 주면 그 내용으로 고쳐서 보낸다.
    """
    try:
        sent = trainer_schedule_service.send_scheduled_routines(
            db, trainer.id, session_id, items=payload.personal_routines
        )
    except trainer_common_service.ClientLinkDetached as exc:
        # 해제·동의 철회된 회원의 일정 — 남의 회원과 같은 404. (#2281, #1631)
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except trainer_schedule_service.ScheduleError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    if sent is None:
        raise HTTPException(status_code=404, detail="일정을 찾을 수 없어요.")
    return sent


@router.post("/trainer/schedule/{session_id}/routines/dismiss")
def trainer_dismiss_schedule_routines(
    session_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> dict[str, bool]:
    """마무리된 PT 의 개인운동을 보내지 않기로 정리한다. (#2224)

    `개인운동 미전송` 표시를 걷어낸다. 무엇을 짰다가 안 보냈는지는 남는다.
    """
    try:
        done = trainer_schedule_service.dismiss_scheduled_routines(
            db, trainer.id, session_id
        )
    except trainer_schedule_service.ScheduleError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    if done is None:
        raise HTTPException(status_code=404, detail="일정을 찾을 수 없어요.")
    return {"dismissed": done}


@router.put("/trainer/schedule/{session_id}", response_model=ScheduleSessionOut)
def trainer_update_session(
    session_id: str,
    payload: ScheduleUpdateRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> ScheduleSessionOut:
    """예약 수정(제공된 필드만). member_id 변경 시 담당 고객이어야 한다.
    완료·취소·노쇼 세션은 기록과의 정합성을 위해 메모·아직 보내지 않은
    프로그램만 수정할 수 있다(그 밖은 409, #2754)."""
    fields = payload.model_dump(exclude_unset=True)
    if fields.get("member_id"):
        _require_client(db, trainer.id, fields["member_id"])
    try:
        out = trainer_schedule_service.update_session(db, trainer.id, session_id, fields)
    except trainer_common_service.ClientLinkDetached as e:
        # 해제·동의 철회된 회원의 일정 — 남의 회원과 같은 404. (#2281, #1631)
        raise HTTPException(status_code=404, detail=str(e)) from e
    except trainer_schedule_service.ScheduleOverlap as e:
        raise HTTPException(
            status_code=409, detail=trainer_schedule_service.overlap_detail(e)
        ) from e
    except trainer_schedule_service.ScheduleConflict as e:
        raise HTTPException(status_code=409, detail=str(e)) from e
    if out is None:
        raise HTTPException(status_code=404, detail="일정을 찾을 수 없어요.")
    return out


@router.delete("/trainer/schedule/{session_id}")
def trainer_delete_session(
    session_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> dict:
    """예약 삭제."""
    try:
        deleted = trainer_schedule_service.delete_session(db, trainer.id, session_id)
    except trainer_schedule_service.ScheduleConflict as e:
        raise HTTPException(status_code=409, detail=str(e)) from e
    if not deleted:
        raise HTTPException(status_code=404, detail="일정을 찾을 수 없어요.")
    return {"status": "deleted"}


@router.post("/trainer/schedule/{session_id}/complete", response_model=ScheduleSessionOut)
def trainer_complete_session(
    session_id: str,
    payload: ScheduleCompleteRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> ScheduleSessionOut:
    """세션 완료(예정→완료). 매칭된 회원이 있으면 운동기록으로 적재.

    취소·노쇼로 이미 마무리된 세션은 409 다 — 하지 않은 PT 를 완료로 되돌리면
    회원 운동 기록으로 적재된다(#871).
    """
    try:
        out = trainer_schedule_service.complete_session(db, trainer.id, session_id, payload.note)
    except trainer_common_service.ClientLinkDetached as e:
        # 해제·동의 철회된 회원의 일정 — 남의 회원과 같은 404. (#2281, #1631)
        raise HTTPException(status_code=404, detail=str(e)) from e
    except trainer_schedule_service.ScheduleError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
    except trainer_schedule_service.ScheduleConflict as e:
        raise HTTPException(status_code=409, detail=str(e)) from e
    if out is None:
        raise HTTPException(status_code=404, detail="일정을 찾을 수 없어요.")
    return out


@router.post("/trainer/schedule/{session_id}/cancel", response_model=ScheduleSessionOut)
def trainer_cancel_session(
    session_id: str,
    payload: ScheduleCancelRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> ScheduleSessionOut:
    """세션 취소(예정→취소). 일정을 지우지 않고 기록으로 남긴다. (#871)

    삭제(`DELETE`)와 다른 동작이다 — 삭제는 잘못 만든 일정을 없애는 일이고,
    이 경로는 실제로 있었던 약속이 진행되지 않았다는 사실을 남긴다. 같은 요청을
    반복해도 200 이고 취소 시각·주체는 처음 값을 지킨다.
    """
    try:
        out = trainer_schedule_service.cancel_session(
            db,
            trainer.id,
            session_id,
            source=payload.source,
            reason=payload.reason.strip(),
        )
    except trainer_schedule_service.ScheduleError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
    except trainer_schedule_service.ScheduleConflict as e:
        raise HTTPException(status_code=409, detail=str(e)) from e
    if out is None:
        raise HTTPException(status_code=404, detail="일정을 찾을 수 없어요.")
    return out


@router.post("/trainer/schedule/{session_id}/reopen", response_model=ScheduleSessionOut)
def trainer_reopen_session(
    session_id: str,
    payload: ScheduleReopenRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> ScheduleSessionOut:
    """완료 세션을 미래 날짜의 예정으로 되돌린다(예정→완료의 역방향). (#1396)

    일정 수정 화면에서 완료된 회차의 날짜를 앞으로 옮길 때만 쓰는 경로다 —
    완료 시 적재된 파생 기록(트레이너 이력·회원 운동기록)을 함께 지운다.
    """
    try:
        out = trainer_schedule_service.reopen_session(
            db,
            trainer.id,
            session_id,
            new_date=payload.date,
            time=payload.time,
            duration_minutes=payload.duration_minutes,
        )
    except trainer_common_service.ClientLinkDetached as e:
        # 해제·동의 철회된 회원의 일정 — 남의 회원과 같은 404. (#2281, #1631)
        raise HTTPException(status_code=404, detail=str(e)) from e
    except trainer_schedule_service.ScheduleOverlap as e:
        # 겹치면 아무것도 바꾸지 않는다 — 완료·날짜·파생 기록이 그대로다. (#2757)
        raise HTTPException(
            status_code=409, detail=trainer_schedule_service.overlap_detail(e)
        ) from e
    except trainer_schedule_service.ScheduleConflict as e:
        raise HTTPException(status_code=409, detail=str(e)) from e
    if out is None:
        raise HTTPException(status_code=404, detail="일정을 찾을 수 없어요.")
    return out


@router.post("/trainer/schedule/{session_id}/no-show", response_model=ScheduleSessionOut)
def trainer_mark_session_no_show(
    session_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> ScheduleSessionOut:
    """세션 노쇼(예정→노쇼). 예약된 시간에 회원이 오지 않았다는 기록. (#871)

    취소와 나누는 까닭은 두 일이 다르기 때문이다 — 취소는 진행 전에 약속이
    거두어진 것이고, 노쇼는 약속이 그대로 있는데 회원이 오지 않은 것이다.
    """
    try:
        out = trainer_schedule_service.mark_session_no_show(db, trainer.id, session_id)
    except trainer_schedule_service.ScheduleError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
    except trainer_schedule_service.ScheduleConflict as e:
        raise HTTPException(status_code=409, detail=str(e)) from e
    if out is None:
        raise HTTPException(status_code=404, detail="일정을 찾을 수 없어요.")
    return out


@router.post(
    "/trainer/schedule/{session_id}/program/send",
    response_model=ScheduleSessionOut,
)
def trainer_send_session_program(
    session_id: str,
    payload: ScheduleProgramSendRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> ScheduleSessionOut:
    """완료한 세션의 프로그램을 그 회원에게 보낸다. (#822)

    수업을 마친 뒤 오늘 한 것을 회원 앱으로 넘기는 마지막 한 걸음이다. 배정
    자체는 코칭 탭의 프로그램 배정과 같은 경로를 타므로, 회원은 출처와 무관하게
    같은 모양의 루틴을 받는다. 같은 세션을 두 번 눌러도 배정은 한 번이다.
    """
    try:
        out = trainer_schedule_service.send_session_program(
            db, trainer.id, session_id,
            client_request_id=payload.client_request_id,
        )
    except trainer_common_service.ClientLinkDetached as e:
        raise HTTPException(status_code=404, detail=str(e)) from e
    except trainer_schedule_service.ScheduleError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
    if out is None:
        raise HTTPException(status_code=404, detail="일정을 찾을 수 없어요.")
    return out
