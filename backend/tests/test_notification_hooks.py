"""알림 생성 지점과 회원 알림 설정. (#489)

알림함이 사실상 비어 있었다 — `Notification` 행을 만드는 코드가 데모 시드와 상담
승인·거절(#467) 두 곳뿐이어서, 트레이너가 메시지를 보내도 루틴을 배정해도 일정을
잡아도 회원은 해당 화면에 직접 들어가야 알 수 있었다.

설정과 함께 검증하는 이유: 서버가 설정을 모르면 알림을 만들 때 끌 수가 없다.
"둘 다 되는가"가 아니라 "끈 항목이 실제로 안 만들어지는가"가 핵심이다.

DB 가 필요하므로 로컬에서는 skip 되고 CI(Postgres) 에서 실행된다.
"""
from __future__ import annotations

from datetime import timedelta
from uuid import uuid4

import pytest

from sqlalchemy import text

from app.core import clock
from app.core.security import hash_password
from app.models.models import (
    ChatMessage,
    MemberNotificationSetting,
    Notification,
    Place,
    TrainerClient,
    TrainerProfile,
    TrainerRoutine,
    TrainerSchedule,
    User,
)
from app.services import notification_service

EMAIL_PREFIX = "noti-test-"
PLACE_PREFIX = "noti-place-"
PASSWORD = "noti-pw-1234"


@pytest.fixture(autouse=True)
def _cleanup(db_session):
    yield
    db_session.rollback()
    user_ids = [
        row[0]
        for row in db_session.query(User.id)
        .filter(User.email.like(f"{EMAIL_PREFIX}%"))
        .all()
    ]
    if user_ids:
        for model, column in (
            (Notification, Notification.user_id),
            (MemberNotificationSetting, MemberNotificationSetting.member_id),
            (ChatMessage, ChatMessage.member_id),
            (TrainerRoutine, TrainerRoutine.member_id),
            (TrainerSchedule, TrainerSchedule.member_id),
            (TrainerClient, TrainerClient.member_id),
        ):
            db_session.query(model).filter(column.in_(user_ids)).delete(
                synchronize_session=False
            )
        for model, column in (
            (ChatMessage, ChatMessage.trainer_id),
            (TrainerRoutine, TrainerRoutine.trainer_id),
            (TrainerSchedule, TrainerSchedule.trainer_id),
            (TrainerClient, TrainerClient.trainer_id),
            (TrainerProfile, TrainerProfile.trainer_id),
        ):
            db_session.query(model).filter(column.in_(user_ids)).delete(
                synchronize_session=False
            )
        db_session.query(User).filter(User.id.in_(user_ids)).delete(
            synchronize_session=False
        )
    db_session.query(Place).filter(Place.id.like(f"{PLACE_PREFIX}%")).delete(
        synchronize_session=False
    )
    db_session.commit()


def _auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _login(client, email: str) -> str:
    response = client.post(
        "/v1/auth/login", data={"username": email, "password": PASSWORD}
    )
    assert response.status_code == 200, response.text
    return response.json()["access_token"]


def _pair(client, db_session) -> tuple[str, str, str, str]:
    """담당 관계가 맺어진 (트레이너 토큰, 회원 id, 회원 토큰, 헬스장 id)."""
    suffix = uuid4().hex[:10]
    place = Place(
        id=f"{PLACE_PREFIX}{suffix}",
        name="알림 테스트 헬스장",
        category="fitness",
        address="서울",
    )
    db_session.add(place)

    trainer_email = f"{EMAIL_PREFIX}trainer-{suffix}@oncare.com"
    trainer = User(
        id=f"noti-trainer-{suffix}",
        email=trainer_email,
        name="알림 트레이너",
        hashed_password=hash_password(PASSWORD),
        role="trainer",
        is_active=True,
    )
    db_session.add(trainer)
    db_session.flush()
    db_session.add(TrainerProfile(trainer_id=trainer.id, gym_id=place.id))
    db_session.commit()

    member_email = f"{EMAIL_PREFIX}member-{suffix}@oncare.com"
    created = client.post(
        "/v1/auth/register",
        json={"email": member_email, "password": PASSWORD, "name": "알림 회원"},
    )
    assert created.status_code == 201, created.text
    member_id = created.json()["id"]

    db_session.add(
        TrainerClient(
            id=f"tc-noti-{suffix}",
            trainer_id=trainer.id,
            member_id=member_id,
            goal="알림 테스트",
            active=True,
            sort_order=1,
        )
    )
    db_session.commit()

    return (
        _login(client, trainer_email),
        member_id,
        _login(client, member_email),
        place.id,
    )


def _titles(client, member_token: str) -> list[str]:
    response = client.get("/v1/notifications", headers=_auth(member_token))
    assert response.status_code == 200, response.text
    return [item["title"] for item in response.json()]


# --- 생성 지점 --------------------------------------------------------------


def test_trainer_message_creates_a_notification(client, db_session):
    trainer_token, member_id, member_token, _ = _pair(client, db_session)

    sent = client.post(
        f"/v1/trainer/clients/{member_id}/chat",
        headers=_auth(trainer_token),
        json={"text": "오늘 운동 어떠셨어요?"},
    )

    assert sent.status_code == 201, sent.text
    assert any("메시지" in title for title in _titles(client, member_token))


def test_routine_assignment_creates_a_notification(client, db_session):
    trainer_token, member_id, member_token, _ = _pair(client, db_session)

    assigned = client.post(
        f"/v1/trainer/clients/{member_id}/routines",
        headers=_auth(trainer_token),
        json={
            "name": "인터벌 러닝",
            "minutes": 30,
            "type": "유산소",
            "reason": "체력 향상",
            "source": "trainer",
        },
    )

    assert assigned.status_code == 201, assigned.text
    assert "새 운동 루틴이 배정되었어요" in _titles(client, member_token)


def test_schedule_creates_a_notification(client, db_session):
    trainer_token, member_id, member_token, _ = _pair(client, db_session)

    created = client.post(
        "/v1/trainer/schedule",
        headers=_auth(trainer_token),
        json={
            "date": (clock.today() + timedelta(days=1)).isoformat(),
            "time": "10:00",
            "client_name": "알림 회원",
            "member_id": member_id,
            "type": "1:1 PT",
            "duration_minutes": 50,
            "note": "",
            "program": [],
        },
    )

    assert created.status_code == 201, created.text
    assert "새 일정이 등록되었어요" in _titles(client, member_token)


def test_report_creates_its_own_notification_kind(client, db_session):
    """리포트는 주간 리포트 종류로 남는다 — 일반 메시지와 구분된다.

    리포트도 채팅으로 전달되므로, 종류를 서비스가 판단하면 둘을 구분할 수 없다.
    """
    trainer_token, member_id, member_token, _ = _pair(client, db_session)
    # 기본값은 주간 리포트 꺼짐이므로, 받도록 켜고 확인한다.
    client.put(
        "/v1/users/me/notification-settings",
        headers=_auth(member_token),
        json={"weekly_report": True},
    )

    sent = client.post(
        f"/v1/trainer/clients/{member_id}/report/send",
        headers=_auth(trainer_token),
        json={"message": "이번 주 잘하셨어요"},
    )

    assert sent.status_code == 201, sent.text
    assert "주간 리포트가 도착했어요" in _titles(client, member_token)


def _items(client, member_token: str) -> list[dict]:
    response = client.get("/v1/notifications", headers=_auth(member_token))
    assert response.status_code == 200, response.text
    return response.json()


def test_report_notification_has_its_own_category(client, db_session):
    """주간 리포트는 `coach_report` 갈래이고, 누르면 코치 대화로 간다(#2085).

    트레이너 메시지와 같은 `coach_chat` 이면 회원 앱 알림함이 리포트도 말풍선으로
    그린다. 목적지는 메시지와 같다.
    """
    trainer_token, member_id, member_token, _ = _pair(client, db_session)
    client.put(
        "/v1/users/me/notification-settings",
        headers=_auth(member_token),
        json={"weekly_report": True},
    )

    sent = client.post(
        f"/v1/trainer/clients/{member_id}/report/send",
        headers=_auth(trainer_token),
        json={"message": "이번 주 잘하셨어요"},
    )

    assert sent.status_code == 201, sent.text
    report = next(
        item
        for item in _items(client, member_token)
        if item["title"] == "주간 리포트가 도착했어요"
    )
    assert report["category"] == notification_service.MEMBER_COACH_REPORT
    assert report["action"] == {"label": "리포트 보기", "target": "coach_chat"}


def test_trainer_message_keeps_the_coach_chat_category(client, db_session):
    """트레이너 메시지는 `coach_chat` 그대로다 — 리포트만 갈래가 나뉜다(#2085)."""
    trainer_token, member_id, member_token, _ = _pair(client, db_session)

    sent = client.post(
        f"/v1/trainer/clients/{member_id}/chat",
        headers=_auth(trainer_token),
        json={"text": "오늘 운동 어떠셨어요?"},
    )

    assert sent.status_code == 201, sent.text
    message = next(
        item for item in _items(client, member_token) if "메시지" in item["title"]
    )
    assert message["category"] == notification_service.MEMBER_COACH_CHAT
    assert message["action"]["target"] == "coach_chat"


def test_member_message_creates_no_notification(client, db_session):
    """회원이 보낸 메시지는 자기 알림함에 남지 않는다."""
    _, _, member_token, _ = _pair(client, db_session)

    sent = client.post(
        "/v1/me/coach/chat",
        headers=_auth(member_token),
        json={"text": "질문 있어요"},
    )

    assert sent.status_code == 201, sent.text
    assert _titles(client, member_token) == []


def test_a_schedule_without_a_member_notifies_nobody(client, db_session):
    """가망 고객 슬롯('신규 고객 · 상담')은 알릴 대상이 없다."""
    trainer_token, _, member_token, _ = _pair(client, db_session)

    created = client.post(
        "/v1/trainer/schedule",
        headers=_auth(trainer_token),
        json={
            "date": (clock.today() + timedelta(days=1)).isoformat(),
            "time": "14:00",
            "client_name": "신규 고객",
            "member_id": None,
            "type": "상담",
            "duration_minutes": 30,
            "note": "",
            "program": [],
        },
    )

    assert created.status_code == 201, created.text
    assert _titles(client, member_token) == []


# --- 일정 변경·취소 (#664) ---------------------------------------------------


def _schedule(client, trainer_token: str, member_id: str | None, **overrides):
    """일정을 하나 만들고 그 id 를 준다."""
    payload = {
        "date": (clock.today() + timedelta(days=1)).isoformat(),
        "time": "10:00",
        "client_name": "알림 회원" if member_id else "신규 고객",
        "member_id": member_id,
        "type": "1:1 PT",
        "duration_minutes": 50,
        "note": "",
        "program": [],
    }
    payload.update(overrides)
    created = client.post(
        "/v1/trainer/schedule", headers=_auth(trainer_token), json=payload
    )
    assert created.status_code == 201, created.text
    return created.json()["id"]


def test_moving_a_session_tells_the_member(client, db_session):
    """시각이 바뀌면 알린다 — 등록만 알리면 회원은 옛 시간에 나간다."""
    trainer_token, member_id, member_token, _ = _pair(client, db_session)
    session_id = _schedule(client, trainer_token, member_id)

    moved = client.put(
        f"/v1/trainer/schedule/{session_id}",
        headers=_auth(trainer_token),
        json={"time": "15:00"},
    )

    assert moved.status_code == 200, moved.text
    assert "일정이 변경되었어요" in _titles(client, member_token)


def test_editing_only_the_note_tells_nobody(client, db_session):
    """메모는 트레이너의 준비물이다. 알리면 알림함이 같은 일정으로 찬다."""
    trainer_token, member_id, member_token, _ = _pair(client, db_session)
    session_id = _schedule(client, trainer_token, member_id)
    before = _titles(client, member_token)

    edited = client.put(
        f"/v1/trainer/schedule/{session_id}",
        headers=_auth(trainer_token),
        json={"note": "스쿼트 자세 확인"},
    )

    assert edited.status_code == 200, edited.text
    assert _titles(client, member_token) == before


def test_cancelling_a_session_tells_the_member(client, db_session):
    trainer_token, member_id, member_token, _ = _pair(client, db_session)
    session_id = _schedule(client, trainer_token, member_id)

    removed = client.delete(
        f"/v1/trainer/schedule/{session_id}", headers=_auth(trainer_token)
    )

    assert removed.status_code in (200, 204), removed.text
    assert "일정이 취소되었어요" in _titles(client, member_token)


def test_unassigning_a_member_tells_that_member(client, db_session):
    """배정을 풀면 회원 쪽에서는 약속이 사라진다 — 취소와 같다."""
    trainer_token, member_id, member_token, _ = _pair(client, db_session)
    session_id = _schedule(client, trainer_token, member_id)

    unassigned = client.put(
        f"/v1/trainer/schedule/{session_id}",
        headers=_auth(trainer_token),
        json={"member_id": ""},
    )

    assert unassigned.status_code == 200, unassigned.text
    assert "일정이 취소되었어요" in _titles(client, member_token)


def test_assigning_an_empty_slot_tells_the_new_member(client, db_session):
    """비어 있던 슬롯에 회원이 들어오면 그 회원에게는 새 일정이다."""
    trainer_token, member_id, member_token, _ = _pair(client, db_session)
    session_id = _schedule(client, trainer_token, None, type="상담")

    assigned = client.put(
        f"/v1/trainer/schedule/{session_id}",
        headers=_auth(trainer_token),
        json={"member_id": member_id},
    )

    assert assigned.status_code == 200, assigned.text
    assert "새 일정이 등록되었어요" in _titles(client, member_token)


def test_cancelling_an_empty_slot_tells_nobody(client, db_session):
    trainer_token, _, member_token, _ = _pair(client, db_session)
    session_id = _schedule(client, trainer_token, None, type="상담")

    removed = client.delete(
        f"/v1/trainer/schedule/{session_id}", headers=_auth(trainer_token)
    )

    assert removed.status_code in (200, 204), removed.text
    assert _titles(client, member_token) == []


def test_a_schedule_change_can_be_switched_off(client, db_session):
    """운동 알림을 끄면 변경 알림도 오지 않는다 — 등록 알림과 같은 종류다."""
    trainer_token, member_id, member_token, _ = _pair(client, db_session)
    session_id = _schedule(client, trainer_token, member_id)
    client.put(
        "/v1/users/me/notification-settings",
        headers=_auth(member_token),
        json={"exercise_reminder": False},
    )
    before = _titles(client, member_token)

    moved = client.put(
        f"/v1/trainer/schedule/{session_id}",
        headers=_auth(trainer_token),
        json={"time": "16:00"},
    )

    assert moved.status_code == 200, moved.text
    assert _titles(client, member_token) == before


def test_a_settings_read_failure_still_delivers_the_message(
    client, db_session, monkeypatch
):
    """설정 조회가 터져도 메시지는 저장된다. (CodeRabbit 리뷰)

    예외를 잡는 것만으로는 부족하다 — DB 오류가 나면 세션이 실패 상태로 남아
    이어지는 커밋까지 함께 죽는다. savepoint 로 격리해야 원래 요청이 산다.
    """
    trainer_token, member_id, member_token, _ = _pair(client, db_session)

    def _boom(db, member_id):  # noqa: ANN001
        db.execute(text("SELECT 1 FROM does_not_exist"))
        raise AssertionError("unreachable")

    monkeypatch.setattr(notification_service, "get_settings", _boom)

    sent = client.post(
        f"/v1/trainer/clients/{member_id}/chat",
        headers=_auth(trainer_token),
        json={"text": "설정이 깨져도 도착해야 합니다"},
    )

    assert sent.status_code == 201, sent.text
    thread = client.get("/v1/me/coach/chat", headers=_auth(member_token))
    assert any(
        m["body"] == "설정이 깨져도 도착해야 합니다" for m in thread.json()
    )


def test_explicit_null_is_rejected(client, db_session):
    """명시적 null 은 422 — 누락('변경 없음')과 구분한다. (CodeRabbit 리뷰)

    다섯 항목 모두 DB NOT NULL 이라 null 로 바꿀 수 있는 값이 아니다. 구분하지
    않으면 `{"weekly_report": null}` 이 조용히 성공하고 아무것도 바뀌지 않는다.
    `ScheduleUpdateRequest` 와 같은 규약이다(#377).
    """
    _, _, member_token, _ = _pair(client, db_session)

    response = client.put(
        "/v1/users/me/notification-settings",
        headers=_auth(member_token),
        json={"weekly_report": None},
    )

    assert response.status_code == 422, response.text


def test_omitted_fields_still_mean_no_change(client, db_session):
    """누락은 여전히 '변경 없음'이다 — null 거절이 부분 수정을 막지 않는다."""
    _, _, member_token, _ = _pair(client, db_session)

    updated = client.put(
        "/v1/users/me/notification-settings",
        headers=_auth(member_token),
        json={"weekly_report": True},
    )

    assert updated.status_code == 200, updated.text
    assert updated.json()["weekly_report"] is True
    assert updated.json()["trainer_message"] is True


def test_an_empty_settings_update_creates_no_row(client, db_session):
    """바꿀 게 없으면 기본값 행을 새로 남기지 않는다. (CodeRabbit 리뷰)"""
    _, member_id, member_token, _ = _pair(client, db_session)

    response = client.put(
        "/v1/users/me/notification-settings",
        headers=_auth(member_token),
        json={},
    )

    assert response.status_code == 200, response.text
    db_session.expire_all()
    assert db_session.get(MemberNotificationSetting, member_id) is None


# --- 수신 설정 --------------------------------------------------------------


def test_settings_default_matches_the_app(client, db_session):
    """저장한 적이 없으면 앱의 현재 기본값과 같다(주간 리포트만 꺼짐)."""
    _, _, member_token, _ = _pair(client, db_session)

    settings = client.get(
        "/v1/users/me/notification-settings", headers=_auth(member_token)
    )

    assert settings.status_code == 200, settings.text
    body = settings.json()
    assert body["trainer_message"] is True
    assert body["exercise_reminder"] is True
    assert body["diet_log"] is True
    assert body["ai_coaching"] is True
    assert body["weekly_report"] is False


def test_settings_survive_a_new_session(client, db_session):
    """계정 단위 저장 — 기기를 바꿔도 유지된다."""
    _, _, member_token, _ = _pair(client, db_session)
    client.put(
        "/v1/users/me/notification-settings",
        headers=_auth(member_token),
        json={"trainer_message": False},
    )

    # 같은 계정으로 다시 로그인해도(= 다른 기기) 값이 남아 있어야 한다.
    email = (
        client.get("/v1/users/me", headers=_auth(member_token)).json()["email"]
    )
    fresh = client.get(
        "/v1/users/me/notification-settings", headers=_auth(_login(client, email))
    )

    assert fresh.json()["trainer_message"] is False


def test_partial_update_leaves_other_items_alone(client, db_session):
    _, _, member_token, _ = _pair(client, db_session)

    updated = client.put(
        "/v1/users/me/notification-settings",
        headers=_auth(member_token),
        json={"weekly_report": True},
    )

    assert updated.status_code == 200, updated.text
    body = updated.json()
    assert body["weekly_report"] is True
    assert body["trainer_message"] is True


def test_a_disabled_kind_creates_no_notification(client, db_session):
    """끈 항목은 알림이 만들어지지 않는다 — 설정을 서버가 갖는 이유."""
    trainer_token, member_id, member_token, _ = _pair(client, db_session)
    client.put(
        "/v1/users/me/notification-settings",
        headers=_auth(member_token),
        json={"trainer_message": False},
    )

    sent = client.post(
        f"/v1/trainer/clients/{member_id}/chat",
        headers=_auth(trainer_token),
        json={"text": "알림은 꺼져 있어야 합니다"},
    )

    assert sent.status_code == 201, sent.text
    assert _titles(client, member_token) == []


def test_a_disabled_kind_still_delivers_the_message(client, db_session):
    """알림만 끄는 것이지 메시지가 사라지는 게 아니다."""
    trainer_token, member_id, member_token, _ = _pair(client, db_session)
    client.put(
        "/v1/users/me/notification-settings",
        headers=_auth(member_token),
        json={"trainer_message": False},
    )

    client.post(
        f"/v1/trainer/clients/{member_id}/chat",
        headers=_auth(trainer_token),
        json={"text": "메시지는 도착해야 합니다"},
    )

    thread = client.get("/v1/me/coach/chat", headers=_auth(member_token))
    assert thread.status_code == 200, thread.text
    assert any(m["body"] == "메시지는 도착해야 합니다" for m in thread.json())


def test_report_is_off_by_default(client, db_session):
    """주간 리포트는 기본 꺼짐이라 켜기 전에는 알림이 없다."""
    trainer_token, member_id, member_token, _ = _pair(client, db_session)

    client.post(
        f"/v1/trainer/clients/{member_id}/report/send",
        headers=_auth(trainer_token),
        json={"message": "이번 주 리포트"},
    )

    assert "주간 리포트가 도착했어요" not in _titles(client, member_token)


def test_trainer_cannot_use_the_member_settings_endpoint(client, db_session):
    trainer_token, _, _, _ = _pair(client, db_session)

    response = client.put(
        "/v1/users/me/notification-settings",
        headers=_auth(trainer_token),
        json={"trainer_message": False},
    )

    assert response.status_code == 403, response.text
