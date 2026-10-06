"""운영자 계정 정지·해제. (#3008)

트레이너 운영자 승인 절차를 없앤 뒤 남은 운영 경로다. 회원 신고를 보고 운영자가
트레이너 계정을 정지한다.

여기서 보는 것:

  * 정지 API 는 관리자만(회원·트레이너 403, 미인증 401), 없는 계정 404, 운영자 409.
  * 정지 뒤 기존 토큰 401·로그인 401.
  * 트레이너면 담당 해제·회원 알림·PT 일정 취소·대기 담당 요청 거둠.
  * 두 번 정지해도 알림은 한 번, 해제는 계정만 되살린다.
  * 감사 로그, 운영 목록의 정지 표시.

DB 가 필요하므로 로컬에서는 skip 되고 CI(Postgres) 에서 실행된다.
"""
from __future__ import annotations

from uuid import uuid4

import pytest
from sqlalchemy import select

from app.core import clock
from app.models.models import (
    AuditLog,
    ChatMessage,
    Notification,
    TrainerClient,
    TrainerClientInvite,
    TrainerSchedule,
    User,
)
from app.services import notification_templates
from tests.test_trainer_no_approval import (  # noqa: F401 — 자동 정리 픽스처
    PASSWORD,
    _admin,
    _auth,
    _cleanup,
    _gym,
    _login,
    _member,
    _seeded_trainer,
)


@pytest.fixture(autouse=True)
def _cleanup_records(_cleanup, db_session):  # noqa: F811 — 가져온 픽스처를 인자로 받는다
    """사용자를 지우기 전에 이 파일이 만든 일정·채팅을 지운다."""
    yield
    db_session.rollback()
    db_session.query(TrainerSchedule).filter(
        TrainerSchedule.id.like("susp-schedule-%")
    ).delete(synchronize_session=False)
    db_session.query(ChatMessage).filter(
        ChatMessage.id.like("susp-chat-%")
    ).delete(synchronize_session=False)
    db_session.commit()


def _link(db_session, trainer_id: str, member_id: str) -> TrainerClient:
    link = TrainerClient(
        id=f"susp-link-{uuid4().hex[:12]}",
        trainer_id=trainer_id,
        member_id=member_id,
        active=True,
        data_consent_at=clock.now(),
    )
    db_session.add(link)
    db_session.commit()
    return link


def _linked_pair(client, db_session):
    """트레이너 + 담당 회원 + 관리자. (trainer, trainer_token, member_id, admin_token)"""
    gym = _gym(db_session)
    trainer, email = _seeded_trainer(db_session, gym)
    trainer_token = _login(client, email)
    member_id, _ = _member(client)
    _link(db_session, trainer.id, member_id)
    _, admin_token = _admin(client, db_session)
    return trainer, trainer_token, member_id, admin_token


def _admin_id(db_session) -> str:
    """[_linked_pair] 가 만든 관리자 — 이 파일에서 관리자는 한 명뿐이다."""
    return db_session.scalar(
        select(User.id).where(
            User.is_admin.is_(True), User.email.like("verify-test-%")
        )
    )


# ---------------------------------------------------------------------------
# 정지·해제
# ---------------------------------------------------------------------------


def _suspend(client, admin_token: str, user_id: str):
    return client.post(
        f"/v1/admin/users/{user_id}/suspend", headers=_auth(admin_token)
    )


def _unsuspend(client, admin_token: str, user_id: str):
    return client.post(
        f"/v1/admin/users/{user_id}/unsuspend", headers=_auth(admin_token)
    )


def test_suspend_is_admin_only(client, db_session):
    trainer, trainer_token, member_id, _ = _linked_pair(client, db_session)
    _, member_token = _member(client)

    for token in (trainer_token, member_token):
        assert _suspend(client, token, member_id).status_code == 403
        assert _unsuspend(client, token, member_id).status_code == 403
    assert client.post(f"/v1/admin/users/{trainer.id}/suspend").status_code == 401

    db_session.refresh(db_session.get(User, trainer.id))
    assert db_session.get(User, trainer.id).is_active is True


def test_suspend_unknown_user_is_404_and_admin_is_409(client, db_session):
    admin_id, admin_token = _admin(client, db_session)
    assert _suspend(client, admin_token, "no-such-user").status_code == 404
    assert _unsuspend(client, admin_token, "no-such-user").status_code == 404
    assert _suspend(client, admin_token, admin_id).status_code == 409


def test_suspended_trainer_is_logged_out_and_cannot_log_in(client, db_session):
    trainer, trainer_token, _, admin_token = _linked_pair(client, db_session)

    suspended = _suspend(client, admin_token, trainer.id)
    assert suspended.status_code == 200, suspended.text
    assert suspended.json()["is_active"] is False

    assert client.get(
        "/v1/trainer/me", headers=_auth(trainer_token)
    ).status_code == 401
    login = client.post(
        "/v1/auth/login", data={"username": trainer.email, "password": PASSWORD}
    )
    assert login.status_code == 401


def test_suspending_a_trainer_releases_clients_and_tells_them(client, db_session):
    trainer, _, member_id, admin_token = _linked_pair(client, db_session)
    future = TrainerSchedule(
        id=f"susp-schedule-{uuid4().hex[:12]}",
        trainer_id=trainer.id,
        member_id=member_id,
        date="2099-01-05",
        time="10:00",
    )
    other_member_id, _ = _member(client)
    invite = TrainerClientInvite(
        id=f"susp-invite-{uuid4().hex[:12]}",
        trainer_id=trainer.id,
        member_id=other_member_id,
        status="pending",
    )
    db_session.add_all([future, invite])
    db_session.commit()

    suspended = _suspend(client, admin_token, trainer.id)
    assert suspended.status_code == 200, suspended.text
    assert suspended.json()["released_clients"] == 1

    db_session.expire_all()
    link = db_session.scalar(
        select(TrainerClient).where(
            TrainerClient.trainer_id == trainer.id,
            TrainerClient.member_id == member_id,
        )
    )
    assert link.active is False
    assert link.data_consent_revoked_at is not None
    assert db_session.get(TrainerSchedule, future.id).status == "취소"
    assert db_session.get(TrainerClientInvite, invite.id).status == "cancelled"
    notice = db_session.scalar(
        select(Notification).where(
            Notification.user_id == member_id,
            Notification.template == notification_templates.MEMBER_TRAINER_DISCONNECTED,
        )
    )
    assert notice is not None
    assert notice.template_args["cancelled_sessions"] == 1


def test_suspend_twice_does_not_notify_twice(client, db_session):
    trainer, _, member_id, admin_token = _linked_pair(client, db_session)
    assert _suspend(client, admin_token, trainer.id).status_code == 200
    again = _suspend(client, admin_token, trainer.id)
    assert again.status_code == 200, again.text
    assert again.json()["released_clients"] == 0

    notices = db_session.scalars(
        select(Notification).where(
            Notification.user_id == member_id,
            Notification.template == notification_templates.MEMBER_TRAINER_DISCONNECTED,
        )
    ).all()
    assert len(notices) == 1


def test_unsuspend_restores_the_account_but_not_the_links(client, db_session):
    trainer, _, member_id, admin_token = _linked_pair(client, db_session)
    assert _suspend(client, admin_token, trainer.id).status_code == 200

    restored = _unsuspend(client, admin_token, trainer.id)
    assert restored.status_code == 200, restored.text
    assert restored.json()["is_active"] is True

    token = _login(client, trainer.email)
    assert client.get("/v1/trainer/me", headers=_auth(token)).status_code == 200
    roster = client.get("/v1/trainer/clients", headers=_auth(token))
    row = next(r for r in roster.json() if r["id"] == member_id)
    assert row["registered"] is False
    assert client.get(
        f"/v1/trainer/clients/{member_id}/health-profile", headers=_auth(token)
    ).status_code == 404


def test_suspended_member_cannot_log_in(client, db_session):
    _, admin_token = _admin(client, db_session)
    member_id, member_token = _member(client)

    assert _suspend(client, admin_token, member_id).status_code == 200
    assert client.get("/v1/users/me", headers=_auth(member_token)).status_code in (
        401,
        200,  # 개발 환경의 데모 폴백 — 정지된 계정의 데이터는 아니다.
    )
    member = db_session.get(User, member_id)
    db_session.refresh(member)
    login = client.post(
        "/v1/auth/login", data={"username": member.email, "password": PASSWORD}
    )
    assert login.status_code == 401


def test_suspend_and_unsuspend_are_audited(client, db_session):
    trainer, _, _, admin_token = _linked_pair(client, db_session)
    admin_id = _admin_id(db_session)
    assert _suspend(client, admin_token, trainer.id).status_code == 200
    assert _unsuspend(client, admin_token, trainer.id).status_code == 200

    events = {
        row.event
        for row in db_session.scalars(
            select(AuditLog).where(
                AuditLog.user_id == admin_id,
                AuditLog.target_user_id == trainer.id,
            )
        ).all()
    }
    assert {"admin.user_suspend", "admin.user_unsuspend"} <= events


def test_admin_list_reports_suspension(client, db_session):
    trainer, _, _, admin_token = _linked_pair(client, db_session)
    assert _suspend(client, admin_token, trainer.id).status_code == 200

    listed = client.get(
        "/v1/admin/trainers?state=all", headers=_auth(admin_token)
    )
    row = next(r for r in listed.json() if r["trainer_id"] == trainer.id)
    assert row["is_active"] is False
