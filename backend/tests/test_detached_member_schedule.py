"""담당이 끊긴 회원의 일정 — 스케줄에 익명으로 남고, 남은 일정은 취소된다. (#2589)

트레이너가 참여한 수업은 담당 해제 뒤에도 트레이너 스케줄에 남는다. 회원 상세·
식단·기록 차단(#2281)과 같은 경계로 누구였는지와 그 수업의 글·프로그램은 가리고,
수정·완료·재개·전송은 계속 막는다. 아직 시작하지 않은 PT 는 해제 때 취소하고,
일정별 알림 대신 해제 알림 한 건이 취소 수를 전한다.
"""

from __future__ import annotations

import json
from collections.abc import Iterator
from dataclasses import dataclass
from datetime import timedelta
from uuid import uuid4

import pytest
from sqlalchemy import select, text

from app.core import clock
from app.core.security import create_access_token
from app.models.models import Notification, TrainerClient, TrainerSchedule, User
from app.services import notification_templates as nt

GUARD_DETAIL = "담당 회원을 찾을 수 없어요."


def _h(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


@dataclass(frozen=True)
class Pair:
    trainer_id: str
    member_id: str
    link_id: str
    headers: dict[str, str]
    member_headers: dict[str, str]


@pytest.fixture()
def pair(db_session) -> Iterator[Pair]:
    """담당 중인 (트레이너, 회원) 한 쌍. 테스트가 해제한다."""
    suffix = uuid4().hex[:10]
    trainer_id = f"detached-trainer-{suffix}"
    member_id = f"detached-member-{suffix}"
    db_session.add_all(
        [
            User(
                id=trainer_id,
                email=f"{trainer_id}@oncare.com",
                name="박코치",
                hashed_password="unused",
                role="trainer",
            ),
            User(
                id=member_id,
                email=f"{member_id}@oncare.com",
                name="해제될 회원",
                hashed_password="unused",
                role="member",
            ),
        ]
    )
    db_session.flush()
    link_id = f"tc-{uuid4().hex[:12]}"
    db_session.add(
        TrainerClient(
            id=link_id,
            trainer_id=trainer_id,
            member_id=member_id,
            active=True,
            data_consent_at=clock.now(),
        )
    )
    db_session.commit()
    try:
        yield Pair(
            trainer_id=trainer_id,
            member_id=member_id,
            link_id=link_id,
            headers=_h(create_access_token(trainer_id)),
            member_headers=_h(create_access_token(member_id)),
        )
    finally:
        db_session.rollback()
        db_session.expire_all()
        db_session.execute(
            text("DELETE FROM users WHERE id = ANY(:ids)"),
            {"ids": [trainer_id, member_id]},
        )
        db_session.commit()


def _session(
    db_session,
    p: Pair,
    *,
    day: str,
    time: str,
    status: str = "예정",
    note: str = "",
) -> str:
    """일정 행을 바로 넣는다 — 지난 날짜도 만들 수 있게 API 를 거치지 않는다."""
    session_id = f"sched-{uuid4().hex[:12]}"
    db_session.add(
        TrainerSchedule(
            id=session_id,
            trainer_id=p.trainer_id,
            member_id=p.member_id,
            client_name="해제될 회원",
            date=day,
            time=time,
            type="1:1 PT",
            duration_minutes=50,
            status=status,
            note=note,
            program_json=json.dumps(
                [{"name": "스쿼트", "type": "근력", "sets": 3, "reps": "10회"}]
            ),
        )
    )
    db_session.commit()
    return session_id


def _day(offset: int) -> str:
    return (clock.today() + timedelta(days=offset)).isoformat()


def _trainer_detaches(client, p: Pair) -> None:
    r = client.delete(f"/v1/trainer/clients/{p.member_id}", headers=p.headers)
    assert r.status_code == 204, r.text


def _member_detaches(client, p: Pair) -> None:
    r = client.delete("/v1/me/coach/trainer", headers=p.member_headers)
    assert r.status_code == 204, r.text


def _schedule(client, p: Pair, day: str) -> dict[str, dict]:
    r = client.get("/v1/trainer/schedule", params={"date": day}, headers=p.headers)
    assert r.status_code == 200, r.text
    return {row["id"]: row for row in r.json()}


def _notices(db_session, user_id: str, template: str) -> list[Notification]:
    db_session.expire_all()
    return list(
        db_session.scalars(
            select(Notification).where(
                Notification.user_id == user_id,
                Notification.template == template,
            )
        ).all()
    )


# ---------------------------------------------------------------------------
# 지난 일정 — 익명으로 남는다
# ---------------------------------------------------------------------------


def test_past_session_stays_on_schedule_anonymously(client, db_session, pair):
    day = _day(-3)
    session_id = _session(
        db_session, pair, day=day, time="10:00", status="완료", note="무릎 조심"
    )
    assert _schedule(client, pair, day)[session_id]["client_name"] == "해제될 회원"

    _trainer_detaches(client, pair)

    row = _schedule(client, pair, day)[session_id]
    assert row["member_detached"] is True
    assert row["client_name"] == "해제 회원"
    assert row["member_id"] is None
    assert row["note"] == ""
    assert row["program"] == []
    assert row["program_sent"] is False
    # 언제·무슨 종류·어떻게 끝났는지는 남는다.
    assert (row["date"], row["time"], row["type"], row["status"]) == (
        day,
        "10:00",
        "1:1 PT",
        "완료",
    )
    assert row["duration_minutes"] == 50


def test_linked_session_is_not_marked_detached(client, db_session, pair):
    day = _day(-2)
    session_id = _session(db_session, pair, day=day, time="11:00", note="메모")

    row = _schedule(client, pair, day)[session_id]

    assert row["member_detached"] is False
    assert row["member_id"] == pair.member_id
    assert row["note"] == "메모"


def test_booked_dates_keep_the_detached_day(client, db_session, pair):
    day = _day(-4)
    _session(db_session, pair, day=day, time="09:00", status="완료")
    _trainer_detaches(client, pair)

    r = client.get("/v1/trainer/schedule/booked-dates", headers=pair.headers)

    assert r.status_code == 200, r.text
    assert day in r.json()


def test_consent_revoked_link_is_anonymous_too(client, db_session, pair):
    """링크가 살아 있어도 동의가 철회됐으면 해제와 같은 경계다(#1631)."""
    day = _day(-1)
    session_id = _session(db_session, pair, day=day, time="08:00", note="메모")
    link = db_session.get(TrainerClient, pair.link_id)
    link.data_consent_at = None
    link.data_consent_revoked_at = clock.now()
    db_session.commit()

    row = _schedule(client, pair, day)[session_id]

    assert row["member_detached"] is True
    assert row["client_name"] == "해제 회원"
    assert row["note"] == ""


@pytest.mark.parametrize(
    ("method", "suffix", "body"),
    [
        ("PUT", "", {"time": "12:00"}),
        ("POST", "/complete", {"note": "해제 뒤 완료"}),
        ("POST", "/program/send", {}),
    ],
    ids=["update", "complete", "program-send"],
)
def test_detached_session_stays_read_only(
    client, db_session, pair, method, suffix, body
):
    session_id = _session(db_session, pair, day=_day(-1), time="07:00")
    _trainer_detaches(client, pair)

    r = client.request(
        method,
        f"/v1/trainer/schedule/{session_id}{suffix}",
        json=body,
        headers=pair.headers,
    )

    assert r.status_code == 404, r.text
    assert r.json()["detail"] == GUARD_DETAIL


def test_detached_session_can_still_be_deleted(client, db_session, pair):
    """삭제는 트레이너가 자기 일정을 정리하는 일이라 막지 않는다."""
    session_id = _session(db_session, pair, day=_day(-5), time="07:00", status="완료")
    _trainer_detaches(client, pair)

    r = client.delete(f"/v1/trainer/schedule/{session_id}", headers=pair.headers)

    assert r.status_code == 200, r.text
    db_session.expire_all()
    assert db_session.get(TrainerSchedule, session_id) is None


def test_member_filter_still_blocks_a_detached_member(client, db_session, pair):
    """회원별 조회는 회원 상세 길이라 해제 뒤에는 닫힌다(#2281)."""
    _session(db_session, pair, day=_day(-1), time="07:00")
    _trainer_detaches(client, pair)

    r = client.get(
        "/v1/trainer/schedule",
        params={"member_id": pair.member_id},
        headers=pair.headers,
    )

    assert r.status_code == 404, r.text


def test_overlap_rejection_does_not_leak_the_detached_name(client, db_session, pair):
    """겹침 거절 응답에 실리는 일정도 스케줄처럼 가린다."""
    today = clock.today_iso()
    # 오늘 00:00 은 이미 시작한 일정이라 해제 때 취소되지 않고 자리를 차지한다.
    session_id = _session(db_session, pair, day=today, time="00:00")
    _trainer_detaches(client, pair)

    r = client.post(
        "/v1/trainer/schedule",
        json={
            "date": today,
            "time": "00:10",
            "client_name": "다른 손님",
            "type": "상담",
            "duration_minutes": 30,
        },
        headers=pair.headers,
    )

    assert r.status_code == 409, r.text
    conflicts = r.json()["detail"]["conflicts"]
    hit = next(c for c in conflicts if c["id"] == session_id)
    assert hit["client_name"] == "해제 회원"
    assert hit["member_id"] is None
    assert hit["member_detached"] is True
    assert "해제될 회원" not in r.text


# ---------------------------------------------------------------------------
# 남은 일정 — 해제 때 취소하고 알림 한 건
# ---------------------------------------------------------------------------


def test_trainer_detach_cancels_remaining_sessions_with_one_notice(
    client, db_session, pair
):
    past = _session(db_session, pair, day=_day(-1), time="10:00", status="완료")
    started = _session(db_session, pair, day=clock.today_iso(), time="00:00")
    future = [
        _session(db_session, pair, day=_day(1), time="10:00"),
        _session(db_session, pair, day=_day(8), time="10:00"),
    ]

    _trainer_detaches(client, pair)

    db_session.expire_all()
    for session_id in future:
        row = db_session.get(TrainerSchedule, session_id)
        assert row.status == "취소"
        assert row.cancellation_source == "trainer"
        assert row.cancellation_reason == "담당 해제"
        assert row.cancelled_at is not None
    # 지난 일정과 이미 시작한 일정은 기록 그대로다.
    assert db_session.get(TrainerSchedule, past).status == "완료"
    assert db_session.get(TrainerSchedule, started).status == "예정"

    notices = _notices(db_session, pair.member_id, nt.MEMBER_TRAINER_DISCONNECTED)
    assert len(notices) == 1
    assert notices[0].title == "담당 트레이너 연결이 해제됐어요"
    assert notices[0].body == (
        "박코치 트레이너와 담당 연결이 해제됐어요. 남은 PT 일정 2건도 취소됐어요."
    )
    # 일정마다 취소 알림을 보내지 않는다.
    assert _notices(db_session, pair.member_id, nt.MEMBER_SCHEDULE_CANCELLED) == []

    # 취소된 남은 일정도 스케줄에 익명 기록으로 남는다.
    row = _schedule(client, pair, _day(1))[future[0]]
    assert row["status"] == "취소"
    assert row["member_detached"] is True
    # 취소 사유는 가린다 — 회원이 적은 사유일 수 있다.
    assert row["cancellation_reason"] == ""


def test_trainer_detach_without_remaining_sessions_only_says_disconnected(
    client, db_session, pair
):
    _session(db_session, pair, day=_day(-1), time="10:00", status="완료")

    _trainer_detaches(client, pair)

    notices = _notices(db_session, pair.member_id, nt.MEMBER_TRAINER_DISCONNECTED)
    assert len(notices) == 1
    assert notices[0].body == "박코치 트레이너와 담당 연결이 해제됐어요."


def test_member_detach_cancels_remaining_sessions_and_tells_the_trainer(
    client, db_session, pair
):
    future = _session(db_session, pair, day=_day(2), time="10:00")

    _member_detaches(client, pair)

    db_session.expire_all()
    row = db_session.get(TrainerSchedule, future)
    assert row.status == "취소"
    assert row.cancellation_source == "member"
    assert row.cancellation_reason == "담당 해제"

    trainer_notices = _notices(
        db_session, pair.trainer_id, nt.TRAINER_MEMBER_DISCONNECTED
    )
    assert len(trainer_notices) == 1
    assert trainer_notices[0].body == (
        "해제될 회원 회원이 담당 연결을 해제했어요. 남은 일정 1건은 취소됐어요."
    )
    # 회원은 스스로 끊었으니 따로 알리지 않는다.
    assert _notices(db_session, pair.member_id, nt.MEMBER_TRAINER_DISCONNECTED) == []
    assert _notices(db_session, pair.member_id, nt.MEMBER_SCHEDULE_CANCELLED) == []


def test_member_detach_without_remaining_sessions_keeps_the_old_notice(
    client, db_session, pair
):
    _member_detaches(client, pair)

    trainer_notices = _notices(
        db_session, pair.trainer_id, nt.TRAINER_MEMBER_DISCONNECTED
    )
    assert len(trainer_notices) == 1
    assert trainer_notices[0].body == "해제될 회원 회원이 담당 연결을 해제했어요."
