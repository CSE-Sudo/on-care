"""데모 회원(김민수) 알림 시드 — 회원앱 데모 알림과 같은 목록. (#1812)

알림함은 트레이너와 이어진 서비스의 흐름(루틴 도착 · PT · 주간 리포트 · 기록 독려 ·
운동 목표)을 보여 주는 자리다. 실서버가 만들지 않는 식단 알림(나트륨 주의 · 저녁 기록
독려)은 뺐다 — 데모에서 본 알림이 실서비스에서 오지 않으면 기능이 사라진 것으로
보인다(#2854). 문구의 수치와 사건은 데모 픽스처·목업(식단 · 운동 ·
트레이너 채팅)에 실제로 있는 것만 쓴다. 예전 시드는 이전 타깃 문구(혈압 기록 · 건강검진
예약)였고 앱 데모와도 달라, 둘러보기와 실서버 데모 계정이 다른 알림함을 보였다.

갈래는 백엔드 알림 갈래다 — 목적지(`action.target`)는 `api/v1/notifications.py` 의
갈래별 표가 정한다. 회원앱 데모의 목적지와 같은 화면으로 이어지도록 고른다:
루틴 → 운동, 코치 채팅·주간 리포트 → 트레이너 채팅. 회원앱 로컬 시드
(`frontend/flutter/lib/core/storage/seed_data.dart`)와 갈래도 같아야 알림함 아이콘이
같다(#2084·#2660).
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from sqlalchemy import delete, select, update
from sqlalchemy.orm import Session

from app.core.clock import SEOUL
from app.core.locale import Locale
from app.db.seed_trainer import TRAINER_NAME
from app.models import models
from app.services import notification_service


@dataclass(frozen=True)
class DemoNotification:
    """시드 알림 한 건. [ago] 만큼 과거에 만든 것으로 넣어 목록 순서와 `time_ago` 가 맞는다."""

    id: str
    title: str
    body: str
    category: str
    ago: timedelta
    read: bool = False
    #: 이 알림만의 목적지(#2690). 없으면 갈래별 표를 따른다. 회원 앱 데모 목록과
    #: 같은 곳으로 가도록 둔다 — 운동 목표·PT 는 운동.
    target: str | None = None


#: 최신순. 안 읽은 알림이 위에 몰려 목록형 알림함의 옅은 파랑 줄이 보인다.
DEMO_NOTIFICATIONS: tuple[DemoNotification, ...] = (
    DemoNotification(
        "noti-demo-3",
        "새 개인운동이 왔어요",
        f"{TRAINER_NAME} 트레이너님이 무릎 상태에 맞춰 걷기 위주 개인운동으로 조정해 보냈어요.",
        notification_service.MEMBER_ROUTINE,
        timedelta(minutes=30),
    ),
    DemoNotification(
        "noti-demo-4",
        "주간 리포트가 도착했어요",
        f"{TRAINER_NAME} 트레이너님이 주간 리포트를 보냈어요.",
        notification_service.MEMBER_COACH_REPORT,
        timedelta(minutes=45),
    ),
    DemoNotification(
        "noti-demo-5",
        "PT 수업 완료",
        f"오늘 18:00 {TRAINER_NAME} 트레이너와 12회차 PT를 마쳤어요!",
        # 실서버가 PT 완료 때 만드는 알림과 같은 갈래다(#3027). 목적지는 갈래별 표와
        # 같은 운동 탭이라 그대로 둔다(#2690 때 채운 값).
        notification_service.MEMBER_PT_DONE,
        timedelta(hours=1),
        target="exercise",
    ),
    DemoNotification(
        "noti-demo-6",
        "트레이너 피드백 도착",
        "마무리로 어깨 회전근개 스트레칭을 꼭 해주세요.",
        notification_service.MEMBER_COACH_CHAT,
        timedelta(hours=2),
    ),
    DemoNotification(
        "noti-demo-7",
        "이번 주 운동 목표까지 조금 남았어요",
        "저강도 유산소(걷기) 30분부터 채워 봐요.",
        "reminder",
        timedelta(hours=3),
        target="exercise",
    ),
    DemoNotification(
        "noti-demo-8",
        "식단 기록을 꾸준히 이어가고 있어요",
        "보름 넘게 하루도 빠짐없이 식단을 기록하고 있어요.",
        "achievement",
        timedelta(hours=26),
        read=True,
    ),
    DemoNotification(
        "noti-demo-9",
        "서비스 점검 안내",
        "내일 02:00~03:00 점검 예정입니다.",
        "system",
        timedelta(hours=28),
        read=True,
    ),
)

#: 이전 시드(혈압 기록 · 건강검진 예약 · 운동 목표)와 빠진 식단 알림(나트륨 주의 ·
#: 저녁 기록 독려, #2854)의 id. 이미 시드된 데모 DB 에서 이 행들을 걷어 낸다.
LEGACY_DEMO_NOTIFICATION_IDS: tuple[str, ...] = (
    "noti-1",
    "noti-2",
    "noti-3",
    "noti-demo-1",
    "noti-demo-2",
)


#: 갈래가 바뀐 데모 알림 → 예전 갈래(#3027). 이미 시드된 DB 에서 예전 갈래로 남은
#: 행만 새 갈래로 옮긴다 — 회원 앱 알림함 아이콘이 갈래로 정해진다.
_LEGACY_CATEGORY_BY_ID: dict[str, str] = {
    "noti-demo-5": "achievement",
}


def seed_demo_notifications(db: Session, user_id: str, *, now: datetime | None = None) -> int:
    """[user_id] 의 데모 알림을 채운다. 넣은 건수를 돌려준다(이미 있으면 0).

    멱등이다 — 새 목록의 첫 알림이 이미 있으면 아무것도 하지 않는다. 이전 시드 행은
    먼저 지운다. 트레이너 활동이 만든 실제 알림은 건드리지 않는다.
    """
    db.execute(
        delete(models.Notification).where(
            models.Notification.user_id == user_id,
            models.Notification.id.in_(LEGACY_DEMO_NOTIFICATION_IDS),
        )
    )
    if db.scalar(
        select(models.Notification.id).where(
            models.Notification.id == DEMO_NOTIFICATIONS[0].id
        )
    ):
        # 목적지 칸(#2690)이 생기기 전에 시드된 DB 도 데모 목적지를 갖게 한다.
        for item in DEMO_NOTIFICATIONS:
            if item.target is None:
                continue
            db.execute(
                update(models.Notification)
                .where(
                    models.Notification.id == item.id,
                    models.Notification.action_target.is_(None),
                )
                .values(action_target=item.target)
            )
        for item in DEMO_NOTIFICATIONS:
            legacy = _LEGACY_CATEGORY_BY_ID.get(item.id)
            if legacy is None:
                continue
            db.execute(
                update(models.Notification)
                .where(
                    models.Notification.id == item.id,
                    models.Notification.category == legacy,
                )
                .values(category=item.category)
            )
        db.commit()
        return 0
    base = now or datetime.now(timezone.utc)
    for item in DEMO_NOTIFICATIONS:
        db.add(
            models.Notification(
                id=item.id,
                user_id=user_id,
                title=item.title,
                body=item.body,
                category=item.category,
                read=item.read,
                action_target=item.target,
                created_at=base - item.ago,
            )
        )
    db.commit()
    return len(DEMO_NOTIFICATIONS)


#: 데모 알림 id → 정해 둔 경과 시간(#2691).
DEMO_AGO_BY_ID: dict[str, timedelta] = {n.id: n.ago for n in DEMO_NOTIFICATIONS}


def demo_time_ago(ago: timedelta, locale: Locale) -> str:
    """데모 알림의 상대 시각 — 회원 앱 데모와 같은 문구다(#2691).

    회원 앱 데모는 하루 지난 알림을 "어제" 로 보인다. 서버의 일반 문구
    (`notification_service.time_ago`)는 "1일 전" 이라, 데모 계정만 데모 문구를 따른다.
    """
    ko = locale == "ko"
    sec = ago.total_seconds()
    if sec < 60:
        return "방금" if ko else "just now"
    if sec < 3600:
        n = int(sec // 60)
        return f"{n}분 전" if ko else f"{n} min ago"
    if sec < 86400:
        n = int(sec // 3600)
        return f"{n}시간 전" if ko else f"{n} {'hour' if n == 1 else 'hours'} ago"
    n = int(sec // 86400)
    if n == 1:
        return "어제" if ko else "yesterday"
    return f"{n}일 전" if ko else f"{n} days ago"


def slide_demo_notifications(
    db: Session, user_id: str, *, now: datetime | None = None
) -> bool:
    """[user_id] 의 데모 알림을 오늘로 옮긴다. 옮겼으면 True. (#2691)

    시드는 한 번만 들어가 날이 지나면 "N일 전" 이 되고, 트레이너 활동이 만든 새
    알림보다 아래로 밀린다. 회원 앱 데모가 날마다 시드를 오늘로 옮기는 것처럼, 가장
    최근 데모 알림이 오늘(서울)이 아니면 모두 `now - ago` 로 옮긴다. 읽음은 회원이
    한 일이라 건드리지 않는다.
    """
    rows = db.scalars(
        select(models.Notification).where(
            models.Notification.user_id == user_id,
            models.Notification.id.in_(DEMO_AGO_BY_ID),
        )
    ).all()
    newest = next((r for r in rows if r.id == DEMO_NOTIFICATIONS[0].id), None)
    if newest is None:
        return False
    now = now or datetime.now(timezone.utc)
    created = newest.created_at
    if created.tzinfo is None:
        created = created.replace(tzinfo=timezone.utc)
    if created.astimezone(SEOUL).date() == now.astimezone(SEOUL).date():
        return False
    for row in rows:
        row.created_at = now - DEMO_AGO_BY_ID[row.id]
    db.commit()
    return True
