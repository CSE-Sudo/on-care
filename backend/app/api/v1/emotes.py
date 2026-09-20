"""채팅 이모티콘 이용권. (#2020)

고르는 창이 열릴 때 상태를 한 번 읽고(`GET /me/emotes`), 사는 것은 한 경로다
(`POST /me/emotes/pass`). MY 탭의 포인트 사용처에서도 같은 항목(`emote_pass_24h`)을
교환할 수 있고, 그쪽은 `POST /me/points/exchange` 가 이 서비스로 넘긴다.
"""
from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.api.deps import RequireMember
from app.db.session import get_db
from app.schemas.emote_api import EmotePassBuyRequest, EmoteStateOut
from app.services import emote_service, points_service

router = APIRouter(tags=["emotes"])


@router.get("/me/emotes", response_model=EmoteStateOut, response_model_by_alias=True)
def my_emotes(
    member: RequireMember,
    db: Annotated[Session, Depends(get_db)],
) -> EmoteStateOut:
    """이용권 상태·값·잔액. 이모티콘 목록은 앱이 들고 있다."""
    return emote_service.state(db, member.id)


@router.post(
    "/me/emotes/pass", response_model=EmoteStateOut, response_model_by_alias=True
)
def buy_pass(
    payload: EmotePassBuyRequest,
    member: RequireMember,
    db: Annotated[Session, Depends(get_db)],
) -> EmoteStateOut:
    """포인트로 24시간 이용권을 산다."""
    try:
        return emote_service.buy(
            db, member.id, client_request_id=payload.client_request_id
        )
    except emote_service.PassAlreadyActive as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    except points_service.InsufficientPoints as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
