"""운영자 계정 정지·해제. (#3009)

인증 계층은 `users.is_active=False` 를 이미 401 로 막는다(`api/deps.py`, 로그인·
refresh 도 같다). 그런데 그 값을 끄는 경로가 없어 정지가 반쯤만 있었다. 여기서
운영자가 끄고 켠다.

정지하면:

- `is_active=False` 와 토큰 세대 올리기(`auth_tokens.bump_version`) — 다른 기기의
  접근·refresh 토큰까지 그 자리에서 무효가 된다. 다시 로그인할 수도 없다.
- 트레이너면 살아 있는 담당 관계를 모두 해제한다. 트레이너가 직접 담당을 해제할
  때와 같은 경로(`remove_client`)라 회원에게 담당 해제 알림이 가고, 아직 시작하지
  않은 PT 일정이 취소되고, PT 재등록 쿠폰이 환불된다.
- 트레이너가 보낸 대기 중 담당 요청을 거둔다 — 정지된 트레이너의 요청을 회원이
  수락해 새 관계가 생기면 안 된다.

해제는 계정만 되살린다. 담당 관계는 복구하지 않는다 — 해제가 곧 데이터 공유 동의
철회이므로(#1631) 회원의 새 동의가 있어야 다시 이어진다.

회원 계정도 정지할 수 있지만 그 회원의 담당 관계는 건드리지 않는다(회원 정지 UI 와
정책은 이 단계 밖이다). 운영자 자신과 다른 운영자는 정지할 수 없다 — 마지막 운영자가
스스로 잠기면 되살릴 사람이 없다.
"""
from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.models import TrainerClient, TrainerClientInvite, User
from app.schemas.admin_ops import AdminUserStatusOut
from app.services import auth_tokens
from app.services.trainer import client_status


class UserNotFound(Exception):
    """정지할 계정이 없다 — 404."""


class SuspensionNotAllowed(Exception):
    """자기 자신이나 다른 운영자를 정지하려 했다 — 409."""


def _out(user: User, *, released_clients: int = 0) -> AdminUserStatusOut:
    return AdminUserStatusOut(
        user_id=user.id,
        role=user.role,
        is_active=bool(user.is_active),
        released_clients=released_clients,
    )


def _require_user(db: Session, user_id: str) -> User:
    user = db.get(User, user_id)
    if user is None:
        raise UserNotFound("계정을 찾을 수 없습니다.")
    return user


def suspend(db: Session, user_id: str, *, admin_id: str) -> AdminUserStatusOut:
    """계정을 정지한다.

    이미 정지된 계정이면 토큰 세대를 다시 올리지 않는다. 트레이너의 남은 담당 정리만
    한 번 더 본다 — 앞선 정지가 정리 중간에 실패했으면 다시 눌러 마저 끝낸다. 남은
    것이 없으면 아무것도 바뀌지 않는다(멱등).
    """
    user = _require_user(db, user_id)
    if user.id == admin_id or user.is_admin:
        raise SuspensionNotAllowed("운영자 계정은 정지할 수 없습니다.")
    if user.is_active:
        user.is_active = False
        auth_tokens.bump_version(user)
        db.commit()

    released = 0
    if user.role == "trainer":
        released = _release_trainer(db, user.id)
    db.refresh(user)
    return _out(user, released_clients=released)


def _release_trainer(db: Session, trainer_id: str) -> int:
    """정지된 트레이너의 담당을 모두 해제하고 대기 중 담당 요청을 거둔다."""
    for invite in db.scalars(
        select(TrainerClientInvite).where(
            TrainerClientInvite.trainer_id == trainer_id,
            TrainerClientInvite.status == "pending",
        )
    ).all():
        invite.status = "cancelled"
    db.commit()

    links = db.scalars(
        select(TrainerClient)
        .where(
            TrainerClient.trainer_id == trainer_id,
            TrainerClient.active.is_(True),
        )
        .order_by(TrainerClient.member_id)
    ).all()
    for link in links:
        # 담당 해제 알림·PT 일정 취소·쿠폰 환불·동의 철회까지 트레이너가 직접
        # 해제할 때와 같다. 링크마다 커밋하므로 중간에 실패해도 앞의 해제는 남고,
        # 정지를 다시 부르면 남은 링크만 이어서 해제한다.
        client_status.remove_client(db, link)
    return len(links)


def unsuspend(db: Session, user_id: str) -> AdminUserStatusOut:
    """정지를 푼다. 계정만 되살리고 담당 관계는 복구하지 않는다."""
    user = _require_user(db, user_id)
    if user.is_active:
        return _out(user)
    user.is_active = True
    db.commit()
    db.refresh(user)
    return _out(user)
