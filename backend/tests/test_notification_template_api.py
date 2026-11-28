"""알림 목록의 문장과 문장 틀. (#2302, #3404) DB 필요.

알림은 문장(`title`·`body`)과 함께 문장 틀·인자를 저장한다. 서버 문장은 한국어
하나다 — `Accept-Language` 가 무엇이든 목록은 저장된 문장을 그대로 준다.

  * 저장: 틀·인자와 한국어 `title`·`body`.
  * 트레이너 목록(`/trainer/notifications`)·회원 목록(`/notifications`): 헤더가
    없든 `ko` 든 `en` 이든 저장된 문장 그대로.
  * 응답에 `template`·`args` 가 실린다 — 앱이 문장을 직접 조립할 때 쓰는 재료다.
  * 틀 없는 옛 알림·모르는 틀·깨진 인자도 저장된 문장이다(500 이 아니다).
  * 회원 알림의 액션 라벨·상대 시각도 한국어다.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from uuid import uuid4

import pytest
from sqlalchemy import select

from app.core.security import hash_password
from app.models.models import (
    ChatMessage,
    HealthProfile,
    Notification,
    Place,
    TrainerClient,
    TrainerProfile,
    TrainerReservation,
    TrainerReservationSlot,
    TrainerRoutine,
    TrainerSchedule,
    User,
)
from app.services import notification_templates as nt

EMAIL_PREFIX = "noti-l10n-"
PLACE_PREFIX = "noti-l10n-place-"
PASSWORD = "noti-l10n-pw-1234"

EN = {"Accept-Language": "en"}
KO = {"Accept-Language": "ko"}
#: 어떤 헤더로 불러도 같은 한국어 응답이어야 한다.
HEADERS = [None, KO, EN, {"Accept-Language": "en-US,en;q=0.9"}]


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
        slot_ids = [
            row[0]
            for row in db_session.query(TrainerReservationSlot.id)
            .filter(TrainerReservationSlot.trainer_id.in_(user_ids))
            .all()
        ]
        if slot_ids:
            db_session.query(TrainerReservation).filter(
                TrainerReservation.slot_id.in_(slot_ids)
            ).delete(synchronize_session=False)
        for model, column in (
            (Notification, Notification.user_id),
            (ChatMessage, ChatMessage.member_id),
            (TrainerRoutine, TrainerRoutine.member_id),
            (TrainerSchedule, TrainerSchedule.member_id),
            (TrainerClient, TrainerClient.member_id),
            (TrainerSchedule, TrainerSchedule.trainer_id),
            (TrainerReservationSlot, TrainerReservationSlot.trainer_id),
            (TrainerProfile, TrainerProfile.trainer_id),
            (HealthProfile, HealthProfile.user_id),
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


def _auth(token: str, extra: dict | None = None) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}", **(extra or {})}


def _login(client, email: str) -> str:
    res = client.post("/v1/auth/login", data={"username": email, "password": PASSWORD})
    assert res.status_code == 200, res.text
    return res.json()["access_token"]


def _pair(client, db_session, *, member_name: str = "Alex", trainer_name: str = "Coach Park"):
    """담당 관계인 (트레이너 토큰, 트레이너 id, 회원 id, 회원 토큰)."""
    suffix = uuid4().hex[:10]
    place = Place(
        id=f"{PLACE_PREFIX}{suffix}", name="L10n Gym", category="fitness", address="Seoul"
    )
    db_session.add(place)
    trainer_email = f"{EMAIL_PREFIX}trainer-{suffix}@oncare.com"
    trainer = User(
        id=f"noti-l10n-trainer-{suffix}",
        email=trainer_email,
        name=trainer_name,
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
        json={"email": member_email, "password": PASSWORD, "name": member_name},
    )
    assert created.status_code == 201, created.text
    member_id = created.json()["id"]
    db_session.add(
        TrainerClient(
            id=f"tc-l10n-{suffix}",
            trainer_id=trainer.id,
            member_id=member_id,
            goal="",
            active=True,
            sort_order=1,
        )
    )
    db_session.commit()
    return _login(client, trainer_email), trainer.id, member_id, _login(client, member_email)


def _trainer_inbox(client, token: str, headers: dict | None = None) -> list[dict]:
    res = client.get("/v1/trainer/notifications", headers=_auth(token, headers))
    assert res.status_code == 200, res.text
    return res.json()


def _member_inbox(client, token: str, headers: dict | None = None) -> list[dict]:
    res = client.get("/v1/notifications", headers=_auth(token, headers))
    assert res.status_code == 200, res.text
    return res.json()


def _add_row(db_session, user_id: str, **fields) -> str:
    row_id = f"noti-l10n-{uuid4().hex[:10]}"
    db_session.add(
        Notification(
            id=row_id,
            user_id=user_id,
            read=False,
            created_at=datetime.now(timezone.utc),
            **fields,
        )
    )
    db_session.commit()
    return row_id


# --------------------------------------------------------------------------
# 트레이너가 받는 알림
# --------------------------------------------------------------------------


def test_member_message_is_stored_with_its_template_and_korean_text(client, db_session):
    trainer_token, trainer_id, member_id, member_token = _pair(client, db_session)
    text = f"Leg day was tough {uuid4().hex[:4]}"
    sent = client.post("/v1/me/coach/chat", json={"text": text}, headers=_auth(member_token))
    assert sent.status_code == 201, sent.text

    row = db_session.scalar(
        select(Notification).where(
            Notification.user_id == trainer_id, Notification.body == text
        )
    )
    assert row is not None
    # 저장되는 문장은 한국어다 — 옛 앱·푸시가 이 값을 읽는다.
    assert row.title == "Alex 회원의 메시지"
    assert row.template == nt.TRAINER_MEMBER_MESSAGE
    assert row.template_args == {"member_name": "Alex"}


@pytest.mark.parametrize("headers", HEADERS)
def test_trainer_inbox_is_korean_whatever_the_header(client, db_session, headers):
    trainer_token, _, _, member_token = _pair(client, db_session)
    text = f"Hello coach {uuid4().hex[:4]}"
    client.post("/v1/me/coach/chat", json={"text": text}, headers=_auth(member_token))

    newest = _trainer_inbox(client, trainer_token, headers)[0]
    assert newest["title"] == "Alex 회원의 메시지"
    # 회원이 쓴 글은 그대로다.
    assert newest["body"] == text
    # 틀과 인자는 함께 실린다 — 트레이너 웹이 문장을 조립할 때 쓰는 재료다.
    assert newest["template"] == nt.TRAINER_MEMBER_MESSAGE
    assert newest["args"] == {"member_name": "Alex"}


def test_member_goal_change_reaches_the_trainer_in_korean(client, db_session):
    trainer_token, _, _, member_token = _pair(client, db_session)
    saved = client.put(
        "/v1/users/me/health-goals",
        headers=_auth(member_token),
        json={"conditions": "근력 향상, 재활"},
    )
    assert saved.status_code == 200, saved.text

    for headers in (None, EN):
        [row] = [
            n for n in _trainer_inbox(client, trainer_token, headers)
            if n["category"] == "health_goal"
        ]
        assert row["title"] == "회원 건강 목표가 바뀌었어요"
        assert row["body"] == "Alex 회원이 건강 목표를 바꿨어요: 근력 향상 · 재활"
        assert row["args"] == {"member_name": "Alex", "focus": ["근력 향상", "재활"]}


def test_member_clearing_goals_says_none(client, db_session):
    trainer_token, _, _, member_token = _pair(client, db_session)
    client.put(
        "/v1/users/me/health-goals", headers=_auth(member_token), json={"conditions": "재활"}
    )
    client.put(
        "/v1/users/me/health-goals", headers=_auth(member_token), json={"conditions": ""}
    )
    for headers in (None, EN):
        assert _trainer_inbox(client, trainer_token, headers)[0]["body"].endswith(": 목표 없음")


def test_reservation_booked_and_cancelled_in_korean(client, db_session):
    trainer_token, _, _, member_token = _pair(client, db_session)
    starts = (datetime.now(timezone.utc) + timedelta(days=5)).replace(
        minute=30, second=0, microsecond=0
    )
    slot = client.post(
        "/v1/trainer/reservation-slots",
        headers=_auth(trainer_token),
        json={"starts_at": starts.isoformat(), "capacity": 1},
    )
    assert slot.status_code == 201, slot.text
    booked = client.post(
        "/v1/reservations", headers=_auth(member_token), json={"slot_id": slot.json()["id"]}
    )
    assert booked.status_code == 201, booked.text

    seoul = starts.astimezone(timezone(timedelta(hours=9)))
    for headers in (None, EN):
        row = _trainer_inbox(client, trainer_token, headers)[0]
        assert row["title"] == "새 예약이 들어왔어요"
        assert row["body"] == f"Alex 회원 · {seoul.month}월 {seoul.day}일 {seoul:%H:%M}"

    client.delete(f"/v1/reservations/{booked.json()['id']}", headers=_auth(member_token))
    for headers in (None, EN):
        assert _trainer_inbox(client, trainer_token, headers)[0]["title"] == "예약이 취소됐어요"


def test_member_rename_reaches_the_trainer_in_korean(client, db_session):
    trainer_token, _, _, member_token = _pair(client, db_session)
    renamed = client.put(
        "/v1/users/me", headers=_auth(member_token), json={"name": "Alexandra"}
    )
    assert renamed.status_code == 200, renamed.text
    for headers in (None, EN):
        [row] = [
            n for n in _trainer_inbox(client, trainer_token, headers)
            if n["category"] == "member_name"
        ]
        assert (row["title"], row["body"]) == (
            "회원 이름이 바뀌었어요", "Alex 회원이 이름을 바꿨어요: Alexandra",
        )


# --------------------------------------------------------------------------
# 옛 알림·깨진 알림
# --------------------------------------------------------------------------


@pytest.mark.parametrize("headers", HEADERS)
def test_old_notifications_without_a_template_keep_their_text(client, db_session, headers):
    trainer_token, trainer_id, _, _ = _pair(client, db_session)
    _add_row(
        db_session, trainer_id, title="새 상담 요청이 도착했어요",
        body="지수 회원 · 2026-10-01", category="consultation",
    )
    newest = _trainer_inbox(client, trainer_token, headers)[0]
    assert newest["title"] == "새 상담 요청이 도착했어요"
    assert newest["body"] == "지수 회원 · 2026-10-01"
    assert newest["template"] is None
    assert newest["args"] is None


@pytest.mark.parametrize(
    ("template", "args"),
    [
        ("from_a_newer_server", {"member_name": "Alex"}),
        (nt.TRAINER_RESERVATION_BOOKED, {"member_name": "Alex", "starts_at": "garbage"}),
        (nt.TRAINER_HEALTH_GOAL, {"member_name": "Alex", "focus": 7}),
    ],
)
def test_unknown_or_broken_templates_answer_with_the_stored_text(
    client, db_session, template, args
):
    trainer_token, trainer_id, _, _ = _pair(client, db_session)
    _add_row(
        db_session, trainer_id, title="저장된 제목", body="저장된 본문",
        category="reservation", template=template, template_args=args,
    )
    for headers in (None, EN):
        newest = _trainer_inbox(client, trainer_token, headers)[0]
        assert (newest["title"], newest["body"]) == ("저장된 제목", "저장된 본문")
        # 틀은 그대로 실어 준다 — 앱이 아는 틀이면 앱이 조립한다.
        assert newest["template"] == template


@pytest.mark.parametrize("headers", HEADERS)
def test_a_stored_notification_is_never_rerendered(client, db_session, headers):
    """응답은 저장된 문장이다 — 틀 문구가 바뀌어도 받은 알림은 그대로다."""
    trainer_token, trainer_id, _, _ = _pair(client, db_session)
    _add_row(
        db_session, trainer_id, title="예전 문구", body="예전 본문", category="message",
        template=nt.TRAINER_MEMBER_MESSAGE, template_args={"member_name": "Alex"},
    )
    newest = _trainer_inbox(client, trainer_token, headers)[0]
    assert (newest["title"], newest["body"]) == ("예전 문구", "예전 본문")


# --------------------------------------------------------------------------
# 트레이너가 한 일로 회원이 받는 알림
# --------------------------------------------------------------------------


def test_trainer_message_reaches_the_member_in_korean(client, db_session):
    trainer_token, _, member_id, member_token = _pair(client, db_session)
    sent = client.post(
        f"/v1/trainer/clients/{member_id}/chat",
        headers=_auth(trainer_token),
        json={"text": "Great session today"},
    )
    assert sent.status_code == 201, sent.text

    for headers in (None, EN):
        row = _member_inbox(client, member_token, headers)[0]
        assert row["title"] == "Coach Park 트레이너의 메시지"
        assert row["body"] == "Great session today"
        assert row["action"] == {"label": "메시지 보기", "target": "coach_chat"}
        assert row["template"] == nt.MEMBER_COACH_MESSAGE


def test_routine_assignment_reaches_the_member_in_korean(client, db_session):
    trainer_token, _, member_id, member_token = _pair(client, db_session)
    assigned = client.post(
        f"/v1/trainer/clients/{member_id}/routines",
        headers=_auth(trainer_token),
        json={
            "name": "Interval run",
            "minutes": 30,
            "type": "유산소",
            "reason": "fitness",
            "source": "trainer",
        },
    )
    assert assigned.status_code == 201, assigned.text

    for headers in (None, EN):
        row = _member_inbox(client, member_token, headers)[0]
        assert (row["title"], row["body"]) == ("새 개인운동이 왔어요", "Interval run · 30분")
        assert row["action"] == {"label": "운동 보기", "target": "exercise"}


def test_trainer_goal_change_reaches_the_member_in_korean(client, db_session):
    trainer_token, _, member_id, member_token = _pair(client, db_session)
    saved = client.put(
        f"/v1/trainer/clients/{member_id}/health-profile",
        headers=_auth(trainer_token),
        json={"conditions": "자세 교정"},
    )
    assert saved.status_code == 200, saved.text

    for headers in (None, EN):
        [row] = [
            n for n in _member_inbox(client, member_token, headers)
            if n["category"] == "health_goals"
        ]
        assert row["body"] == "Coach Park 트레이너가 건강 목표를 바꿨어요: 자세 교정"
        assert row["action"] == {"label": "목표 보기", "target": "health_goals"}


# --------------------------------------------------------------------------
# 액션 라벨
# --------------------------------------------------------------------------

# 회원 알림 갈래 → 라벨.
ACTION_LABELS = {
    "reminder": "기록하러 가기",
    "health_check": "기록하러 가기",
    "achievement": "대시보드 보기",
    "coach_chat": "메시지 보기",
    "coach_report": "리포트 보기",
    "routine": "운동 보기",
    "coach_invite": "요청 확인",
    "consultation_result": "트레이너 보기",
    "consult_decision": "상담 요청 보기",
    "benefits": "내 혜택 보기",
    "points_shop": "포인트 사용처 보기",
    "health_goals": "목표 보기",
    # PT 일정 — 운동 탭의 다음 PT 배지·예약(#3028).
    "member_schedule": "일정 보기",
    # PT 수업 완료·피드백 도착 — 운동 탭의 PT 기록(#3027).
    "pt_done": "PT 기록 보기",
}


@pytest.mark.parametrize(("category", "label"), sorted(ACTION_LABELS.items()))
def test_action_labels_are_korean_whatever_the_header(client, db_session, category, label):
    _, _, member_id, member_token = _pair(client, db_session)
    _add_row(db_session, member_id, title="t", body="b", category=category)
    for headers in HEADERS:
        assert _member_inbox(client, member_token, headers)[0]["action"]["label"] == label


@pytest.mark.parametrize("category", ["system", "brand_new"])
def test_categories_without_an_action_stay_without_one(client, db_session, category):
    _, _, member_id, member_token = _pair(client, db_session)
    _add_row(db_session, member_id, title="t", body="b", category=category)
    assert _member_inbox(client, member_token, EN)[0]["action"] is None


def test_every_action_category_has_a_label():
    from app.api.v1 import notifications as router

    for category in router._ACTION_BY_CATEGORY:
        action = router._action_for(category)
        assert action is not None
        assert action.label == ACTION_LABELS[category]


# --------------------------------------------------------------------------
# 일정·포인트 알림과 상대 시각
# --------------------------------------------------------------------------


def _future_day(days: int = 30) -> str:
    return (datetime.now(timezone.utc) + timedelta(days=days)).date().isoformat()


def test_schedule_added_and_cancelled_reach_the_member_in_korean(client, db_session):
    trainer_token, _, member_id, member_token = _pair(client, db_session)
    day = _future_day()
    month, dom = int(day[5:7]), int(day[8:10])
    ko_day = f"{month}월 {dom}일"
    created = client.post(
        "/v1/trainer/schedule",
        json={
            "date": day, "time": "19:00", "client_name": "Alex",
            "member_id": member_id, "type": "상담", "duration_minutes": 30,
        },
        headers=_auth(trainer_token),
    )
    assert created.status_code == 201, created.text

    row = db_session.scalar(
        select(Notification).where(
            Notification.user_id == member_id,
            Notification.template == nt.MEMBER_SCHEDULE_ADDED,
        )
    )
    assert row is not None
    # 날짜는 0 을 채우지 않는 `10월 1일` 꼴(#3120).
    assert (row.title, row.body) == ("새 일정이 등록됐어요", f"{ko_day} 19:00 · 상담")
    assert row.template_args == {"date": day, "time": "19:00", "type": "상담"}

    removed = client.delete(
        f"/v1/trainer/schedule/{created.json()['id']}", headers=_auth(trainer_token)
    )
    assert removed.status_code in (200, 204), removed.text

    for headers in (None, EN):
        rows = {n["title"]: n for n in _member_inbox(client, member_token, headers)}
        assert rows["새 일정이 등록됐어요"]["body"] == f"{ko_day} 19:00 · 상담"
        assert rows["일정이 취소됐어요"]["body"] == f"{ko_day} 19:00 · 상담"


@pytest.mark.parametrize(
    ("template", "args", "category"),
    [
        (
            nt.MEMBER_COUPON_EXPIRING,
            {"item": "pt_renewal", "benefit": "PT 재등록 30,000원 할인", "days": 2,
             "last_day": "2026-10-03"},
            "benefits",
        ),
        (
            nt.MEMBER_COUPON_CANCELLED,
            {"item": "locker_month", "benefit": "개인 락커 1개월 무료", "reason": "gym",
             "refunded": 7000},
            "benefits",
        ),
        (
            nt.MEMBER_CHALLENGE_RESULT,
            {"succeeded": True, "week_start": "2026-09-28", "goal": 4, "days": 4,
             "reward": 1200, "stake": 1000},
            "points_shop",
        ),
    ],
)
def test_points_notifications_reach_the_member_as_stored(
    client, db_session, template, args, category
):
    _, _, member_id, member_token = _pair(client, db_session)
    cols = nt.columns(template, args)
    _add_row(db_session, member_id, category=category, **cols)

    for headers in (None, EN):
        row = _member_inbox(client, member_token, headers)[0]
        assert (row["title"], row["body"]) == (cols["title"], cols["body"])
        assert row["template"] == template
        assert row["args"] == args


def test_queue_stores_points_templates_with_korean_text(client, db_session):
    """서비스 경로(`notification_service.queue`)가 틀·인자와 문장을 함께 저장한다."""
    from app.services import notification_service

    _, _, member_id, _ = _pair(client, db_session)
    row = notification_service.queue(
        db_session,
        member_id=member_id,
        kind=notification_service.WEEKLY_CHALLENGE,
        category=notification_service.MEMBER_POINTS_SHOP,
        template=nt.MEMBER_CHALLENGE_RESULT,
        template_args={"succeeded": False, "week_start": "2026-09-28", "goal": 4,
                       "days": 2, "reward": 1200, "stake": 1000},
    )
    db_session.commit()
    assert row is not None
    assert row.title == "주간 챌린지 목표를 채우지 못했어요"
    assert row.body.startswith("9월 28일 ~ 10월 4일 목표 4회 중 2회 운동해")
    assert row.template == nt.MEMBER_CHALLENGE_RESULT


@pytest.mark.parametrize(
    ("ago", "label"),
    [
        (timedelta(seconds=5), "방금 전"),
        (timedelta(minutes=5, seconds=10), "5분 전"),
        (timedelta(hours=3, minutes=1), "3시간 전"),
        (timedelta(days=2, minutes=1), "2일 전"),
    ],
)
def test_time_ago_is_korean_in_both_inboxes(client, db_session, ago, label):
    trainer_token, trainer_id, member_id, member_token = _pair(client, db_session)
    for user_id in (trainer_id, member_id):
        row_id = _add_row(db_session, user_id, category="system", title="t", body="b")
        db_session.get(Notification, row_id).created_at = datetime.now(timezone.utc) - ago
        db_session.commit()

    for inbox, token in ((_trainer_inbox, trainer_token), (_member_inbox, member_token)):
        for headers in HEADERS:
            assert inbox(client, token, headers)[0]["time_ago"] == label
