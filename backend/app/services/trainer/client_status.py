"""트레이너 도메인 — 회원 활성/휴면 관리 상태와 담당 해제. (#707)"""
from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.models.models import (
    TrainerClient, User,
)
from app.schemas.trainer_api import (
    TrainerClientStatusOut,
)
from app.services import (
    data_consent_service,
    diet_coach_inputs,
    diet_trainer_pick,
    notification_service,
    notification_templates,
    points_coupon_service,
)
from app.services.trainer._common import (
    ClientLinkDetached,
    _cancel_sessions_on_detach,
    _roster_active,
)


# ---- 회원 활성/휴면 관리 상태 (#707) ----


class ClientConsentRequired(Exception):
    """회원이 데이터 공유 동의를 철회한 링크를 트레이너 혼자 되살리려 했다. (#1631)

    재등록 라우트에서 409 로 옮긴다. 다시 담당이 되려면 회원이 동의하는 경로
    (담당 요청 수락·상담·연결 코드)를 지나야 한다.
    """


def remove_client(db: Session, link: TrainerClient) -> None:
    """담당 목록에서만 제거하고 회원이 보는 공유 데이터는 보존한다.

    관계 행이 사라지면 트레이너의 고객 기반 화면과 권한에서 제외된다. 스케줄,
    프로그램·루틴, 리포트, PT 이력과 대화 원본은 삭제하지 않는다. 회원 운동 기록에
    적재된 PT 는 회원 앱에 계속 보이고, 코치 채팅·일정은 같은 트레이너와 다시
    연결하면 다시 보인다(`build_member_*` 는 활성 담당 기준이다).

    담당이 끝나므로 회원의 PT 재등록 쿠폰을 취소하고 포인트를 돌려준다(#1787).

    트레이너가 끊어도 담당 해제는 데이터 공유 동의 철회다(#1631) — 동의를 비우고
    철회 시각을 남긴다. 이미 주고받은 기록은 위와 같이 그대로 둔다. 회원 메모도
    출처와 상관없이 남기고 `_require_client` 가 열람만 막는다(#2520) — 회원의 새
    동의로 다시 이어져야 다시 보인다.

    아직 시작하지 않은 PT 는 취소하고(#2589), 회원에게는 해제 사실과 취소한
    일정 수를 알림 한 건으로 알린다 — 일정마다 알리면 반복 PT 수만큼 쏟아진다.
    """
    link.active = False
    data_consent_service.revoke(link, by=data_consent_service.BY_TRAINER)
    cancelled = _cancel_sessions_on_detach(
        db, link.trainer_id, link.member_id, source="trainer"
    )
    trainer_name = db.scalar(select(User.name).where(User.id == link.trainer_id))
    notification_service.queue(
        db,
        member_id=link.member_id,
        kind=notification_service.PT_LINK_NOTICE,
        # 취소된 일정이 있으면 일정으로, 없으면 새 트레이너를 찾는 화면으로.
        category=(
            notification_service.MEMBER_SCHEDULE
            if cancelled
            else notification_service.MEMBER_CONSULTATION
        ),
        template=notification_templates.MEMBER_TRAINER_DISCONNECTED,
        template_args={
            "trainer_name": (trainer_name or "").strip(),
            "cancelled_sessions": cancelled,
        },
    )
    points_coupon_service.cancel_renewal_coupons(db, link.member_id)
    # 이 트레이너가 확정해 둔 식단 추천도 내린다(#2378) — 담당이 끝난 트레이너의
    # 추천이 회원 홈에 남으면 안 된다.
    diet_trainer_pick.clear(db, link.member_id, link.trainer_id)
    # 끊은 트레이너의 메시지로 만든 식단 AI 조언·추천 메뉴를 내려놓는다(#1631).
    diet_coach_inputs.forget_trainer_notes(db, link.member_id)
    db.commit()


def restore_client(db: Session, link: TrainerClient) -> None:
    """과거 담당 관계를 다시 등록 상태로 전환한다.

    동의가 철회된 링크는 되살리지 않는다(#1631) — 회원이 끊은 관계를 트레이너가
    혼자 되돌리면 회원은 동의하지 않은 트레이너에게 다시 묶인다.
    [ClientConsentRequired] 다.
    """
    if link.active:
        return
    if data_consent_service.blocks_access(link):
        raise ClientConsentRequired(
            "회원이 데이터 공유 동의를 철회했습니다. 담당 요청을 보내 회원의 동의를 다시 받아 주세요."
        )
    occupied = db.scalar(
        select(TrainerClient.id).where(
            TrainerClient.member_id == link.member_id,
            TrainerClient.active.is_(True),
        )
    )
    if occupied is not None:
        raise ClientLinkDetached("이미 다른 트레이너가 담당 중인 회원입니다.")
    link.active = True
    link.dormant = False
    try:
        db.commit()
    except IntegrityError:
        # 위 조회와 커밋 사이에 다른 복구·담당 요청 수락이 먼저 들어왔다 —
        # 회원당 활성 담당 1명 부분 유일 인덱스(`uq_trainer_client_active_member`)
        # 에 걸린 것이다. 500 대신 조회로 막았을 때와 같은 409 로 옮긴다(#2911).
        db.rollback()
        raise ClientLinkDetached(
            "이미 다른 트레이너가 담당 중인 회원입니다."
        ) from None


def set_client_active(
    db: Session, link: TrainerClient, active: bool
) -> TrainerClientStatusOut:
    """담당 회원을 활성/휴면으로 전환한다.

    `dormant` 만 건드린다 — 담당 링크(`active`)·루틴·기록·식단·채팅은 그대로다.
    휴면 회원도 조회·채팅·루틴 배정이 전부 그대로 되고, 회원 앱에서 코치가
    사라지지도 않는다. 트레이너의 관리 표시일 뿐이다.

    이미 같은 상태면 아무것도 쓰지 않고 그 상태를 돌려준다 — 연타나 재시도가
    상태를 흔들지 않는다(멱등).

    담당이 이미 해제된 링크는 [ClientLinkDetached] 다. 여기서 `dormant` 를
    내려 봐야 로스터는 계속 휴면으로 보이므로(`_roster_active`), 성공으로
    응답하면 화면이 "저장했는데 그대로"가 된다. 담당 재배정은 이 기능의 범위가
    아니다.
    """
    if not link.active:
        raise ClientLinkDetached("담당 관계가 해제된 회원입니다.")
    if link.dormant is not (not active):
        link.dormant = not active
        db.commit()
        db.refresh(link)
    return TrainerClientStatusOut(
        member_id=link.member_id, active=_roster_active(link)
    )
