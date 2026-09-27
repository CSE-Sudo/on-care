"""트레이너 고객 삭제는 계정 삭제가 아닌 담당 관계 해제다."""

from uuid import uuid4

from app.core.security import create_access_token
from app.models.models import (
    ChatMessage,
    RoutineHistory,
    TrainerClient,
    TrainerClientMemo,
    TrainerFollowUpTask,
    TrainerReportFeedback,
    TrainerRoutine,
    TrainerSchedule,
    User,
)


TRAINER_ID = "trainer-demo"
MEMBER_ID = "user-jisu"


def _headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _login(client, email: str) -> str:
    response = client.post(
        "/v1/auth/login",
        data={"username": email, "password": "oncare123"},
    )
    assert response.status_code == 200, response.text
    return response.json()["access_token"]


def test_trainer_removes_assignment_but_keeps_member(client, db_session):
    token = _login(client, "trainer@oncare.com")
    member_id = f"remove-member-{uuid4().hex[:10]}"
    member = User(
        id=member_id,
        email=f"{member_id}@oncare.com",
        name="삭제 확인 고객",
        hashed_password="unused",
        role="member",
    )
    db_session.add(member)
    db_session.commit()
    pair_rows = [
        TrainerClient(
            id=f"link-{uuid4().hex[:12]}",
            trainer_id=TRAINER_ID,
            member_id=member_id,
            active=True,
        ),
        TrainerSchedule(
            id=f"schedule-{uuid4().hex[:12]}",
            trainer_id=TRAINER_ID,
            member_id=member_id,
            date="2026-08-27",
            time="10:00",
        ),
        TrainerRoutine(
            id=f"routine-{uuid4().hex[:12]}",
            trainer_id=TRAINER_ID,
            member_id=member_id,
            name="삭제할 프로그램",
            type="근력",
        ),
        TrainerReportFeedback(
            id=f"report-{uuid4().hex[:12]}",
            trainer_id=TRAINER_ID,
            member_id=member_id,
            week_start="2026-08-24",
            body="삭제할 리포트",
        ),
        TrainerClientMemo(
            id=f"memo-{uuid4().hex[:12]}",
            trainer_id=TRAINER_ID,
            member_id=member_id,
            body="삭제할 메모",
        ),
        TrainerFollowUpTask(
            id=f"follow-{uuid4().hex[:12]}",
            trainer_id=TRAINER_ID,
            member_id=member_id,
            title="삭제할 후속 관리",
            due_date="2026-08-28",
        ),
        ChatMessage(
            id=f"chat-{uuid4().hex[:12]}",
            trainer_id=TRAINER_ID,
            member_id=member_id,
            sender="trainer",
            body="삭제할 메시지",
        ),
        RoutineHistory(
            id=f"history-{uuid4().hex[:12]}",
            trainer_id=TRAINER_ID,
            member_id=member_id,
            date="2026-08-27",
        ),
    ]
    link_id = pair_rows[0].id
    expected_preserved = [(type(row), row.id) for row in pair_rows[1:]]
    db_session.add_all(pair_rows)
    db_session.commit()
    try:
        response = client.delete(
            f"/v1/trainer/clients/{member_id}", headers=_headers(token)
        )
        assert response.status_code == 204, response.text

        db_session.expire_all()
        assert db_session.get(User, member_id) is not None
        detached = db_session.get(TrainerClient, link_id)
        assert detached is not None
        assert detached.active is False
        # 담당 해제는 데이터 공유 동의 철회다(#1631).
        assert detached.data_consent_at is None
        assert detached.data_consent_revoked_at is not None
        for model, row_id in expected_preserved:
            assert db_session.get(model, row_id) is not None
        roster = client.get("/v1/trainer/clients", headers=_headers(token)).json()
        roster_row = next(row for row in roster if row["id"] == member_id)
        assert roster_row["registered"] is False
        schedule = client.get(
            "/v1/trainer/schedule",
            params={"date": "2026-08-27"},
            headers=_headers(token),
        ).json()
        assert not any(row["id"] == expected_preserved[0][1] for row in schedule)
        repeated = client.delete(
            f"/v1/trainer/clients/{member_id}", headers=_headers(token)
        )
        assert repeated.status_code == 404

        # 동의가 철회된 회원은 트레이너 혼자 되살릴 수 없다(#1631).
        restored = client.put(
            f"/v1/trainer/clients/{member_id}/registration", headers=_headers(token)
        )
        assert restored.status_code == 409
        roster = client.get("/v1/trainer/clients", headers=_headers(token)).json()
        roster_row = next(row for row in roster if row["id"] == member_id)
        assert roster_row["registered"] is False
    finally:
        db_session.expire_all()
        saved_link = db_session.get(TrainerClient, link_id)
        if saved_link is not None:
            db_session.delete(saved_link)
        for model, row_id in reversed(expected_preserved):
            row = db_session.get(model, row_id)
            if row is not None:
                db_session.delete(row)
        saved = db_session.get(User, member_id)
        if saved is not None:
            db_session.delete(saved)
            db_session.commit()


def test_another_trainer_cannot_remove_client(client, db_session):
    other_id = f"trainer-{uuid4().hex[:10]}"
    other = User(
        id=other_id,
        email=f"{other_id}@oncare.com",
        name="다른 트레이너",
        hashed_password="unused",
        role="trainer",
    )
    db_session.add(other)
    db_session.commit()
    try:
        response = client.delete(
            f"/v1/trainer/clients/{MEMBER_ID}",
            headers=_headers(create_access_token(other_id)),
        )
        assert response.status_code == 404
    finally:
        db_session.delete(other)
        db_session.commit()
