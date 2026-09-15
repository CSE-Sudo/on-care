"""
회원측 트레이너 미러 — 회원 앱이 '내 담당 코치'와 상호작용하는 엔드포인트.

트레이너 앱(#251/#252)이 쓰는 것과 같은 공유 테이블(ChatMessage, TrainerRoutine,
TrainerSchedule, TrainerClient)을 회원 관점으로 읽고 쓴다. 이로써 트레이너↔회원
상호작용이 양방향으로 닫힌다(트레이너 발신→회원 수신, 회원 발신→트레이너 로스터 반영).

읽기는 CurrentUser(회원, 데모 폴백 허용, 트레이너 토큰 403)로, 쓰기는 RequireMember
(엄격, 트레이너 계정 차단)로 보호한다.
"""
from __future__ import annotations

from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.api.deps import CurrentUser, RequireMember
from app.db.session import get_db
from app.schemas.exercise_api import AssignedRoutineCompleteRequest
from app.schemas.trainer_api import (
    ChatMessageOut, ChatSendRequest, MemberClientInviteOut,
    MemberCoachOut, MemberInviteAcceptRequest, RoutineCompleteOut, RoutineOut,
    ScheduleSessionOut,
)
from app.services import trainer_client_invite_service, trainer_service

router = APIRouter(tags=["member-coach"])


def _my_trainer_or_404(db: Session, member_id: str) -> str:
    trainer_id = trainer_service.get_member_trainer_id(db, member_id)
    if trainer_id is None:
        raise HTTPException(status_code=404, detail="담당 트레이너가 없습니다.")
    return trainer_id


@router.get("/me/coach", response_model=MemberCoachOut)
def my_coach(
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> MemberCoachOut:
    """내 담당 트레이너 요약."""
    coach = trainer_service.build_member_coach(db, current_user.id)
    if coach is None:
        raise HTTPException(status_code=404, detail="담당 트레이너가 없습니다.")
    return coach


@router.delete("/me/coach", status_code=204)
def disconnect_my_coach(
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> None:
    """코치 관계 전체 해제 — MY 탭의 **헬스장** 휴지통.

    `GET /me/coach` 가 트레이너와 헬스장을 함께 돌려주듯, 이 삭제도 둘 다 끊는다.
    떠난 헬스장의 트레이너를 담당으로 남길 수는 없기 때문이다. 트레이너만 끊으려면
    `DELETE /me/coach/trainer` 를 쓴다. (#444)

    이미 연결이 없으면 404 가 아니라 204 다. 해제는 멱등이어야 하고, 두 번 눌렀다고
    오류 화면을 보일 이유가 없다.
    """
    trainer_service.disconnect_member_gym(db, current_user.id)


@router.delete("/me/coach/trainer", status_code=204)
def disconnect_my_trainer(
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> None:
    """담당 트레이너만 해제 — 헬스장 연결은 남는다. MY 탭의 **트레이너** 휴지통.

    헬스장은 그대로 두고 담당만 바꾸는 흐름(트레이너 교체)이 있어야 하므로 전체
    해제와 나눈다. 전체 해제와 마찬가지로 멱등이다. (#444)
    """
    trainer_service.disconnect_member_coach(db, current_user.id)


@router.get("/me/coach/routines", response_model=list[RoutineOut])
def my_routines(
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> list[RoutineOut]:
    """트레이너/AI가 나에게 배정한 루틴."""
    return trainer_service.build_member_routines(db, current_user.id)


@router.post(
    "/me/coach/routines/{routine_id}/complete",
    response_model=RoutineCompleteOut,
)
def complete_my_routine(
    routine_id: str,
    payload: AssignedRoutineCompleteRequest,
    member: RequireMember,
    db: Annotated[Session, Depends(get_db)],
) -> RoutineCompleteOut:
    """나에게 배정된 루틴을 회원 운동 기록으로 한 번만 완료한다.

    AI 추천 루틴이면 포인트 적립 결과(`points`)가 함께 온다(#1786).
    """
    # intensity 는 AssignedRoutineCompleteRequest 의 Literal 에서 422 로 걸린다.
    # 담당 트레이너가 없는 회원도 AI 자동 추천을 수행한다(#782). 예전에는 여기서
    # 404 로 끊겨, 화면에 보이는 운동을 완료할 수 없었다.
    trainer_id = trainer_service.get_member_trainer_id(db, member.id)
    try:
        return trainer_service.complete_assigned_routine(
            db,
            trainer_id,
            member.id,
            routine_id,
            minutes=payload.minutes,
            sets=payload.sets,
            reps=payload.reps,
            weight=payload.weight,
            intensity=payload.intensity,
            member_note=payload.member_note,
        )
    except trainer_service.RoutineNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.delete(
    "/me/coach/routines/{routine_id}/complete",
    response_model=RoutineOut,
)
def uncomplete_my_routine(
    routine_id: str,
    member: RequireMember,
    db: Annotated[Session, Depends(get_db)],
) -> RoutineOut:
    """완료 표시를 되돌린다 — 그 배정으로 남은 운동 기록을 지운다. (#1131)

    체크를 잘못 눌렀을 때 되돌릴 방법이 없으면, 하지 않은 운동이 주간 시간·
    칼로리에 그대로 남는다. 배정 자체는 지우지 않는다 — 지우는 것은 `수행`이지
    `할 일`이 아니다.
    """
    trainer_id = trainer_service.get_member_trainer_id(db, member.id)
    try:
        return trainer_service.uncomplete_assigned_routine(
            db, trainer_id, member.id, routine_id
        )
    except trainer_service.RoutineNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.delete("/me/coach/routines/{routine_id}", status_code=204)
def delete_my_routine(
    routine_id: str,
    member: RequireMember,
    db: Annotated[Session, Depends(get_db)],
) -> None:
    """내 개인 운동 취소. **담당 트레이너가 없을 때만.** (#1020)

    담당이 있는 회원에게는 취소가 트레이너의 일이다 — 트레이너가 배정한 것을
    회원이 조용히 없애면 다음 상담에서 둘이 서로 다른 기록을 본다. 그 경우는
    403 이다(404 가 아니라): 루틴은 분명히 있고 회원 화면에도 보인다.
    """
    try:
        trainer_service.delete_own_routine(db, member.id, routine_id)
    except trainer_service.RoutineNotCancellable as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    except trainer_service.RoutineNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.get("/me/coach/sessions", response_model=list[ScheduleSessionOut])
def my_sessions(
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> list[ScheduleSessionOut]:
    """내 PT 세션(담당 트레이너 스케줄에서 나와 매칭된 것), 최신순."""
    return trainer_service.build_member_sessions(db, current_user.id)


@router.get("/me/coach/chat", response_model=list[ChatMessageOut])
def my_chat(
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
    limit: int = Query(50, ge=1, le=100),
    before: str | None = Query(None, description="ISO datetime 커서(이전 페이지, 응답 created_at)"),
    before_id: str | None = Query(None, description="복합 커서 tie-break — 이전 페이지 가장 오래된 id"),
) -> list[ChatMessageOut]:
    """담당 트레이너와의 채팅(오래된→최신). 발신자는 회원 관점(me|trainer)."""
    trainer_id = _my_trainer_or_404(db, current_user.id)
    before_dt: datetime | None = None
    if before:
        try:
            before_dt = datetime.fromisoformat(before)
        except ValueError as e:
            raise HTTPException(status_code=422, detail="before 는 ISO datetime 이어야 합니다.") from e
    return trainer_service.build_chat_thread(
        db, trainer_id, current_user.id,
        limit=limit, before=before_dt, before_id=before_id, viewer="member",
    )


@router.get("/me/coach/chat/unread", response_model=dict)
def my_unread(
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> dict:
    """트레이너가 보낸 미확인 메시지 수."""
    trainer_id = trainer_service.get_member_trainer_id(db, current_user.id)
    count = trainer_service.member_unread_count(db, trainer_id, current_user.id) if trainer_id else 0
    return {"unread": count}


@router.post("/me/coach/chat", response_model=ChatMessageOut, status_code=201)
def send_to_coach(
    payload: ChatSendRequest,
    member: RequireMember,
    db: Annotated[Session, Depends(get_db)],
) -> ChatMessageOut:
    """회원이 담당 트레이너에게 메시지 발신(트레이너 로스터 last_message 에 자동 반영)."""
    trainer_id = _my_trainer_or_404(db, member.id)
    text = payload.text.strip()
    if not text:
        raise HTTPException(status_code=400, detail="빈 메시지는 보낼 수 없습니다.")
    try:
        return trainer_service.send_message(
            db,
            trainer_id,
            member.id,
            "member",
            text,
            viewer="member",
            client_request_id=payload.client_request_id,
        )
    except trainer_service.IdempotencyConflict as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@router.post("/me/coach/chat/read")
def mark_coach_chat_read(
    member: RequireMember,
    db: Annotated[Session, Depends(get_db)],
) -> dict:
    """담당 트레이너 스레드를 읽음 처리(트레이너 발신 메시지)."""
    trainer_id = _my_trainer_or_404(db, member.id)
    n = trainer_service.mark_thread_read(db, trainer_id, member.id, "member")
    return {"marked_read": n}


# ---------------------------------------------------------------------------
# 트레이너가 보낸 담당 요청 — 회원이 수락해야 담당이 생긴다. (#919)
#
# 상담 요청(회원 → 트레이너)의 반대 방향이다. 담당 관계는 내 식단·건강 기록을
# 여는 권한이라, 트레이너가 명단에 밀어 넣는 것이 아니라 내가 수락한다.
# ---------------------------------------------------------------------------


@router.get("/me/coach/invites", response_model=list[MemberClientInviteOut])
def my_coach_invites(
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> list[MemberClientInviteOut]:
    """나에게 온 대기 중인 담당 요청."""
    return trainer_client_invite_service.list_for_member(db, current_user.id)


@router.post(
    "/me/coach/invites/{invite_id}/accept", response_model=MemberClientInviteOut
)
def accept_coach_invite(
    invite_id: str,
    payload: MemberInviteAcceptRequest,
    member: RequireMember,
    db: Annotated[Session, Depends(get_db)],
) -> MemberClientInviteOut:
    """수락한다 — 담당 링크가 여기서 생긴다.

    데이터 공유 동의를 함께 받는다. 수락하는 순간 트레이너가 회원의 식단·운동·
    신체 정보를 읽으므로, 그 문을 여는 동작과 동의가 같은 요청이어야 한다. (#1022)
    """
    try:
        return trainer_client_invite_service.accept(
            db,
            member.id,
            invite_id,
            data_sharing_consent=payload.data_sharing_consent,
        )
    except trainer_client_invite_service.DataSharingConsentRequired as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except trainer_client_invite_service.InviteNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except (
        trainer_client_invite_service.InviteAlreadyDecided,
        trainer_client_invite_service.MemberAlreadyCoached,
    ) as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@router.post(
    "/me/coach/invites/{invite_id}/reject", response_model=MemberClientInviteOut
)
def reject_coach_invite(
    invite_id: str,
    member: RequireMember,
    db: Annotated[Session, Depends(get_db)],
) -> MemberClientInviteOut:
    """거절한다. 담당 링크는 만들지 않는다."""
    try:
        return trainer_client_invite_service.reject(db, member.id, invite_id)
    except trainer_client_invite_service.InviteNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except trainer_client_invite_service.InviteAlreadyDecided as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
