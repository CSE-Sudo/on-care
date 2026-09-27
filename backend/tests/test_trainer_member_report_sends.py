"""회원별 리포트 전송 이력 — `GET /trainer/clients/{member_id}/reports/sent`. (#2393, DB 필요)

트레이너 웹의 회원별 지난 리포트 화면이 이 응답을 읽는다. 근거와 접는 규칙은
주 단위 조회(`GET /trainer/reports/sent`, #2288)와 같다 — 리포트 전송이 남긴
채팅 메시지의 `report_week_start`, 한 주 여러 번이면 가장 최근 것 하나와 횟수.
"""
from __future__ import annotations

from collections.abc import Iterator
from datetime import date, datetime, timedelta, timezone
from uuid import uuid4

import pytest
from sqlalchemy import text

from app.core.security import create_access_token
from app.models.models import ChatMessage, TrainerClient, User
from app.services import trainer_service

TRAINER_ID = "trainer-demo"
PDF = b"%PDF-1.4\n1 0 obj<<>>endobj\n%%EOF\n"
BASE = datetime(2025, 9, 2, 1, 0, tzinfo=timezone.utc)

# 이 파일이 만든 사용자. 회원은 데모 트레이너의 로스터에 `sort_order` 0 으로 끼어들어,
# 남겨 두면 로스터 첫 줄을 쓰는 다른 파일의 테스트가 이 회원을 집는다.
_created: list[str] = []


@pytest.fixture(autouse=True)
def _cleanup_created_users() -> Iterator[None]:
    yield
    if not _created:
        return
    from app.db.session import SessionLocal

    db = SessionLocal()
    try:
        # 링크·메시지·알림은 `users.id` CASCADE 로 함께 지워진다.
        db.execute(text("DELETE FROM users WHERE id = ANY(:ids)"), {"ids": list(_created)})
        db.commit()
    finally:
        db.close()
        _created.clear()


def _h(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _url(member_id: str) -> str:
    return f"/v1/trainer/clients/{member_id}/reports/sent"


def _trainer_tok(client) -> str:
    r = client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    )
    assert r.status_code == 200, r.text
    return r.json()["access_token"]


def _member(db, *, trainer_id: str = TRAINER_ID, active: bool = True) -> str:
    """이 테스트만 쓰는 담당 회원. 다른 테스트의 전송과 섞이지 않게 새로 만든다."""
    member_id = f"history-member-{uuid4().hex[:10]}"
    _created.append(member_id)
    db.add(
        User(
            id=member_id,
            email=f"{member_id}@oncare.com",
            name="리포트 이력 회원",
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
    trainer_id = f"history-trainer-{uuid4().hex[:10]}"
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


def _history(db, member_id: str, *, limit: int = 12, before: date | None = None):
    return trainer_service.list_member_report_sends(
        db, TRAINER_ID, member_id, limit=limit, before=before
    )


def _weeks(out) -> list[str]:
    return [s.week_start for s in out.sends]


# ---- 첫 줄 요약 ----


def test_preview_takes_the_first_non_blank_line():
    body = "\n\n  이번 주 식단이 좋았어요  \n운동은 조금 부족했어요"
    assert trainer_service.report_feedback_preview(body) == "이번 주 식단이 좋았어요"


def test_preview_keeps_a_short_line_whole():
    line = "가" * trainer_service.REPORT_PREVIEW_LENGTH
    assert trainer_service.report_feedback_preview(line) == line


def test_preview_cuts_a_long_line_with_an_ellipsis():
    line = "나" * (trainer_service.REPORT_PREVIEW_LENGTH + 30)
    preview = trainer_service.report_feedback_preview(line)
    assert len(preview) == trainer_service.REPORT_PREVIEW_LENGTH
    assert preview.endswith("…")


def test_preview_of_an_empty_body_is_empty():
    assert trainer_service.report_feedback_preview("  \n \n") == ""


# ---- 서비스 ----


def test_service_orders_weeks_newest_first(client, db_session):
    member = _member(db_session)
    # 보낸 순서와 주 순서를 일부러 엇갈리게 둔다 — 정렬 기준은 주다.
    _message(db_session, member, week="2025-09-15", at=BASE)
    _message(db_session, member, week="2025-09-01", at=BASE + timedelta(days=20))
    _message(db_session, member, week="2025-09-08", at=BASE + timedelta(days=10))

    out = _history(db_session, member)

    assert out.member_id == member
    assert _weeks(out) == ["2025-09-15", "2025-09-08", "2025-09-01"]
    assert out.next_before is None


def test_service_folds_repeated_sends_of_a_week(client, db_session):
    member = _member(db_session)
    _message(db_session, member, week="2025-09-01", body="첫 전송", at=BASE)
    latest_id = _message(
        db_session,
        member,
        week="2025-09-01",
        body="고쳐서 다시\n두 번째 줄",
        at=BASE + timedelta(hours=3),
        pdf=True,
    )
    _message(db_session, member, week="2025-09-01", body="중간", at=BASE + timedelta(hours=1))

    [send] = _history(db_session, member).sends

    assert send.send_count == 3
    assert send.message_id == latest_id
    assert send.feedback_preview == "고쳐서 다시"
    assert send.has_pdf is True
    assert send.sent_at.startswith("2025-09-02T04:00:00")


def test_service_read_follows_the_latest_send(client, db_session):
    member = _member(db_session)
    _message(db_session, member, week="2025-09-01", at=BASE, read=True)
    _message(db_session, member, week="2025-09-01", at=BASE + timedelta(hours=1))
    _message(db_session, member, week="2025-09-08", at=BASE + timedelta(days=7), read=True)

    by_week = {s.week_start: s for s in _history(db_session, member).sends}

    assert by_week["2025-09-01"].read is False
    assert by_week["2025-09-08"].read is True


def test_service_ignores_plain_chat_and_member_messages(client, db_session):
    member = _member(db_session)
    _message(db_session, member, week=None, body="일반 대화")
    _message(db_session, member, week="2025-09-01", sender="member")
    _message(db_session, member, week="2025-09-08")

    assert _weeks(_history(db_session, member)) == ["2025-09-08"]


def test_service_keeps_other_members_and_trainers_apart(client, db_session):
    member = _member(db_session)
    neighbour = _member(db_session)
    other = _trainer(db_session)
    _message(db_session, member, week="2025-09-01")
    _message(db_session, neighbour, week="2025-09-08")
    _message(db_session, member, week="2025-09-15", trainer_id=other)

    assert _weeks(_history(db_session, member)) == ["2025-09-01"]


def test_service_pages_by_week_with_before(client, db_session):
    member = _member(db_session)
    weeks = ["2025-09-01", "2025-09-08", "2025-09-15", "2025-09-22", "2025-09-29"]
    for i, week in enumerate(weeks):
        _message(db_session, member, week=week, at=BASE + timedelta(days=7 * i))
    # 쪽 경계의 주에 재전송이 있어도 횟수가 두 쪽에 나뉘지 않는다.
    _message(db_session, member, week="2025-09-22", at=BASE + timedelta(days=40))

    first = _history(db_session, member, limit=2)
    assert _weeks(first) == ["2025-09-29", "2025-09-22"]
    assert first.sends[1].send_count == 2
    assert first.next_before == "2025-09-22"

    second = _history(
        db_session, member, limit=2, before=date.fromisoformat(first.next_before)
    )
    assert _weeks(second) == ["2025-09-15", "2025-09-08"]
    assert second.next_before == "2025-09-08"

    last = _history(
        db_session, member, limit=2, before=date.fromisoformat(second.next_before)
    )
    assert _weeks(last) == ["2025-09-01"]
    assert last.next_before is None


def test_service_exact_last_page_has_no_cursor(client, db_session):
    member = _member(db_session)
    _message(db_session, member, week="2025-09-01")
    _message(db_session, member, week="2025-09-08")

    out = _history(db_session, member, limit=2)

    assert len(out.sends) == 2
    assert out.next_before is None


def test_service_mid_week_before_excludes_that_week(client, db_session):
    member = _member(db_session)
    _message(db_session, member, week="2025-09-01")
    _message(db_session, member, week="2025-09-08")

    # 2025-09-10 은 수요일 — 그 주(09-08)는 빠지고 이전 주만 온다.
    out = _history(db_session, member, before=date(2025, 9, 10))

    assert _weeks(out) == ["2025-09-01"]


def test_service_empty_history(client, db_session):
    member = _member(db_session)

    out = _history(db_session, member)

    assert out.member_id == member
    assert out.sends == []
    assert out.next_before is None


def test_weekly_roster_view_uses_the_same_fold(client, db_session):
    """주 단위 조회와 회원별 조회가 같은 전송을 같은 횟수·시각으로 본다."""
    member = _member(db_session)
    _message(db_session, member, week="2025-09-01", at=BASE)
    _message(db_session, member, week="2025-09-01", at=BASE + timedelta(hours=2), read=True)

    [mine] = _history(db_session, member).sends
    [roster] = [
        s
        for s in trainer_service.list_report_sends(
            db_session, TRAINER_ID, date(2025, 9, 1)
        ).sends
        if s.member_id == member
    ]

    assert (mine.send_count, mine.sent_at, mine.read) == (
        roster.send_count,
        roster.sent_at,
        roster.read,
    )


# ---- API ----


def test_api_returns_sends_newest_first_with_the_documented_shape(client, db_session):
    member = _member(db_session)
    _message(db_session, member, week="2025-09-01", at=BASE, body="첫 주")
    latest = _message(
        db_session, member, week="2025-09-08", at=BASE + timedelta(days=7), body="둘째 주"
    )
    token = _trainer_tok(client)

    r = client.get(_url(member), headers=_h(token))

    assert r.status_code == 200, r.text
    body = r.json()
    assert set(body) == {"member_id", "sends", "next_before"}
    assert body["member_id"] == member
    assert body["next_before"] is None
    assert [s["week_start"] for s in body["sends"]] == ["2025-09-08", "2025-09-01"]
    assert body["sends"][0] == {
        "week_start": "2025-09-08",
        "sent_at": trainer_service._iso(BASE + timedelta(days=7)),
        "read": False,
        "send_count": 1,
        "message_id": latest,
        "has_pdf": False,
        "feedback_preview": "둘째 주",
    }


def test_api_a_real_send_shows_up(client, db_session):
    member = _member(db_session)
    token = _trainer_tok(client)
    for body in ("처음 보낸 글", "다시 보낸 글\n자세한 내용"):
        sent = client.post(
            f"/v1/trainer/clients/{member}/report/send",
            headers=_h(token),
            json={"week_start": "2025-10-06", "message": body},
        )
        assert sent.status_code == 201, sent.text

    [send] = client.get(_url(member), headers=_h(token)).json()["sends"]

    assert send["week_start"] == "2025-10-06"
    assert send["send_count"] == 2
    assert send["message_id"] == sent.json()["id"]
    assert send["feedback_preview"] == "다시 보낸 글"


def test_api_a_pdf_send_carries_its_message_id(client, db_session, tmp_path, monkeypatch):
    from app.core.config import get_settings

    monkeypatch.setattr(get_settings(), "report_pdf_storage_dir", str(tmp_path))
    member = _member(db_session)
    token = _trainer_tok(client)
    sent = client.post(
        f"/v1/trainer/clients/{member}/report/send-pdf",
        headers=_h(token),
        data={"week_start": "2025-10-15", "message": "PDF 로 보냅니다"},
        files={"pdf": ("weekly.pdf", PDF, "application/pdf")},
    )
    assert sent.status_code == 201, sent.text

    [send] = client.get(_url(member), headers=_h(token)).json()["sends"]

    assert send["week_start"] == "2025-10-13"
    assert send["has_pdf"] is True
    assert send["message_id"] == sent.json()["id"]


def test_api_pages_with_limit_and_before(client, db_session):
    member = _member(db_session)
    for i, week in enumerate(["2025-09-01", "2025-09-08", "2025-09-15"]):
        _message(db_session, member, week=week, at=BASE + timedelta(days=7 * i))
    token = _trainer_tok(client)

    first = client.get(_url(member), params={"limit": 2}, headers=_h(token)).json()
    assert [s["week_start"] for s in first["sends"]] == ["2025-09-15", "2025-09-08"]
    assert first["next_before"] == "2025-09-08"

    second = client.get(
        _url(member),
        params={"limit": 2, "before": first["next_before"]},
        headers=_h(token),
    ).json()
    assert [s["week_start"] for s in second["sends"]] == ["2025-09-01"]
    assert second["next_before"] is None


def test_api_empty_history(client, db_session):
    member = _member(db_session)
    token = _trainer_tok(client)

    r = client.get(_url(member), headers=_h(token))

    assert r.status_code == 200, r.text
    assert r.json() == {"member_id": member, "sends": [], "next_before": None}


def test_api_read_reflects_the_member_opening_it(client, db_session):
    member = _member(db_session)
    _message(db_session, member, week="2025-09-01", at=BASE, read=True)
    _message(db_session, member, week="2025-09-08", at=BASE + timedelta(days=7))
    token = _trainer_tok(client)

    sends = client.get(_url(member), headers=_h(token)).json()["sends"]

    assert {s["week_start"]: s["read"] for s in sends} == {
        "2025-09-08": False,
        "2025-09-01": True,
    }


def test_api_rejects_a_member_whose_assignment_ended(client, db_session):
    member = _member(db_session, active=False)
    _message(db_session, member, week="2025-09-01")
    token = _trainer_tok(client)

    r = client.get(_url(member), headers=_h(token))

    assert r.status_code == 404


def test_api_rejects_another_trainers_member(client, db_session):
    other = _trainer(db_session)
    theirs = _member(db_session, trainer_id=other)
    _message(db_session, theirs, week="2025-09-01", trainer_id=other)
    token = _trainer_tok(client)

    r = client.get(_url(theirs), headers=_h(token))

    assert r.status_code == 404


def test_api_ended_and_foreign_members_look_the_same(client, db_session):
    """해제된 회원과 남의 회원이 같은 답이어야 해제 사실이 드러나지 않는다(#2281)."""
    ended = _member(db_session, active=False)
    foreign = _member(db_session, trainer_id=_trainer(db_session))
    token = _trainer_tok(client)

    a = client.get(_url(ended), headers=_h(token))
    b = client.get(_url(foreign), headers=_h(token))

    assert a.status_code == b.status_code == 404
    assert a.json() == b.json()


def test_api_other_trainer_cannot_read_my_member(client, db_session):
    member = _member(db_session)
    _message(db_session, member, week="2025-09-01")
    other = _trainer(db_session)

    r = client.get(_url(member), headers=_h(create_access_token(other)))

    assert r.status_code == 404


def test_api_rejects_a_malformed_before(client, db_session):
    member = _member(db_session)
    token = _trainer_tok(client)

    r = client.get(_url(member), params={"before": "지난주"}, headers=_h(token))

    assert r.status_code == 422


def test_api_rejects_an_out_of_range_limit(client, db_session):
    member = _member(db_session)
    token = _trainer_tok(client)

    for limit in (0, 101):
        r = client.get(_url(member), params={"limit": limit}, headers=_h(token))
        assert r.status_code == 422


def test_api_requires_a_signed_in_trainer(client, db_session):
    member = _member(db_session)
    assert client.get(_url(member)).status_code == 401


def test_api_a_member_account_is_forbidden(client, db_session):
    member = _member(db_session)
    r = client.post(
        "/v1/auth/login",
        data={"username": "jisu@oncare.com", "password": "oncare123"},
    )
    assert r.status_code == 200, r.text

    got = client.get(_url(member), headers=_h(r.json()["access_token"]))

    assert got.status_code == 403
