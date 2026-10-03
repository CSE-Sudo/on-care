"""반려 트레이너의 담당 회원 기록 잠금과 운영자 계정 정지. (#3009)

여기서 보는 것:

  * 반려된 트레이너는 이미 맺은 담당 회원의 기록 API 에서 403 `trainer_not_approved`.
  * 승인 트레이너는 그대로 200, 다시 승인하면 다시 200(링크는 그대로).
  * 대기·프로필 없는 트레이너의 기존 담당은 잠그지 않는다(반려만 잠근다).
  * 로스터에는 이름·연결 상태만 남고 수치·미리보기는 빈다.
  * 정지 API — 관리자만, 정지 뒤 기존 토큰 401·로그인 401, 트레이너면 담당 해제·
    회원 알림·PT 일정 취소·대기 담당 요청 거둠, 해제는 계정만 되살림, 감사 로그.

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
    TrainerProfile,
    TrainerSchedule,
    User,
)
from app.services import notification_templates
from tests.test_trainer_verification import (  # noqa: F401 — 자동 정리 픽스처
    PASSWORD,
    _admin,
    _approve,
    _assert_not_approved,
    _auth,
    _cleanup,
    _gym,
    _login,
    _member,
    _reject,
    _seeded_trainer,
)


@pytest.fixture(autouse=True)
def _cleanup_records(_cleanup, db_session):
    """사용자를 지우기 전에 이 파일이 만든 일정·채팅을 지운다."""
    yield
    db_session.rollback()
    db_session.query(TrainerSchedule).filter(
        TrainerSchedule.id.like("lock-schedule-%")
    ).delete(synchronize_session=False)
    db_session.query(ChatMessage).filter(
        ChatMessage.id.like("lock-chat-%")
    ).delete(synchronize_session=False)
    db_session.commit()


def _link(db_session, trainer_id: str, member_id: str) -> TrainerClient:
    link = TrainerClient(
        id=f"lock-link-{uuid4().hex[:12]}",
        trainer_id=trainer_id,
        member_id=member_id,
        active=True,
        data_consent_at=clock.now(),
    )
    db_session.add(link)
    db_session.commit()
    return link


def _linked_pair(client, db_session):
    """승인된 트레이너 + 담당 회원 + 관리자. (trainer, trainer_token, member_id, admin_token)"""
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


#: 담당 회원 기록 경로 — 식단·운동·건강 정보·채팅·메모·리포트·루틴·후속 관리·일정.
_RECORD_PATHS = (
    "health-profile",
    "records/span",
    "history",
    "chat",
    "memos",
    "feedbacks",
    "routines",
    "deliveries/latest",
    "follow-ups",
    "report/goals",
    "exercise-week",
)


@pytest.mark.parametrize("path", _RECORD_PATHS)
def test_rejected_trainer_cannot_read_existing_client_records(
    client, db_session, path
):
    trainer, trainer_token, member_id, admin_token = _linked_pair(client, db_session)
    url = f"/v1/trainer/clients/{member_id}/{path}"

    before = client.get(url, headers=_auth(trainer_token))
    assert before.status_code == 200, before.text

    assert _reject(client, admin_token, trainer.id, "자격 확인 불가").status_code == 200
    _assert_not_approved(client.get(url, headers=_auth(trainer_token)))


def test_rejected_trainer_cannot_write_to_existing_clients(client, db_session):
    trainer, trainer_token, member_id, admin_token = _linked_pair(client, db_session)
    assert _reject(client, admin_token, trainer.id).status_code == 200

    _assert_not_approved(
        client.post(
            f"/v1/trainer/clients/{member_id}/chat",
            json={"text": "안녕하세요"},
            headers=_auth(trainer_token),
        )
    )
    _assert_not_approved(
        client.post(
            f"/v1/trainer/clients/{member_id}/memos",
            json={"body": "메모"},
            headers=_auth(trainer_token),
        )
    )


def test_reapproval_reopens_the_same_link(client, db_session):
    trainer, trainer_token, member_id, admin_token = _linked_pair(client, db_session)
    url = f"/v1/trainer/clients/{member_id}/health-profile"

    assert _reject(client, admin_token, trainer.id).status_code == 200
    _assert_not_approved(client.get(url, headers=_auth(trainer_token)))
    assert _approve(client, admin_token, trainer.id).status_code == 200

    reopened = client.get(url, headers=_auth(trainer_token))
    assert reopened.status_code == 200, reopened.text
    link = db_session.scalar(
        select(TrainerClient).where(
            TrainerClient.trainer_id == trainer.id,
            TrainerClient.member_id == member_id,
        )
    )
    db_session.refresh(link)
    # 반려는 담당 관계를 끊지 않는다 — 동의도 그대로다.
    assert link.active is True
    assert link.data_consent_at is not None


def test_rejected_roster_keeps_names_but_hides_numbers(client, db_session):
    trainer, trainer_token, member_id, admin_token = _linked_pair(client, db_session)
    db_session.add(
        ChatMessage(
            id=f"lock-chat-{uuid4().hex[:12]}",
            trainer_id=trainer.id,
            member_id=member_id,
            sender="member",
            body="오늘 식단 봐 주세요",
        )
    )
    db_session.commit()

    before = client.get("/v1/trainer/clients", headers=_auth(trainer_token))
    row = next(r for r in before.json() if r["id"] == member_id)
    assert row["last_message"] == "오늘 식단 봐 주세요"

    assert _reject(client, admin_token, trainer.id).status_code == 200
    after = client.get("/v1/trainer/clients", headers=_auth(trainer_token))
    assert after.status_code == 200, after.text
    row = next(r for r in after.json() if r["id"] == member_id)
    assert row["name"] == "승인 회원"
    assert row["registered"] is True
    assert row["last_message"] != "오늘 식단 봐 주세요"
    assert row["last_message_at"] is None
    assert row["signals"] == []


def test_rejected_trainer_sees_member_sessions_anonymised(client, db_session):
    trainer, trainer_token, member_id, admin_token = _linked_pair(client, db_session)
    day = clock.today().isoformat()
    db_session.add(
        TrainerSchedule(
            id=f"lock-schedule-{uuid4().hex[:12]}",
            trainer_id=trainer.id,
            member_id=member_id,
            date=day,
            time="23:30",
        )
    )
    db_session.commit()

    assert _reject(client, admin_token, trainer.id).status_code == 200
    listed = client.get(
        f"/v1/trainer/schedule?date={day}", headers=_auth(trainer_token)
    )
    assert listed.status_code == 200, listed.text
    rows = listed.json()
    assert rows, "일정은 스케줄에 남는다"
    assert all(row.get("member_id") != member_id for row in rows)
    assert all(row.get("member_detached") for row in rows)


def test_only_rejection_locks_records(client, db_session):
    """잠금은 반려뿐이다 — 대기·프로필 없는 트레이너의 기존 담당은 그대로 열린다."""
    trainer, trainer_token, member_id, _ = _linked_pair(client, db_session)
    url = f"/v1/trainer/clients/{member_id}/memos"
    profile = db_session.scalar(
        select(TrainerProfile).where(TrainerProfile.trainer_id == trainer.id)
    )
    profile.verification_status = "pending"
    db_session.commit()
    assert client.get(url, headers=_auth(trainer_token)).status_code == 200

    db_session.delete(profile)
    db_session.commit()
    assert client.get(url, headers=_auth(trainer_token)).status_code == 200


def test_rejected_trainer_keeps_profile_endpoints(client, db_session):
    trainer, trainer_token, _, admin_token = _linked_pair(client, db_session)
    assert _reject(client, admin_token, trainer.id).status_code == 200

    me = client.get("/v1/trainer/me", headers=_auth(trainer_token))
    assert me.status_code == 200, me.text
    assert me.json()["verification"]["status"] == "rejected"
    assert client.get(
        "/v1/trainer/notifications", headers=_auth(trainer_token)
    ).status_code == 200


def test_rejected_read_is_not_audited_as_a_client_read(client, db_session):
    trainer, trainer_token, member_id, admin_token = _linked_pair(client, db_session)
    assert _reject(client, admin_token, trainer.id).status_code == 200

    client.get(
        f"/v1/trainer/clients/{member_id}/health-profile",
        headers=_auth(trainer_token),
    )
    assert (
        db_session.scalar(
            select(AuditLog).where(
                AuditLog.event == "trainer.client_read",
                AuditLog.user_id == trainer.id,
                AuditLog.target_user_id == member_id,
            )
        )
        is None
    )


# ---------------------------------------------------------------------------
# 계정 정지
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
        id=f"lock-schedule-{uuid4().hex[:12]}",
        trainer_id=trainer.id,
        member_id=member_id,
        date="2099-01-05",
        time="10:00",
    )
    other_member_id, _ = _member(client)
    invite = TrainerClientInvite(
        id=f"lock-invite-{uuid4().hex[:12]}",
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
        "/v1/admin/trainers?status=all", headers=_auth(admin_token)
    )
    row = next(r for r in listed.json() if r["trainer_id"] == trainer.id)
    assert row["is_active"] is False
