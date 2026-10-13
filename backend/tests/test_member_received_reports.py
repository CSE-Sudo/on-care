"""회원이 받은 리포트 목록과, 대화가 사라진 뒤에도 남는 수신 기록. (#3348) DB 필요.

`GET /me/coach/reports` 가 지키는 것:

- 받은 리포트를 주별로, 최신 주부터 한 번에 준다. 같은 주를 여러 번 받았으면
  가장 최근 것 하나다.
- 담당이 끊기거나 바뀐 뒤에도 받은 리포트가 남고 열린다.
- 보낸 트레이너가 탈퇴해 대화가 사라져도 받은 주는 남고, 그때 굳힌 값으로 열린다.

계정은 전부 이 파일이 만들고 테스트마다 지운다 — 시드 계정에 전송·식단 행을
남기면 로스터와 리포트를 읽는 다른 테스트가 흔들린다(#2471).
"""
from __future__ import annotations

from datetime import date, timedelta
from uuid import uuid4

import pytest
from sqlalchemy import delete, select

from app.core import clock
from app.core.security import create_access_token
from app.models.models import (
    ChatMessage,
    DietEntry,
    MemberReceivedReport,
    TrainerClient,
    User,
)
from app.services import received_reports, weekly_report_access
from app.services.trainer.reports import week_start_of

LIST = "/v1/me/coach/reports"
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


def _user(db, role: str, name: str = "받은 리포트 계정") -> str:
    user_id = f"rcv-{role}-{uuid4().hex[:10]}"
    _created.append(user_id)
    db.add(
        User(
            id=user_id,
            email=f"{user_id}@oncare.com",
            name=name,
            hashed_password="unused",
            role=role,
        )
    )
    db.commit()
    return user_id


def _link(db, trainer_id: str, member_id: str) -> None:
    db.add(
        TrainerClient(
            id=f"link-{uuid4().hex[:12]}",
            trainer_id=trainer_id,
            member_id=member_id,
            active=True,
        )
    )
    db.commit()


def _unlink(db, trainer_id: str, member_id: str) -> None:
    """담당 해제 — 링크가 사라진다. 대화는 남는다."""
    db.execute(
        delete(TrainerClient).where(
            TrainerClient.trainer_id == trainer_id,
            TrainerClient.member_id == member_id,
        )
    )
    db.commit()


def _pair(db, trainer_name: str = "김코치") -> tuple[str, str]:
    """이 테스트만 쓰는 트레이너와 그 담당 회원."""
    trainer_id = _user(db, "trainer", trainer_name)
    member_id = _user(db, "member")
    _link(db, trainer_id, member_id)
    return trainer_id, member_id


def _back(weeks: int) -> date:
    """이번 주 월요일(KST)에서 [weeks] 주 전 월요일."""
    return week_start_of(clock.today()) - timedelta(weeks=weeks)


def _send(client, trainer_id: str, member_id: str, week: date, text: str = "잘했어요"):
    sent = client.post(
        f"/v1/trainer/clients/{member_id}/report/send",
        headers=_h(trainer_id),
        json={"week_start": week.isoformat(), "message": text},
    )
    assert sent.status_code == 201, sent.text
    return sent.json()


def _send_pdf(client, trainer_id: str, member_id: str, week: date):
    sent = client.post(
        f"/v1/trainer/clients/{member_id}/report/send-pdf",
        headers=_h(trainer_id),
        data={"week_start": week.isoformat(), "message": "PDF 로 보냅니다"},
        files={"pdf": ("weekly.pdf", PDF, "application/pdf")},
    )
    assert sent.status_code == 201, sent.text
    return sent.json()


def _list(client, member_id: str, **params) -> dict:
    res = client.get(LIST, params=params, headers=_h(member_id))
    assert res.status_code == 200, res.text
    return res.json()


def _meal(db, member_id: str, day: date, *, kcal: int) -> None:
    db.add(
        DietEntry(
            id=f"diet-{uuid4().hex[:12]}",
            user_id=member_id,
            date=day.isoformat(),
            meal_type="lunch",
            total_calories=kcal,
            sodium_mg=100,
        )
    )
    db.commit()


def _withdraw(db, trainer_id: str) -> None:
    """트레이너 탈퇴 — 계정 행이 사라지고 대화는 CASCADE 로 함께 지워진다."""
    db.rollback()
    db.execute(delete(User).where(User.id == trainer_id))
    db.commit()
    db.expire_all()


@pytest.fixture
def pdf_dir(tmp_path, monkeypatch):
    """PDF 를 임시 폴더에 쓴다 — 개발용 저장 폴더에 파일을 남기지 않는다."""
    from app.core.config import get_settings

    monkeypatch.setattr(get_settings(), "report_pdf_storage_dir", str(tmp_path))
    return tmp_path


# ───────────────────────────── 목록의 모양 ─────────────────────────────


def test_a_member_who_received_nothing_gets_an_empty_list(client, db_session):
    _, member = _pair(db_session)

    assert _list(client, member) == {"reports": [], "next_before": None}


def test_a_member_without_a_trainer_gets_an_empty_list_not_404(client, db_session):
    """대화 조회와 다르다 — 담당이 없어도 목록은 200 이다."""
    member = _user(db_session, "member")

    assert _list(client, member)["reports"] == []


def test_a_sent_report_shows_with_who_sent_it_and_when(client, db_session):
    trainer, member = _pair(db_session, "박코치")
    week = _back(1)

    sent = _send(client, trainer, member, week, "이번 주 수고했어요")

    (row,) = _list(client, member)["reports"]
    assert row == {
        "id": sent["id"],
        "week_start": week.isoformat(),
        "sent_at": sent["created_at"],
        "trainer_name": "박코치",
        "body": "이번 주 수고했어요",
        "attachment": None,
    }


def test_a_pdf_report_carries_its_attachment(client, db_session, pdf_dir):
    trainer, member = _pair(db_session)

    sent = _send_pdf(client, trainer, member, _back(1))

    (row,) = _list(client, member)["reports"]
    assert row["attachment"] == sent["attachment"]
    assert row["attachment"]["type"] == "pdf"
    # 목록이 준 경로로 회원이 그 파일을 받는다.
    got = client.get(f"/v1{row['attachment']['download_path']}", headers=_h(member))
    assert got.status_code == 200
    assert got.content == PDF


def test_ordinary_messages_are_not_reports(client, db_session):
    trainer, member = _pair(db_session)
    said = client.post(
        f"/v1/trainer/clients/{member}/chat",
        headers=_h(trainer),
        json={"text": "오늘 운동 어땠어요?"},
    )
    assert said.status_code in (200, 201), said.text

    assert _list(client, member)["reports"] == []
    assert (
        db_session.scalar(
            select(MemberReceivedReport.id).where(
                MemberReceivedReport.member_id == member
            )
        )
        is None
    )


def test_a_week_sent_twice_shows_only_the_latest(client, db_session):
    trainer, member = _pair(db_session)
    week = _back(1)
    _send(client, trainer, member, week, "처음 보낸 글")
    again = _send(client, trainer, member, week, "고쳐 보낸 글")

    (row,) = _list(client, member)["reports"]

    assert row["id"] == again["id"]
    assert row["body"] == "고쳐 보낸 글"


def test_weeks_come_newest_first_whatever_the_send_order(client, db_session):
    trainer, member = _pair(db_session)
    # 오래된 주를 나중에 보내도 목록은 주 순서다.
    for back in (1, 3, 2):
        _send(client, trainer, member, _back(back))

    weeks = [r["week_start"] for r in _list(client, member)["reports"]]

    assert weeks == [_back(1).isoformat(), _back(2).isoformat(), _back(3).isoformat()]


def test_pages_are_cut_by_week_and_the_cursor_walks_back(client, db_session):
    trainer, member = _pair(db_session)
    for back in (1, 2, 3):
        _send(client, trainer, member, _back(back))

    first = _list(client, member, limit=2)
    second = _list(client, member, limit=2, before=first["next_before"])

    assert [r["week_start"] for r in first["reports"]] == [
        _back(1).isoformat(),
        _back(2).isoformat(),
    ]
    assert first["next_before"] == _back(2).isoformat()
    assert [r["week_start"] for r in second["reports"]] == [_back(3).isoformat()]
    assert second["next_before"] is None


def test_a_full_last_page_has_no_cursor(client, db_session):
    trainer, member = _pair(db_session)
    for back in (1, 2):
        _send(client, trainer, member, _back(back))

    assert _list(client, member, limit=2)["next_before"] is None


def test_a_mid_week_cursor_folds_to_its_monday(client, db_session):
    trainer, member = _pair(db_session)
    for back in (1, 2):
        _send(client, trainer, member, _back(back))

    # 지난주 수요일 → 지난주는 빠지고 그 앞 주만 온다.
    page = _list(client, member, before=(_back(1) + timedelta(days=2)).isoformat())

    assert [r["week_start"] for r in page["reports"]] == [_back(2).isoformat()]


@pytest.mark.parametrize("before", ["20261005", "2026-13-01", "지난주"])
def test_a_malformed_cursor_is_422(client, db_session, before):
    _, member = _pair(db_session)

    res = client.get(LIST, params={"before": before}, headers=_h(member))

    assert res.status_code == 422


def test_the_list_holds_only_my_own_reports(client, db_session):
    trainer, member = _pair(db_session)
    other = _user(db_session, "member")
    _link(db_session, trainer, other)
    _send(client, trainer, other, _back(1))

    assert _list(client, member)["reports"] == []


def test_a_trainer_token_cannot_read_the_member_list(client, db_session):
    trainer, _ = _pair(db_session)

    assert client.get(LIST, headers=_h(trainer)).status_code == 403


# ─────────────────────── 담당이 끊기거나 바뀐 뒤 ───────────────────────


def test_reports_stay_listed_and_open_after_the_trainer_is_released(
    client, db_session
):
    trainer, member = _pair(db_session)
    week = _back(1)
    sent = _send(client, trainer, member, week)

    _unlink(db_session, trainer, member)

    # 대화는 담당이 없어 404 지만 받은 리포트는 그대로다.
    assert client.get("/v1/me/coach/chat", headers=_h(member)).status_code == 404
    (row,) = _list(client, member)["reports"]
    assert row["id"] == sent["id"]
    assert row["trainer_name"] == "김코치"
    opened = client.get(
        REPORT,
        params={"week_start": week.isoformat(), "message_id": row["id"]},
        headers=_h(member),
    )
    assert opened.status_code == 200, opened.text


def test_a_pdf_stays_downloadable_after_the_trainer_is_released(
    client, db_session, pdf_dir
):
    trainer, member = _pair(db_session)
    _send_pdf(client, trainer, member, _back(1))

    _unlink(db_session, trainer, member)

    (row,) = _list(client, member)["reports"]
    got = client.get(f"/v1{row['attachment']['download_path']}", headers=_h(member))
    assert got.status_code == 200
    assert got.content == PDF


def test_reports_from_the_previous_trainer_show_after_a_switch(client, db_session):
    old, member = _pair(db_session, "이전코치")
    _send(client, old, member, _back(2), "이전 담당의 글")
    _unlink(db_session, old, member)
    new = _user(db_session, "trainer", "새코치")
    _link(db_session, new, member)
    _send(client, new, member, _back(1), "새 담당의 글")

    rows = _list(client, member)["reports"]

    assert [(r["week_start"], r["trainer_name"], r["body"]) for r in rows] == [
        (_back(1).isoformat(), "새코치", "새 담당의 글"),
        (_back(2).isoformat(), "이전코치", "이전 담당의 글"),
    ]


# ───────────────────── 보낸 트레이너가 탈퇴한 뒤 ─────────────────────


def test_a_received_week_survives_the_trainer_leaving_the_service(client, db_session):
    trainer, member = _pair(db_session)
    week = _back(1)
    sent = _send(client, trainer, member, week, "탈퇴 전에 보낸 글")

    _withdraw(db_session, trainer)

    # 대화는 계정과 함께 사라졌다.
    assert db_session.get(ChatMessage, sent["id"]) is None
    (row,) = _list(client, member)["reports"]
    assert row["id"] == sent["id"]
    assert row["week_start"] == week.isoformat()
    assert row["body"] == "탈퇴 전에 보낸 글"
    assert row["sent_at"] == sent["created_at"]
    # 탈퇴한 사람의 이름은 남기지 않는다.
    assert row["trainer_name"] is None
    assert weekly_report_access.can_open(db_session, member, week)


def test_a_week_nobody_sent_stays_closed_after_the_trainer_leaves(client, db_session):
    trainer, member = _pair(db_session)
    _send(client, trainer, member, _back(1))

    _withdraw(db_session, trainer)

    res = client.get(
        REPORT, params={"week_start": _back(2).isoformat()}, headers=_h(member)
    )
    assert res.status_code == 403


def test_the_report_opens_with_its_frozen_numbers_after_the_trainer_leaves(
    client, db_session
):
    trainer, member = _pair(db_session)
    week = _back(1)
    _meal(db_session, member, week, kcal=1300)
    sent = _send(client, trainer, member, week)
    # 보낸 뒤에 기록을 더 넣는다 — 굳힌 값은 그대로여야 한다.
    _meal(db_session, member, week, kcal=400)

    _withdraw(db_session, trainer)

    for params in (
        {"week_start": week.isoformat(), "message_id": sent["id"]},
        # 누른 전송을 모르는 길(결과지의 직전 주)도 받은 값으로 선다.
        {"week_start": week.isoformat()},
    ):
        res = client.get(REPORT, params=params, headers=_h(member))
        assert res.status_code == 200, res.text
        body = res.json()
        assert body["calories_week"][0] == 1300
        assert body["snapshot_at"] is not None


def test_a_pdf_report_loses_its_file_but_not_its_week_when_the_trainer_leaves(
    client, db_session, pdf_dir
):
    """파일은 대화에 달려 있어 함께 사라진다 — 주는 남아 결과지로 열린다."""
    trainer, member = _pair(db_session)
    week = _back(1)
    _meal(db_session, member, week, kcal=900)
    _send_pdf(client, trainer, member, week)

    _withdraw(db_session, trainer)

    (row,) = _list(client, member)["reports"]
    assert row["attachment"] is None
    res = client.get(
        REPORT,
        params={"week_start": week.isoformat(), "message_id": row["id"]},
        headers=_h(member),
    )
    assert res.status_code == 200, res.text
    assert res.json()["calories_week"][0] == 900


def test_the_receipt_goes_with_the_member_account(client, db_session):
    trainer, member = _pair(db_session)
    _send(client, trainer, member, _back(1))

    db_session.execute(delete(User).where(User.id == member))
    db_session.commit()

    assert (
        db_session.scalar(
            select(MemberReceivedReport.id).where(
                MemberReceivedReport.member_id == member
            )
        )
        is None
    )


# ───────────────────────── 서비스: 수신 기록 읽기 ─────────────────────────


def test_a_send_writes_a_receipt_that_mirrors_the_message(client, db_session):
    trainer, member = _pair(db_session)
    week = _back(1)
    sent = _send(client, trainer, member, week, "받은 글")

    receipt = db_session.get(MemberReceivedReport, sent["id"])
    message = db_session.get(ChatMessage, sent["id"])

    assert receipt is not None and message is not None
    assert receipt.member_id == member
    assert receipt.trainer_id == trainer
    assert receipt.week_start == week.isoformat()
    assert receipt.body == "받은 글"
    assert receipt.created_at == message.created_at
    assert receipt.report_snapshot_json == message.report_snapshot_json


def test_received_is_per_member_and_per_week(client, db_session):
    trainer, member = _pair(db_session)
    other = _user(db_session, "member")
    _send(client, trainer, member, _back(1))

    assert received_reports.received(db_session, member, _back(1))
    assert not received_reports.received(db_session, member, _back(2))
    assert not received_reports.received(db_session, other, _back(1))


def test_a_snapshot_is_not_picked_by_another_members_message_id(client, db_session):
    trainer, member = _pair(db_session)
    other = _user(db_session, "member")
    _link(db_session, trainer, other)
    theirs = _send(client, trainer, other, _back(1))

    assert (
        received_reports.latest_with_snapshot(
            db_session, member, _back(1), message_id=theirs["id"]
        )
        is None
    )
