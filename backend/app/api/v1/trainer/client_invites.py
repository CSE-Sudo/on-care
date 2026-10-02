"""트레이너 라우터 — 담당 요청·연결 코드. (#919)"""
from __future__ import annotations

from typing import Annotated

from fastapi import (
    APIRouter,
    Depends,
    HTTPException,
    Query,
)
from sqlalchemy.orm import Session

from app.api.deps import RequireApprovedTrainer, RequireTrainer
from app.core.config import get_settings
from app.core.rate_limit import (
    check_key,
    rate_limit,
)
from app.db.session import get_db
from app.schemas.trainer_api import (
    PairedMemberOut,
    PairingCodeRedeem,
    TrainerClientInviteCreate, TrainerClientInviteOut,
)
from app.services import (
    member_pairing_service,
    trainer_client_invite_service,
)


router = APIRouter(tags=["trainer"])


# ---------------------------------------------------------------------------


def _check_pairing_attempt(trainer_id: str) -> None:
    """연결 코드 미리보기·사용의 트레이너 단위 한도. (#2815)

    IP 버킷(`pairing-redeem`)은 요청마다 주소를 바꾸면 갈라진다. 트레이너 계정은
    공개 가입이라 id 버킷 하나로도 부족해 하루 상한을 함께 둔다. 두 엔드포인트가
    같은 키를 쓴다 — 미리보기도 코드를 맞혀 보는 시도다.
    """
    settings = get_settings()
    check_key(
        f"pairing-redeem:trainer:{trainer_id}",
        settings.rate_limit_auth_per_minute,
    )
    check_key(
        f"pairing-redeem-day:trainer:{trainer_id}",
        settings.pairing_redeem_per_day,
        24 * 60 * 60.0,
    )


@router.post(
    "/trainer/pairing-code/preview",
    response_model=PairedMemberOut,
    dependencies=[Depends(rate_limit("pairing-redeem"))],
)
def trainer_preview_pairing_code(
    payload: PairingCodeRedeem,
    trainer: RequireApprovedTrainer,  # 승인 전 403(#2825)
    db: Annotated[Session, Depends(get_db)],
) -> PairedMemberOut:
    """코드가 가리키는 회원을 **연결하지 않고** 보여 준다. (#1634)

    여섯 자리를 잘못 누르면 남의 식단·건강 기록이 열린다. 되돌릴 수 없는
    사고라, 연결 전에 이름·성별·나이·목표를 눈으로 확인시킨다.

    코드를 태우지 않는다 — 확인하고 그만두는 것이 정상 흐름이고, 그때마다
    회원이 코드를 다시 띄워야 할 이유가 없다. 연결(`POST /trainer/pairing-code`)
    이 쓰는 순간에만 사라진다.

    소비와 같은 rate limit 버킷을 쓴다. 확인도 코드를 맞혀 보는 시도다. IP 버킷에
    더해 트레이너 id 버킷(분·하루)을 함께 건다(#2815) — IP 를 바꿔도 한 트레이너의
    시도는 한 곳에서 센다.
    """
    _check_pairing_attempt(trainer.id)
    try:
        return trainer_client_invite_service.preview_pairing_code(
            db, trainer.id, payload.code
        )
    except member_pairing_service.CodeNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except trainer_client_invite_service.MemberNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except trainer_client_invite_service.MemberAlreadyCoached as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@router.post(
    "/trainer/pairing-code",
    response_model=PairedMemberOut,
    dependencies=[Depends(rate_limit("pairing-redeem"))],
)
def trainer_redeem_pairing_code(
    payload: PairingCodeRedeem,
    trainer: RequireApprovedTrainer,  # 승인 전 403(#2825)
    db: Annotated[Session, Depends(get_db)],
) -> PairedMemberOut:
    """회원이 띄운 6자리 동기화 코드로 담당 관계를 **바로** 만든다. (#1634)

    담당 요청과 달리 회원의 수락을 기다리지 않는다. 코드를 발급해 불러 준 것이
    회원 본인이고 그 화면이 공유 범위를 말한다 — 이미 받은 동의를 한 번 더
    받을 이유가 없다.

    **코드가 맞는지만 확인하는 조회는 두지 않는다.** 소비하지 않는 확인이
    있으면 100만 조합을 훑을 수 있다. 이 호출 한 번이 확인이자 소비이고, 그
    위에 rate limit 이 얹힌다.

    코드가 틀렸는지·만료됐는지·이미 쓰였는지는 구분해 알려 주지 않는다(404).
    갈라 주면 어떤 코드가 존재하기는 했는지를 알려 주는 셈이다.
    """
    _check_pairing_attempt(trainer.id)
    try:
        return trainer_client_invite_service.redeem_pairing_code(
            db, trainer.id, payload.code
        )
    except member_pairing_service.CodeNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except trainer_client_invite_service.MemberNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except trainer_client_invite_service.MemberAlreadyCoached as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    except member_pairing_service.PairingError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc


@router.get("/trainer/client-invites", response_model=list[TrainerClientInviteOut])
def trainer_client_invites(
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
    status: str = Query("pending", pattern="^(pending|all)$"),
) -> list[TrainerClientInviteOut]:
    """내가 보낸 담당 요청."""
    return trainer_client_invite_service.list_sent(db, trainer.id, status=status)


@router.post(
    "/trainer/client-invites",
    response_model=TrainerClientInviteOut,
    status_code=201,
)
def create_trainer_client_invite(
    payload: TrainerClientInviteCreate,
    trainer: RequireApprovedTrainer,  # 승인 전 403(#2825)
    db: Annotated[Session, Depends(get_db)],
) -> TrainerClientInviteOut:
    """담당 요청을 보낸다. 명단에는 아직 아무것도 생기지 않는다."""
    try:
        return trainer_client_invite_service.invite(
            db, trainer.id, payload.member_id, payload.message
        )
    except trainer_client_invite_service.MemberNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except trainer_client_invite_service.NotAMember as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except (
        trainer_client_invite_service.MemberAlreadyCoached,
        trainer_client_invite_service.DuplicatePendingInvite,
    ) as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@router.delete("/trainer/client-invites/{invite_id}", status_code=200)
def cancel_trainer_client_invite(
    invite_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> dict:
    """보낸 요청을 거둬들인다."""
    try:
        trainer_client_invite_service.cancel(db, trainer.id, invite_id)
    except trainer_client_invite_service.InviteNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except trainer_client_invite_service.InviteAlreadyDecided as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    return {"status": "cancelled"}
