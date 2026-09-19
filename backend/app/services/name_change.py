"""이름을 바꾼 사실을 상대에게 한 번 알린다. (#2065)

알림은 만든 순간의 이름을 글자로 담는다(`Notification.title`·`body`). 그래서 이미
받은 알림은 **그때 이름으로 남고**, 이름을 바꾼 뒤의 알림부터 새 이름을 쓴다. 받은
순간의 기록이라 고쳐 쓰지 않는다. 대신 이름이 바뀌면 상대에게 알림을 하나 보내,
알림함에 남은 옛 이름과 목록의 새 이름을 잇는다.

지금은 회원 쪽만 있다. 트레이너는 이름을 바꿀 길이 아직 없다 — 트레이너 프로필
수정(`PUT /trainer/me`)은 이름을 받지 않고, 계정 수정(`PUT /users/me`)은 회원
전용이다. 트레이너 이름 수정을 열 때 같은 방식으로 담당 회원에게 알린다.
"""
from __future__ import annotations

from sqlalchemy.orm import Session

from app.models.models import User
from app.services import notification_service
from app.services.trainer_service import get_member_trainer_id


def record_member_rename(db: Session, member: User, *, before: str | None) -> bool:
    """회원이 이름을 바꿨으면 담당 트레이너에게 알린다. 알렸으면 True.

    **커밋하지 않는다** — 이름 저장과 같은 트랜잭션에 얹는다. 담당 트레이너가 없거나
    이름이 그대로면(앞뒤 공백만 다른 경우 포함) 아무것도 하지 않는다.
    """
    old = (before or "").strip()
    new = (member.name or "").strip()
    if not old or not new or old == new:
        return False
    trainer_id = get_member_trainer_id(db, member.id)
    if trainer_id is None:
        return False
    notification_service.queue_for_trainer(
        db,
        trainer_id=trainer_id,
        kind=notification_service.TRAINER_MEMBER_NAME_KIND,
        title="회원 이름 변경",
        body=f"{old} 회원이 이름을 바꿨어요: {new}",
        subject_id=member.id,
    )
    return True
