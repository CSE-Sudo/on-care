"""알림 목록의 요청 언어 대응. (#2302) DB 필요.

알림은 만든 순간의 한국어 문장만 저장해, 영어 화면에서도 한국어로 보였다. 이제
문장 틀과 인자를 함께 저장하고 목록 API 가 요청 언어로 조립한다.

  * 저장: 틀·인자와 **예전과 같은 한국어** `title`·`body`.
  * 트레이너 목록(`/trainer/notifications`)·회원 목록(`/notifications`): 영어 요청은
    영어 제목·본문, 한국어 요청과 헤더 없는 요청은 저장된 문장 그대로.
  * 응답에 `template`·`args` 가 실린다 — 트레이너 웹이 ARB 로 조립하는 재료다.
  * 틀 없는 옛 알림·모르는 틀·깨진 인자는 저장된 문장으로 돌아간다(500 이 아니다).
  * 회원 알림의 액션 라벨도 요청 언어다.
"""
from __future__ import annotations

import re
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
HANGUL = re.compile(r"[가-힣]")

EN = {"Accept-Language": "en"}
KO = {"Accept-Language": "ko"}


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
    # 저장되는 문장은 예전과 같은 한국어다 — 옛 앱·푸시가 이 값을 읽는다.
    assert row.title == "Alex 회원의 메시지"
    assert row.template == nt.TRAINER_MEMBER_MESSAGE
    assert row.template_args == {"member_name": "Alex"}


def test_trainer_inbox_speaks_the_request_language(client, db_session):
    trainer_token, _, _, member_token = _pair(client, db_session)
    text = f"Hello coach {uuid4().hex[:4]}"
    client.post("/v1/me/coach/chat", json={"text": text}, headers=_auth(member_token))

    en = _trainer_inbox(client, trainer_token, EN)[0]
    assert en["title"] == "Message from Alex"
    # 회원이 쓴 글은 번역하지 않는다.
    assert en["body"] == text
    assert en["template"] == nt.TRAINER_MEMBER_MESSAGE
    assert en["args"] == {"member_name": "Alex"}

    for headers in (KO, None, {"Accept-Language": "fr"}):
        ko = _trainer_inbox(client, trainer_token, headers)[0]
        assert ko["title"] == "Alex 회원의 메시지"
        assert ko["body"] == text
        # 틀은 언어와 무관하게 같이 실린다.
        assert ko["template"] == nt.TRAINER_MEMBER_MESSAGE


@pytest.mark.parametrize(
    "header", ["en-US,en;q=0.9", "EN", "fr, en;q=0.5", "ko;q=0.2, en;q=0.8"]
)
def test_english_is_picked_from_real_browser_headers(client, db_session, header):
    trainer_token, _, _, member_token = _pair(client, db_session)
    client.post("/v1/me/coach/chat", json={"text": "hi"}, headers=_auth(member_token))
    newest = _trainer_inbox(client, trainer_token, {"Accept-Language": header})[0]
    assert newest["title"] == "Message from Alex"


def test_member_goal_change_reaches_the_trainer_in_english(client, db_session):
    trainer_token, _, _, member_token = _pair(client, db_session)
    saved = client.put(
        "/v1/users/me/health-goals",
        headers=_auth(member_token),
        json={"conditions": "근력 향상, 재활"},
    )
    assert saved.status_code == 200, saved.text

    [en] = [n for n in _trainer_inbox(client, trainer_token, EN) if n["category"] == "health_goal"]
    assert en["title"] == "Member goals changed"
    assert en["body"] == "Alex changed their health goals: Build strength · Rehab"
    assert en["args"] == {"member_name": "Alex", "focus": ["근력 향상", "재활"]}
    assert not HANGUL.search(en["title"] + en["body"])

    [ko] = [n for n in _trainer_inbox(client, trainer_token) if n["category"] == "health_goal"]
    assert ko["title"] == "회원 건강 목표 변경"
    assert ko["body"] == "Alex 회원이 건강 목표를 바꿨어요: 근력 향상 · 재활"


def test_member_clearing_goals_says_none(client, db_session):
    trainer_token, _, _, member_token = _pair(client, db_session)
    client.put(
        "/v1/users/me/health-goals", headers=_auth(member_token), json={"conditions": "재활"}
    )
    client.put(
        "/v1/users/me/health-goals", headers=_auth(member_token), json={"conditions": ""}
    )
    newest = _trainer_inbox(client, trainer_token, EN)[0]
    assert newest["body"] == "Alex changed their health goals: none"
    assert _trainer_inbox(client, trainer_token)[0]["body"].endswith(": 목표 없음")


def test_reservation_booked_and_cancelled_in_english(client, db_session):
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
    en = _trainer_inbox(client, trainer_token, EN)[0]
    assert en["title"] == "New booking"
    assert en["body"] == f"Alex · {seoul:%m/%d %H:%M}"
    ko = _trainer_inbox(client, trainer_token)[0]
    assert ko["title"] == "새 예약이 들어왔어요"
    assert ko["body"] == f"Alex 회원 · {seoul:%m월 %d일 %H:%M}"

    client.delete(f"/v1/reservations/{booked.json()['id']}", headers=_auth(member_token))
    en = _trainer_inbox(client, trainer_token, EN)[0]
    assert en["title"] == "Booking cancelled"
    assert en["body"] == f"Alex · {seoul:%m/%d %H:%M}"
    assert _trainer_inbox(client, trainer_token)[0]["title"] == "예약이 취소되었습니다"


def test_member_rename_reaches_the_trainer_in_english(client, db_session):
    trainer_token, _, _, member_token = _pair(client, db_session)
    renamed = client.put(
        "/v1/users/me", headers=_auth(member_token), json={"name": "Alexandra"}
    )
    assert renamed.status_code == 200, renamed.text
    [en] = [n for n in _trainer_inbox(client, trainer_token, EN) if n["category"] == "member_name"]
    assert (en["title"], en["body"]) == ("Member renamed", "Alex changed their name to Alexandra.")
    [ko] = [n for n in _trainer_inbox(client, trainer_token) if n["category"] == "member_name"]
    assert (ko["title"], ko["body"]) == ("회원 이름 변경", "Alex 회원이 이름을 바꿨어요: Alexandra")


# --------------------------------------------------------------------------
# 옛 알림·깨진 알림
# --------------------------------------------------------------------------


def test_old_notifications_without_a_template_keep_their_text(client, db_session):
    trainer_token, trainer_id, _, _ = _pair(client, db_session)
    _add_row(
        db_session, trainer_id, title="새 상담 요청이 도착했어요",
        body="지수 회원 · 2026-10-01", category="consultation",
    )
    newest = _trainer_inbox(client, trainer_token, EN)[0]
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
def test_unknown_or_broken_templates_fall_back_to_the_stored_text(
    client, db_session, template, args
):
    trainer_token, trainer_id, _, _ = _pair(client, db_session)
    _add_row(
        db_session, trainer_id, title="저장된 제목", body="저장된 본문",
        category="reservation", template=template, template_args=args,
    )
    newest = _trainer_inbox(client, trainer_token, EN)[0]
    assert (newest["title"], newest["body"]) == ("저장된 제목", "저장된 본문")
    # 틀은 그대로 실어 준다 — 앱이 아는 틀이면 앱이 조립한다.
    assert newest["template"] == template


def test_korean_never_rerenders_a_stored_notification(client, db_session):
    """한국어 응답은 저장된 문장이다 — 틀 문구가 바뀌어도 받은 알림은 그대로다."""
    trainer_token, trainer_id, _, _ = _pair(client, db_session)
    _add_row(
        db_session, trainer_id, title="예전 문구", body="예전 본문", category="message",
        template=nt.TRAINER_MEMBER_MESSAGE, template_args={"member_name": "Alex"},
    )
    newest = _trainer_inbox(client, trainer_token, KO)[0]
    assert (newest["title"], newest["body"]) == ("예전 문구", "예전 본문")
    assert _trainer_inbox(client, trainer_token, EN)[0]["title"] == "Message from Alex"


# --------------------------------------------------------------------------
# 트레이너가 한 일로 회원이 받는 알림
# --------------------------------------------------------------------------


def test_trainer_message_reaches_the_member_in_english(client, db_session):
    trainer_token, _, member_id, member_token = _pair(client, db_session)
    sent = client.post(
        f"/v1/trainer/clients/{member_id}/chat",
        headers=_auth(trainer_token),
        json={"text": "Great session today"},
    )
    assert sent.status_code == 201, sent.text

    en = _member_inbox(client, member_token, EN)[0]
    assert en["title"] == "Message from Coach Park"
    assert en["body"] == "Great session today"
    assert en["action"] == {"label": "View chat", "target": "coach_chat"}
    assert en["template"] == nt.MEMBER_COACH_MESSAGE

    ko = _member_inbox(client, member_token)[0]
    assert ko["title"] == "Coach Park 트레이너의 메시지"
    assert ko["action"] == {"label": "대화 보기", "target": "coach_chat"}


def test_routine_assignment_reaches_the_member_in_english(client, db_session):
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

    en = _member_inbox(client, member_token, EN)[0]
    assert en["title"] == "New workout routine assigned"
    assert en["body"] == "Interval run · 30 min"
    assert en["action"] == {"label": "View workouts", "target": "exercise"}
    ko = _member_inbox(client, member_token)[0]
    assert (ko["title"], ko["body"]) == ("새 운동 루틴이 배정되었어요", "Interval run · 30분")


def test_trainer_goal_change_reaches_the_member_in_english(client, db_session):
    trainer_token, _, member_id, member_token = _pair(client, db_session)
    saved = client.put(
        f"/v1/trainer/clients/{member_id}/health-profile",
        headers=_auth(trainer_token),
        json={"conditions": "자세 교정"},
    )
    assert saved.status_code == 200, saved.text

    [en] = [n for n in _member_inbox(client, member_token, EN) if n["category"] == "health_goals"]
    assert en["title"] == "Your health goals changed"
    assert en["body"] == "Coach Park changed your health goals: Posture correction"
    assert en["action"] == {"label": "View goals", "target": "health_goals"}
    [ko] = [n for n in _member_inbox(client, member_token) if n["category"] == "health_goals"]
    assert ko["body"] == "Coach Park 트레이너님이 건강 목표를 바꿨어요: 자세 교정"
    assert ko["action"] == {"label": "목표 보기", "target": "health_goals"}


# --------------------------------------------------------------------------
# 액션 라벨
# --------------------------------------------------------------------------

# 회원 알림 갈래 → (한국어 라벨, 영어 라벨). 한국어는 예전 값 그대로다.
ACTION_LABELS = {
    "reminder": ("기록하러 가기", "Log now"),
    "health_check": ("기록하러 가기", "Log now"),
    "achievement": ("대시보드 보기", "View dashboard"),
    "coach_chat": ("대화 보기", "View chat"),
    "coach_report": ("리포트 보기", "View report"),
    "routine": ("운동 보기", "View workouts"),
    "coach_invite": ("요청 확인", "View request"),
    "consultation_result": ("트레이너 보기", "View trainer"),
    "consult_decision": ("상담 요청 보기", "View consultation requests"),
    "benefits": ("내 혜택 보기", "View my benefits"),
    "points_shop": ("포인트 사용처 보기", "View points shop"),
    "health_goals": ("목표 보기", "View goals"),
    # PT 일정 — 운동 탭의 다음 PT 배지·예약(#3028).
    "member_schedule": ("일정 보기", "View schedule"),
    # PT 수업 완료·피드백 도착 — 운동 탭의 PT 기록(#3027).
    "pt_done": ("PT 기록 보기", "View PT record"),
}


@pytest.mark.parametrize(("category", "labels"), sorted(ACTION_LABELS.items()))
def test_action_labels_follow_the_request_language(client, db_session, category, labels):
    _, _, member_id, member_token = _pair(client, db_session)
    _add_row(db_session, member_id, title="t", body="b", category=category)
    ko_label, en_label = labels
    assert _member_inbox(client, member_token)[0]["action"]["label"] == ko_label
    assert _member_inbox(client, member_token, KO)[0]["action"]["label"] == ko_label
    assert _member_inbox(client, member_token, EN)[0]["action"]["label"] == en_label


@pytest.mark.parametrize("category", ["system", "brand_new"])
def test_categories_without_an_action_stay_without_one(client, db_session, category):
    _, _, member_id, member_token = _pair(client, db_session)
    _add_row(db_session, member_id, title="t", body="b", category=category)
    assert _member_inbox(client, member_token, EN)[0]["action"] is None


def test_every_action_category_has_an_english_label():
    from app.api.v1 import notifications as router

    for category in router._ACTION_BY_CATEGORY:
        action = router._action_for(category, "en")
        assert action is not None
        assert not HANGUL.search(action.label), (category, action.label)


# --------------------------------------------------------------------------
# 일정·포인트 알림과 상대 시각
# --------------------------------------------------------------------------


def _future_day(days: int = 30) -> str:
    return (datetime.now(timezone.utc) + timedelta(days=days)).date().isoformat()


def test_schedule_added_and_cancelled_reach_the_member_in_english(client, db_session):
    trainer_token, _, member_id, member_token = _pair(client, db_session)
    day = _future_day()
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
    # 저장 문장은 예전과 같은 한국어다.
    assert (row.title, row.body) == ("새 일정이 등록되었어요", f"{day} 19:00 · 상담")
    assert row.template_args == {"date": day, "time": "19:00", "type": "상담"}

    removed = client.delete(
        f"/v1/trainer/schedule/{created.json()['id']}", headers=_auth(trainer_token)
    )
    assert removed.status_code in (200, 204), removed.text

    en = {n["title"]: n for n in _member_inbox(client, member_token, EN)}
    assert en["New session scheduled"]["body"] == f"{day} 19:00 · Consultation"
    assert en["Session cancelled"]["body"] == f"{day} 19:00 · Consultation"
    ko = {n["title"]: n for n in _member_inbox(client, member_token, KO)}
    assert ko["새 일정이 등록되었어요"]["body"] == f"{day} 19:00 · 상담"
    assert ko["일정이 취소되었어요"]["body"] == f"{day} 19:00 · 상담"


@pytest.mark.parametrize(
    ("template", "args", "category", "en_title"),
    [
        (
            nt.MEMBER_COUPON_EXPIRING,
            {"item": "pt_renewal", "benefit": "PT 재등록 30,000원 할인", "days": 2,
             "last_day": "2026-10-03"},
            "benefits",
            "Coupon expiring soon",
        ),
        (
            nt.MEMBER_COUPON_CANCELLED,
            {"item": "locker_month", "benefit": "개인 락커 1개월 무료", "reason": "gym",
             "refunded": 7000},
            "benefits",
            "Locker coupon cancelled",
        ),
        (
            nt.MEMBER_CHALLENGE_RESULT,
            {"succeeded": True, "week_start": "2026-09-28", "goal": 4, "days": 4,
             "reward": 1200, "stake": 1000},
            "points_shop",
            "Weekly challenge complete! You earned 1,200P",
        ),
    ],
)
def test_points_notifications_reach_the_member_in_english(
    client, db_session, template, args, category, en_title
):
    _, _, member_id, member_token = _pair(client, db_session)
    cols = nt.columns(template, args)
    _add_row(db_session, member_id, category=category, **cols)

    en = _member_inbox(client, member_token, EN)[0]
    assert en["title"] == en_title
    assert not HANGUL.search(en["title"] + en["body"])
    assert en["template"] == template
    assert en["args"] == args
    ko = _member_inbox(client, member_token, KO)[0]
    assert (ko["title"], ko["body"]) == (cols["title"], cols["body"])


def test_queue_stores_points_templates_with_korean_text(client, db_session):
    """서비스 경로(`notification_service.queue`)가 틀·인자와 한국어를 함께 저장한다."""
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
    assert row.body.startswith("9월 28일~10월 4일 목표 4회 중 2회 운동해")
    assert row.template == nt.MEMBER_CHALLENGE_RESULT


@pytest.mark.parametrize(
    ("ago", "ko", "en"),
    [
        (timedelta(seconds=5), "방금 전", "just now"),
        (timedelta(minutes=5, seconds=10), "5분 전", "5 min ago"),
        (timedelta(hours=3, minutes=1), "3시간 전", "3 hours ago"),
        (timedelta(days=2, minutes=1), "2일 전", "2 days ago"),
    ],
)
def test_time_ago_follows_the_request_language_in_both_inboxes(
    client, db_session, ago, ko, en
):
    trainer_token, trainer_id, member_id, member_token = _pair(client, db_session)
    for user_id in (trainer_id, member_id):
        row_id = _add_row(db_session, user_id, category="system", title="t", body="b")
        db_session.get(Notification, row_id).created_at = datetime.now(timezone.utc) - ago
        db_session.commit()

    for inbox, token in ((_trainer_inbox, trainer_token), (_member_inbox, member_token)):
        assert inbox(client, token, EN)[0]["time_ago"] == en
        assert inbox(client, token, KO)[0]["time_ago"] == ko
        # 헤더 없는 요청(옛 앱)은 예전 그대로 한국어다.
        assert inbox(client, token)[0]["time_ago"] == ko
