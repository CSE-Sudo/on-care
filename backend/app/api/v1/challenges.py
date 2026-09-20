"""
주간 운동 챌린지 라우터 — 이번 주 상태·참가·내 챌린지. (#1789)

  GET  /me/challenges/weekly        -> 이번 주 챌린지와 참가 가능 여부
  POST /me/challenges/weekly/join   -> 201 { challenge, spent, balance }
  GET  /me/challenges               -> 챌린지 배열(최근 주 먼저)

읽기는 CurrentUser(데모 폴백 허용), 쓰기는 RequireMember 다 — 포인트 사용처와
같은 규약이다. 지난 주 판정은 읽기·참가 경로가 먼저 한다(스케줄러 없음).
"""
from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.api.deps import CurrentUser, RequireMember
from app.db.session import get_db
from app.schemas.challenge_api import (
    ChallengeJoinOut,
    ChallengeJoinRequest,
    ChallengeOut,
    WeeklyChallengeOut,
)
from app.services import points_service, weekly_challenge_service

router = APIRouter(tags=["challenges"])


@router.get("/me/challenges/weekly", response_model=WeeklyChallengeOut)
def weekly_challenge(
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> WeeklyChallengeOut:
    """이번 주 챌린지·진행과 참가 가능 여부. 막힌 이유와 모자란 포인트를 함께 준다."""
    return weekly_challenge_service.weekly_state(db, current_user.id)


@router.post(
    "/me/challenges/weekly/join", response_model=ChallengeJoinOut, status_code=201
)
def join_weekly_challenge(
    member: RequireMember,
    db: Annotated[Session, Depends(get_db)],
    payload: ChallengeJoinRequest | None = None,
) -> ChallengeJoinOut:
    """이번 주 챌린지에 참가한다. 내역에는 `spend`(challenge_stake)로 남는다.

    월·화요일이 아니거나, 이번 주에 이미 참가했거나, 잔액이 모자라면 409 다.
    """
    try:
        return weekly_challenge_service.join(
            db,
            member.id,
            client_request_id=payload.client_request_id if payload else None,
        )
    except points_service.InsufficientPoints as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    except weekly_challenge_service.ChallengeError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@router.get("/me/challenges", response_model=list[ChallengeOut])
def my_challenges(
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> list[ChallengeOut]:
    """내 챌린지(최근 주 먼저, 최대 20). 읽기 전에 끝난 주를 판정한다."""
    return weekly_challenge_service.list_challenges(db, current_user.id)
