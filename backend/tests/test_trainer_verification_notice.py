"""승인·반려 알림(#3010)과 `/trainer/me` 의 운영자 표시(#3008).

여기서 보는 것:

  * 승인하면 트레이너에게 `verification` 알림 1건, 반려는 사유를 본문으로.
  * 같은 상태로 다시 처리하면 알림이 늘지 않는다. 반려 → 재승인은 각각 1건.
  * 트레이너 수신 설정과 무관하게 보낸다.
  * 영어 알림함은 틀로 조립한다(사유는 그대로).
  * `/trainer/me` 의 `is_admin` 은 운영자 계정만 참.
  * 관리자 목록·결정은 운영자 트레이너 계정으로도 된다(트레이너 웹에서 쓴다).

DB 가 필요한 테스트는 로컬에서는 skip 되고 CI(Postgres) 에서 실행된다.
"""
from __future__ import annotations

from sqlalchemy import select

from app.models.models import Notification, TrainerProfile, User
from app.services import notification_service, notification_templates
from tests.test_trainer_verification import (  # noqa: F401 — 자동 정리 픽스처
    _admin,
    _approve,
    _auth,
    _cleanup,
    _gym,
    _login,
    _reject,
    _seeded_trainer,
    _sign_up_trainer,
)


def _notices(db_session, trainer_id: str) -> list[Notification]:
    db_session.expire_all()
    return list(
        db_session.scalars(
            select(Notification)
            .where(
                Notification.user_id == trainer_id,
                Notification.category == notification_service.TRAINER_VERIFICATION_KIND,
            )
            .order_by(Notification.created_at, Notification.id)
        ).all()
    )


# ---------------------------------------------------------------------------
# 틀(DB 없이)
# ---------------------------------------------------------------------------


def test_verification_templates_are_registered():
    codes = notification_templates.codes()
    assert notification_templates.TRAINER_VERIFICATION_APPROVED in codes
    assert notification_templates.TRAINER_VERIFICATION_REJECTED in codes
    assert len(notification_service.TRAINER_VERIFICATION_KIND) <= 20


def test_verification_kind_is_distinct_from_other_kinds():
    ns = notification_service
    others = {
        ns.TRAINER_MESSAGE_KIND,
        ns.TRAINER_CONSULTATION_KIND,
        ns.TRAINER_RESERVATION_KIND,
        ns.TRAINER_HEALTH_GOAL_KIND,
        ns.TRAINER_MEMBER_NAME_KIND,
        ns.TRAINER_MEMBER_LEFT_KIND,
        ns.TRAINER_CONSULT_WITHDRAWN_KIND,
        ns.TRAINER_INVITE_ACCEPTED_KIND,
        ns.TRAINER_INVITE_REJECTED_KIND,
        # 회원 알림의 category 집합과도 겹치지 않는다(한 컬럼을 공유한다).
        "reminder",
        "health_check",
        "achievement",
        "system",
    }
    assert ns.TRAINER_VERIFICATION_KIND not in others


def test_verification_kind_has_no_setting_switch():
    assert (
        notification_service.TRAINER_VERIFICATION_KIND
        not in notification_service._TRAINER_SETTING_COLUMN
    )


def test_rejected_template_keeps_the_written_reason():
    cols = notification_templates.columns(
        notification_templates.TRAINER_VERIFICATION_REJECTED,
        {"has_note": True},
        body="소속 헬스장을 확인할 수 없어요.",
    )
    assert cols["title"] == "운영자 승인이 반려되었어요"
    assert cols["body"] == "소속 헬스장을 확인할 수 없어요."


def test_rejected_template_without_reason_points_to_my():
    cols = notification_templates.columns(
        notification_templates.TRAINER_VERIFICATION_REJECTED, {"has_note": False}
    )
    assert "MY" in cols["body"]


def test_verification_templates_render_in_english():
    title, body = notification_templates.localize(
        title="운영자 승인이 완료되었어요",
        body="",
        template=notification_templates.TRAINER_VERIFICATION_APPROVED,
        template_args={},
        locale="en",
    )
    assert title == "Your trainer account is approved"
    assert "Find a trainer" in body

    title, body = notification_templates.localize(
        title="운영자 승인이 반려되었어요",
        body="서류 보완",
        template=notification_templates.TRAINER_VERIFICATION_REJECTED,
        template_args={"has_note": True},
        locale="en",
    )
    assert title == "Your trainer account was not approved"
    assert body == "서류 보완"


# ---------------------------------------------------------------------------
# 알림(DB)
# ---------------------------------------------------------------------------


def test_approval_notifies_the_trainer_once(client, db_session):
    gym = _gym(db_session)
    trainer_id, _ = _sign_up_trainer(client, gym)
    _, admin_token = _admin(client, db_session)

    assert _approve(client, admin_token, trainer_id).status_code == 200
    notices = _notices(db_session, trainer_id)
    assert len(notices) == 1
    assert notices[0].template == notification_templates.TRAINER_VERIFICATION_APPROVED
    assert notices[0].read is False

    # 같은 상태로 다시 처리하면 알림이 늘지 않는다.
    assert _approve(client, admin_token, trainer_id).status_code == 200
    assert len(_notices(db_session, trainer_id)) == 1


def test_rejection_notifies_with_the_reason(client, db_session):
    gym = _gym(db_session)
    trainer_id, _ = _sign_up_trainer(client, gym)
    _, admin_token = _admin(client, db_session)

    assert _reject(client, admin_token, trainer_id, "  서류 보완  ").status_code == 200
    notices = _notices(db_session, trainer_id)
    assert len(notices) == 1
    assert notices[0].template == notification_templates.TRAINER_VERIFICATION_REJECTED
    assert notices[0].body == "서류 보완"
    assert notices[0].template_args == {"has_note": True}

    # 사유만 고친 반려는 상태가 그대로라 알림을 더 만들지 않는다.
    assert _reject(client, admin_token, trainer_id, "다른 사유").status_code == 200
    assert len(_notices(db_session, trainer_id)) == 1


def test_reject_then_reapprove_notifies_each_change(client, db_session):
    gym = _gym(db_session)
    trainer_id, _ = _sign_up_trainer(client, gym)
    _, admin_token = _admin(client, db_session)

    assert _reject(client, admin_token, trainer_id).status_code == 200
    assert _approve(client, admin_token, trainer_id).status_code == 200
    templates = [n.template for n in _notices(db_session, trainer_id)]
    assert templates == [
        notification_templates.TRAINER_VERIFICATION_REJECTED,
        notification_templates.TRAINER_VERIFICATION_APPROVED,
    ]


def test_pending_to_pending_never_notifies(client, db_session):
    gym = _gym(db_session)
    trainer_id, _ = _sign_up_trainer(client, gym)
    assert _notices(db_session, trainer_id) == []


def test_verification_notice_ignores_the_message_setting(client, db_session):
    gym = _gym(db_session)
    trainer_id, _ = _sign_up_trainer(client, gym)
    _, admin_token = _admin(client, db_session)
    profile = db_session.scalar(
        select(TrainerProfile).where(TrainerProfile.trainer_id == trainer_id)
    )
    profile.notify_new_message = False
    db_session.commit()

    assert _approve(client, admin_token, trainer_id).status_code == 200
    assert len(_notices(db_session, trainer_id)) == 1


def test_trainer_inbox_lists_the_verification_notice(client, db_session):
    gym = _gym(db_session)
    trainer_id, trainer_token = _sign_up_trainer(client, gym)
    _, admin_token = _admin(client, db_session)
    assert _reject(client, admin_token, trainer_id, "서류 보완").status_code == 200

    listed = client.get(
        "/v1/trainer/notifications",
        headers={**_auth(trainer_token), "Accept-Language": "en"},
    )
    assert listed.status_code == 200, listed.text
    row = next(
        r for r in listed.json()
        if r.get("template") == notification_templates.TRAINER_VERIFICATION_REJECTED
    )
    assert row["category"] == notification_service.TRAINER_VERIFICATION_KIND
    assert row["title"] == "Your trainer account was not approved"
    assert row["body"] == "서류 보완"


# ---------------------------------------------------------------------------
# 운영자 표시(#3008)
# ---------------------------------------------------------------------------


def test_trainer_me_is_admin_false_by_default(client, db_session):
    gym = _gym(db_session)
    _, trainer_token = _sign_up_trainer(client, gym)
    me = client.get("/v1/trainer/me", headers=_auth(trainer_token))
    assert me.status_code == 200, me.text
    assert me.json()["is_admin"] is False


def test_trainer_me_is_admin_true_for_an_admin_trainer(client, db_session):
    gym = _gym(db_session)
    trainer, email = _seeded_trainer(db_session, gym)
    user = db_session.get(User, trainer.id)
    user.is_admin = True
    db_session.commit()

    token = _login(client, email)
    me = client.get("/v1/trainer/me", headers=_auth(token))
    assert me.status_code == 200, me.text
    assert me.json()["is_admin"] is True

    # 트레이너 웹의 운영 화면이 쓰는 경로 — 운영자 트레이너 계정으로도 열린다.
    pending_id, _ = _sign_up_trainer(client, gym)
    listed = client.get("/v1/admin/trainers", headers=_auth(token))
    assert listed.status_code == 200, listed.text
    row = next(r for r in listed.json() if r["trainer_id"] == pending_id)
    assert row["status"] == "pending"
    assert row["is_active"] is True
    assert _approve(client, token, pending_id).status_code == 200


def test_reject_reason_over_300_is_422(client, db_session):
    gym = _gym(db_session)
    trainer_id, _ = _sign_up_trainer(client, gym)
    _, admin_token = _admin(client, db_session)
    too_long = _reject(client, admin_token, trainer_id, "가" * 301)
    assert too_long.status_code == 422
    profile = db_session.scalar(
        select(TrainerProfile).where(TrainerProfile.trainer_id == trainer_id)
    )
    db_session.refresh(profile)
    assert profile.verification_status == "pending"
