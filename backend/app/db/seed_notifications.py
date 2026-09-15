"""데모 회원(김민수) 알림 시드 — 회원앱 데모 알림과 같은 목록. (#1812)

알림함은 트레이너와 이어진 서비스의 흐름(루틴 도착 · PT 일정 · 주간 리포트 · 기록
독려 · 달성)을 보여 주는 자리다. 예전 시드는 이전 타깃 문구(혈압 기록 · 건강검진
예약)였고 앱 데모와도 달라, 둘러보기와 실서버 데모 계정이 다른 알림함을 보였다.

갈래는 백엔드 알림 갈래다 — 목적지(`action.target`)는 `api/v1/notifications.py` 의
갈래별 표가 정한다. 회원앱 데모의 목적지와 같은 화면으로 이어지도록 고른다:
루틴 → 운동, 회원 일정 → 일정, 코치 채팅 → 트레이너 채팅.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from sqlalchemy import delete, select
from sqlalchemy.orm import Session

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


#: 최신순. 안 읽은 알림이 위에 몰려 목록형 알림함의 옅은 파랑 줄이 보인다.
DEMO_NOTIFICATIONS: tuple[DemoNotification, ...] = (
    DemoNotification(
        "noti-demo-1",
        "나트륨 섭취 주의",
        "점심 짬뽕으로 오늘 나트륨이 3,421mg까지 올랐어요. 물을 충분히 드세요.",
        "reminder",
        timedelta(minutes=10),
    ),
    DemoNotification(
        "noti-demo-2",
        "새 운동 루틴이 도착했어요",
        "김트레이너님이 내일 할 하체 루틴을 보냈어요.",
        notification_service.MEMBER_ROUTINE,
        timedelta(minutes=30),
    ),
    DemoNotification(
        "noti-demo-3",
        "PT 수업 완료",
        "오늘 18:00 김트레이너와 12회차 PT를 마쳤어요!",
        "achievement",
        timedelta(hours=1),
    ),
    DemoNotification(
        "noti-demo-4",
        "트레이너 피드백 도착",
        "마무리로 어깨 회전근개 스트레칭을 꼭 해주세요.",
        notification_service.MEMBER_COACH_CHAT,
        timedelta(hours=2),
    ),
    DemoNotification(
        "noti-demo-5",
        "내일 PT 일정이 있어요",
        "내일 18:00 김트레이너와 13회차 PT가 예정돼 있어요.",
        notification_service.MEMBER_SCHEDULE,
        timedelta(hours=3),
    ),
    DemoNotification(
        "noti-demo-6",
        "이번 주 리포트가 등록됐어요",
        "김트레이너님이 9월 2주차 리포트를 보냈어요.",
        notification_service.MEMBER_COACH_CHAT,
        timedelta(hours=5),
    ),
    DemoNotification(
        "noti-demo-7",
        "저녁 식단을 기록해 주세요",
        "오늘 저녁 식단이 아직 없어요. 사진 한 장이면 돼요.",
        "reminder",
        timedelta(hours=26),
        read=True,
    ),
    DemoNotification(
        "noti-demo-8",
        "7일 연속 기록 달성!",
        "일주일 동안 하루도 빠짐없이 식단을 기록했어요.",
        "achievement",
        timedelta(hours=27),
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
    DemoNotification(
        "noti-demo-10",
        "이번 주 운동 목표 80% 달성",
        "남은 이틀 동안 유산소 40분이면 목표를 채워요.",
        "achievement",
        timedelta(days=2),
        read=True,
    ),
)

#: 이전 시드(혈압 기록 · 건강검진 예약 · 운동 목표)의 id. 이미 시드된 데모 DB 에서
#: 이 행들을 걷어 내고 새 목록으로 바꾼다.
LEGACY_DEMO_NOTIFICATION_IDS: tuple[str, ...] = ("noti-1", "noti-2", "noti-3")


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
                created_at=base - item.ago,
            )
        )
    db.commit()
    return len(DEMO_NOTIFICATIONS)
