"""만료·트레이너 정지·탈퇴 때 회원 상담 정리. (#3360)

회원의 상담 요청이 실제 상태와 다르게 남는 경우가 셋 있었다.

  * 만료 정리가 트레이너 쪽 조회에서만 돌아, 트레이너가 앱을 열지 않으면 지난
    요청이 회원 화면에 "대기 중" 으로 남았다.
  * 트레이너가 정지돼도 상담 요청은 그대로였다.
  * 트레이너가 탈퇴하면 대기 요청만 닫히고 수락된 상담은 `수락됨` 으로 남았다.

DB 가 필요하므로 로컬에서는 skip 되고 CI(Postgres) 에서 실행된다.
"""
from __future__ import annotations

from datetime import timedelta

from app.core import clock
from app.models.models import (
    ConsultationRequest,
    Notification,
    TrainerReservationSlot,
    TrainerSchedule,
    User,
)
from app.services import consultation_service, notification_templates
from app.services.trainer import _common as trainer_common_service

from tests.test_consultation_decision import (  # noqa: F401 — `_cleanup` 은 정리 픽스처다
    PASSWORD,
    _accept,
    _auth,
    _cleanup,
    _login,
    _member,
    _request_consultation,
    _trainer,
)


def _row(db_session, consultation_id: str) -> ConsultationRequest:
    db_session.expire_all()
    return db_session.get(ConsultationRequest, consultation_id)


def _slot_of(db_session, consultation_id: str) -> TrainerReservationSlot:
    """그 요청이 신청 때 고른 자리."""
    slot_id = _row(db_session, consultation_id).slot_id
    return db_session.get(TrainerReservationSlot, slot_id)


def _remaining(db_session, slot_id: str) -> int:
    db_session.expire_all()
    return db_session.get(TrainerReservationSlot, slot_id).remaining


def _notices(db_session, member_id: str) -> list[Notification]:
    db_session.expire_all()
    return (
        db_session.query(Notification)
        .filter(Notification.user_id == member_id)
        .order_by(Notification.created_at, Notification.id)
        .all()
    )


def _templates(db_session, member_id: str) -> list[str | None]:
    return [n.template for n in _notices(db_session, member_id)]


def _mine(client, member_token: str) -> list[dict]:
    response = client.get("/v1/consultations/me", headers=_auth(member_token))
    assert response.status_code == 200, response.text
    return response.json()


def _age(db_session, consultation_id: str, *, hours: float) -> None:
    """요청을 [hours] 시간 전에 낸 것으로 돌린다 — 24시간 규칙으로 만료시킨다."""
    row = _row(db_session, consultation_id)
    row.created_at = clock.now() - timedelta(hours=hours)
    db_session.commit()


def _admin_token(client, db_session) -> str:
    """관리자 하나. 운영자 판별은 `users.is_admin` 이다."""
    member_id, _ = _member(client)
    user = db_session.get(User, member_id)
    user.is_admin = True
    db_session.commit()
    return _login(client, user.email)


def _suspend(client, admin_token: str, user_id: str):
    return client.post(
        f"/v1/admin/users/{user_id}/suspend", headers=_auth(admin_token)
    )


def _delete_trainer(client, trainer_token: str):
    return client.request(
        "DELETE",
        "/v1/trainer/me",
        json={"current_password": PASSWORD},
        headers=_auth(trainer_token),
    )


def _schedule(db_session, consultation_id: str) -> TrainerSchedule:
    db_session.expire_all()
    return (
        db_session.query(TrainerSchedule)
        .filter(TrainerSchedule.consultation_id == consultation_id)
        .one()
    )


# --- 회원 조회의 만료 정리 -----------------------------------------------------


def test_member_list_expires_a_stale_request_without_the_trainer(client, db_session):
    """트레이너가 앱을 열지 않아도 회원이 목록을 열면 지난 요청이 만료로 보인다."""
    trainer, _ = _trainer(client, db_session)
    member_id, member_token = _member(client)
    consultation_id = _request_consultation(client, member_token, trainer_id=trainer.id)
    slot_id = _row(db_session, consultation_id).slot_id
    assert _remaining(db_session, slot_id) == 0
    _age(db_session, consultation_id, hours=30)

    mine = _mine(client, member_token)

    assert [item["status"] for item in mine] == ["expired"]
    assert _row(db_session, consultation_id).status == "expired"
    # 잡고 있던 자리가 풀리고, 만료 알림이 회원에게 간다.
    assert _remaining(db_session, slot_id) == 1
    assert notification_templates.MEMBER_CONSULT_EXPIRED in _templates(
        db_session, member_id
    )


def test_member_list_expires_once_the_slot_is_two_hours_away(client, db_session):
    """자리 시작 2시간 전을 지나면 만료다 — 트레이너 쪽 정리와 같은 기준이다."""
    trainer, _ = _trainer(client, db_session)
    member_id, member_token = _member(client)
    consultation_id = _request_consultation(
        client, member_token, trainer_id=trainer.id, hours_ahead=5
    )
    starts_at = _slot_of(db_session, consultation_id).starts_at
    passed = starts_at - timedelta(hours=2) + timedelta(minutes=1)

    listed = consultation_service.list_my_consultations(
        db_session, member_id, now=passed
    )

    assert [item.status for item in listed] == ["expired"]
    assert _row(db_session, consultation_id).status == "expired"


def test_member_list_leaves_a_live_request_pending(client, db_session):
    """아직 시간이 남은 요청은 건드리지 않고, 알림도 만들지 않는다."""
    trainer, _ = _trainer(client, db_session)
    member_id, member_token = _member(client)
    consultation_id = _request_consultation(client, member_token, trainer_id=trainer.id)
    before = _templates(db_session, member_id)

    assert [item["status"] for item in _mine(client, member_token)] == ["pending"]

    assert _row(db_session, consultation_id).status == "pending"
    assert _templates(db_session, member_id) == before


def test_member_list_notifies_expiry_only_once(client, db_session):
    """목록을 다시 열어도 만료 알림은 한 번이다."""
    trainer, _ = _trainer(client, db_session)
    member_id, member_token = _member(client)
    consultation_id = _request_consultation(client, member_token, trainer_id=trainer.id)
    _age(db_session, consultation_id, hours=30)

    _mine(client, member_token)
    _mine(client, member_token)

    assert (
        _templates(db_session, member_id).count(
            notification_templates.MEMBER_CONSULT_EXPIRED
        )
        == 1
    )


def test_member_list_does_not_expire_other_members_requests(client, db_session):
    """정리 범위는 그 회원의 요청뿐이다."""
    trainer, _ = _trainer(client, db_session)
    _, mine_token = _member(client)
    _, other_token = _member(client)
    other_id = _request_consultation(client, other_token, trainer_id=trainer.id)
    _age(db_session, other_id, hours=30)

    assert _mine(client, mine_token) == []

    assert _row(db_session, other_id).status == "pending"


def test_member_detail_expires_a_stale_request(client, db_session):
    """상세도 목록과 같은 상태를 준다."""
    trainer, _ = _trainer(client, db_session)
    _, member_token = _member(client)
    consultation_id = _request_consultation(client, member_token, trainer_id=trainer.id)
    _age(db_session, consultation_id, hours=30)

    response = client.get(
        f"/v1/consultations/{consultation_id}", headers=_auth(member_token)
    )

    assert response.status_code == 200, response.text
    assert response.json()["status"] == "expired"


def test_member_can_request_the_same_trainer_again_after_expiry(client, db_session):
    """만료로 내려가면 같은 트레이너에게 다시 신청할 수 있다."""
    trainer, _ = _trainer(client, db_session)
    _, member_token = _member(client)
    first_id = _request_consultation(client, member_token, trainer_id=trainer.id)
    _age(db_session, first_id, hours=30)
    assert [item["status"] for item in _mine(client, member_token)] == ["expired"]

    second_id = _request_consultation(client, member_token, trainer_id=trainer.id)

    assert _row(db_session, second_id).status == "pending"


# --- 트레이너 정지 -------------------------------------------------------------


def test_suspension_cancels_a_pending_request_and_tells_the_member(client, db_session):
    """정지된 트레이너에게 낸 대기 요청은 취소되고 회원에게 알림이 간다."""
    trainer, _ = _trainer(client, db_session)
    member_id, member_token = _member(client)
    consultation_id = _request_consultation(client, member_token, trainer_id=trainer.id)
    slot_id = _row(db_session, consultation_id).slot_id
    admin_token = _admin_token(client, db_session)

    assert _suspend(client, admin_token, trainer.id).status_code == 200

    row = _row(db_session, consultation_id)
    assert row.status == "cancelled"
    assert row.decided_at is not None
    # 트레이너의 자리는 남는다 — 잡고 있던 자리를 돌려준다.
    assert _remaining(db_session, slot_id) == 1
    notice = next(
        n
        for n in _notices(db_session, member_id)
        if n.template == notification_templates.MEMBER_CONSULT_TRAINER_UNAVAILABLE
    )
    assert notice.category == "consult_decision"
    assert notice.template_args["trainer_name"] == trainer.name
    assert not notice.template_args.get("booked")

    mine = _mine(client, member_token)
    assert [item["status"] for item in mine] == ["cancelled"]
    # 다시 신청하라는 안내가 붙으면 안 된다 — 정지된 트레이너에게는 신청할 수 없다.
    assert mine[0]["cancelled_by_trainer"] is False


def test_suspension_cancels_an_accepted_consultation_with_its_schedule(
    client, db_session
):
    """수락된 상담은 일정·자리까지 함께 거두고, 확정된 상담이 취소됐다고 알린다."""
    trainer, trainer_token = _trainer(client, db_session)
    member_id, member_token = _member(client)
    consultation_id = _request_consultation(client, member_token, trainer_id=trainer.id)
    slot_id = _row(db_session, consultation_id).slot_id
    _accept(client, trainer_token, consultation_id)
    admin_token = _admin_token(client, db_session)

    assert _suspend(client, admin_token, trainer.id).status_code == 200

    row = _row(db_session, consultation_id)
    assert row.status == "cancelled"
    assert row.decided_by is None
    schedule = _schedule(db_session, consultation_id)
    assert schedule.status == trainer_common_service.SCHEDULE_CANCELLED
    assert schedule.cancellation_source == "trainer"
    assert (
        schedule.cancellation_reason
        == consultation_service.TRAINER_EXIT_CONSULT_CANCEL_REASON
    )
    assert _remaining(db_session, slot_id) == 1
    notice = next(
        n
        for n in _notices(db_session, member_id)
        if n.template == notification_templates.MEMBER_CONSULT_TRAINER_UNAVAILABLE
    )
    assert notice.template_args["booked"] is True
    assert notice.template_args["starts_at"] is not None
    assert notice.title == "확정된 상담이 취소되었어요"


def test_suspension_expires_a_stale_pending_request_instead(client, db_session):
    """만료 시각이 지난 대기 요청은 취소가 아니라 평소처럼 만료다."""
    trainer, _ = _trainer(client, db_session)
    member_id, member_token = _member(client)
    consultation_id = _request_consultation(client, member_token, trainer_id=trainer.id)
    _age(db_session, consultation_id, hours=30)
    admin_token = _admin_token(client, db_session)

    assert _suspend(client, admin_token, trainer.id).status_code == 200

    assert _row(db_session, consultation_id).status == "expired"
    templates = _templates(db_session, member_id)
    assert notification_templates.MEMBER_CONSULT_EXPIRED in templates
    assert notification_templates.MEMBER_CONSULT_TRAINER_UNAVAILABLE not in templates


def test_suspending_twice_notifies_once(client, db_session):
    """이미 정리된 상담은 다시 정지해도 알림이 늘지 않는다."""
    trainer, trainer_token = _trainer(client, db_session)
    member_id, member_token = _member(client)
    consultation_id = _request_consultation(client, member_token, trainer_id=trainer.id)
    _accept(client, trainer_token, consultation_id)
    admin_token = _admin_token(client, db_session)

    assert _suspend(client, admin_token, trainer.id).status_code == 200
    assert _suspend(client, admin_token, trainer.id).status_code == 200

    assert (
        _templates(db_session, member_id).count(
            notification_templates.MEMBER_CONSULT_TRAINER_UNAVAILABLE
        )
        == 1
    )


def test_suspension_leaves_other_trainers_consultations(client, db_session):
    """다른 트레이너에게 낸 상담은 건드리지 않는다."""
    trainer, _ = _trainer(client, db_session)
    other, _ = _trainer(client, db_session)
    _, member_token = _member(client)
    other_id = _request_consultation(client, member_token, trainer_id=other.id)
    admin_token = _admin_token(client, db_session)

    assert _suspend(client, admin_token, trainer.id).status_code == 200

    assert _row(db_session, other_id).status == "pending"


def test_suspension_keeps_a_consultation_that_already_started(client, db_session):
    """이미 시작한 수락 상담은 있었던 일이라 그대로 둔다."""
    trainer, trainer_token = _trainer(client, db_session)
    member_id, member_token = _member(client)
    consultation_id = _request_consultation(
        client, member_token, trainer_id=trainer.id, hours_ahead=5
    )
    _accept(client, trainer_token, consultation_id)
    before = _templates(db_session, member_id)
    after_start = clock.now() + timedelta(hours=6)

    cancelled = consultation_service.cancel_for_trainer_suspension(
        db_session, db_session.get(User, trainer.id), now=after_start
    )
    db_session.commit()

    assert cancelled == 0
    assert _row(db_session, consultation_id).status == "accepted"
    assert (
        _schedule(db_session, consultation_id).status
        == trainer_common_service.SCHEDULE_UPCOMING
    )
    assert _templates(db_session, member_id) == before


# --- 트레이너 탈퇴 -------------------------------------------------------------


def test_trainer_deletion_cancels_an_accepted_consultation(client, db_session):
    """탈퇴한 트레이너가 수락해 둔 상담은 취소되고 회원에게 알림이 간다."""
    trainer, trainer_token = _trainer(client, db_session)
    member_id, member_token = _member(client)
    consultation_id = _request_consultation(client, member_token, trainer_id=trainer.id)
    _accept(client, trainer_token, consultation_id)

    deleted = _delete_trainer(client, trainer_token)
    assert deleted.status_code == 200, deleted.text

    row = _row(db_session, consultation_id)
    assert (row.status, row.trainer_id) == ("cancelled", None)
    notice = next(
        n
        for n in _notices(db_session, member_id)
        if n.template == notification_templates.MEMBER_CONSULT_TRAINER_LEFT
    )
    assert notice.template_args["booked"] is True
    assert notice.title == "확정된 상담이 취소되었어요"

    mine = _mine(client, member_token)
    assert [item["status"] for item in mine] == ["cancelled"]
    # 트레이너가 지워져 이름이 없다 — 앱이 대체 문구를 쓴다.
    assert mine[0]["trainer_name"] is None


def test_trainer_deletion_still_cancels_pending_requests(client, db_session):
    """대기 요청은 예전처럼 요청 취소 알림으로 닫힌다(#3241)."""
    trainer, trainer_token = _trainer(client, db_session)
    member_id, member_token = _member(client)
    consultation_id = _request_consultation(client, member_token, trainer_id=trainer.id)

    assert _delete_trainer(client, trainer_token).status_code == 200

    assert _row(db_session, consultation_id).status == "cancelled"
    notice = next(
        n
        for n in _notices(db_session, member_id)
        if n.template == notification_templates.MEMBER_CONSULT_TRAINER_LEFT
    )
    assert not notice.template_args.get("booked")
    assert notice.title == "상담 요청이 취소되었어요"


def test_trainer_deletion_keeps_a_consultation_that_already_started(client, db_session):
    """이미 시작한 수락 상담은 `수락됨` 으로 남고 알리지 않는다."""
    trainer, trainer_token = _trainer(client, db_session)
    member_id, member_token = _member(client)
    consultation_id = _request_consultation(
        client, member_token, trainer_id=trainer.id, hours_ahead=5
    )
    _accept(client, trainer_token, consultation_id)
    before = _templates(db_session, member_id)
    after_start = clock.now() + timedelta(hours=6)

    cancelled = consultation_service.cancel_accepted_for_trainer_deletion(
        db_session, db_session.get(User, trainer.id), now=after_start
    )
    db_session.commit()

    assert cancelled == 0
    assert _row(db_session, consultation_id).status == "accepted"
    assert _templates(db_session, member_id) == before
