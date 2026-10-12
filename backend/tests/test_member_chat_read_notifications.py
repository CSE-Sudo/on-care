"""회원이 대화를 읽으면 메시지·리포트 알림도 읽음이 된다. (#3343) DB 필요.

트레이너 쪽은 #2291 에서 대화 읽음과 메시지 알림을 묶었다. 회원 쪽은 대화의
`read_at` 만 채워, 대화를 다 읽어 대화 배지가 꺼져도 종 표시는 알림함에서 하나씩
누를 때까지 남아 있었다.
"""
from __future__ import annotations

from uuid import uuid4

import pytest

TRAINER_ID = "trainer-demo"
JISU = "user-jisu"
MINSU = "user-7d4e9a2c5f18"

_COACH_KINDS = ("coach_chat", "coach_report")


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


@pytest.fixture(autouse=True)
def keep_seed_unread(db_session):
    """대화 읽음이 시드 알림까지 읽음으로 바꾼다 — 끝나면 원래대로 돌린다.

    회원 분기는 갈래 전체를 읽으므로, 시드에 미읽음으로 깔린 메시지·리포트 알림도
    함께 바뀐다. 다른 테스트가 시드 미읽음 수를 보므로 되돌려 둔다.
    """
    from app.models.models import Notification

    before = [
        row.id
        for row in db_session.query(Notification).filter(
            Notification.user_id.in_((JISU, MINSU)),
            Notification.category.in_(_COACH_KINDS),
            Notification.read.is_(False),
        )
    ]
    yield
    db_session.rollback()
    if before:
        db_session.query(Notification).filter(Notification.id.in_(before)).update(
            {Notification.read: False}, synchronize_session=False
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


def _row_by_id(db_session, notification_id: str):
    from app.models.models import Notification

    db_session.expire_all()
    return db_session.get(Notification, notification_id)


def _unread_coach_rows(db_session, member_id: str) -> list:
    from app.models.models import Notification

    db_session.expire_all()
    return (
        db_session.query(Notification)
        .filter(
            Notification.user_id == member_id,
            Notification.category.in_(_COACH_KINDS),
            Notification.read.is_(False),
        )
        .all()
    )


def _unread(client, token: str) -> int:
    res = client.get("/v1/notifications/unread-count", headers=_h(token))
    assert res.status_code == 200, res.text
    return res.json()["unread"]


def _send_as_trainer(client, trainer_token: str, member_id: str) -> str:
    text = f"메시지 {uuid4().hex[:8]}"
    res = client.post(
        f"/v1/trainer/clients/{member_id}/chat",
        json={"text": text},
        headers=_h(trainer_token),
    )
    assert res.status_code == 201, res.text
    return text


def _read_as_member(client, token: str) -> dict:
    res = client.post("/v1/me/coach/chat/read", headers=_h(token))
    assert res.status_code == 200, res.text
    return res.json()


# ---- API ----


def test_reading_the_thread_marks_trainer_message_notifications_read(
    client, db_session, trainer_token, jisu_token
):
    """트레이너가 여러 번 보낸 메시지 알림이 대화 읽음 한 번에 모두 꺼진다."""
    _read_as_member(client, jisu_token)
    for _ in range(3):
        _send_as_trainer(client, trainer_token, JISU)
    assert len(_unread_coach_rows(db_session, JISU)) == 3

    assert _read_as_member(client, jisu_token)["marked_read"] == 3

    assert _unread_coach_rows(db_session, JISU) == []


def test_bell_count_drops_by_the_coach_notifications(
    client, db_session, trainer_token, jisu_token, created_notifications
):
    """종 표시 수는 메시지·리포트 알림만큼만 줄고, 다른 갈래는 남는다."""
    _read_as_member(client, jisu_token)
    _insert(
        db_session, created_notifications,
        user_id=JISU, category="member_schedule",
    )
    baseline = _unread(client, jisu_token)
    _send_as_trainer(client, trainer_token, JISU)
    _insert(
        db_session, created_notifications,
        user_id=JISU, category="coach_report",
    )
    assert _unread(client, jisu_token) == baseline + 2

    _read_as_member(client, jisu_token)

    assert _unread(client, jisu_token) == baseline


def test_reading_marks_report_notifications_read(
    client, db_session, jisu_token, created_notifications
):
    """리포트도 대화 스레드로 도착하므로 함께 읽음이 된다."""
    report = _insert(
        db_session, created_notifications,
        user_id=JISU, category="coach_report",
    )

    _read_as_member(client, jisu_token)

    assert _row_by_id(db_session, report).read is True


@pytest.mark.parametrize(
    "category",
    [
        "member_schedule",
        "routine",
        "consultation_result",
        "pt_done",
        "reminder",
        "achievement",
        "system",
    ],
)
def test_reading_leaves_other_kinds_unread(
    client, db_session, jisu_token, created_notifications, category
):
    """일정·루틴·담당 연결 같은 다른 갈래 알림은 대화에서 확인한 것이 아니다."""
    other = _insert(
        db_session, created_notifications, user_id=JISU, category=category
    )

    _read_as_member(client, jisu_token)

    assert _row_by_id(db_session, other).read is False


def test_reading_leaves_another_members_notifications_unread(
    client, db_session, jisu_token, created_notifications
):
    """내가 읽어도 다른 회원의 메시지 알림은 그대로다."""
    theirs = _insert(
        db_session, created_notifications, user_id=MINSU, category="coach_chat"
    )

    _read_as_member(client, jisu_token)

    assert _row_by_id(db_session, theirs).read is False


def test_marked_read_counts_messages_not_notifications(
    client, db_session, jisu_token, created_notifications
):
    """반환값은 읽은 메시지 수다 — 알림만 남아 있으면 0 이고 알림은 꺼진다."""
    _read_as_member(client, jisu_token)
    stale = _insert(
        db_session, created_notifications, user_id=JISU, category="coach_chat"
    )

    assert _read_as_member(client, jisu_token)["marked_read"] == 0

    assert _row_by_id(db_session, stale).read is True


def test_reading_twice_is_idempotent(client, db_session, trainer_token, jisu_token):
    """이미 읽은 대화를 다시 읽어도 달라지는 것이 없다."""
    _send_as_trainer(client, trainer_token, JISU)
    _read_as_member(client, jisu_token)
    before = _unread(client, jisu_token)

    assert _read_as_member(client, jisu_token)["marked_read"] == 0

    assert _unread(client, jisu_token) == before


def test_trainer_reading_leaves_member_notifications_unread(
    client, db_session, trainer_token, created_notifications
):
    """트레이너가 대화를 읽는 것은 회원 알림과 무관하다."""
    mine = _insert(
        db_session, created_notifications, user_id=JISU, category="coach_chat"
    )

    res = client.post(
        f"/v1/trainer/clients/{JISU}/chat/read", headers=_h(trainer_token)
    )
    assert res.status_code == 200, res.text

    assert _row_by_id(db_session, mine).read is False


# ---- 서비스 단위 ----


def test_service_member_reader_marks_only_coach_kinds(
    client, db_session, created_notifications
):
    """mark_thread_read(reader='member') 가 고르는 행을 직접 확인한다."""
    from app.services.trainer import chat as trainer_chat_service

    chat = _insert(
        db_session, created_notifications, user_id=JISU, category="coach_chat"
    )
    report = _insert(
        db_session, created_notifications, user_id=JISU, category="coach_report"
    )
    schedule = _insert(
        db_session, created_notifications,
        user_id=JISU, category="member_schedule",
    )
    other_member = _insert(
        db_session, created_notifications, user_id=MINSU, category="coach_chat"
    )
    trainer_side = _insert(
        db_session, created_notifications,
        user_id=TRAINER_ID, category="message", subject_id=JISU,
    )

    trainer_chat_service.mark_thread_read(db_session, TRAINER_ID, JISU, "member")

    assert _row_by_id(db_session, chat).read is True
    assert _row_by_id(db_session, report).read is True
    assert _row_by_id(db_session, schedule).read is False
    assert _row_by_id(db_session, other_member).read is False
    assert _row_by_id(db_session, trainer_side).read is False


def test_service_trainer_reader_does_not_touch_member_notifications(
    client, db_session, created_notifications
):
    """reader='trainer' 는 회원의 메시지·리포트 알림을 건드리지 않는다."""
    from app.services.trainer import chat as trainer_chat_service

    chat = _insert(
        db_session, created_notifications, user_id=JISU, category="coach_chat"
    )
    report = _insert(
        db_session, created_notifications, user_id=JISU, category="coach_report"
    )

    trainer_chat_service.mark_thread_read(db_session, TRAINER_ID, JISU, "trainer")

    assert _row_by_id(db_session, chat).read is False
    assert _row_by_id(db_session, report).read is False
