"""담당이 해제된 회원의 데이터는 트레이너가 읽지도 쓰지도 못한다. (#2281)

담당 해제는 링크 행을 지우지 않고 `active=False` 로 내린다(`remove_client`). 예전
권한 확인은 행이 있는지만 봐서, 해제 뒤에도 식단·사진·건강 정보·채팅·루틴·메모·
리포트·AI 코치·일정이 그대로 열렸고, 해제된 회원에게 일정을 잡으면 새 일정 알림까지
나갔다.

여기서 보는 것:

* 회원 단위 엔드포인트 전부가 해제 뒤 **남의 회원과 같은 404·같은 문구**다.
* 막힌 쓰기는 아무 행도 남기지 않는다(채팅·일정·루틴·메모·리포트·알림).
* `_require_client` 를 지나지 않는 경로(제안 승인·일정의 프로그램 전송·일정 등록 뒤
  배정)도 같은 경계를 본다.
* 해제 전에 잡아 둔 일정을 id 로 여는 경로(개인운동 전송·완료·수정·되돌리기)도
  막힌다. 취소는 열려 있다. 동의 없이 살아 있는 링크도 같다(#1631).
* 해제된 링크를 다뤄야 하는 곳(해제·재등록·활성/휴면 전환·로스터·내 할 일)은
  예전 동작 그대로다.
* 휴면(`dormant`)은 담당 해제가 아니다 — 계속 열린다.
"""

from __future__ import annotations

from collections.abc import Iterator
from dataclasses import dataclass
from datetime import timedelta
from uuid import uuid4

import pytest
from sqlalchemy import func, select, text

from app.core import clock
from app.core.security import create_access_token
from app.models.models import (
    ChatMessage,
    ExerciseSession,
    Notification,
    RoutineHistory,
    TrainerClient,
    TrainerClientMemo,
    TrainerFollowUpTask,
    TrainerReportFeedback,
    TrainerRoutine,
    TrainerSchedule,
    User,
)

GUARD_DETAIL = "담당 고객을 찾을 수 없습니다."


def _h(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


@dataclass
class Pair:
    trainer_id: str
    member_id: str
    link_id: str
    headers: dict[str, str]


def _cleanup(db_session, user_ids: list[str]) -> None:
    db_session.rollback()
    db_session.expire_all()
    # 행 대부분은 `users.id` CASCADE 로 함께 지워진다. 트레이너가 회원에게 남긴
    # 행도 두 사람 중 하나를 참조하므로 여기서 한꺼번에 사라진다.
    db_session.execute(
        text("DELETE FROM users WHERE id = ANY(:ids)"), {"ids": user_ids}
    )
    db_session.commit()


def _make_pair(db_session, *, active: bool = True) -> Pair:
    suffix = uuid4().hex[:10]
    trainer_id = f"inactive-trainer-{suffix}"
    member_id = f"inactive-member-{suffix}"
    db_session.add_all(
        [
            User(
                id=trainer_id,
                email=f"{trainer_id}@oncare.com",
                name="해제 확인 트레이너",
                hashed_password="unused",
                role="trainer",
            ),
            User(
                id=member_id,
                email=f"{member_id}@oncare.com",
                name="해제 확인 회원",
                hashed_password="unused",
                role="member",
            ),
        ]
    )
    db_session.flush()  # TrainerClient 의 FK 부모를 먼저 반영한다.
    link_id = f"tc-{uuid4().hex[:12]}"
    db_session.add(
        TrainerClient(
            id=link_id,
            trainer_id=trainer_id,
            member_id=member_id,
            active=active,
        )
    )
    db_session.commit()
    return Pair(
        trainer_id=trainer_id,
        member_id=member_id,
        link_id=link_id,
        headers=_h(create_access_token(trainer_id)),
    )


@pytest.fixture()
def pair(db_session) -> Iterator[Pair]:
    """담당 중인 (트레이너, 회원) 한 쌍. 테스트가 해제한다."""
    created = _make_pair(db_session)
    try:
        yield created
    finally:
        _cleanup(db_session, [created.trainer_id, created.member_id])


def _detach(client, p: Pair) -> None:
    """실제 화면이 쓰는 경로로 담당을 해제한다."""
    r = client.delete(f"/v1/trainer/clients/{p.member_id}", headers=p.headers)
    assert r.status_code == 204, r.text


def _count(db_session, model, **where) -> int:
    db_session.expire_all()
    stmt = select(func.count()).select_from(model)
    for column, value in where.items():
        stmt = stmt.where(getattr(model, column) == value)
    return db_session.scalar(stmt)


def _assert_guard(r) -> None:
    assert r.status_code == 404, r.text
    assert r.json()["detail"] == GUARD_DETAIL


def _future_day(days: int = 3) -> str:
    return (clock.today() + timedelta(days=days)).isoformat()


def _this_monday() -> str:
    today = clock.today()
    return (today - timedelta(days=today.weekday())).isoformat()


# ---------------------------------------------------------------------------
# 회원 단위 엔드포인트 — (메서드, 경로, 요청 본문) 전부가 해제 뒤 404
# ---------------------------------------------------------------------------

_PROGRAM_SESSIONS = [
    {
        "id": "session-1",
        "name": "",
        "exercises": [{"id": "ex-1", "name": "스쿼트", "sets": 3, "reps": 10}],
    }
]

#: 읽기 — 해제 전에는 200 으로 열리던 것들이다(아래 대조 테스트).
READ_ENDPOINTS: list[tuple[str, str, dict]] = [
    ("health-profile", "/health-profile", {}),
    ("diet", "/diet", {}),
    ("diet-days", "/diet/days", {}),
    ("exercise-weeks", "/exercise/weeks", {}),
    ("records-span", "/records/span", {}),
    ("history", "/history", {}),
    ("diet-advice", "/diet-advice", {"period": "today"}),
    ("exercise-advice", "/exercise-advice", {"period": "today"}),
    ("exercise-week", "/exercise-week", {}),
    ("chat", "/chat", {}),
    ("routines", "/routines", {}),
    ("routine-suggestions", "/routine-suggestions", {}),
    ("memos", "/memos", {}),
    ("follow-ups", "/follow-ups", {}),
    ("ai-coach-history", "/ai-coach", {}),
    ("report", "/report", {}),
    ("report-summary", "/report/summary", {}),
    ("report-feedback", "/report/feedback", {}),
    ("report-member-feedback", "/report/member-feedback", {}),
    ("report-goals", "/report/goals", {}),
]

#: 쓰기·부수 효과 — (id, 메서드, 경로 접미사, json 본문).
WRITE_ENDPOINTS: list[tuple[str, str, str, dict | None]] = [
    ("health-profile-put", "PUT", "/health-profile", {}),
    (
        "routine-feedback",
        "PUT",
        "/history/hist-unknown/feedback",
        {"feedback": "해제 뒤 피드백"},
    ),
    ("chat-send", "POST", "/chat", {"text": "해제 뒤 메시지"}),
    ("chat-read", "POST", "/chat/read", None),
    ("routine-assign", "POST", "/routines", {"name": "해제 뒤 루틴", "type": "근력"}),
    (
        "routine-suggest",
        "POST",
        "/routine-suggestions",
        {"name": "해제 뒤 제안", "minutes": 20, "type": "유산소"},
    ),
    (
        "program-assign",
        "POST",
        "/program",
        {"name": "해제 뒤 프로그램", "sessions": _PROGRAM_SESSIONS},
    ),
    ("routine-update", "PUT", "/routines/routine-unknown", {"name": "바꾼 이름"}),
    ("routine-delete", "DELETE", "/routines/routine-unknown", None),
    ("memo-create", "POST", "/memos", {"body": "해제 뒤 메모"}),
    ("memo-update", "PUT", "/memos/memo-unknown", {"body": "바꾼 메모"}),
    ("memo-delete", "DELETE", "/memos/memo-unknown", None),
    (
        "follow-up-create",
        "POST",
        "/follow-ups",
        {"title": "해제 뒤 할 일", "due_date": "2099-01-01"},
    ),
    ("routine-options", "POST", "/routine-options", {}),
    ("ai-coach", "POST", "/ai-coach", {"message": "이 회원 식단 어때요?"}),
    ("report-feedback-put", "PUT", "/report/feedback", {"body": "해제 뒤 코멘트"}),
    ("report-goals-put", "PUT", "/report/goals", {"goals": ["해제 뒤 목표"]}),
    ("report-send", "POST", "/report/send", {"message": "해제 뒤 리포트"}),
]


def _call(client, p: Pair, method: str, suffix: str, body, params=None):
    url = f"/v1/trainer/clients/{p.member_id}{suffix}"
    return client.request(method, url, json=body, params=params, headers=p.headers)


@pytest.mark.parametrize(
    ("suffix", "params"),
    [(suffix, params) for _, suffix, params in READ_ENDPOINTS],
    ids=[name for name, _, _ in READ_ENDPOINTS],
)
def test_reads_open_while_linked(client, pair, suffix, params):
    """대조군 — 담당 중이면 같은 요청이 열린다. 404 가 요청 모양 탓이 아님을 보인다."""
    r = _call(client, pair, "GET", suffix, None, params)
    assert r.status_code == 200, r.text


@pytest.mark.parametrize(
    ("suffix", "params"),
    [(suffix, params) for _, suffix, params in READ_ENDPOINTS],
    ids=[name for name, _, _ in READ_ENDPOINTS],
)
def test_reads_are_blocked_after_detach(client, pair, suffix, params):
    _detach(client, pair)
    _assert_guard(_call(client, pair, "GET", suffix, None, params))


@pytest.mark.parametrize(
    ("method", "suffix", "body"),
    [(m, s, b) for _, m, s, b in WRITE_ENDPOINTS],
    ids=[name for name, *_ in WRITE_ENDPOINTS],
)
def test_writes_are_blocked_after_detach(client, pair, method, suffix, body):
    _detach(client, pair)
    _assert_guard(_call(client, pair, method, suffix, body))


def test_diet_photo_is_blocked_before_the_photo_lookup(client, pair):
    """사진 id 를 알아도 해제 뒤에는 담당 확인에서 먼저 막힌다.

    담당 중일 때 없는 사진은 '사진을 찾을 수 없습니다.' 다 — 해제 뒤 문구가
    담당 쪽으로 바뀌는 것으로 확인이 사진 조회보다 앞선다는 것을 본다.
    """
    url = f"/v1/trainer/clients/{pair.member_id}/diet/photos/photo-unknown"
    linked = client.get(url, headers=pair.headers)
    assert linked.status_code == 404
    assert linked.json()["detail"] != GUARD_DETAIL

    _detach(client, pair)
    _assert_guard(client.get(url, headers=pair.headers))


def test_multipart_sends_are_blocked_after_detach(client, db_session, pair):
    """사진·PDF 전송도 파일을 저장하기 전에 막힌다."""
    _detach(client, pair)
    base = f"/v1/trainer/clients/{pair.member_id}"
    image = client.post(
        f"{base}/chat/image",
        files={"image": ("pose.png", b"\x89PNG\r\n\x1a\n" + b"0" * 32, "image/png")},
        data={"message": "자세 사진"},
        headers=pair.headers,
    )
    _assert_guard(image)
    pdf = client.post(
        f"{base}/report/send-pdf",
        files={"pdf": ("report.pdf", b"%PDF-1.4\n%%EOF", "application/pdf")},
        data={"week_start": _this_monday()},
        headers=pair.headers,
    )
    _assert_guard(pdf)
    assert _count(db_session, ChatMessage, member_id=pair.member_id) == 0


def test_blocked_writes_leave_no_rows_and_no_notifications(client, db_session, pair):
    """막힌 쓰기는 회원에게 아무것도 남기지 않는다 — 알림을 포함해서."""
    _detach(client, pair)
    before_notifications = _count(db_session, Notification, user_id=pair.member_id)

    for _, method, suffix, body in WRITE_ENDPOINTS:
        _assert_guard(_call(client, pair, method, suffix, body))

    who = {"trainer_id": pair.trainer_id, "member_id": pair.member_id}
    assert _count(db_session, ChatMessage, **who) == 0
    assert _count(db_session, TrainerRoutine, **who) == 0
    assert _count(db_session, TrainerClientMemo, **who) == 0
    assert _count(db_session, TrainerFollowUpTask, **who) == 0
    assert _count(db_session, TrainerReportFeedback, **who) == 0
    assert (
        _count(db_session, Notification, user_id=pair.member_id)
        == before_notifications
    )


# ---------------------------------------------------------------------------
# 일정 — 회원을 붙이는 경로
# ---------------------------------------------------------------------------


def test_schedule_create_for_detached_member_is_blocked_without_notice(
    client, db_session, pair
):
    """이슈의 핵심 증상 — 해제된 회원에게 일정을 잡으면 새 일정 알림이 나갔다."""
    _detach(client, pair)
    before = _count(db_session, Notification, user_id=pair.member_id)

    r = client.post(
        "/v1/trainer/schedule",
        json={
            "date": _future_day(),
            "time": "09:00",
            "member_id": pair.member_id,
            "client_name": "해제 확인 회원",
            "type": "1:1 PT",
        },
        headers=pair.headers,
    )
    _assert_guard(r)
    assert _count(db_session, TrainerSchedule, trainer_id=pair.trainer_id) == 0
    assert _count(db_session, Notification, user_id=pair.member_id) == before


@pytest.mark.parametrize("path", ["recurring/preview", "recurring"])
def test_recurring_schedule_for_detached_member_is_blocked(
    client, db_session, pair, path
):
    _detach(client, pair)
    r = client.post(
        f"/v1/trainer/schedule/{path}",
        json={
            "date": _future_day(),
            "time": "09:00",
            "member_id": pair.member_id,
            "weekdays": [1, 3],
            "count": 4,
        },
        headers=pair.headers,
    )
    _assert_guard(r)
    assert _count(db_session, TrainerSchedule, trainer_id=pair.trainer_id) == 0


def test_program_schedule_for_detached_member_is_blocked(client, db_session, pair):
    """프로그램 탭 `일정 추가`는 배정과 일정을 함께 만든다 — 둘 다 생기지 않는다."""
    _detach(client, pair)
    r = client.post(
        f"/v1/trainer/clients/{pair.member_id}/program-schedule",
        json={
            "name": "해제 뒤 일정 추가",
            "sessions": _PROGRAM_SESSIONS,
            "date": _future_day(),
            "time": "10:00",
            "duration_minutes": 50,
        },
        headers=pair.headers,
    )
    _assert_guard(r)
    who = {"trainer_id": pair.trainer_id, "member_id": pair.member_id}
    assert _count(db_session, TrainerSchedule, **who) == 0
    assert _count(db_session, TrainerRoutine, **who) == 0


def test_schedule_filter_by_detached_member_is_blocked(client, pair):
    _detach(client, pair)
    r = client.get(
        "/v1/trainer/schedule",
        params={"member_id": pair.member_id},
        headers=pair.headers,
    )
    _assert_guard(r)


def test_moving_a_session_to_a_detached_member_is_blocked(client, db_session, pair):
    """회원이 없는 일정을 해제된 회원에게 옮기는 것도 담당 확인을 지난다."""
    created = client.post(
        "/v1/trainer/schedule",
        json={"date": _future_day(), "time": "11:00", "type": "상담"},
        headers=pair.headers,
    )
    assert created.status_code == 201, created.text
    session_id = created.json()["id"]
    _detach(client, pair)

    r = client.put(
        f"/v1/trainer/schedule/{session_id}",
        json={"member_id": pair.member_id},
        headers=pair.headers,
    )
    _assert_guard(r)
    db_session.expire_all()
    assert db_session.get(TrainerSchedule, session_id).member_id is None


def test_completed_session_program_is_not_sent_after_detach(
    client, db_session, pair
):
    """해제 전에 잡고 마친 PT 라도 해제 뒤에는 회원에게 루틴을 보내지 않는다."""
    created = client.post(
        "/v1/trainer/schedule",
        json={
            "date": clock.today_iso(),
            "time": "06:10",
            "member_id": pair.member_id,
            "client_name": "해제 확인 회원",
            "type": "1:1 PT",
            "program": [{"name": "스쿼트", "sets": 3, "reps": "10회"}],
        },
        headers=pair.headers,
    )
    assert created.status_code == 201, created.text
    session_id = created.json()["id"]
    done = client.post(
        f"/v1/trainer/schedule/{session_id}/complete",
        json={"note": "완료"},
        headers=pair.headers,
    )
    assert done.status_code == 200, done.text
    _detach(client, pair)

    r = client.post(
        f"/v1/trainer/schedule/{session_id}/program/send",
        json={},
        headers=pair.headers,
    )
    _assert_guard(r)
    db_session.expire_all()
    assert db_session.get(TrainerSchedule, session_id).program_sent_at is None
    assert (
        _count(
            db_session,
            TrainerRoutine,
            trainer_id=pair.trainer_id,
            member_id=pair.member_id,
        )
        == 0
    )


def test_completed_session_program_is_sent_while_linked(client, db_session, pair):
    """대조군 — 담당 중이면 같은 전송이 된다."""
    created = client.post(
        "/v1/trainer/schedule",
        json={
            "date": clock.today_iso(),
            "time": "06:20",
            "member_id": pair.member_id,
            "client_name": "해제 확인 회원",
            "type": "1:1 PT",
            "program": [{"name": "런지", "sets": 3, "reps": "12회"}],
        },
        headers=pair.headers,
    )
    assert created.status_code == 201, created.text
    session_id = created.json()["id"]
    assert (
        client.post(
            f"/v1/trainer/schedule/{session_id}/complete",
            json={"note": "완료"},
            headers=pair.headers,
        ).status_code
        == 200
    )
    r = client.post(
        f"/v1/trainer/schedule/{session_id}/program/send",
        json={},
        headers=pair.headers,
    )
    assert r.status_code == 200, r.text


# ---------------------------------------------------------------------------
# 제안 승인 — 회원 id 가 경로에 없는 쓰기
# ---------------------------------------------------------------------------


def test_pending_suggestion_cannot_be_approved_after_detach(
    client, db_session, pair
):
    """해제 전에 만든 운동 제안을 해제 뒤 승인하면 배정·알림이 나가지 않는다."""
    made = _call(
        client,
        pair,
        "POST",
        "/routine-suggestions",
        {"name": "해제 전 제안", "minutes": 20, "type": "유산소"},
    )
    assert made.status_code == 201, made.text
    suggestion_id = made.json()["id"]
    _detach(client, pair)
    before = _count(db_session, Notification, user_id=pair.member_id)

    r = client.post(
        f"/v1/trainer/routine-suggestions/{suggestion_id}/approve",
        json={},
        headers=pair.headers,
    )
    _assert_guard(r)
    db_session.expire_all()
    row = db_session.get(TrainerRoutine, suggestion_id)
    assert row.status != "approved"
    assert row.reviewed_at is None
    assert _count(db_session, Notification, user_id=pair.member_id) == before


def test_pending_suggestion_can_still_be_dismissed_after_detach(client, pair):
    """치우는 것은 회원에게 아무것도 보내지 않으므로 해제 뒤에도 된다."""
    made = _call(
        client,
        pair,
        "POST",
        "/routine-suggestions",
        {"name": "치울 제안", "minutes": 15, "type": "스트레칭"},
    )
    assert made.status_code == 201, made.text
    _detach(client, pair)
    r = client.post(
        f"/v1/trainer/routine-suggestions/{made.json()['id']}/dismiss",
        headers=pair.headers,
    )
    assert r.status_code == 200, r.text


def test_pending_suggestion_is_approved_while_linked(client, pair):
    """대조군 — 담당 중이면 승인된다."""
    made = _call(
        client,
        pair,
        "POST",
        "/routine-suggestions",
        {"name": "승인할 제안", "minutes": 25, "type": "유산소"},
    )
    assert made.status_code == 201, made.text
    r = client.post(
        f"/v1/trainer/routine-suggestions/{made.json()['id']}/approve",
        json={},
        headers=pair.headers,
    )
    assert r.status_code == 200, r.text


# ---------------------------------------------------------------------------
# 해제된 링크를 다뤄야 하는 곳 — 예전 동작 그대로
# ---------------------------------------------------------------------------


def test_detached_member_stays_on_roster_as_unregistered(client, pair):
    _detach(client, pair)
    roster = client.get("/v1/trainer/clients", headers=pair.headers)
    assert roster.status_code == 200, roster.text
    row = next(r for r in roster.json() if r["id"] == pair.member_id)
    assert row["registered"] is False
    assert row["active"] is False


def test_detach_twice_is_404_and_status_change_is_409(client, pair):
    _detach(client, pair)
    again = client.delete(
        f"/v1/trainer/clients/{pair.member_id}", headers=pair.headers
    )
    _assert_guard(again)
    status = client.put(
        f"/v1/trainer/clients/{pair.member_id}/status",
        json={"active": True},
        headers=pair.headers,
    )
    assert status.status_code == 409, status.text


def test_restoring_registration_reopens_access(client, db_session):
    """재등록은 해제된 링크를 직접 읽는다 — 막히면 되돌릴 길이 없다.

    철회 기록이 없는 옛 해제 링크가 대상이다. 지금의 해제는 동의를 철회하므로
    그 링크는 재등록이 409 다(#1631, 아래 테스트).
    """
    legacy = _make_pair(db_session, active=False)
    try:
        diet = f"/v1/trainer/clients/{legacy.member_id}/diet"
        _assert_guard(client.get(diet, headers=legacy.headers))

        restored = client.put(
            f"/v1/trainer/clients/{legacy.member_id}/registration",
            headers=legacy.headers,
        )
        assert restored.status_code == 204, restored.text
        assert client.get(diet, headers=legacy.headers).status_code == 200
    finally:
        _cleanup(db_session, [legacy.trainer_id, legacy.member_id])


def test_restoring_after_detach_needs_the_members_new_consent(client, pair):
    """해제는 동의 철회라, 트레이너 혼자 재등록해 기록을 다시 열 수 없다. (#1631)"""
    diet = f"/v1/trainer/clients/{pair.member_id}/diet"
    _detach(client, pair)

    restored = client.put(
        f"/v1/trainer/clients/{pair.member_id}/registration", headers=pair.headers
    )
    assert restored.status_code == 409, restored.text
    _assert_guard(client.get(diet, headers=pair.headers))


def test_my_follow_up_stays_mine_after_detach(client, db_session, pair):
    """해제 전에 남긴 할 일은 해제 뒤에도 내 목록에서 고치고 끝낼 수 있다.

    등록은 담당을 요구하지만 등록 뒤 조회·수정·완료는 `trainer_id` 만 본다 —
    여기서 담당을 다시 요구하면 지울 수도 없는 항목이 목록에 남는다.
    """
    created = _call(
        client,
        pair,
        "POST",
        "/follow-ups",
        {"title": "해제 전 할 일", "due_date": clock.today_iso()},
    )
    assert created.status_code == 201, created.text
    task_id = created.json()["id"]
    _detach(client, pair)

    listed = client.get(
        "/v1/trainer/follow-ups", params={"scope": "open"}, headers=pair.headers
    )
    assert listed.status_code == 200
    assert task_id in [t["id"] for t in listed.json()]
    updated = client.put(
        f"/v1/trainer/follow-ups/{task_id}",
        json={"title": "해제 뒤 고친 할 일"},
        headers=pair.headers,
    )
    assert updated.status_code == 200, updated.text
    done = client.post(
        f"/v1/trainer/follow-ups/{task_id}/complete", headers=pair.headers
    )
    assert done.status_code == 200, done.text


def test_detach_preserves_the_members_records(client, db_session, pair):
    """막는 것은 트레이너의 접근이지 기록이 아니다 — 해제 전 대화는 그대로 남는다."""
    sent = _call(client, pair, "POST", "/chat", {"text": "해제 전 메시지"})
    assert sent.status_code == 201, sent.text
    _detach(client, pair)
    who = {"trainer_id": pair.trainer_id, "member_id": pair.member_id}
    assert _count(db_session, ChatMessage, **who) == 1


# ---------------------------------------------------------------------------
# 휴면·다른 트레이너 — 경계가 넓거나 좁지 않은가
# ---------------------------------------------------------------------------


def test_dormant_member_is_still_open(client, pair):
    """휴면(`dormant`)은 트레이너의 관리 표시일 뿐 담당 해제가 아니다. (#707)"""
    status = client.put(
        f"/v1/trainer/clients/{pair.member_id}/status",
        json={"active": False},
        headers=pair.headers,
    )
    assert status.status_code == 200, status.text
    assert status.json()["active"] is False

    for _, suffix, params in READ_ENDPOINTS:
        r = _call(client, pair, "GET", suffix, None, params)
        assert r.status_code == 200, (suffix, r.text)
    sent = _call(client, pair, "POST", "/chat", {"text": "휴면이어도 보낸다"})
    assert sent.status_code == 201, sent.text


def test_former_trainer_is_blocked_while_new_trainer_is_open(client, db_session):
    """회원이 다른 트레이너에게 옮겨 가면 예전 트레이너만 막히고 새 트레이너는 열린다."""
    former = _make_pair(db_session)
    suffix = uuid4().hex[:10]
    new_trainer_id = f"inactive-new-trainer-{suffix}"
    try:
        _detach(client, former)
        db_session.add(
            User(
                id=new_trainer_id,
                email=f"{new_trainer_id}@oncare.com",
                name="새 담당 트레이너",
                hashed_password="unused",
                role="trainer",
            )
        )
        db_session.flush()
        db_session.add(
            TrainerClient(
                id=f"tc-{uuid4().hex[:12]}",
                trainer_id=new_trainer_id,
                member_id=former.member_id,
                active=True,
            )
        )
        db_session.commit()

        diet = f"/v1/trainer/clients/{former.member_id}/diet"
        _assert_guard(client.get(diet, headers=former.headers))
        opened = client.get(diet, headers=_h(create_access_token(new_trainer_id)))
        assert opened.status_code == 200, opened.text
    finally:
        _cleanup(db_session, [former.trainer_id, former.member_id, new_trainer_id])


def test_detached_and_never_linked_answer_the_same(client, db_session, pair):
    """해제된 회원과 담당한 적 없는 회원은 응답으로 구별되지 않는다."""
    stranger = _make_pair(db_session)
    try:
        _detach(client, pair)
        detached = client.get(
            f"/v1/trainer/clients/{pair.member_id}/memos", headers=pair.headers
        )
        never = client.get(
            f"/v1/trainer/clients/{stranger.member_id}/memos", headers=pair.headers
        )
        assert (detached.status_code, detached.json()) == (
            never.status_code,
            never.json(),
        )
    finally:
        _cleanup(db_session, [stranger.trainer_id, stranger.member_id])


def test_link_seeded_inactive_is_blocked(client, db_session):
    """해제 API 를 거치지 않고 처음부터 `active=False` 인 링크도 같다(시드·이관 데이터)."""
    p = _make_pair(db_session, active=False)
    try:
        _assert_guard(
            client.get(f"/v1/trainer/clients/{p.member_id}/diet", headers=p.headers)
        )
        _assert_guard(
            client.post(
                f"/v1/trainer/clients/{p.member_id}/chat",
                json={"text": "막혀야 한다"},
                headers=p.headers,
            )
        )
    finally:
        _cleanup(db_session, [p.trainer_id, p.member_id])


# ---------------------------------------------------------------------------
# 서비스 경계
# ---------------------------------------------------------------------------


def test_has_active_client_link(db_session, pair):
    from app.services import trainer_service

    assert trainer_service.has_active_client_link(
        db_session, pair.trainer_id, pair.member_id
    )
    link = db_session.get(TrainerClient, pair.link_id)
    link.active = False
    db_session.commit()
    assert not trainer_service.has_active_client_link(
        db_session, pair.trainer_id, pair.member_id
    )
    assert not trainer_service.has_active_client_link(
        db_session, pair.trainer_id, "nobody"
    )
    assert not trainer_service.has_active_client_link(
        db_session, "nobody", pair.member_id
    )


def test_routine_option_analysis_ignores_a_detached_link(db_session, pair):
    """루틴 후보 분석도 해제된 링크로는 회원 데이터를 모으지 않는다."""
    from app.schemas.trainer_api import RoutineOptionsRequest
    from app.services import trainer_routine_options_service as svc

    link = db_session.get(TrainerClient, pair.link_id)
    link.active = False
    db_session.commit()
    with pytest.raises(ValueError, match=GUARD_DETAIL):
        svc.build_member_analysis(
            db_session, pair.trainer_id, pair.member_id, RoutineOptionsRequest()
        )


# ---------------------------------------------------------------------------
# 일정 id 로 여는 경로 — 해제 전에 잡아 둔 일정 (#1631)
# ---------------------------------------------------------------------------


def _member_detaches(client, p: Pair) -> None:
    """회원이 앱에서 담당을 끊는다 — 동의 철회까지 함께 일어나는 경로."""
    r = client.delete(
        "/v1/me/coach/trainer",
        headers=_h(create_access_token(p.member_id)),
    )
    assert r.status_code == 204, r.text


def _session_with_personal_routine(client, p: Pair, *, time: str) -> str:
    """오늘 PT 를 잡고 개인운동을 붙인 뒤 일정 id 를 준다."""
    r = client.post(
        f"/v1/trainer/clients/{p.member_id}/program-schedule",
        json={
            "name": "해제 확인 PT",
            "sessions": _PROGRAM_SESSIONS,
            "date": clock.today_iso(),
            "time": time,
            "duration_minutes": 30,
            "personal_routines": [
                {"name": "해제 확인 걷기", "minutes": 30, "type": "유산소"},
            ],
        },
        headers=p.headers,
    )
    assert r.status_code == 201, r.text
    return r.json()["session"]["id"]


def _plain_session(client, p: Pair, *, day: str, time: str) -> str:
    r = client.post(
        "/v1/trainer/schedule",
        json={
            "date": day,
            "time": time,
            "member_id": p.member_id,
            "client_name": "해제 확인 회원",
            "type": "1:1 PT",
            "duration_minutes": 50,
            "program": [{"name": "스쿼트", "sets": 3, "reps": "10회"}],
        },
        headers=p.headers,
    )
    assert r.status_code == 201, r.text
    return r.json()["id"]


def test_personal_routines_are_not_sent_after_the_member_detaches(
    client, db_session, pair
):
    """취소한 PT 의 개인운동을 해제 뒤에 보내면 회원에게 운동과 알림이 갔다."""
    session_id = _session_with_personal_routine(client, pair, time="06:20")
    cancelled = client.post(
        f"/v1/trainer/schedule/{session_id}/cancel",
        json={"source": "member", "reason": "몸살"},
        headers=pair.headers,
    )
    assert cancelled.status_code == 200, cancelled.text
    _member_detaches(client, pair)
    before = _count(db_session, Notification, user_id=pair.member_id)

    r = client.post(
        f"/v1/trainer/schedule/{session_id}/routines/send",
        json={},
        headers=pair.headers,
    )
    _assert_guard(r)
    db_session.expire_all()
    statuses = db_session.scalars(
        select(TrainerRoutine.status).where(
            TrainerRoutine.schedule_id == session_id,
            TrainerRoutine.delivery_kind.is_not(None),
        )
    ).all()
    assert statuses == ["scheduled"]
    assert _count(db_session, Notification, user_id=pair.member_id) == before


def test_personal_routines_are_sent_while_linked(client, db_session, pair):
    """같은 흐름이라도 담당 중이면 그대로 간다 — 막은 것은 해제 뒤뿐이다."""
    session_id = _session_with_personal_routine(client, pair, time="06:40")
    assert client.post(
        f"/v1/trainer/schedule/{session_id}/cancel",
        json={"source": "member", "reason": "몸살"},
        headers=pair.headers,
    ).status_code == 200

    r = client.post(
        f"/v1/trainer/schedule/{session_id}/routines/send",
        json={},
        headers=pair.headers,
    )
    assert r.status_code == 200, r.text
    db_session.expire_all()
    assert db_session.scalars(
        select(TrainerRoutine.status).where(
            TrainerRoutine.schedule_id == session_id,
            TrainerRoutine.delivery_kind.is_not(None),
        )
    ).all() == ["approved"]


def test_completing_a_session_after_detach_writes_nothing_for_the_member(
    client, db_session, pair
):
    """해제 전에 잡은 오늘 PT 를 해제 뒤 완료하면 회원 운동 기록이 생겼다."""
    # 이미 시작한 시각이어야 한다 — 아직 시작 전이면 해제가 취소해 버린다(#2589).
    session_id = _plain_session(client, pair, day=clock.today_iso(), time="00:00")
    _member_detaches(client, pair)

    r = client.post(
        f"/v1/trainer/schedule/{session_id}/complete",
        json={"note": "해제 뒤 완료"},
        headers=pair.headers,
    )
    _assert_guard(r)
    db_session.expire_all()
    assert db_session.get(TrainerSchedule, session_id).status == "예정"
    assert _count(db_session, ExerciseSession, user_id=pair.member_id) == 0
    assert _count(db_session, RoutineHistory, member_id=pair.member_id) == 0


def test_rescheduling_a_session_after_detach_sends_no_notice(
    client, db_session, pair
):
    """해제 뒤 시간을 옮기면 회원에게 일정 변경 알림이 갔다."""
    session_id = _plain_session(client, pair, day=_future_day(), time="07:30")
    _member_detaches(client, pair)
    before = _count(db_session, Notification, user_id=pair.member_id)

    r = client.put(
        f"/v1/trainer/schedule/{session_id}",
        json={"time": "08:30"},
        headers=pair.headers,
    )
    _assert_guard(r)
    db_session.expire_all()
    assert db_session.get(TrainerSchedule, session_id).time == "07:30"
    assert _count(db_session, Notification, user_id=pair.member_id) == before


def test_reopening_a_completed_session_after_detach_keeps_the_member_record(
    client, db_session, pair
):
    """되돌리기는 회원 운동 기록을 지운다 — 해제 뒤에는 회원 기록에 손대지 않는다."""
    session_id = _plain_session(client, pair, day=clock.today_iso(), time="07:50")
    done = client.post(
        f"/v1/trainer/schedule/{session_id}/complete",
        json={"note": "완료"},
        headers=pair.headers,
    )
    assert done.status_code == 200, done.text
    records = _count(db_session, ExerciseSession, user_id=pair.member_id)
    assert records == 1
    _member_detaches(client, pair)

    r = client.post(
        f"/v1/trainer/schedule/{session_id}/reopen",
        json={"date": _future_day()},
        headers=pair.headers,
    )
    _assert_guard(r)
    assert _count(db_session, ExerciseSession, user_id=pair.member_id) == records


def test_cancelling_a_session_after_detach_still_works(client, db_session, pair):
    """취소는 막지 않는다 — 잡혀 있던 약속이 없어졌다는 통보는 해제 뒤에도 필요하다.

    시작 전 일정은 해제가 이미 취소한다(#2589). 그래서 해제 때 남는 **이미 시작한**
    예정 일정으로 본다.
    """
    session_id = _plain_session(client, pair, day=clock.today_iso(), time="00:00")
    _member_detaches(client, pair)

    r = client.post(
        f"/v1/trainer/schedule/{session_id}/cancel",
        json={"source": "trainer", "reason": "담당 종료"},
        headers=pair.headers,
    )
    assert r.status_code == 200, r.text


# ---------------------------------------------------------------------------
# 동의 없이 살아 있는 링크 — `_require_client` 밖의 경로도 같이 닫힌다 (#1631)
# ---------------------------------------------------------------------------


def _revoke_but_keep_active(db_session, p: Pair) -> None:
    """철회된 뒤 새 동의 없이 되살아난 링크(예: 동의 시각이 없던 옛 상담의 수락)."""
    link = db_session.get(TrainerClient, p.link_id)
    link.data_consent_at = None
    link.data_consent_revoked_at = clock.now()
    link.active = True
    db_session.commit()


def test_has_active_client_link_needs_consent(db_session, pair):
    from app.services import trainer_service

    _revoke_but_keep_active(db_session, pair)
    assert not trainer_service.has_active_client_link(
        db_session, pair.trainer_id, pair.member_id
    )


def test_program_schedule_is_blocked_without_consent(client, db_session, pair):
    _revoke_but_keep_active(db_session, pair)
    r = client.post(
        f"/v1/trainer/clients/{pair.member_id}/program-schedule",
        json={
            "name": "동의 없는 일정 추가",
            "sessions": _PROGRAM_SESSIONS,
            "date": _future_day(),
            "time": "10:00",
            "duration_minutes": 50,
        },
        headers=pair.headers,
    )
    _assert_guard(r)
    who = {"trainer_id": pair.trainer_id, "member_id": pair.member_id}
    assert _count(db_session, TrainerSchedule, **who) == 0
    assert _count(db_session, TrainerRoutine, **who) == 0


def test_session_paths_are_blocked_without_consent(client, db_session, pair):
    """링크가 살아 있어도 동의가 없으면 일정 id 경로가 회원에게 쓰지 않는다."""
    session_id = _plain_session(client, pair, day=clock.today_iso(), time="08:40")
    _revoke_but_keep_active(db_session, pair)

    _assert_guard(
        client.post(
            f"/v1/trainer/schedule/{session_id}/complete",
            json={"note": "동의 없음"},
            headers=pair.headers,
        )
    )
    assert _count(db_session, ExerciseSession, user_id=pair.member_id) == 0
