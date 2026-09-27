"""트레이너 메시지 알림의 보낸 회원·대화 읽음 연동. (#2291) DB 필요.

전에는 메시지 알림에 보낸 회원이 남지 않아 알림을 눌러도 고객 목록으로만
갔고, 트레이너가 그 회원과의 대화를 읽어도 알림은 미읽음으로 남아 배지에
계속 걸려 있었다.
"""
from __future__ import annotations

from uuid import uuid4

import pytest

TRAINER_ID = "trainer-demo"
JISU = "user-jisu"
MINSU = "user-7d4e9a2c5f18"


def _login(client, email: str, password: str = "oncare123") -> str:
    res = client.post(
        "/v1/auth/login", data={"username": email, "password": password}
    )
    assert res.status_code == 200, res.text
    return res.json()["access_token"]


def _h(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture()
def trainer_token(client) -> str:
    return _login(client, "trainer@oncare.com")


@pytest.fixture()
def jisu_token(client) -> str:
    return _login(client, "jisu@oncare.com")


@pytest.fixture()
def minsu_token(client) -> str:
    return _login(client, "minsu@oncare.com")


@pytest.fixture()
def created_notifications(db_session):
    """테스트가 직접 넣은 알림 id. 끝나면 지운다."""
    from app.models.models import Notification

    ids: list[str] = []
    yield ids
    db_session.rollback()
    if ids:
        db_session.query(Notification).filter(Notification.id.in_(ids)).delete(
            synchronize_session=False
        )
        db_session.commit()


def _insert(db_session, ids: list[str], **fields):
    from app.models.models import Notification

    row = Notification(
        id=f"noti-{uuid4().hex[:12]}",
        title=fields.pop("title", "테스트 알림"),
        body=fields.pop("body", ""),
        read=fields.pop("read", False),
        **fields,
    )
    db_session.add(row)
    db_session.commit()
    ids.append(row.id)
    return row.id


def _send_as_member(client, token: str) -> str:
    text = f"메시지 {uuid4().hex[:8]}"
    res = client.post("/v1/me/coach/chat", json={"text": text}, headers=_h(token))
    assert res.status_code == 201, res.text
    return text


def _trainer_rows(client, trainer_token) -> list[dict]:
    res = client.get("/v1/trainer/notifications", headers=_h(trainer_token))
    assert res.status_code == 200, res.text
    return res.json()


def _row_by_body(client, trainer_token, body: str) -> dict:
    rows = [r for r in _trainer_rows(client, trainer_token) if r["body"] == body]
    assert len(rows) == 1, rows
    return rows[0]


def _row_by_id(db_session, notification_id: str):
    from app.models.models import Notification

    db_session.expire_all()
    return db_session.get(Notification, notification_id)


def _unread(client, trainer_token) -> int:
    res = client.get(
        "/v1/trainer/notifications/unread-count", headers=_h(trainer_token)
    )
    assert res.status_code == 200, res.text
    return res.json()["unread"]


def _read_thread(client, trainer_token, member_id: str) -> dict:
    res = client.post(
        f"/v1/trainer/clients/{member_id}/chat/read", headers=_h(trainer_token)
    )
    assert res.status_code == 200, res.text
    return res.json()


# ---- 보낸 회원 기록 ----


def test_message_notification_records_the_sender(client, trainer_token, jisu_token):
    """회원 메시지 알림은 보낸 회원을 subject_id 로 남긴다."""
    text = _send_as_member(client, jisu_token)

    row = _row_by_body(client, trainer_token, text)
    assert row["category"] == "message"
    assert row["subject_id"] == JISU
    assert row["read"] is False


def test_each_member_is_recorded_as_their_own_sender(
    client, trainer_token, jisu_token, minsu_token
):
    """두 회원이 보낸 알림이 서로의 id 로 섞이지 않는다."""
    jisu_text = _send_as_member(client, jisu_token)
    minsu_text = _send_as_member(client, minsu_token)

    assert _row_by_body(client, trainer_token, jisu_text)["subject_id"] == JISU
    assert _row_by_body(client, trainer_token, minsu_text)["subject_id"] == MINSU


def test_trainer_messages_do_not_notify_the_trainer(client, trainer_token):
    """트레이너가 보낸 메시지로는 트레이너 알림이 생기지 않는다(회귀)."""
    text = f"트레이너 발신 {uuid4().hex[:8]}"
    res = client.post(
        f"/v1/trainer/clients/{JISU}/chat",
        json={"text": text},
        headers=_h(trainer_token),
    )
    assert res.status_code == 201, res.text
    assert all(r["body"] != text for r in _trainer_rows(client, trainer_token))


# ---- 대화 읽음 → 알림 읽음 ----


def test_reading_the_thread_marks_its_message_notifications_read(
    client, trainer_token, jisu_token
):
    """대화를 읽으면 그 회원이 보낸 메시지 알림이 모두 읽음이 된다."""
    first = _send_as_member(client, jisu_token)
    second = _send_as_member(client, jisu_token)
    before = _unread(client, trainer_token)

    _read_thread(client, trainer_token, JISU)

    assert _row_by_body(client, trainer_token, first)["read"] is True
    assert _row_by_body(client, trainer_token, second)["read"] is True
    assert _unread(client, trainer_token) <= before - 2


def test_reading_one_thread_leaves_other_members_unread(
    client, trainer_token, jisu_token, minsu_token
):
    """다른 회원의 메시지 알림은 그 회원 대화를 읽기 전까지 남는다."""
    jisu_text = _send_as_member(client, jisu_token)
    minsu_text = _send_as_member(client, minsu_token)

    _read_thread(client, trainer_token, JISU)

    assert _row_by_body(client, trainer_token, jisu_text)["read"] is True
    assert _row_by_body(client, trainer_token, minsu_text)["read"] is False

    _read_thread(client, trainer_token, MINSU)
    assert _row_by_body(client, trainer_token, minsu_text)["read"] is True


def test_thread_read_count_still_counts_chat_messages_only(
    client, trainer_token, jisu_token
):
    """응답의 marked_read 는 채팅 메시지 수 그대로다 — 알림 수가 섞이지 않는다."""
    _read_thread(client, trainer_token, JISU)
    _send_as_member(client, jisu_token)
    _send_as_member(client, jisu_token)

    assert _read_thread(client, trainer_token, JISU)["marked_read"] == 2
    # 두 번째 읽음은 채팅·알림 모두 할 일이 없다.
    assert _read_thread(client, trainer_token, JISU)["marked_read"] == 0


def test_other_kinds_about_the_same_member_stay_unread(
    client, trainer_token, db_session, created_notifications
):
    """같은 회원을 가리켜도 메시지가 아닌 알림(건강 목표 변경)은 건드리지 않는다."""
    goal_id = _insert(
        db_session,
        created_notifications,
        user_id=TRAINER_ID,
        category="health_goal",
        subject_id=JISU,
    )

    _read_thread(client, trainer_token, JISU)

    assert _row_by_id(db_session, goal_id).read is False


def test_old_message_notifications_without_sender_stay_unread(
    client, trainer_token, db_session, created_notifications
):
    """보낸 회원이 없는 옛 알림은 누구 것인지 몰라 그대로 둔다."""
    old_id = _insert(
        db_session,
        created_notifications,
        user_id=TRAINER_ID,
        category="message",
        subject_id=None,
    )

    _read_thread(client, trainer_token, JISU)

    assert _row_by_id(db_session, old_id).read is False


def test_already_read_notifications_are_left_as_is(
    client, trainer_token, db_session, created_notifications
):
    """이미 읽은 알림은 그대로 읽음이다(되돌리지 않는다)."""
    read_id = _insert(
        db_session,
        created_notifications,
        user_id=TRAINER_ID,
        category="message",
        subject_id=JISU,
        read=True,
    )

    _read_thread(client, trainer_token, JISU)

    assert _row_by_id(db_session, read_id).read is True


def test_other_accounts_notifications_are_not_touched(
    client, trainer_token, db_session, created_notifications
):
    """다른 계정의 알림은 같은 회원·같은 종류라도 건드리지 않는다."""
    foreign_id = _insert(
        db_session,
        created_notifications,
        user_id="user-sungho",
        category="message",
        subject_id=JISU,
    )

    _read_thread(client, trainer_token, JISU)

    assert _row_by_id(db_session, foreign_id).read is False


def test_member_reading_the_thread_leaves_trainer_notifications(
    client, trainer_token, jisu_token
):
    """회원이 대화를 읽는 것은 트레이너 알림과 무관하다."""
    text = _send_as_member(client, jisu_token)

    res = client.post("/v1/me/coach/chat/read", headers=_h(jisu_token))
    assert res.status_code == 200, res.text

    assert _row_by_body(client, trainer_token, text)["read"] is False


def test_reading_a_non_client_thread_is_rejected_and_changes_nothing(
    client, trainer_token, jisu_token, db_session, created_notifications
):
    """담당이 아닌 회원 id 로는 읽음 처리가 막히고 알림도 그대로다."""
    stray_id = _insert(
        db_session,
        created_notifications,
        user_id=TRAINER_ID,
        category="message",
        subject_id="user-not-a-client",
    )

    res = client.post(
        "/v1/trainer/clients/user-not-a-client/chat/read",
        headers=_h(trainer_token),
    )
    assert res.status_code in (403, 404), res.text
    assert _row_by_id(db_session, stray_id).read is False


def test_member_token_cannot_mark_a_trainer_thread_read(client, jisu_token):
    """회원 토큰으로는 트레이너 쪽 읽음 경로를 쓸 수 없다."""
    res = client.post(f"/v1/trainer/clients/{JISU}/chat/read", headers=_h(jisu_token))
    assert res.status_code == 403


# ---- 서비스 단위 ----


def test_service_marks_only_matching_trainer_message_notifications(
    client, db_session, created_notifications
):
    """mark_thread_read(reader='trainer') 가 고르는 행을 직접 확인한다."""
    from app.services import trainer_service

    target = _insert(
        db_session, created_notifications,
        user_id=TRAINER_ID, category="message", subject_id=JISU,
    )
    other_member = _insert(
        db_session, created_notifications,
        user_id=TRAINER_ID, category="message", subject_id=MINSU,
    )
    other_kind = _insert(
        db_session, created_notifications,
        user_id=TRAINER_ID, category="reservation", subject_id=JISU,
    )

    trainer_service.mark_thread_read(db_session, TRAINER_ID, JISU, "trainer")

    assert _row_by_id(db_session, target).read is True
    assert _row_by_id(db_session, other_member).read is False
    assert _row_by_id(db_session, other_kind).read is False


def test_service_member_reader_does_not_touch_notifications(
    client, db_session, created_notifications
):
    """reader='member' 는 알림을 건드리지 않는다."""
    from app.services import trainer_service

    target = _insert(
        db_session, created_notifications,
        user_id=TRAINER_ID, category="message", subject_id=JISU,
    )

    trainer_service.mark_thread_read(db_session, TRAINER_ID, JISU, "member")

    assert _row_by_id(db_session, target).read is False


def test_disabled_message_notifications_still_allow_thread_read(
    client, trainer_token, jisu_token
):
    """메시지 알림을 끈 상태에서도 대화 읽음은 그대로 동작한다."""
    client.put(
        "/v1/trainer/me/settings",
        json={"notify_new_message": False},
        headers=_h(trainer_token),
    )
    try:
        _read_thread(client, trainer_token, JISU)
        text = _send_as_member(client, jisu_token)
        assert all(r["body"] != text for r in _trainer_rows(client, trainer_token))
        assert _read_thread(client, trainer_token, JISU)["marked_read"] == 1
    finally:
        client.put(
            "/v1/trainer/me/settings",
            json={"notify_new_message": True},
            headers=_h(trainer_token),
        )
