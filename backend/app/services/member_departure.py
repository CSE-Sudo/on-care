"""담당 회원이 떠난 사실을 트레이너에게 알린다. (#2174)

회원이 탈퇴하거나 담당 트레이너·헬스장 연결을 끊으면 트레이너 회원 목록에서 바로
사라진다. 알림이 없으면 트레이너는 한 명이 조용히 빠진 이유를 알 길이 없다.

**담당이 끊기기 전에** 불러야 한다. 담당 트레이너를 찾는 기준이 활성 링크라, 해제나
탈퇴 뒤에는 누구에게 알릴지 알 수 없다. 커밋하지 않는다 — 해제·탈퇴와 같은
트랜잭션에 얹어, 해제는 됐는데 알림만 없는 반쪽 상태가 생기지 않게 한다.
"""
from __future__ import annotations

from typing import Literal

from sqlalchemy.orm import Session

from app.models.models import User
from app.services import notification_service
from app.services.trainer_service import get_member_trainer_id

Reason = Literal["withdrawn", "disconnected"]

_TITLES: dict[str, str] = {
    "withdrawn": "회원 탈퇴",
    "disconnected": "담당 연결 해제",
}
_BODIES: dict[str, str] = {
    "withdrawn": "{name} 회원이 탈퇴했어요.",
    "disconnected": "{name} 회원이 담당 연결을 끊었어요.",
}


def notify_trainer(db: Session, member: User, *, reason: Reason) -> bool:
    """담당 트레이너에게 회원이 떠났다고 알린다. 알렸으면 True.

    담당 트레이너가 없으면 아무것도 하지 않는다 — 헬스장만 연결된 회원이 헬스장을
    끊는 경우, 이미 해제한 연결을 한 번 더 끊는 경우가 그렇다.

    회원 id 를 `subject_id` 로 남기지 않는다. 떠난 회원의 상세는 트레이너가 더 열 수
    없어, 이 알림은 이동하지 않고 확인만 한다.
    """
    trainer_id = get_member_trainer_id(db, member.id)
    if trainer_id is None:
        return False
    name = (member.name or "").strip() or "이름 없는"
    notification_service.queue_for_trainer(
        db,
        trainer_id=trainer_id,
        kind=notification_service.TRAINER_MEMBER_LEFT_KIND,
        title=_TITLES[reason],
        body=_BODIES[reason].format(name=name),
    )
    return True
