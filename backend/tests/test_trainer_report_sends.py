"""리포트 전송 이력 — `GET /trainer/reports/sent`. (#2288, DB 필요)

트레이너 웹의 작업대는 이 응답으로 `전송 완료` 열을 세운다. 예전에는 앱 메모리
에만 기록이 있어 새로고침하면 보낸 회원이 미전송으로 돌아갔고, 같은 리포트를
한 번 더 보낼 수 있었다. 근거는 리포트 전송이 남긴 채팅 메시지의
`report_week_start` 하나다.
"""
from __future__ import annotations

from datetime import date, datetime, timedelta, timezone
from uuid import uuid4

import pytest
from sqlalchemy import delete, select

from app.core.security import create_access_token
from app.models.models import ChatMessage, TrainerClient, User
from app.services.trainer import _common as trainer_common_service
from app.services.trainer import reports as trainer_reports_service

TRAINER_ID = "trainer-demo"
SENT = "/v1/trainer/reports/sent"
PDF = b"%PDF-1.4\n1 0 obj<<>>endobj\n%%EOF\n"

# 이 파일이 만든 계정 id. 테스트가 끝날 때마다 지운다.
_created: list[str] = []


@pytest.fixture(autouse=True)
def _drop_created_accounts(db_session):
    """이 파일이 만든 회원·트레이너를 테스트마다 지운다. (#2471)

    남겨 두면 `trainer-demo` 로스터 맨 앞에 선다 — 새 담당 링크는 `sort_order`
    0 이고 로스터는 `sort_order` → 회원 id 순이라 `sends-…` 가 시드의 `user-…`
    보다 앞이다. 로스터 첫 회원을 집어 쓰는 다른 파일의 테스트가, 담당이 끝난
    회원을 우연히 집는 실행에서만 404 로 떨어졌다. `users.id` 를 참조하는 FK 는
    모두 CASCADE/SET NULL 이라 `User` 행만 지우면 링크·메시지가 함께 정리된다.
    """
    yield
    if not _created:
        return
    db_session.rollback()
    db_session.execute(delete(User).where(User.id.in_(list(_created))))
    db_session.commit()
    _created.clear()


def _h(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _trainer_tok(client) -> str:
    r = client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    )
    assert r.status_code == 200, r.text
    return r.json()["access_token"]


def _member(db, *, trainer_id: str = TRAINER_ID, active: bool = True) -> str:
    """이 테스트만 쓰는 담당 회원. 다른 테스트의 전송과 섞이지 않게 새로 만든다."""
    member_id = f"sends-member-{uuid4().hex[:10]}"
    _created.append(member_id)
    db.add(
        User(
            id=member_id,
            email=f"{member_id}@oncare.com",
            name="전송 이력 회원",
            hashed_password="unused",
            role="member",
        )
    )
    db.commit()
    db.add(
        TrainerClient(
            id=f"link-{uuid4().hex[:12]}",
            trainer_id=trainer_id,
            member_id=member_id,
            active=active,
        )
    )
    db.commit()
    return member_id


def _trainer(db) -> str:
    trainer_id = f"sends-trainer-{uuid4().hex[:10]}"
    _created.append(trainer_id)
    db.add(
        User(
            id=trainer_id,
            email=f"{trainer_id}@oncare.com",
            name="다른 트레이너",
            hashed_password="unused",
            role="trainer",
        )
    )
    db.commit()
    return trainer_id


def _message(
    db,
    member_id: str,
    *,
    week: str | None,
    body: str = "이번 주 리포트입니다.",
    trainer_id: str = TRAINER_ID,
    sender: str = "trainer",
    at: datetime | None = None,
    read: bool = False,
    pdf: bool = False,
) -> str:
    """앱을 거치지 않고 메시지 한 건을 남긴다 — 시각·읽음을 정해 두려고."""
    message_id = f"chat-{uuid4().hex[:12]}"
    created = at or datetime.now(timezone.utc)
    db.add(
        ChatMessage(
            id=message_id,
            trainer_id=trainer_id,
            member_id=member_id,
            sender=sender,
            body=body,
            report_week_start=week,
            attachment_type="pdf" if pdf else None,
            attachment_file_name="weekly.pdf" if pdf else None,
            attachment_file_id=f"file-{uuid4().hex}" if pdf else None,
            attachment_file_size=len(PDF) if pdf else None,
            read_at=created if read else None,
            created_at=created,
        )
    )
    db.commit()
    return message_id


def _sends(client, token: str, week: str) -> dict[str, dict]:
    r = client.get(SENT, params={"week_start": week}, headers=_h(token))
    assert r.status_code == 200, r.text
    return {s["member_id"]: s for s in r.json()["sends"]}


# ---- 서비스 ----


def test_service_folds_repeated_sends_into_the_latest_with_a_count(
    client, db_session
):
    member = _member(db_session)
    base = datetime(2025, 10, 7, 1, 0, tzinfo=timezone.utc)
    _message(db_session, member, week="2025-10-06", body="첫 전송", at=base)
    _message(
        db_session,
        member,
        week="2025-10-06",
        body="고쳐서 다시",
        at=base + timedelta(hours=3),
        read=True,
        pdf=True,
    )

    out = trainer_reports_service.list_report_sends(
        db_session, TRAINER_ID, date(2025, 10, 6)
    )
    [send] = [s for s in out.sends if s.member_id == member]

    assert out.week_start == "2025-10-06"
    assert send.message == "고쳐서 다시"
    assert send.send_count == 2
    assert send.read is True
    assert send.has_pdf is True
    assert send.sent_at.startswith("2025-10-07T04:00:00")


def test_service_normalises_a_mid_week_day_to_monday(client, db_session):
    member = _member(db_session)
    _message(db_session, member, week="2025-10-13")

    out = trainer_reports_service.list_report_sends(
        db_session, TRAINER_ID, date(2025, 10, 16)
    )

    assert out.week_start == "2025-10-13"
    assert member in {s.member_id for s in out.sends}


def test_service_ignores_plain_chat_member_messages_and_other_weeks(
    client, db_session
):
    member = _member(db_session)
    _message(db_session, member, week=None, body="일반 대화")
    _message(db_session, member, week="2025-10-20", sender="member")
    _message(db_session, member, week="2025-10-27", body="다음 주 리포트")

    out = trainer_reports_service.list_report_sends(
        db_session, TRAINER_ID, date(2025, 10, 20)
    )

    assert member not in {s.member_id for s in out.sends}


def test_service_skips_members_whose_assignment_ended(client, db_session):
    member = _member(db_session, active=False)
    _message(db_session, member, week="2025-11-03")

    out = trainer_reports_service.list_report_sends(
        db_session, TRAINER_ID, date(2025, 11, 3)
    )

    assert member not in {s.member_id for s in out.sends}


def test_service_keeps_trainers_apart(client, db_session):
    other = _trainer(db_session)
    mine = _member(db_session)
    theirs = _member(db_session, trainer_id=other)
    _message(db_session, mine, week="2025-11-10")
    _message(db_session, theirs, week="2025-11-10", trainer_id=other)

    my_ids = {
        s.member_id
        for s in trainer_reports_service.list_report_sends(
            db_session, TRAINER_ID, date(2025, 11, 10)
        ).sends
    }
    their_ids = {
        s.member_id
        for s in trainer_reports_service.list_report_sends(
            db_session, other, date(2025, 11, 10)
        ).sends
    }

    assert mine in my_ids and theirs not in my_ids
    assert their_ids == {theirs}


def test_service_answers_an_empty_list_for_a_week_with_no_sends(client, db_session):
    other = _trainer(db_session)

    out = trainer_reports_service.list_report_sends(db_session, other, date(2019, 2, 4))

    assert out.week_start == "2019-02-04"
    assert out.sends == []


# ---- API ----


def test_a_text_send_shows_up_after_reloading(client, db_session):
    """새로고침한 앱이 다시 물어도 보낸 회원이 전송 완료로 돌아온다."""
    member = _member(db_session)
    token = _trainer_tok(client)
    week = "2025-12-01"
    assert member not in _sends(client, token, week)

    sent = client.post(
        f"/v1/trainer/clients/{member}/report/send",
        headers=_h(token),
        json={"week_start": week, "message": "이번 주 잘했어요"},
    )
    assert sent.status_code == 201, sent.text

    send = _sends(client, token, week)[member]
    assert send == {
        "member_id": member,
        "week_start": week,
        "sent_at": sent.json()["created_at"],
        "message": "이번 주 잘했어요",
        "read": False,
        "has_pdf": False,
        "send_count": 1,
    }


def test_a_pdf_send_is_recorded_with_its_attachment(
    client, db_session, tmp_path, monkeypatch
):
    from app.core.config import get_settings

    monkeypatch.setattr(get_settings(), "report_pdf_storage_dir", str(tmp_path))
    member = _member(db_session)
    token = _trainer_tok(client)
    sent = client.post(
        f"/v1/trainer/clients/{member}/report/send-pdf",
        headers=_h(token),
        data={
            "week_start": "2025-12-10",
            "message": "PDF 로 보냅니다",
            "client_request_id": f"sends-{uuid4().hex[:12]}",
        },
        files={"pdf": ("weekly.pdf", PDF, "application/pdf")},
    )
    assert sent.status_code == 201, sent.text

    send = _sends(client, token, "2025-12-08")[member]
    assert send["has_pdf"] is True
    assert send["message"] == "PDF 로 보냅니다"
    assert send["week_start"] == "2025-12-08"


def test_a_pdf_retry_with_the_same_key_is_not_counted_twice(
    client, db_session, tmp_path, monkeypatch
):
    from app.core.config import get_settings

    monkeypatch.setattr(get_settings(), "report_pdf_storage_dir", str(tmp_path))
    member = _member(db_session)
    token = _trainer_tok(client)
    form = {
        "week_start": "2025-12-15",
        "message": "재시도",
        "client_request_id": f"sends-retry-{uuid4().hex[:12]}",
    }
    for _ in range(2):
        r = client.post(
            f"/v1/trainer/clients/{member}/report/send-pdf",
            headers=_h(token),
            data=form,
            files={"pdf": ("weekly.pdf", PDF, "application/pdf")},
        )
        assert r.status_code == 201, r.text

    assert _sends(client, token, "2025-12-15")[member]["send_count"] == 1


def test_sending_again_counts_and_keeps_the_latest_body(client, db_session):
    member = _member(db_session)
    token = _trainer_tok(client)
    week = "2025-12-22"
    for body in ("처음 보낸 글", "다시 보낸 글"):
        r = client.post(
            f"/v1/trainer/clients/{member}/report/send",
            headers=_h(token),
            json={"week_start": week, "message": body},
        )
        assert r.status_code == 201, r.text

    send = _sends(client, token, week)[member]
    assert send["send_count"] == 2
    assert send["message"] == "다시 보낸 글"


def test_a_send_for_another_week_does_not_leak(client, db_session):
    member = _member(db_session)
    token = _trainer_tok(client)
    r = client.post(
        f"/v1/trainer/clients/{member}/report/send",
        headers=_h(token),
        json={"week_start": "2026-01-05", "message": "1월 첫 주"},
    )
    assert r.status_code == 201, r.text

    assert member in _sends(client, token, "2026-01-05")
    assert member not in _sends(client, token, "2026-01-12")
    assert member not in _sends(client, token, "2025-12-29")


def test_the_default_week_is_this_week(client, db_session):
    token = _trainer_tok(client)
    r = client.get(SENT, headers=_h(token))

    assert r.status_code == 200, r.text
    this_monday = trainer_reports_service.week_start_of(
        date.fromisoformat(trainer_common_service.today_iso())
    )
    assert r.json()["week_start"] == this_monday.isoformat()


def test_the_response_carries_exactly_what_the_app_reads(client, db_session):
    member = _member(db_session)
    _message(db_session, member, week="2026-01-19")
    token = _trainer_tok(client)

    body = client.get(
        SENT, params={"week_start": "2026-01-19"}, headers=_h(token)
    ).json()

    assert set(body) == {"week_start", "sends"}
    send = next(s for s in body["sends"] if s["member_id"] == member)
    assert set(send) == {
        "member_id",
        "week_start",
        "sent_at",
        "message",
        "read",
        "has_pdf",
        "send_count",
    }


def test_a_malformed_week_is_rejected(client):
    token = _trainer_tok(client)
    r = client.get(SENT, params={"week_start": "지난주"}, headers=_h(token))
    assert r.status_code == 422


def test_a_future_week_is_rejected(client):
    token = _trainer_tok(client)
    future = date.fromisoformat(trainer_common_service.today_iso()) + timedelta(days=14)
    r = client.get(SENT, params={"week_start": future.isoformat()}, headers=_h(token))
    assert r.status_code == 422


def test_requires_a_signed_in_trainer(client):
    assert client.get(SENT).status_code == 401


def test_a_member_account_cannot_read_trainer_send_history(client):
    r = client.post(
        "/v1/auth/login",
        data={"username": "jisu@oncare.com", "password": "oncare123"},
    )
    assert r.status_code == 200, r.text
    got = client.get(SENT, headers=_h(r.json()["access_token"]))
    assert got.status_code == 403


def test_another_trainer_sees_none_of_my_sends(client, db_session):
    member = _member(db_session)
    _message(db_session, member, week="2026-02-02")
    other = _trainer(db_session)

    theirs = _sends(client, create_access_token(other), "2026-02-02")

    assert member not in theirs


# ---- 정리 (#2471) ----


def test_accounts_made_here_are_tracked_for_cleanup(client, db_session):
    member = _member(db_session, active=False)
    trainer = _trainer(db_session)

    assert member in _created
    assert trainer in _created


def test_no_account_from_an_earlier_test_is_left_behind(client, db_session):
    """앞 테스트들이 만든 `sends-…` 계정은 이 테스트가 시작할 때 이미 없다."""
    assert _created == []
    left = db_session.scalars(
        select(User.id).where(
            User.id.like("sends-member-%") | User.id.like("sends-trainer-%")
        )
    ).all()
    assert left == []


def test_the_roster_does_not_open_with_a_test_account(client, db_session):
    """정리 뒤 `trainer-demo` 로스터의 첫 회원은 시드 회원이다."""
    token = _trainer_tok(client)
    r = client.get("/v1/trainer/clients", headers=_h(token))
    assert r.status_code == 200, r.text
    roster = r.json()
    assert roster
    assert not roster[0]["id"].startswith("sends-member-")
