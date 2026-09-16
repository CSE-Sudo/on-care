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
from sqlalchemy import func, select, tuple_, update
from sqlalchemy.orm import Session

from app.api.deps import CurrentUser, RequireMember
from app.core.pagination import DEFAULT_PAGE, MAX_PAGE, parse_before
from app.db.session import get_db
from app.models.models import Notification
from app.schemas.misc_api import NotificationAction, NotificationOut
from app.schemas.user import (
    MemberNotificationSettings,
    MemberNotificationSettingsUpdate,
)
from app.services import notification_service, points_coupon_service

router = APIRouter(tags=["notifications"])

# 알림 카테고리 → 바로가기 액션(프론트 라우트 힌트). system 은 액션 없음.
_ACTION_BY_CATEGORY: dict[str, NotificationAction] = {
    # 성격만 나타내던 기존 값들.
    "reminder": NotificationAction(label="기록하러 가기", target="dashboard"),
    "health_check": NotificationAction(label="일정 보기", target="schedule"),
    "achievement": NotificationAction(label="대시보드 보기", target="dashboard"),
    # 트레이너가 한 일 — 예전에는 전부 `system` 으로 뭉쳐 갈 곳이 없었다(#636).
    notification_service.MEMBER_COACH_CHAT: NotificationAction(
        label="대화 보기", target="coach_chat"
    ),
    notification_service.MEMBER_ROUTINE: NotificationAction(
        label="운동 보기", target="exercise"
    ),
    notification_service.MEMBER_SCHEDULE: NotificationAction(
        label="일정 보기", target="schedule"
    ),
    notification_service.MEMBER_CONSULTATION: NotificationAction(
        label="트레이너 보기", target="exercise"
    ),
    # 쿠폰 사용 처리·취소·만료 임박 — MY 의 내 혜택으로 간다(#1787).
    notification_service.MEMBER_BENEFITS: NotificationAction(
        label="내 혜택 보기", target="my_benefits"
    ),
    # 담당 트레이너가 건강 목표를 바꿨다 — 바뀐 목표를 확인하는 MY 건강 목표(#1832).
    notification_service.MEMBER_HEALTH_GOALS: NotificationAction(
        label="목표 보기", target="health_goals"
    ),
}


def _action_for(category: str) -> NotificationAction | None:
    return _ACTION_BY_CATEGORY.get(category)


#: 회원·트레이너 알림함이 같은 문구를 써야 해서 서비스로 옮겼다. (#503)
_time_ago = notification_service.time_ago


@router.get("/notifications", response_model=list[NotificationOut])
def list_notifications(
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
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

    읽기 전에 만료가 3일 이내로 다가온 쿠폰의 알림을 만든다(#1787). 주기 작업이
    없어, 회원이 알림함을 여는 순간이 알림이 생기는 시점이다. 쿠폰마다 한 번뿐이고,
    만들지 못해도 알림 목록은 그대로 준다.
    """
    try:
        if points_coupon_service.remind_expiring(db, current_user.id):
            db.commit()
    except Exception:  # noqa: BLE001 — 만료 알림 실패가 알림함을 막지 않는다
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
    return [
        NotificationOut(
            id=r.id, title=r.title, body=r.body, category=r.category,
            read=r.read, created_at=r.created_at, time_ago=_time_ago(r.created_at),
            action=_action_for(r.category),
        )
        for r in rows
    ]


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
    n = db.scalar(
        select(func.count())
        .select_from(Notification)
        .where(Notification.user_id == current_user.id, Notification.read.is_(False))
    ) or 0
    return {"unread": n}


@router.post("/notifications/read-all")
def mark_all_read(
    current_user: CurrentUser,
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
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> dict:
    row = db.scalar(select(Notification).where(Notification.id == notification_id))
    if row is None or row.user_id != current_user.id:
        raise HTTPException(status_code=404, detail="알림을 찾을 수 없습니다.")
    row.read = True
    db.commit()
    return {"id": notification_id, "read": True}


@router.delete("/notifications/{notification_id}")
def delete_notification(
    notification_id: str,
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> dict:
    """알림 삭제(본인 소유만)."""
    row = db.scalar(select(Notification).where(Notification.id == notification_id))
    if row is None or row.user_id != current_user.id:
        raise HTTPException(status_code=404, detail="알림을 찾을 수 없습니다.")
    db.delete(row)
    db.commit()
    return {"status": "deleted"}
