"""트레이너 라우터 — 알림함. (#503)"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Annotated

from fastapi import (
    APIRouter,
    Depends,
    HTTPException,
    Query,
    Response,
)
from sqlalchemy import func, select, update
from sqlalchemy.orm import Session

from app.api.deps import RequireTrainer
from app.core.locale import Locale, RequestLocale
from app.core.pagination import parse_before
from app.db.session import get_db
from app.models.models import (
    Notification,
)
from app.schemas.trainer_api import (
    TrainerNotificationOut,
)
from app.services import (
    notification_service,
    notification_templates,
)


router = APIRouter(tags=["trainer"])


#: 트레이너 알림함 다음 쪽 커서를 싣는 응답 헤더(#2293). 본문은 전과 같은 배열로
#: 두어 기존 클라이언트가 그대로 읽고, 다음 쪽이 있을 때만 두 헤더가 붙는다.
#: 값은 쿼리 `before`·`before_id` 에 그대로 되돌려 준다. 브라우저(트레이너 웹)가
#: 읽을 수 있게 CORS `expose_headers` 에도 올린다(`app/main.py`).
NEXT_BEFORE_HEADER = "X-Next-Before"


NEXT_BEFORE_ID_HEADER = "X-Next-Before-Id"


# ---- 알림함 (#503) ----
#
# 회원용 `/notifications` 를 재사용할 수 없다 — `get_current_user` 가 트레이너
# 계정을 403 으로 막는 **회원 전용** 경로다(역할 분리). 저장되는 행은 같은
# `notifications` 테이블이고 `user_id` 가 일반 사용자 FK라 스키마 변경은 없다.


def _notification_out(row: Notification, locale: Locale) -> TrainerNotificationOut:
    """트레이너 알림 한 건. 제목·본문은 요청 언어로 조립한다(#2302).

    트레이너 웹은 `template`·`args` 로 ARB 문장을 직접 조립하고, 모르는 틀일 때만
    `title`·`body` 를 쓴다. 그 값도 요청 언어라, 새 틀을 아직 모르는 빌드도 알맞은
    언어로 보인다. 한국어이거나 틀이 없는 옛 알림은 저장된 문장 그대로다.
    """
    title, body = notification_templates.localize(
        title=row.title,
        body=row.body,
        template=row.template,
        template_args=row.template_args,
        locale=locale,
    )
    return TrainerNotificationOut(
        id=row.id,
        title=title,
        body=body,
        category=row.category,
        read=row.read,
        created_at=row.created_at,
        time_ago=notification_service.time_ago(row.created_at, locale),
        subject_id=row.subject_id,
        template=row.template,
        args=row.template_args,
        target_date=row.target_date,
    )


def _cursor_value(moment: datetime) -> str:
    """커서 헤더에 싣는 시각. `parse_before` 가 그대로 읽는 ISO 형식(UTC)이다."""
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=timezone.utc)
    return moment.astimezone(timezone.utc).isoformat()


@router.get("/trainer/notifications", response_model=list[TrainerNotificationOut])
def trainer_notifications(
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
    locale: RequestLocale,
    response: Response,
    limit: int = Query(
        notification_service.TRAINER_PAGE_DEFAULT,
        ge=1,
        le=notification_service.TRAINER_PAGE_MAX,
        description="한 번에 가져올 최신 알림 수",
    ),
    before: str | None = Query(
        None, description="ISO datetime 커서(다음 쪽) — 받은 마지막 알림의 created_at"
    ),
    before_id: str | None = Query(
        None, description="복합 커서 tie-break — 받은 마지막 알림의 id"
    ),
) -> list[TrainerNotificationOut]:
    """트레이너가 받은 알림 한 쪽(최신순). 다음 쪽은 커서로 이어 받는다. (#2293)

    파라미터 없이 부르면 전처럼 최신 100건이다. 다음 쪽이 있으면
    `X-Next-Before`·`X-Next-Before-Id` 헤더에 커서가 실리고, 없으면 두 헤더가
    없다 — 그게 마지막 쪽이라는 뜻이다.

    미읽음 배지(`/trainer/notifications/unread-count`)와 모두 읽음은 쪽 나눔과
    무관하게 이 트레이너의 알림 전체를 대상으로 한다.
    """
    cursor = parse_before(before)
    if before_id is not None and cursor is None:
        # tie-break 만 오면 어디서 자를지 알 수 없다. 조용히 첫 쪽을 주면
        # 클라이언트가 같은 알림을 다시 이어 붙인다.
        raise HTTPException(
            status_code=422, detail="before_id 는 before 와 함께 보내야 합니다."
        )
    rows, last = notification_service.list_for_trainer(
        db, trainer.id, limit=limit, before=cursor, before_id=before_id
    )
    if last is not None:
        response.headers[NEXT_BEFORE_HEADER] = _cursor_value(last.created_at)
        response.headers[NEXT_BEFORE_ID_HEADER] = last.id
    return [_notification_out(row, locale) for row in rows]


@router.get("/trainer/notifications/unread-count", response_model=dict)
def trainer_unread_notifications(
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> dict:
    """사이드바 배지가 읽는 값."""
    count = db.scalar(
        select(func.count())
        .select_from(Notification)
        .where(Notification.user_id == trainer.id, Notification.read.is_(False))
    )
    return {"unread": int(count or 0)}


@router.post("/trainer/notifications/read-all")
def trainer_read_all_notifications(
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> dict:
    marked = db.execute(
        update(Notification)
        .where(Notification.user_id == trainer.id, Notification.read.is_(False))
        .values(read=True)
    ).rowcount
    db.commit()
    return {"marked_read": int(marked or 0)}


@router.post("/trainer/notifications/{notification_id}/read")
def trainer_read_notification(
    notification_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> dict:
    row = db.scalar(
        select(Notification).where(
            Notification.id == notification_id,
            # 남의 알림은 존재조차 드러내지 않는다.
            Notification.user_id == trainer.id,
        )
    )
    if row is None:
        raise HTTPException(status_code=404, detail="알림을 찾을 수 없습니다.")
    row.read = True
    db.commit()
    return {"id": row.id, "read": True}
