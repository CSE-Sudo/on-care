"""채팅 이모티콘 — 하나씩 사서 7일 동안 쓴다. (#2153)

고르는 창이 열릴 때 상태를 한 번 읽고(`GET /me/emotes`), 이모티콘 하나를 사는 것은
`POST /me/emotes/{emote_id}/unlock` 이다. 포인트 사용처에서는 팔지 않는다 — 무엇을
사는지는 고르는 자리에서 봐야 알 수 있다.
"""
from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.api.deps import RequireMember
from app.db.session import get_db
from app.schemas.emote_api import EmoteStateOut, EmoteUnlockRequest
from app.services import emote_service, points_service

router = APIRouter(tags=["emotes"])

# 409·400 을 앱이 문구로 나누는 코드. 같은 409 라도 "이미 열려 있음" 과 "담당 없음" 은
# 회원에게 할 말이 다르다. (#2845)
ALREADY_UNLOCKED_CODE = "already_unlocked"
TRAINER_REQUIRED_CODE = "trainer_required"
INSUFFICIENT_POINTS_CODE = "insufficient_points"


@router.get("/me/emotes", response_model=EmoteStateOut)
def my_emotes(
    member: RequireMember,
    db: Annotated[Session, Depends(get_db)],
) -> EmoteStateOut:
    """쓰고 있는 이모티콘·값·잔액. 이모티콘 목록은 앱이 들고 있다."""
    return emote_service.state(db, member.id)


@router.post("/me/emotes/{emote_id}/unlock", response_model=EmoteStateOut)
def unlock_emote(
    emote_id: str,
    payload: EmoteUnlockRequest,
    member: RequireMember,
    db: Annotated[Session, Depends(get_db)],
) -> EmoteStateOut:
    """포인트로 이모티콘 하나를 7일 동안 연다."""
    try:
        return emote_service.unlock(
            db, member.id, emote_id, client_request_id=payload.client_request_id
        )
    except emote_service.UnknownEmote as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except emote_service.TrainerRequired as exc:
        raise HTTPException(
            status_code=409,
            detail={"code": TRAINER_REQUIRED_CODE, "message": str(exc)},
        ) from exc
    except emote_service.AlreadyUnlocked as exc:
        # 응답을 못 받고 다른 키로 다시 산 경우도 여기 온다 — 앱은 실패가 아니라
        # "이미 열려 있음" 으로 안내한다. (#2845)
        raise HTTPException(
            status_code=409,
            detail={"code": ALREADY_UNLOCKED_CODE, "message": str(exc)},
        ) from exc
    except points_service.InsufficientPoints as exc:
        raise HTTPException(
            status_code=400,
            detail={"code": INSUFFICIENT_POINTS_CODE, "message": str(exc)},
        ) from exc
