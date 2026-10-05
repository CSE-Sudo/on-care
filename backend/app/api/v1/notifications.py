"""
알림 라우터 — 프론트 계약 정렬.

  GET  /notifications              -> 최신순 배열 (time_ago 포함, 기본 50건·커서)
  POST /notifications/{id}/read    -> 읽음 처리

회원 알림 수신 설정(GET/PUT /users/me/notification-settings)도 여기 둔다 — 알림을
만드는 일과 끄는 일은 같은 도메인이다. (#489)
"""
from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select, tuple_, update
from sqlalchemy.orm import Session

from app.api.deps import CurrentUser, RequireMember
from app.core.locale import Locale, RequestLocale, localized
from app.core.pagination import DEFAULT_PAGE, MAX_PAGE, parse_before
from app.db.seed_notifications import (
    DEMO_AGO_BY_ID,
    demo_time_ago,
    slide_demo_notifications,
)
from app.db.session import get_db
from app.models.models import Notification
from app.schemas.misc_api import NotificationAction, NotificationOut
from app.schemas.user import (
    MemberNotificationSettings,
    MemberNotificationSettingsUpdate,
)
from app.services import (
    notification_service,
    notification_templates,
    points_coupon_service,
    weekly_challenge_service,
)

router = APIRouter(tags=["notifications"])

# 알림 카테고리 → 바로가기 액션(프론트 라우트 힌트). system 은 액션 없음.
#
# 라벨은 (한국어, 영어) 쌍이다(#2302). 저장되는 값이 아니라 응답마다 만드는 말이라
# 요청 언어(`Accept-Language`)로 고른다. 헤더가 없으면 한국어 — 예전과 같다.
_ACTION_BY_CATEGORY: dict[str, tuple[str, str, str]] = {
    # 성격만 나타내던 기존 값들.
    "reminder": ("기록하러 가기", "Log now", "dashboard"),
    "health_check": ("기록하러 가기", "Log now", "dashboard"),
    "achievement": ("대시보드 보기", "View dashboard", "dashboard"),
    # 트레이너가 한 일 — 예전에는 전부 `system` 으로 뭉쳐 갈 곳이 없었다(#636).
    notification_service.MEMBER_COACH_CHAT: ("대화 보기", "View chat", "coach_chat"),
    # 주간 리포트 — 리포트 카드가 있는 코치 대화로 간다. 메시지와 목적지는 같고
    # 알림함 아이콘만 다르다(#2085).
    notification_service.MEMBER_COACH_REPORT: ("리포트 보기", "View report", "coach_chat"),
    notification_service.MEMBER_ROUTINE: ("운동 보기", "View workouts", "exercise"),
    # PT 일정 등록·변경·취소·인계, 담당 해제·트레이너 탈퇴로 취소된 일정(#3028).
    # 운동 탭이 트레이너 일정과 회원 예약을 합친 다음 PT 배지와 헬스장 패널의 예약
    # 목록을 함께 보여 주는 곳이다. 예전에는 회원 앱에 일정을 볼 자리가 없어(#1928)
    # 액션을 달지 않았고, 일정 알림만 눌러도 아무 화면이 열리지 않았다.
    notification_service.MEMBER_SCHEDULE: ("일정 보기", "View schedule", "exercise"),
    # PT 완료·피드백 도착 — 운동 탭의 PT 기록(완료 PT 카드와 피드백)(#3027).
    notification_service.MEMBER_PT_DONE: ("PT 기록 보기", "View PT record", "exercise"),
    notification_service.MEMBER_COACH_INVITE: ("요청 확인", "View request", "exercise"),
    notification_service.MEMBER_CONSULTATION: ("트레이너 보기", "View trainer", "exercise"),
    # 상담 요청의 승인·거절·만료 — 결과와 사유가 있는 내 상담 요청(#2067).
    notification_service.MEMBER_CONSULTATION_DECISION: (
        "상담 요청 보기", "View consultation requests", "consultations"
    ),
    # 쿠폰 사용 처리·취소·만료 임박 — MY 의 내 혜택으로 간다(#1787).
    notification_service.MEMBER_BENEFITS: ("내 혜택 보기", "View my benefits", "my_benefits"),
    # 주간 챌린지 결과 — 포인트 사용처로 간다(#1789).
    notification_service.MEMBER_POINTS_SHOP: (
        "포인트 사용처 보기", "View points shop", "points_shop"
    ),
    # 담당 트레이너가 건강 목표를 바꿨다 — 바뀐 목표를 확인하는 MY 건강 목표(#1832).
    notification_service.MEMBER_HEALTH_GOALS: ("목표 보기", "View goals", "health_goals"),
}


#: 알림별 목적지(`Notification.action_target`, #2690)의 라벨. 갈래별 표와 목적지가
#: 같으면 그 라벨을 쓰고, 여기 없는 목적지는 "보기" 다.
_LABEL_BY_TARGET: dict[str, tuple[str, str]] = {
    "diet": ("식단 보기", "View diet"),
    "exercise": ("운동 보기", "View workouts"),
    "dashboard": ("홈 보기", "View home"),
    "coach_chat": ("대화 보기", "View chat"),
}


def _action_for(
    category: str, locale: Locale = "ko", target: str | None = None
) -> NotificationAction | None:
    """알림의 행동 유도. [target] 이 있으면 그 목적지, 없으면 갈래별 표다(#2690)."""
    entry = _ACTION_BY_CATEGORY.get(category)
    if target:
        if entry is not None and entry[2] == target:
            ko, en = entry[0], entry[1]
        else:
            ko, en = _LABEL_BY_TARGET.get(target, ("보기", "View"))
        return NotificationAction(label=localized(ko, en, locale), target=target)
    if entry is None:
        return None
    ko, en, target = entry
    return NotificationAction(label=localized(ko, en, locale), target=target)


def notification_out(row: Notification, locale: Locale) -> NotificationOut:
    """회원 알림 한 건의 응답. 제목·본문·라벨은 요청 언어다(#2302).

    제목·본문은 저장된 문장 틀을 요청 언어로 조립한다. 한국어이거나 틀이 없는 옛
    알림이면 저장된 문장 그대로다(`notification_templates.localize`).
    """
    title, body = notification_templates.localize(
        title=row.title, body=row.body, template=row.template,
        template_args=row.template_args, locale=locale,
    )
    # 데모 계정 알림은 회원 앱 데모처럼 정해 둔 시각으로 보인다(#2691).
    demo_ago = DEMO_AGO_BY_ID.get(row.id)
    return NotificationOut(
        id=row.id, title=title, body=body, category=row.category,
        read=row.read, created_at=row.created_at,
        time_ago=(
            demo_time_ago(demo_ago, locale)
            if demo_ago is not None
            else _time_ago(row.created_at, locale)
        ),
        action=_action_for(row.category, locale, row.action_target),
        invite_id=row.invite_id,
        template=row.template, args=row.template_args,
    )


#: 회원·트레이너 알림함이 같은 문구를 써야 해서 서비스로 옮겼다. (#503)
_time_ago = notification_service.time_ago


@router.get("/notifications", response_model=list[NotificationOut])
def list_notifications(
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
    locale: RequestLocale,
    limit: int = Query(
        DEFAULT_PAGE, ge=1, le=MAX_PAGE, description="한 번에 가져올 최신 알림 수"
    ),
    before: str | None = Query(
        None, description="ISO datetime 커서(다음 쪽) — 받은 마지막 알림의 created_at"
    ),
    before_id: str | None = Query(
        None, description="복합 커서 tie-break — 받은 마지막 알림의 id"
    ),
) -> list[NotificationOut]:
    """내 알림(최신순, 기본 50건). 다음 쪽은 커서로 이어 받는다. (#965)

    상한이 없던 시절에는 계정을 오래 쓸수록 알림 탭을 열 때마다 응답이 선형으로
    커졌다 — 알림을 만드는 훅은 여럿인데 지우는 경로가 없었기 때문이다.

    커서는 채팅 스레드와 같은 모양이다(`GET /me/coach/chat`): 받은 마지막 알림의
    `(created_at, id)` 를 `(before, before_id)` 로 넘긴다. 같은 `created_at` 이
    여러 건이어도 경계에서 빠지거나 겹치지 않도록 복합 커서를 쓴다 — 알림은 훅
    하나가 여러 건을 한 트랜잭션에 넣기도 해서 동시각이 실제로 나온다.

    파라미터 없이 부르면 최신 50건이다. 기존 클라이언트는 그대로 동작한다.

    제목·본문·액션 라벨은 요청 언어(`Accept-Language`)로 준다(#2302). 헤더가 없으면
    한국어 — 저장된 문장 그대로다.

    읽기 전에 만료가 3일 이내로 다가온 쿠폰의 알림을 만든다(#1787). 주기 작업이
    없어, 회원이 알림함을 여는 순간이 알림이 생기는 시점이다. 쿠폰마다 한 번뿐이고,
    만들지 못해도 알림 목록은 그대로 준다.
    """
    try:
        if points_coupon_service.remind_expiring(db, current_user.id):
            db.commit()
    except Exception:  # noqa: BLE001 — 만료 알림 실패가 알림함을 막지 않는다
        db.rollback()
    # 끝난 주의 챌린지 결과 알림도 같은 이유로 여기서 생긴다(#1789).
    weekly_challenge_service.settle_quietly(db, current_user.id)
    # 데모 계정 알림은 날이 바뀌면 오늘로 옮긴다 — 회원 앱 데모와 같다(#2691).
    try:
        slide_demo_notifications(db, current_user.id)
    except Exception:  # noqa: BLE001 — 옮기지 못해도 알림 목록은 그대로 준다
        db.rollback()
    query = select(Notification).where(Notification.user_id == current_user.id)
    cursor = parse_before(before)
    if cursor is not None:
        if before_id is not None:
            query = query.where(
                tuple_(Notification.created_at, Notification.id) < (cursor, before_id)
            )
        else:
            query = query.where(Notification.created_at < cursor)
    rows = db.scalars(
        query.order_by(Notification.created_at.desc(), Notification.id.desc())
        .limit(limit)
    ).all()
    return [notification_out(r, locale) for r in rows]


@router.get(
    "/users/me/notification-settings",
    response_model=MemberNotificationSettings,
)
def get_notification_settings(
    user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> MemberNotificationSettings:
    """회원 알림 수신 설정. 저장한 적이 없으면 기본값을 준다. (#489)

    전에는 앱이 SharedPreferences 에만 저장해 기기를 바꾸면 초기화됐고, 서버가
    설정을 몰라 알림을 만들 때 끌 수도 없었다.
    """
    return MemberNotificationSettings(
        **_settings_payload(notification_service.get_settings(db, user.id))
    )


@router.put(
    "/users/me/notification-settings",
    response_model=MemberNotificationSettings,
)
def update_notification_settings(
    payload: MemberNotificationSettingsUpdate,
    user: RequireMember,
    db: Annotated[Session, Depends(get_db)],
) -> MemberNotificationSettings:
    """보낸 항목만 반영한다."""
    fields = {
        f"notif_{name}": value
        for name, value in payload.model_dump(exclude_none=True).items()
    }
    updated = notification_service.update_settings(db, user.id, fields)
    return MemberNotificationSettings(**_settings_payload(updated))


def _settings_payload(settings: dict[str, bool]) -> dict[str, bool]:
    """서비스의 `notif_*` 키를 응답 필드 이름으로 옮긴다."""
    return {key.removeprefix("notif_"): value for key, value in settings.items()}


@router.get("/notifications/unread-count", response_model=dict)
def unread_count(
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> dict:
    """미확인 알림 수(배지용)."""
    return {"unread": notification_service.unread_count(db, current_user.id)}


@router.post("/notifications/read-all")
def mark_all_read(
    current_user: RequireMember,
    db: Annotated[Session, Depends(get_db)],
) -> dict:
    """내 미확인 알림을 모두 읽음 처리."""
    result = db.execute(
        update(Notification)
        .where(Notification.user_id == current_user.id, Notification.read.is_(False))
        .values(read=True)
    )
    db.commit()
    return {"marked_read": result.rowcount or 0}


@router.post("/notifications/{notification_id}/read", status_code=200)
def mark_read(
    notification_id: str,
    current_user: RequireMember,
    db: Annotated[Session, Depends(get_db)],
) -> dict:
    row = db.scalar(select(Notification).where(Notification.id == notification_id))
    if row is None or row.user_id != current_user.id:
        raise HTTPException(status_code=404, detail="알림을 찾을 수 없어요.")
    row.read = True
    db.commit()
    return {"id": notification_id, "read": True}


@router.delete("/notifications/{notification_id}")
def delete_notification(
    notification_id: str,
    current_user: RequireMember,
    db: Annotated[Session, Depends(get_db)],
) -> dict:
    """알림 삭제(본인 소유만)."""
    row = db.scalar(select(Notification).where(Notification.id == notification_id))
    if row is None or row.user_id != current_user.id:
        raise HTTPException(status_code=404, detail="알림을 찾을 수 없어요.")
    db.delete(row)
    db.commit()
    return {"status": "deleted"}
