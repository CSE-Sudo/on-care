"""트레이너 라우터 — 내 계정(프로필·소속 헬스장·비밀번호·탈퇴·알림 설정)."""
from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import (
    APIRouter,
    Depends,
    HTTPException,
    Query,
    Request,
)
from sqlalchemy.orm import Session
from starlette.concurrency import run_in_threadpool

from app.api.deps import RequireTrainer
from app.core.rate_limit import PasswordChangeGuard, rate_limit
from app.core.security import hash_password, verify_password
from app.db.session import get_db
from app.models.models import (
    AccountDeletionReason,
)
from app.schemas.user import AccountDeleteRequest, PasswordChanged
from app.schemas.trainer_api import (
    TrainerGymAffiliation, TrainerGymCandidate, TrainerGymProfileOut,
    TrainerGymProfileUpdate, TrainerKakaoGymSelect,
    TrainerMe, TrainerMeUpdate,
    TrainerNotificationSettings, TrainerNotificationSettingsUpdate,
    TrainerPasswordChange,
)
from app.services import (
    audit,
    auth_tokens,
    reauth,
    data_consent_service,
    attachment_cleanup,
    trainer_gym_search,
)
from app.services.trainer import gym as trainer_gym_service
from app.services.trainer import notification_settings as trainer_notification_settings_service
from app.services.trainer import profile as trainer_profile_service
from app.api.v1.trainer._common import (
    _require_profile,
)


router = APIRouter(tags=["trainer"])


@router.get("/trainer/me", response_model=TrainerMe)
def trainer_me(
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> TrainerMe:
    profile = _require_profile(db, trainer.id)
    return trainer_profile_service.build_trainer_me(db, trainer, profile)


@router.put("/trainer/me", response_model=TrainerMe)
def trainer_update_me(
    payload: TrainerMeUpdate,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> TrainerMe:
    """프로필 부분 수정. 보낸 필드만 반영하고, 이름/이메일은 계정 소관이라 건드리지 않는다."""
    profile = _require_profile(db, trainer.id)
    fields = payload.model_dump(exclude_unset=True)
    if not fields:
        # 빈 PATCH 를 성공으로 처리하면 클라이언트가 저장됐다고 오해한다.
        raise HTTPException(status_code=400, detail="수정할 항목이 없어요.")
    try:
        return trainer_profile_service.update_trainer_profile(db, trainer, profile, fields)
    except trainer_profile_service.GymTextNotEditable as e:
        # 값이 틀린 게 아니라 헬스장 정보가 소속에서만 파생되는 것과 충돌하는 것이라
        # 422 가 아니라 409.
        raise HTTPException(
            status_code=409,
            detail="헬스장 정보는 직접 수정할 수 없어요. "
                   "헬스장을 검색해 소속을 설정해 주세요.",
        ) from e


@router.put("/trainer/me/gym", response_model=TrainerMe)
def trainer_set_gym(
    payload: TrainerGymAffiliation,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> TrainerMe:
    """소속 헬스장 설정·변경. (#452)

    시드(`seed_gyms`)의 이름 매칭 백필 말고는 `gym_id` 를 채울 길이 없었다. 자기
    프로필만 바꿀 수 있고(`RequireTrainer` 가 토큰의 트레이너로 고정), 실재하는
    fitness Place 가 아니면 404 다.
    """
    profile = _require_profile(db, trainer.id)
    me = trainer_gym_service.set_trainer_gym(db, trainer, profile, payload.gym_id)
    if me is None:
        raise HTTPException(status_code=404, detail="헬스장을 찾을 수 없어요.")
    return me


@router.get("/trainer/gyms/search", response_model=list[TrainerGymCandidate])
async def trainer_search_gyms(
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
    query: str = Query(min_length=1, max_length=100, description="헬스장 이름·주소"),
    lat: float | None = Query(None, ge=-90, le=90, description="거리순 정렬용 위도"),
    lng: float | None = Query(None, ge=-180, le=180),
) -> list[TrainerGymCandidate]:
    """소속으로 고를 헬스장 검색. (#2543)

    등록된 헬스장을 먼저, 카카오에서 찾은 헬스장을 뒤에 싣는다. 카카오 키가 없거나
    호출이 실패하면 등록된 헬스장만 나온다.
    """
    if (lat is None) != (lng is None):
        raise HTTPException(status_code=422, detail="lat 과 lng 는 함께 보내야 해요.")
    q = query.strip()
    if not q:
        raise HTTPException(status_code=422, detail="검색어를 입력하세요.")
    return await trainer_gym_search.search(db, q, lat, lng)


@router.get("/trainer/gyms/nearby", response_model=list[TrainerGymCandidate])
async def trainer_nearby_gyms(
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
    lat: float = Query(ge=-90, le=90, description="트레이너의 현재 위도"),
    lng: float = Query(ge=-180, le=180, description="트레이너의 현재 경도"),
) -> list[TrainerGymCandidate]:
    """현재 위치 주변의 소속 후보 헬스장 — 가까운 순. (#3223)

    `trainer_gym_search.NEARBY_RADIUS_M` 안의 등록 헬스장과 카카오 결과를 합친다.
    고르는 길은 이름 검색 결과와 같다(`registered` 로 갈린다). 좌표는 이 요청의
    거리 계산에만 쓰고 저장하지 않는다.
    """
    return await trainer_gym_search.nearby(db, lat, lng)


@router.put("/trainer/me/gym/kakao", response_model=TrainerMe)
async def trainer_set_kakao_gym(
    payload: TrainerKakaoGymSelect,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> TrainerMe:
    """카카오 검색 결과로 소속 설정. 처음 고른 헬스장은 이때 `places` 에 들어간다. (#2543)

    서버가 카카오를 다시 검색해 확인하므로, 헬스장이 아니거나 찾을 수 없으면 404,
    카카오를 쓸 수 없으면 503 이다. 동기 DB 조회는 스레드풀에서 한다(#2835).
    """
    profile = await run_in_threadpool(_require_profile, db, trainer.id)
    try:
        me = await trainer_gym_search.select_kakao_gym(
            db, trainer, profile, payload.kakao_place_id, payload.name.strip()
        )
    except trainer_gym_search.GymLookupUnavailable as e:
        raise HTTPException(
            status_code=503, detail="지금은 헬스장을 확인할 수 없어요. 잠시 뒤 다시 시도해 주세요."
        ) from e
    if me is None:
        raise HTTPException(status_code=404, detail="헬스장을 찾을 수 없어요.")
    return me


_NO_GYM_DETAIL = "소속 헬스장이 없습니다. 헬스장을 먼저 설정하세요."


@router.get("/trainer/me/gym/profile", response_model=TrainerGymProfileOut)
def trainer_gym_profile(
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> TrainerGymProfileOut:
    """소속 헬스장의 영업시간·전화·태그. 소속이 없으면 409. (#2700)"""
    profile = _require_profile(db, trainer.id)
    try:
        return trainer_gym_service.get_trainer_gym_profile(db, profile)
    except trainer_gym_service.NoGymAffiliation as e:
        raise HTTPException(status_code=409, detail=_NO_GYM_DETAIL) from e


@router.put("/trainer/me/gym/profile", response_model=TrainerGymProfileOut)
def trainer_update_gym_profile(
    payload: TrainerGymProfileUpdate,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> TrainerGymProfileOut:
    """소속 헬스장의 영업시간·전화·태그 부분 수정. (#2700)

    소속 트레이너 누구나 고칠 수 있고 마지막 저장이 남는다. 소속이 없으면 409 —
    값이 틀린 게 아니라 고칠 헬스장이 없는 상태라서다. 평점은 받지 않는다(422).
    같은 헬스장 소속 트레이너 모두의 `gym.hours`·`gym.phone` 이 함께 바뀐다.
    """
    profile = _require_profile(db, trainer.id)
    fields = payload.model_dump(exclude_unset=True)
    if not fields:
        raise HTTPException(status_code=400, detail="수정할 항목이 없습니다.")
    try:
        return trainer_gym_service.update_trainer_gym_profile(db, profile, fields)
    except trainer_gym_service.NoGymAffiliation as e:
        raise HTTPException(status_code=409, detail=_NO_GYM_DETAIL) from e


@router.delete("/trainer/me/gym", response_model=TrainerMe)
def trainer_clear_gym(
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> TrainerMe:
    """소속 해제. 원래 소속이 없어도 200 — 해제는 두 번 눌러도 오류가 아니다.

    갱신된 프로필을 그대로 돌려주므로 클라이언트가 다시 GET 하지 않아도 된다.
    """
    profile = _require_profile(db, trainer.id)
    return trainer_gym_service.clear_trainer_gym(db, trainer, profile)


@router.post(
    "/trainer/me/password",
    status_code=200,
    response_model=PasswordChanged,
    dependencies=[Depends(rate_limit("trainer-password-change"))],
)
def trainer_change_password(
    request: Request,
    payload: TrainerPasswordChange,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> PasswordChanged:
    """비밀번호 변경. 현재 비밀번호가 맞아야 하고, 같은 값으로는 바꿀 수 없다.

    바꾸면 계정의 토큰 세대가 올라가 **다른 기기에 이미 나간 접근·refresh 토큰이
    모두 무효**가 된다(#2766) — 비밀번호를 바꾸는 이유는 대개 누가 계정을 쓰고
    있을지 모른다는 의심이다. 요청한 기기는 응답에 담긴 새 토큰으로 이어 쓴다.

    시도 제한(#2913): IP 한도에 더해 **계정 단위 실패 잠금**을 건다. 접근 토큰을
    손에 넣은 쪽이 현재 비밀번호를 맞혀 보면, 맞히는 순간 다른 기기 토큰까지 끊고
    계정을 가져간다. 로그인 잠금과 같은 창(`login_lockout_seconds`) 안에
    `password_change_max_failures` 번 틀리면 남은 시간 동안 429 이고, 틀린 시도는
    감사 로그에 남는다. 시도는 비밀번호 확인보다 먼저 세고 맞으면 지운다(#3238) —
    동시 요청도 한도만큼만 확인에 들어간다.
    """
    guard = PasswordChangeGuard(trainer.id)
    guard.claim()
    if not verify_password(payload.current_password, trainer.hashed_password):
        audit.record(
            db,
            event=audit.PASSWORD_CHANGE,
            user_id=trainer.id,
            ip=audit.client_ip(request),
            success=False,
            detail="current_password_mismatch",
        )
        # 현재 비밀번호 불일치는 401 이 아니라 400 — 토큰은 유효하므로
        # 클라이언트가 로그아웃 처리로 오인하면 안 된다.
        raise HTTPException(status_code=400, detail="현재 비밀번호가 일치하지 않아요.")
    guard.clear()
    if verify_password(payload.new_password, trainer.hashed_password):
        raise HTTPException(status_code=400, detail="현재와 다른 비밀번호를 입력해 주세요.")
    trainer.hashed_password = hash_password(payload.new_password)
    # 비밀번호와 세대는 한 트랜잭션으로 — 하나만 반영되면 옛 토큰이 살아남거나
    # 비밀번호는 그대로인데 모든 기기가 끊긴다.
    auth_tokens.bump_version(trainer)
    # 변경 사실만 남긴다(#2830) — 비밀번호와 같은 트랜잭션이라 둘 중 하나만 남지 않는다.
    audit.stage(
        db,
        event=audit.PASSWORD_CHANGE,
        user_id=trainer.id,
        ip=audit.client_ip(request),
    )
    db.commit()
    tokens = auth_tokens.issue_token_pair(trainer)
    return PasswordChanged(
        access_token=tokens.access_token, refresh_token=tokens.refresh_token
    )


#: 트레이너 탈퇴 화면이 보여 주는 사유(#2264). 회원 사유(`DELETION_REASONS`)와 같은
#: 표에 남기되 `trainer_` 를 붙여 섞이지 않게 한다 — 표에는 누가 썼는지 없으니
#: 코드만으로 회원·트레이너를 가를 수 있어야 한다. 모르는 값은 버린다.
TRAINER_DELETION_REASONS: frozenset[str] = frozenset(
    {
        "rarely_used",
        "hard_to_use",
        "missing_feature",
        "leaving_work",
        "found_alternative",
        "other",
    }
)


@router.delete("/trainer/me")
def trainer_delete_me(
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
    request: Request,
    payload: AccountDeleteRequest | None = None,
) -> dict:
    """트레이너 탈퇴. 담당 회원에게 알린 뒤 계정과 딸린 데이터를 지운다. (#505)

    회원 탈퇴(`DELETE /users/me`)와 대칭이다. 담당 회원이 남아 있어도 막지 않는다 —
    막으면 담당이 있는 트레이너는 계정을 영영 지울 수 없다.

    고른 사유가 있으면 회원 탈퇴와 같은 표에 계정과 잇지 않고 남긴다(#2264).
    사유는 없어도 된다 — 탈퇴를 막는 조건이 아니라 물어보는 자리다.
    본인 확인은 늘 필요하다(#3039, 회원 탈퇴와 같은 `services/reauth.py`). 예전
    화면의 "이름 입력" 확인은 화면 안의 실수 방지일 뿐 서버는 보지 않았다.
    """
    reauth.require(
        db,
        trainer,
        action=reauth.DELETE_ACCOUNT,
        ip=audit.client_ip(request),
        current_password=payload.current_password if payload else None,
        social_provider=payload.social_provider if payload else None,
        social_token=payload.social_token if payload else None,
    )
    for reason in sorted(
        set(payload.reasons if payload else []) & TRAINER_DELETION_REASONS
    ):
        db.add(
            AccountDeletionReason(
                id=f"del-{uuid.uuid4().hex[:12]}",
                reason=f"trainer_{reason}",
            )
        )
    # 동의 종료·탈퇴를 감사 기록으로 남긴다 — 삭제와 같은 트랜잭션이다(#2830).
    data_consent_service.stage_account_withdrawal(
        db, trainer, ip=audit.client_ip(request)
    )
    # 채팅 첨부의 바이트는 DB 밖에 있어 CASCADE 가 닿지 않는다 — 행이 사라지기
    # 전에 목록을 잡아 두고, 탈퇴 커밋이 끝난 뒤에 지운다(#2817).
    attachments = attachment_cleanup.files_in_threads(db, trainer_id=trainer.id)
    trainer_profile_service.delete_trainer_account(db, trainer)
    attachment_cleanup.purge(attachments)
    return {"status": "deleted"}


@router.get("/trainer/me/settings", response_model=TrainerNotificationSettings)
def trainer_settings(
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> TrainerNotificationSettings:
    """알림 수신 설정. 기본값은 서버가 소유한다 — 클라이언트마다 기본값을
    들고 있으면 기기별로 갈라진다."""
    return trainer_notification_settings_service.build_notification_settings(
        _require_profile(db, trainer.id)
    )


@router.put("/trainer/me/settings", response_model=TrainerNotificationSettings)
def trainer_update_settings(
    payload: TrainerNotificationSettingsUpdate,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> TrainerNotificationSettings:
    """알림 수신 설정 부분 수정."""
    fields = payload.model_dump(exclude_unset=True)
    if not fields:
        raise HTTPException(status_code=400, detail="수정할 항목이 없어요.")
    return trainer_notification_settings_service.update_notification_settings(
        db, _require_profile(db, trainer.id), fields
    )
