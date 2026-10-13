"""보낸 리포트·구매 리포트의 내용 고정. (#3349)

리포트는 보내거나 산 뒤에 달라지면 안 된다. 이 파일이 지키는 것은 세 가지다.

- 글로 받은 리포트의 수치는 보낸 뒤 회원이 기록·목표를 고쳐도 그대로다.
- 산 리포트의 감지 기록은 감지 창(30일)이 지나도 살 때와 같다.
- 굳힌 값이 없는 옛 리포트도 오류 없이 열린다(지금 값으로 다시 계산).

계정은 전부 이 파일이 만들고 테스트마다 지운다 — 시드 계정(`trainer-demo` 등)에
전송·구매·식단 행을 남기면 로스터와 리포트를 읽는 다른 테스트가 흔들린다(#2471).
DB 가 있어야 돈다(로컬 skip, CI 실행).
"""
from __future__ import annotations

import json
from datetime import date, datetime, timedelta, timezone
from uuid import uuid4

import pytest
from sqlalchemy import delete, select, update

from app.core import clock
from app.core.security import create_access_token
from app.models.models import (
    AiMessage,
    ChatMessage,
    DietEntry,
    HealthProfile,
    TrainerClient,
    User,
    WeeklyReportPurchase,
)
from app.services import report_snapshot_service, weekly_report_purchase_service
from app.services.trainer.reports import week_start_of

REPORT = "/v1/me/coach/weekly-report"
PDF = b"%PDF-1.4\n1 0 obj<<>>endobj\n%%EOF\n"

# 이 파일이 만든 계정 id. 테스트가 끝날 때마다 지운다.
_created: list[str] = []


@pytest.fixture(autouse=True)
def _drop_created_accounts(db_session):
    """만든 회원·트레이너를 지운다. `users.id` FK 는 CASCADE 라 딸린 행도 사라진다."""
    yield
    if not _created:
        return
    db_session.rollback()
    db_session.execute(delete(User).where(User.id.in_(list(_created))))
    db_session.commit()
    _created.clear()


def _h(user_id: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {create_access_token(user_id)}"}


def _user(db, role: str) -> str:
    user_id = f"snap-{role}-{uuid4().hex[:10]}"
    _created.append(user_id)
    db.add(
        User(
            id=user_id,
            email=f"{user_id}@oncare.com",
            name="스냅샷 계정",
            hashed_password="unused",
            role=role,
        )
    )
    db.commit()
    return user_id


def _pair(db) -> tuple[str, str]:
    """이 테스트만 쓰는 트레이너와 그 담당 회원."""
    trainer_id = _user(db, "trainer")
    member_id = _user(db, "member")
    db.add(
        TrainerClient(
            id=f"link-{uuid4().hex[:12]}",
            trainer_id=trainer_id,
            member_id=member_id,
            active=True,
        )
    )
    db.commit()
    return trainer_id, member_id


def _last_monday() -> date:
    """지난주 월요일(KST) — 끝난 주라 값이 날마다 움직이지 않는다."""
    return week_start_of(clock.today()) - timedelta(days=7)


def _meal(db, member_id: str, day: date, *, kcal: int, sodium: int) -> str:
    entry_id = f"diet-{uuid4().hex[:12]}"
    db.add(
        DietEntry(
            id=entry_id,
            user_id=member_id,
            date=day.isoformat(),
            meal_type="lunch",
            total_calories=kcal,
            sodium_mg=sodium,
        )
    )
    db.commit()
    return entry_id


def _profile(db, member_id: str, **values) -> None:
    db.expire_all()
    profile = db.scalar(select(HealthProfile).where(HealthProfile.user_id == member_id))
    if profile is None:
        db.add(HealthProfile(user_id=member_id, **values))
    else:
        for key, value in values.items():
            setattr(profile, key, value)
    db.commit()


def _send(client, trainer_id: str, member_id: str, week: date, text: str = "잘했어요"):
    sent = client.post(
        f"/v1/trainer/clients/{member_id}/report/send",
        headers=_h(trainer_id),
        json={"week_start": week.isoformat(), "message": text},
    )
    assert sent.status_code == 201, sent.text
    return sent.json()


def _report(client, member_id: str, week: date, message_id: str | None = None) -> dict:
    params = {"week_start": week.isoformat()}
    if message_id is not None:
        params["message_id"] = message_id
    r = client.get(REPORT, params=params, headers=_h(member_id))
    assert r.status_code == 200, r.text
    return r.json()


def _legacy_send(db, trainer_id: str, member_id: str, week: date) -> str:
    """#3349 전의 전송 — 주차만 있고 굳힌 값이 없다."""
    message_id = f"chat-{uuid4().hex[:12]}"
    db.add(
        ChatMessage(
            id=message_id,
            trainer_id=trainer_id,
            member_id=member_id,
            sender="trainer",
            body="예전에 보낸 리포트",
            report_week_start=week.isoformat(),
            created_at=datetime.now(timezone.utc),
        )
    )
    db.commit()
    return message_id


def _say(db, member_id: str, text: str, at: datetime) -> None:
    """회원이 AI 챗봇에 한 말 한 줄을 [at] 시각으로 남긴다."""
    from app.services.coach import conversation

    exchange = conversation.append_exchange(
        db, member_id, question=text, reply="알겠어요", sources=[]
    )
    db.execute(
        update(AiMessage)
        .where(AiMessage.id == exchange.question.id)
        .values(created_at=at)
    )
    db.commit()


def _noon(day: date) -> datetime:
    return datetime(day.year, day.month, day.day, 12, tzinfo=clock.SEOUL)


# ---- 순수 로직: 감지 스냅샷 읽기 ----


def test_no_insight_snapshot_reads_as_unknown_not_as_empty():
    """남긴 것이 없는 것(null)과 감지가 없던 것(빈 목록)은 다르다."""
    assert report_snapshot_service.read_insights(None) is None
    assert report_snapshot_service.read_insights("[]") == []


@pytest.mark.parametrize("raw", ["", "{", '{"kind": "discomfort"}', '[{"kind": 1}]'])
def test_a_broken_insight_snapshot_reads_as_unknown(raw):
    assert report_snapshot_service.read_insights(raw) is None


def test_an_insight_snapshot_keeps_kind_part_and_time():
    raw = json.dumps(
        [
            {
                "kind": "discomfort",
                "body_part": "무릎",
                "created_at": "2026-09-16T03:00:00+00:00",
            }
        ],
        ensure_ascii=False,
    )
    (row,) = report_snapshot_service.read_insights(raw)
    assert row.kind == "discomfort"
    assert row.body_part == "무릎"
    assert row.created_at == datetime(2026, 9, 16, 3, tzinfo=timezone.utc)


# ---- 글로 보낸 리포트 ----


def test_a_text_send_keeps_the_numbers_it_was_sent_with(client, db_session):
    """보낸 뒤 그 주 식단을 고쳐도 회원이 여는 리포트는 그대로다."""
    trainer, member = _pair(db_session)
    week = _last_monday()
    meal = _meal(db_session, member, week, kcal=1800, sodium=2400)
    sent = _send(client, trainer, member, week)

    before = _report(client, member, week, sent["id"])
    assert before["calories_week"][0] == 1800
    assert before["snapshot_at"] is not None

    db_session.execute(
        update(DietEntry)
        .where(DietEntry.id == meal)
        .values(total_calories=900, sodium_mg=500)
    )
    db_session.commit()
    _meal(db_session, member, week + timedelta(days=1), kcal=700, sodium=300)

    after = _report(client, member, week, sent["id"])
    assert after == before


def test_a_text_send_keeps_the_goals_it_was_judged_by(client, db_session):
    """건강 목표를 바꿔도 지난 리포트의 부족·초과 판정이 뒤집히지 않는다."""
    trainer, member = _pair(db_session)
    week = _last_monday()
    _profile(db_session, member, daily_sodium_mg=2000, daily_calories=1900)
    _meal(db_session, member, week, kcal=1800, sodium=2400)
    sent = _send(client, trainer, member, week)

    _profile(db_session, member, daily_sodium_mg=3000, daily_calories=2500)

    report = _report(client, member, week, sent["id"])
    assert report["sodium_target"] == 2000
    assert report["calorie_target"] == 1900
    assert report["sodium_over_days"] == 1


def test_the_snapshot_never_carries_the_trainers_draft(client, db_session):
    """본문 없이 보내 서버가 초안을 써도, 굳힌 값의 `message` 는 비어 있다."""
    trainer, member = _pair(db_session)
    week = _last_monday()
    sent = client.post(
        f"/v1/trainer/clients/{member}/report/send",
        headers=_h(trainer),
        json={"week_start": week.isoformat()},
    )
    assert sent.status_code == 201, sent.text
    assert sent.json()["body"] != ""

    assert _report(client, member, week, sent.json()["id"])["message"] == ""
    stored = db_session.scalar(
        select(ChatMessage.report_snapshot_json).where(
            ChatMessage.id == sent.json()["id"]
        )
    )
    assert json.loads(stored)["message"] == ""


def test_each_send_of_the_same_week_opens_its_own_numbers(client, db_session):
    """같은 주를 두 번 받았으면 누른 전송의 값이 열린다."""
    trainer, member = _pair(db_session)
    week = _last_monday()
    _meal(db_session, member, week, kcal=1000, sodium=100)
    first = _send(client, trainer, member, week, "첫 번째")
    _meal(db_session, member, week, kcal=500, sodium=100)
    second = _send(client, trainer, member, week, "두 번째")

    assert _report(client, member, week, first["id"])["calories_week"][0] == 1000
    assert _report(client, member, week, second["id"])["calories_week"][0] == 1500


def test_without_a_message_the_latest_send_of_that_week_is_read(client, db_session):
    """결과지가 직전 주로 견줄 때도 회원이 마지막으로 받은 값이다."""
    trainer, member = _pair(db_session)
    week = _last_monday()
    _meal(db_session, member, week, kcal=1000, sodium=100)
    _send(client, trainer, member, week, "첫 번째")
    _meal(db_session, member, week, kcal=500, sodium=100)
    _send(client, trainer, member, week, "두 번째")
    _meal(db_session, member, week, kcal=250, sodium=100)

    report = _report(client, member, week)
    assert report["calories_week"][0] == 1500
    assert report["snapshot_at"] is not None


def test_a_send_made_mid_week_is_only_read_through_its_own_message(
    client, db_session
):
    """진행 중에 굳힌 값은 그 전송을 열 때만 쓴다 — 주 전체의 값이 아니다."""
    trainer, member = _pair(db_session)
    week = week_start_of(clock.today())
    _meal(db_session, member, week, kcal=1000, sodium=100)
    sent = _send(client, trainer, member, week)
    _meal(db_session, member, week, kcal=500, sodium=100)

    opened = _report(client, member, week, sent["id"])
    assert opened["calories_week"][0] == 1000
    assert opened["snapshot_at"] is not None
    plain = _report(client, member, week)
    assert plain["calories_week"][0] == 1500
    assert plain["snapshot_at"] is None


def test_a_week_that_was_never_sent_is_still_computed_now(client, db_session):
    _, member = _pair(db_session)
    week = _last_monday()
    _meal(db_session, member, week, kcal=1200, sodium=100)

    report = _report(client, member, week)
    assert report["calories_week"][0] == 1200
    assert report["snapshot_at"] is None

    _meal(db_session, member, week, kcal=300, sodium=100)
    assert _report(client, member, week)["calories_week"][0] == 1500


def test_a_send_of_another_week_does_not_freeze_this_one(client, db_session):
    trainer, member = _pair(db_session)
    week = _last_monday()
    _meal(db_session, member, week, kcal=1200, sodium=100)
    other = _send(client, trainer, member, week - timedelta(days=7))

    report = _report(client, member, week, other["id"])
    assert report["week_start"] == week.isoformat()
    assert report["snapshot_at"] is None


def test_an_old_send_without_a_snapshot_opens_with_current_values(client, db_session):
    """굳힌 값이 없는 옛 리포트 — 오류 없이, 지금처럼 다시 계산한다."""
    trainer, member = _pair(db_session)
    week = _last_monday()
    legacy = _legacy_send(db_session, trainer, member, week)
    _meal(db_session, member, week, kcal=1100, sodium=100)

    report = _report(client, member, week, legacy)
    assert report["calories_week"][0] == 1100
    assert report["snapshot_at"] is None
    assert report["message"] == ""


def test_a_snapshot_that_no_longer_parses_falls_back_to_now(client, db_session):
    """저장된 한 줄이 깨졌다고 리포트가 열리지 않으면 안 된다."""
    trainer, member = _pair(db_session)
    week = _last_monday()
    _meal(db_session, member, week, kcal=1100, sodium=100)
    sent = _send(client, trainer, member, week)
    db_session.execute(
        update(ChatMessage)
        .where(ChatMessage.id == sent["id"])
        .values(report_snapshot_json='{"week_start": 3}')
    )
    db_session.commit()

    report = _report(client, member, week, sent["id"])
    assert report["calories_week"][0] == 1100
    assert report["snapshot_at"] is None


def test_another_members_send_is_never_read(client, db_session):
    """남의 전송 id 를 넣어도 그 회원의 값이 열리지 않는다."""
    trainer, member = _pair(db_session)
    other = _user(db_session, "member")
    db_session.add(
        TrainerClient(
            id=f"link-{uuid4().hex[:12]}",
            trainer_id=trainer,
            member_id=other,
            active=True,
        )
    )
    db_session.commit()
    week = _last_monday()
    _meal(db_session, other, week, kcal=2222, sodium=100)
    theirs = _send(client, trainer, other, week)

    report = _report(client, member, week, theirs["id"])
    assert report["member_id"] == member
    assert report["calories_week"][0] == 0
    assert report["snapshot_at"] is None


def test_a_pdf_send_also_keeps_its_numbers(client, db_session, tmp_path, monkeypatch):
    """PDF 로 받은 주도 결과지의 직전 주 비교에서는 받은 값으로 선다."""
    from app.core.config import get_settings

    monkeypatch.setattr(get_settings(), "report_pdf_storage_dir", str(tmp_path))
    trainer, member = _pair(db_session)
    week = _last_monday()
    _meal(db_session, member, week, kcal=1300, sodium=100)
    sent = client.post(
        f"/v1/trainer/clients/{member}/report/send-pdf",
        headers=_h(trainer),
        data={"week_start": week.isoformat(), "message": "PDF 로 보냅니다"},
        files={"pdf": ("weekly.pdf", PDF, "application/pdf")},
    )
    assert sent.status_code == 201, sent.text
    _meal(db_session, member, week, kcal=400, sodium=100)

    assert _report(client, member, week)["calories_week"][0] == 1300


def test_the_trainer_keeps_reading_live_values(client, db_session):
    """트레이너의 리포트 화면은 초안을 쓰는 자리라 지금 값을 본다."""
    trainer, member = _pair(db_session)
    week = _last_monday()
    _meal(db_session, member, week, kcal=1000, sodium=100)
    _send(client, trainer, member, week)
    _meal(db_session, member, week, kcal=500, sodium=100)

    r = client.get(
        f"/v1/trainer/clients/{member}/report",
        params={"week_start": week.isoformat()},
        headers=_h(trainer),
    )
    assert r.status_code == 200, r.text
    assert r.json()["calories_week"][0] == 1500
    assert "snapshot_at" not in r.json()


def test_the_chat_message_does_not_expose_the_snapshot(client, db_session):
    """굳힌 값은 리포트 조회로만 나간다 — 대화 응답이 무거워지지 않는다."""
    trainer, member = _pair(db_session)
    sent = _send(client, trainer, member, _last_monday())
    assert "report_snapshot" not in sent
    assert "report_snapshot_json" not in sent


# ---- 포인트로 산 리포트 ----


def _buyer(db) -> str:
    member_id = _user(db, "member")
    _profile(db, member_id, activity_points=weekly_report_purchase_service.COST)
    return member_id


def _buy(client, member_id: str):
    r = client.post(
        "/v1/me/points/exchange", json={"item": "weekly_report"}, headers=_h(member_id)
    )
    assert r.status_code == 201, r.text
    return r.json()


def _purchases(client, member_id: str) -> list[dict]:
    r = client.get("/v1/me/weekly-reports", headers=_h(member_id))
    assert r.status_code == 200, r.text
    return r.json()["reports"]


def test_a_bought_report_keeps_the_insights_it_was_bought_with(client, db_session):
    """살 때 적혀 있던 감지가 감지 창을 벗어난 뒤에도 그대로다."""
    member = _buyer(db_session)
    week = weekly_report_purchase_service.target_week()
    _say(db_session, member, "무릎이 아파요", _noon(week + timedelta(days=1)))
    _say(db_session, member, "무릎이 또 아파요", _noon(week + timedelta(days=3)))
    _buy(client, member)

    (bought,) = _purchases(client, member)
    assert [(i["kind"], i["body_part"]) for i in bought["insights"]] == [
        ("discomfort", "무릎"),
        ("discomfort", "무릎"),
    ]

    # 한 달 넘게 지난 것과 같은 상태 — 대화의 그 줄들이 감지 창 밖으로 나간다.
    db_session.execute(
        update(AiMessage)
        .where(AiMessage.content.in_(["무릎이 아파요", "무릎이 또 아파요"]))
        .where(AiMessage.role == "user")
        .values(created_at=clock.now() - timedelta(days=45))
    )
    db_session.commit()
    live = client.get("/v1/ai-coach/insights", headers=_h(member)).json()
    assert live["insights"] == []

    assert _purchases(client, member)[0]["insights"] == bought["insights"]


def test_a_bought_report_only_keeps_insights_of_its_own_week(client, db_session):
    """그 주(KST 월~일) 것만, 오래된 것 먼저 남긴다. 회원의 문장은 남기지 않는다."""
    member = _buyer(db_session)
    week = weekly_report_purchase_service.target_week()
    _say(db_session, member, "허리가 뻐근해요", _noon(week + timedelta(days=5)))
    _say(db_session, member, "무릎이 아파요", _noon(week))
    _say(db_session, member, "어깨가 불편해요", _noon(week - timedelta(days=1)))
    _say(db_session, member, "손목 통증이 있어요", _noon(week + timedelta(days=7)))
    _buy(client, member)

    (bought,) = _purchases(client, member)
    assert [i["body_part"] for i in bought["insights"]] == ["무릎", "허리"]
    assert all(set(i) == {"kind", "body_part", "created_at"} for i in bought["insights"])


def test_a_week_bought_with_no_insights_says_so(client, db_session):
    """감지가 없던 주는 빈 목록이다 — "모른다"(null)와 구분된다."""
    member = _buyer(db_session)
    _buy(client, member)
    assert _purchases(client, member)[0]["insights"] == []


def test_a_bought_report_keeps_its_numbers(client, db_session):
    member = _buyer(db_session)
    week = weekly_report_purchase_service.target_week()
    _meal(db_session, member, week, kcal=1600, sodium=100)
    _buy(client, member)
    _meal(db_session, member, week, kcal=900, sodium=100)

    report = _report(client, member, week)
    assert report["calories_week"][0] == 1600
    assert report["snapshot_at"] is not None


def test_an_old_purchase_without_a_snapshot_still_opens(client, db_session):
    """#3349 전에 산 주 — 감지는 "모른다" 로, 수치는 지금 값으로 연다."""
    member = _user(db_session, "member")
    week = weekly_report_purchase_service.target_week()
    db_session.add(
        WeeklyReportPurchase(
            id=f"wrp-{uuid4().hex[:12]}",
            user_id=member,
            week_start=week.isoformat(),
            cost=weekly_report_purchase_service.COST,
        )
    )
    db_session.commit()
    _meal(db_session, member, week, kcal=1400, sodium=100)

    (bought,) = _purchases(client, member)
    assert bought["insights"] is None
    report = _report(client, member, week)
    assert report["calories_week"][0] == 1400
    assert report["snapshot_at"] is None


def test_a_retried_purchase_does_not_take_a_second_snapshot(client, db_session):
    """같은 요청의 재시도는 처음 굳힌 값을 그대로 둔다."""
    member = _buyer(db_session)
    week = weekly_report_purchase_service.target_week()
    _meal(db_session, member, week, kcal=1600, sodium=100)
    key = f"snap-{uuid4().hex[:12]}"
    body = {"item": "weekly_report", "client_request_id": key}
    first = client.post("/v1/me/points/exchange", json=body, headers=_h(member))
    assert first.status_code == 201, first.text
    _meal(db_session, member, week, kcal=900, sodium=100)
    again = client.post("/v1/me/points/exchange", json=body, headers=_h(member))
    assert again.status_code == 201, again.text

    assert _report(client, member, week)["calories_week"][0] == 1600


# ---- 정리 ----


def test_no_account_from_this_file_is_left_behind(client, db_session):
    """앞선 테스트가 만든 계정이 남아 있지 않다 — 전송·구매·식단 행도 함께 지워진다."""
    left = db_session.scalars(select(User.id).where(User.id.like("snap-%"))).all()
    assert left == []
