"""회원과 주고받은 피드백 모아 보기 — 출처·범위·담당 경계. (#2615) DB 필요."""
from __future__ import annotations

from datetime import datetime, timedelta
from uuid import uuid4

import pytest

from app.core import clock
from app.db.seed_trainer import TRAINER_ID
from app.db.session import SessionLocal
from app.models.models import (
    ChatMessage,
    MemberWeeklyFeedback,
    TrainerClient,
    TrainerSchedule,
    User,
)


def _headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture()
def trainer_token(client) -> str:
    response = client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    )
    assert response.status_code == 200, response.text
    return response.json()["access_token"]


@pytest.fixture()
def member_id(client):
    """다른 테스트의 시드와 섞이지 않는 새 회원을 데모 트레이너에 잇는다."""
    email = f"feedbacks-2615-{uuid4().hex[:8]}@oncare.com"
    response = client.post(
        "/v1/auth/register",
        json={"email": email, "password": "test-pw-1234", "name": "피드백 테스트 회원"},
    )
    assert response.status_code == 201, response.text
    member = response.json()["id"]
    db = SessionLocal()
    try:
        db.add(TrainerClient(id=f"link-{member}", trainer_id=TRAINER_ID, member_id=member))
        db.commit()
    finally:
        db.close()
    yield member
    db = SessionLocal()
    try:
        for model, column in (
            (ChatMessage, ChatMessage.member_id),
            (TrainerSchedule, TrainerSchedule.member_id),
            (MemberWeeklyFeedback, MemberWeeklyFeedback.user_id),
            (TrainerClient, TrainerClient.member_id),
        ):
            db.query(model).filter(column == member).delete()
        db.commit()
    finally:
        db.close()


def _monday(weeks_ago: int = 0):
    today = clock.today()
    return today - timedelta(days=today.weekday()) - timedelta(weeks=weeks_ago)


def _add(*rows) -> None:
    db = SessionLocal()
    try:
        db.add_all(rows)
        db.commit()
    finally:
        db.close()


def _schedule(member: str, suffix: str, *, days_ago: int, note: str, **kw):
    return TrainerSchedule(
        id=f"fb-sch-{member}-{suffix}",
        trainer_id=kw.get("trainer_id", TRAINER_ID),
        member_id=member,
        date=(clock.today() - timedelta(days=days_ago)).isoformat(),
        time="10:00",
        type=kw.get("type_", "1:1 PT"),
        status=kw.get("status", "완료"),
        note=note,
    )


def _report(member: str, suffix: str, *, week, body: str, minutes_ago: int):
    return ChatMessage(
        id=f"fb-msg-{member}-{suffix}",
        trainer_id=TRAINER_ID,
        member_id=member,
        sender="trainer",
        body=body,
        report_week_start=week.isoformat(),
        created_at=datetime.now(clock.SEOUL) - timedelta(minutes=minutes_ago),
    )


def _weekly(member: str, *, weeks_ago: int, note: str = ""):
    return MemberWeeklyFeedback(
        id=f"fb-mwf-{member}-{weeks_ago}",
        user_id=member,
        week_start=_monday(weeks_ago).isoformat(),
        condition="tired",
        intensity="hard",
        pain_area="무릎",
        note=note,
    )


def _feedbacks(client, token: str, member: str) -> list[dict]:
    response = client.get(
        f"/v1/trainer/clients/{member}/feedbacks", headers=_headers(token)
    )
    assert response.status_code == 200, response.text
    return response.json()


def test_feedbacks_gather_three_sources_newest_first(client, trainer_token, member_id):
    """완료 PT 피드백·보낸 리포트·회원 주간 피드백이 한 목록에 최신 먼저 온다."""
    _add(
        _schedule(member_id, "pt", days_ago=1, note="스쿼트 자세 좋아짐"),
        _report(member_id, "r1", week=_monday(1), body="지난주 잘했어요\n둘째 줄", minutes_ago=5),
        _weekly(member_id, weeks_ago=0, note="이번 주 바빴어요"),
    )

    items = _feedbacks(client, trainer_token, member_id)

    kinds = [item["kind"] for item in items]
    assert sorted(kinds) == ["pt_session", "report", "weekly"]
    dates = [item["date"] for item in items]
    assert dates == sorted(dates, reverse=True)

    pt = next(i for i in items if i["kind"] == "pt_session")
    assert pt["direction"] == "to_member"
    assert pt["body"] == "스쿼트 자세 좋아짐"
    assert pt["schedule_id"] == f"fb-sch-{member_id}-pt"

    report = next(i for i in items if i["kind"] == "report")
    assert report["direction"] == "to_member"
    assert report["week_start"] == _monday(1).isoformat()
    # 회원이 받은 글 전체다 — 첫 줄 미리보기가 아니다.
    assert report["body"] == "지난주 잘했어요\n둘째 줄"

    weekly = next(i for i in items if i["kind"] == "weekly")
    assert weekly["direction"] == "from_member"
    assert weekly["body"] == "이번 주 바빴어요"
    assert (weekly["condition"], weekly["intensity"], weekly["pain_area"]) == (
        "tired", "hard", "무릎",
    )


def test_feedbacks_leave_out_what_is_not_a_sent_feedback(
    client, trainer_token, member_id
):
    """예정·상담·빈 메모·창 밖 PT 는 피드백이 아니다. 같은 주 재전송은 최근 것 하나."""
    _add(
        _schedule(member_id, "plan", days_ago=0, note="다음엔 하체", status="예정"),
        _schedule(member_id, "consult", days_ago=2, note="등록 상담", type_="상담"),
        _schedule(member_id, "empty", days_ago=3, note=""),
        _schedule(member_id, "old", days_ago=120, note="오래된 피드백"),
        _report(member_id, "old-send", week=_monday(0), body="첫 전송", minutes_ago=30),
        _report(member_id, "new-send", week=_monday(0), body="다시 보낸 글", minutes_ago=1),
    )

    items = _feedbacks(client, trainer_token, member_id)

    assert [i["kind"] for i in items] == ["report"]
    assert items[0]["body"] == "다시 보낸 글"


def test_weekly_feedback_starts_from_the_week_the_link_began(
    client, trainer_token, member_id
):
    """담당이 이번 주에 시작됐으면 이전 트레이너 시절의 주간 피드백은 뺀다."""
    db = SessionLocal()
    try:
        link = db.query(TrainerClient).filter(TrainerClient.member_id == member_id).one()
        link.data_consent_at = datetime.now(clock.SEOUL)
        db.commit()
    finally:
        db.close()
    _add(
        _weekly(member_id, weeks_ago=0, note="이번 주"),
        _weekly(member_id, weeks_ago=2, note="이전 트레이너에게 쓴 글"),
    )

    items = _feedbacks(client, trainer_token, member_id)

    assert [i["body"] for i in items] == ["이번 주"]


def test_other_trainers_pt_feedback_is_not_mine(client, trainer_token, member_id):
    """남이 지도한 PT 의 피드백은 싣지 않는다."""
    other_id = f"trainer-{uuid4().hex[:10]}"
    _add(
        User(
            id=other_id,
            email=f"{other_id}@oncare.com",
            name="다른 트레이너",
            hashed_password="unused",
            role="trainer",
        )
    )
    try:
        _add(_schedule(member_id, "theirs", days_ago=1, note="남의 피드백", trainer_id=other_id))
        assert _feedbacks(client, trainer_token, member_id) == []
    finally:
        db = SessionLocal()
        try:
            db.query(TrainerSchedule).filter(TrainerSchedule.trainer_id == other_id).delete()
            db.query(User).filter(User.id == other_id).delete()
            db.commit()
        finally:
            db.close()


def test_feedbacks_are_404_for_a_member_i_do_not_manage(client, trainer_token):
    """담당이 아닌 회원은 다른 회원 경로와 같은 404 다."""
    response = client.get(
        f"/v1/trainer/clients/not-my-member-{uuid4().hex[:6]}/feedbacks",
        headers=_headers(trainer_token),
    )
    assert response.status_code == 404, response.text
