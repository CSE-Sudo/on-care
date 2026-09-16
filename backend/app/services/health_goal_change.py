"""건강 목표 변경 기록과 상대 알림. (#1832)

건강 목표(`HealthProfile.conditions` 의 목표 칩)는 회원(온보딩·MY)과 담당
트레이너(트레이너 웹 회원 신체·목표 창)가 **같은 칸**을 함께 고친다(#1814, #1818).

서로 승인을 받게 하면 담당 트레이너가 없는 회원은 확인해 줄 사람이 없고, 승인 전에는
권장치·트레이너 추천·AI 루틴이 어느 목표를 따라야 할지 애매해진다. 그래서 바꾸면
**바로 적용하고, 상대에게 알리고, 누가 언제 바꿨는지 남긴다.**

목표 칩이 실제로 바뀐 저장에만 기록한다. 주의사항 글이나 수치 목표만 고친 저장,
같은 목표를 순서만 바꿔 다시 보낸 저장은 목표 변경이 아니다 — 그런 저장마다 알림이
가면 상대는 곧 알림을 읽지 않게 된다.

호출부의 트랜잭션에 얹는다(커밋하지 않는다). 기록과 알림이 목표 저장과 함께
성사되어야, 목표는 바뀌었는데 알림만 없는 반쪽 상태가 생기지 않는다.
"""
from __future__ import annotations

import uuid

from sqlalchemy.orm import Session

from app.core import clock
from app.models.models import HealthProfile, Notification, User
from app.services import health_focus, notification_service
from app.services.trainer_service import get_member_trainer_id

CHANGED_BY_MEMBER = "member"
CHANGED_BY_TRAINER = "trainer"

#: 알림 본문에서 목표를 모두 비웠을 때 쓰는 말.
NO_FOCUS_LABEL = "목표 없음"


def focus_changed(before: str | None, after: str | None) -> bool:
    """두 `conditions` 가 가리키는 건강 목표 **집합**이 다른가.

    주의사항 글은 보지 않고, 목표의 순서도 보지 않는다.
    """
    return set(health_focus.focus_in(before)) != set(health_focus.focus_in(after))


def _label(conditions: str | None) -> str:
    return health_focus.focus_label(conditions) or NO_FOCUS_LABEL


def _stamp(profile: HealthProfile, changed_by: str, actor_id: str) -> None:
    profile.focus_changed_by = changed_by
    profile.focus_changed_by_id = actor_id
    profile.focus_changed_at = clock.now()


def record_member_change(
    db: Session, profile: HealthProfile, *, before: str | None, member: User
) -> bool:
    """회원이 저장한 뒤 부른다. 목표가 바뀌었으면 기록하고 담당 트레이너에게 알린다.

    담당 트레이너가 없으면 기록만 남긴다. 바뀌었으면 True.
    """
    if not focus_changed(before, profile.conditions):
        return False
    _stamp(profile, CHANGED_BY_MEMBER, member.id)
    trainer_id = get_member_trainer_id(db, member.id)
    if trainer_id is not None:
        notification_service.queue_for_trainer(
            db,
            trainer_id=trainer_id,
            kind=notification_service.TRAINER_HEALTH_GOAL_KIND,
            title="회원 건강 목표 변경",
            body=f"{member.name} 회원이 건강 목표를 바꿨어요: {_label(profile.conditions)}",
            subject_id=member.id,
        )
    return True


def record_trainer_change(
    db: Session,
    profile: HealthProfile,
    *,
    before: str | None,
    trainer: User,
    member_id: str,
) -> bool:
    """트레이너가 회원 목표를 저장한 뒤 부른다. 바뀌었으면 기록하고 회원에게 알린다.

    회원 알림은 수신 설정을 보지 않는다 — 내 목표가 남의 손으로 바뀐 사실은 끌 수
    있는 알림이 아니다(상담 결과 알림과 같은 이유). 바뀌었으면 True.
    """
    if not focus_changed(before, profile.conditions):
        return False
    _stamp(profile, CHANGED_BY_TRAINER, trainer.id)
    db.add(
        Notification(
            id=f"noti-{uuid.uuid4().hex[:12]}",
            user_id=member_id,
            title="건강 목표가 바뀌었어요",
            body=f"{trainer.name} 트레이너님이 건강 목표를 바꿨어요: {_label(profile.conditions)}",
            category=notification_service.MEMBER_HEALTH_GOALS,
            read=False,
            subject_id=member_id,
        )
    )
    return True
