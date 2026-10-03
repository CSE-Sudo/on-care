"""PT 완료·주간 피드백 알림과 알림별 목적지. (#3026, #3027, #3028)

세 갈래를 한 파일에서 지키는 까닭은 모두 **트레이너와 회원 사이에 오가던 일이
알림 없이 저장만 되던 곳**이기 때문이다.

  * #3026 — 회원이 주간 피드백(컨디션·강도·통증)을 내도 트레이너는 리포트 화면을
    직접 열어야 알았다. 이제 담당 트레이너 알림함에 한 건이 오고, 같은 주를 고쳐
    내면 읽기 전에는 그 한 건이 최신 답으로 바뀐다.
  * #3027 — 트레이너가 PT 를 완료 처리하거나 끝난 PT 에 피드백을 적어도 회원은 운동
    탭을 열어야 알았다. 이제 회원 알림함에 한 건이 오고 운동 탭 PT 기록으로 간다.
  * #3028 — PT 일정 알림에 이동 버튼이 없었다. 이제 운동 탭으로 가고, 알림마다
    목적지를 `queue(action_target=...)` 로 따로 줄 수 있다.

DB 가 필요하므로 로컬에서는 skip 되고 CI(Postgres) 에서 실행된다.
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
from app.services import notification_service
from app.services import notification_templates as nt


def _h(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


@dataclass(frozen=True)
class Pair:
    trainer_id: str
    member_id: str
    headers: dict[str, str]
    member_headers: dict[str, str]


def _make_pair(db_session, *, trainer_name: str = "박코치", member_name: str = "지수") -> Pair:
    suffix = uuid4().hex[:10]
    trainer_id = f"ptfb-trainer-{suffix}"
    member_id = f"ptfb-member-{suffix}"
    db_session.add_all(
        [
            User(
                id=trainer_id,
                email=f"{trainer_id}@oncare.com",
                name=trainer_name,
                hashed_password="unused",
                role="trainer",
                is_active=True,
            ),
            User(
                id=member_id,
                email=f"{member_id}@oncare.com",
                name=member_name,
                hashed_password="unused",
                role="member",
                is_active=True,
            ),
        ]
    )
    db_session.flush()
    db_session.add(
        TrainerClient(
            id=f"tc-{uuid4().hex[:12]}",
            trainer_id=trainer_id,
            member_id=member_id,
            active=True,
            data_consent_at=clock.now(),
        )
    )
    db_session.commit()
    return Pair(
        trainer_id=trainer_id,
        member_id=member_id,
        headers=_h(create_access_token(trainer_id)),
        member_headers=_h(create_access_token(member_id)),
    )


@pytest.fixture()
def made(db_session) -> Iterator[list[Pair]]:
    """테스트가 만든 쌍들. 끝나면 사용자째 지운다(알림·일정은 CASCADE)."""
    pairs: list[Pair] = []
    try:
        yield pairs
    finally:
        db_session.rollback()
        db_session.expire_all()
        ids = [p.trainer_id for p in pairs] + [p.member_id for p in pairs]
        if ids:
            db_session.execute(
                text("DELETE FROM users WHERE id = ANY(:ids)"), {"ids": ids}
            )
            db_session.commit()


@pytest.fixture()
def pair(db_session, made) -> Pair:
    p = _make_pair(db_session)
    made.append(p)
    return p


# --------------------------------------------------------------------------
# 도우미
# --------------------------------------------------------------------------


def _member_inbox(client, p: Pair, locale: str | None = None) -> list[dict]:
    headers = dict(p.member_headers)
    if locale:
        headers["Accept-Language"] = locale
    res = client.get("/v1/notifications", params={"limit": 100}, headers=headers)
    assert res.status_code == 200, res.text
    return res.json()


def _trainer_inbox(client, p: Pair, locale: str | None = None) -> list[dict]:
    headers = dict(p.headers)
    if locale:
        headers["Accept-Language"] = locale
    res = client.get("/v1/trainer/notifications", headers=headers)
    assert res.status_code == 200, res.text
    return res.json()


def _of(rows: list[dict], category: str) -> list[dict]:
    return [r for r in rows if r["category"] == category]


def _past_session(
    db_session,
    p: Pair,
    *,
    days_ago: int = 1,
    time: str = "10:00",
    type_: str = "1:1 PT",
    note: str = "",
    status: str = "예정",
    with_member: bool = True,
) -> str:
    """이미 시작한 일정을 바로 넣는다 — 완료는 시작 뒤에만 된다(#2760)."""
    session_id = f"sched-{uuid4().hex[:12]}"
    db_session.add(
        TrainerSchedule(
            id=session_id,
            trainer_id=p.trainer_id,
            member_id=p.member_id if with_member else None,
            client_name="지수" if with_member else "신규 고객",
            date=(clock.today() - timedelta(days=days_ago)).isoformat(),
            time=time,
            type=type_,
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


def _complete(client, p: Pair, session_id: str, note: str = "") -> dict:
    res = client.post(
        f"/v1/trainer/schedule/{session_id}/complete",
        headers=p.headers,
        json={"note": note},
    )
    assert res.status_code == 200, res.text
    return res.json()


def _send_feedback(client, p: Pair, **overrides) -> dict:
    payload = {
        "week_start": "2026-09-21",
        "condition": "good",
        "intensity": "right",
    }
    payload.update(overrides)
    res = client.put(
        "/v1/me/coach/weekly-feedback", headers=p.member_headers, json=payload
    )
    assert res.status_code == 200, res.text
    return res.json()


def _turn_off_exercise(client, p: Pair) -> None:
    res = client.put(
        "/v1/users/me/notification-settings",
        headers=p.member_headers,
        json={"exercise_reminder": False},
    )
    assert res.status_code == 200, res.text


# ==========================================================================
# #3027 — PT 완료·피드백 알림
# ==========================================================================


def test_completing_a_pt_tells_the_member_once(client, db_session, pair):
    sid = _past_session(db_session, pair)

    _complete(client, pair, sid, note="스쿼트 무릎 방향 좋아졌어요")

    rows = _of(_member_inbox(client, pair), notification_service.MEMBER_PT_DONE)
    assert len(rows) == 1
    row = rows[0]
    assert row["title"] == "박코치 트레이너와 1회차 PT를 마쳤어요"
    assert row["body"] == "스쿼트 무릎 방향 좋아졌어요"
    assert row["action"] == {"label": "PT 기록 보기", "target": "exercise"}
    assert row["read"] is False


def test_completing_again_adds_nothing(client, db_session, pair):
    """완료는 멱등이다 — 다시 눌러도 기록도 알림도 한 번뿐이다."""
    sid = _past_session(db_session, pair)

    _complete(client, pair, sid, note="좋아요")
    _complete(client, pair, sid, note="좋아요")

    assert len(_of(_member_inbox(client, pair), "pt_done")) == 1


def test_completion_without_a_note_says_it_was_logged(client, db_session, pair):
    sid = _past_session(db_session, pair)

    _complete(client, pair, sid)

    row = _of(_member_inbox(client, pair), "pt_done")[0]
    assert row["body"] == "운동 기록에 남겼어요"


def test_completion_uses_the_note_written_before_the_class(client, db_session, pair):
    """완료 요청에 메모가 없으면 미리 적어 둔 메모가 회원에게 보이는 피드백이다."""
    sid = _past_session(db_session, pair, note="다음 시간엔 무게를 올려요")

    _complete(client, pair, sid)

    row = _of(_member_inbox(client, pair), "pt_done")[0]
    assert row["body"] == "다음 시간엔 무게를 올려요"


def test_session_numbers_count_finished_pts(client, db_session, pair):
    """회차는 회원 앱 PT 카드와 같은 번호다(`_done_pt_numbers`)."""
    first = _past_session(db_session, pair, days_ago=3)
    second = _past_session(db_session, pair, days_ago=1)

    _complete(client, pair, first)
    _complete(client, pair, second)

    titles = [r["title"] for r in _of(_member_inbox(client, pair), "pt_done")]
    assert "박코치 트레이너와 1회차 PT를 마쳤어요" in titles
    assert "박코치 트레이너와 2회차 PT를 마쳤어요" in titles


def test_consultation_completion_tells_nobody(client, db_session, pair):
    """상담은 수업이 아니다 — 상담 기록은 트레이너만 본다(#2515)."""
    sid = _past_session(db_session, pair, type_="상담", note="상담 기록")

    _complete(client, pair, sid, note="상담 기록")

    assert _of(_member_inbox(client, pair), "pt_done") == []


def test_session_without_a_member_tells_nobody(client, db_session, pair):
    sid = _past_session(db_session, pair, with_member=False)

    _complete(client, pair, sid)

    count = db_session.scalar(
        select(Notification.id).where(
            Notification.category == notification_service.MEMBER_PT_DONE,
            Notification.user_id == pair.member_id,
        )
    )
    assert count is None


def test_exercise_switch_off_silences_pt_completion(client, db_session, pair):
    """PT 기록 알림은 회원 운동 기록에 관한 알림이라 운동 스위치를 따른다."""
    _turn_off_exercise(client, pair)
    sid = _past_session(db_session, pair)

    _complete(client, pair, sid, note="수고하셨어요")

    assert _of(_member_inbox(client, pair), "pt_done") == []


def test_exercise_switch_off_still_completes_the_pt(client, db_session, pair):
    """알림을 끈 회원이어도 완료·기록 적재는 그대로다."""
    _turn_off_exercise(client, pair)
    sid = _past_session(db_session, pair)

    out = _complete(client, pair, sid, note="수고하셨어요")

    assert out["status"] == "완료"


def test_first_feedback_on_a_finished_pt_tells_the_member(client, db_session, pair):
    """수업이 끝난 뒤 피드백을 적는 흐름(#2754)도 알린다."""
    sid = _past_session(db_session, pair)
    _complete(client, pair, sid)

    edited = client.put(
        f"/v1/trainer/schedule/{sid}",
        headers=pair.headers,
        json={"note": "허리 각도 신경 써 주세요"},
    )

    assert edited.status_code == 200, edited.text
    rows = _of(_member_inbox(client, pair), "pt_done")
    assert len(rows) == 2
    feedback = next(r for r in rows if r["title"] == "트레이너 피드백이 도착했어요")
    assert feedback["body"] == "허리 각도 신경 써 주세요"
    assert feedback["action"]["target"] == "exercise"


def test_editing_existing_feedback_tells_nobody(client, db_session, pair):
    """이미 있던 피드백을 고칠 때마다 알리면 오타 하나 고친 것도 알림이 된다."""
    sid = _past_session(db_session, pair)
    _complete(client, pair, sid, note="첫 피드백")
    before = len(_of(_member_inbox(client, pair), "pt_done"))

    edited = client.put(
        f"/v1/trainer/schedule/{sid}",
        headers=pair.headers,
        json={"note": "첫 피드백 (오타 수정)"},
    )

    assert edited.status_code == 200, edited.text
    assert len(_of(_member_inbox(client, pair), "pt_done")) == before


def test_note_on_an_upcoming_pt_tells_nobody(client, db_session, pair):
    """예정 PT 의 메모는 트레이너의 준비물이다 — 회원에게 보이지 않는다."""
    created = client.post(
        "/v1/trainer/schedule",
        headers=pair.headers,
        json={
            "date": (clock.today() + timedelta(days=2)).isoformat(),
            "time": "10:00",
            "client_name": "지수",
            "member_id": pair.member_id,
            "type": "1:1 PT",
            "duration_minutes": 50,
            "note": "",
            "program": [],
        },
    )
    assert created.status_code == 201, created.text

    edited = client.put(
        f"/v1/trainer/schedule/{created.json()['id']}",
        headers=pair.headers,
        json={"note": "스쿼트 자세 확인"},
    )

    assert edited.status_code == 200, edited.text
    assert _of(_member_inbox(client, pair), "pt_done") == []


def test_feedback_on_a_finished_consultation_tells_nobody(client, db_session, pair):
    sid = _past_session(db_session, pair, type_="상담", status="완료")

    edited = client.put(
        f"/v1/trainer/schedule/{sid}",
        headers=pair.headers,
        json={"note": "상담 기록"},
    )

    assert edited.status_code == 200, edited.text
    assert _of(_member_inbox(client, pair), "pt_done") == []


def test_pt_alerts_read_in_english(client, db_session, pair):
    sid = _past_session(db_session, pair)
    _complete(client, pair, sid)

    row = _of(_member_inbox(client, pair, "en"), "pt_done")[0]
    assert row["title"] == "You finished PT session 1 with 박코치"
    assert row["body"] == "Saved to your workout log"
    assert row["action"] == {"label": "View PT record", "target": "exercise"}


def test_pt_alert_keeps_the_template_for_the_app(client, db_session, pair):
    sid = _past_session(db_session, pair)
    _complete(client, pair, sid, note="좋아요")

    db_session.expire_all()
    row = db_session.scalar(
        select(Notification).where(
            Notification.user_id == pair.member_id,
            Notification.category == notification_service.MEMBER_PT_DONE,
        )
    )
    assert row.template == nt.MEMBER_PT_COMPLETED
    assert row.template_args["session_number"] == 1
    assert row.template_args["has_note"] is True


# ==========================================================================
# #3026 — 회원 주간 피드백 → 트레이너 알림
# ==========================================================================


def test_weekly_feedback_tells_the_trainer(client, db_session, pair):
    _send_feedback(client, pair)

    rows = _of(_trainer_inbox(client, pair), "weekly_feedback")
    assert len(rows) == 1
    row = rows[0]
    assert row["title"] == "지수 회원이 주간 피드백을 보냈어요"
    assert row["body"] == "컨디션 좋았어요 · 운동 강도 적당했어요"
    assert row["subject_id"] == pair.member_id
    assert row["target_date"] == "2026-09-21"
    assert row["template"] == nt.TRAINER_MEMBER_WEEKLY_FEEDBACK
    assert row["read"] is False


def test_weekly_feedback_mid_week_date_points_at_the_monday(client, db_session, pair):
    _send_feedback(client, pair, week_start="2026-09-24")

    row = _of(_trainer_inbox(client, pair), "weekly_feedback")[0]
    assert row["target_date"] == "2026-09-21"


def test_pain_changes_the_title_but_hides_where(client, db_session, pair):
    """통증은 제목에 드러나되 아픈 곳은 싣지 않는다(#2619 와 같은 규칙)."""
    _send_feedback(
        client, pair, condition="tired", intensity="too_hard",
        pain_area="왼쪽 어깨", pain_on="2026-09-23",
    )

    row = _of(_trainer_inbox(client, pair), "weekly_feedback")[0]
    assert row["title"] == "지수 회원이 통증을 알렸어요"
    assert "어깨" not in row["title"]
    assert "어깨" not in row["body"]
    assert "어깨" not in json.dumps(row["args"], ensure_ascii=False)


def test_resubmitting_before_reading_rewrites_the_same_alert(client, db_session, pair):
    """답을 고칠 때마다 같은 회원 줄이 쌓이면 무엇이 최신인지 읽을 수 없다."""
    _send_feedback(client, pair, condition="good")
    first = _of(_trainer_inbox(client, pair), "weekly_feedback")[0]

    _send_feedback(client, pair, condition="bad", intensity="too_hard")

    rows = _of(_trainer_inbox(client, pair), "weekly_feedback")
    assert len(rows) == 1
    assert rows[0]["id"] == first["id"]
    assert rows[0]["title"] == "지수 회원이 주간 피드백을 보냈어요"
    assert rows[0]["body"] == "컨디션 많이 힘들었어요 · 운동 강도 너무 힘들었어요"


def test_resubmitting_before_reading_moves_the_alert_to_the_top(client, db_session, pair):
    _send_feedback(client, pair)
    db_session.execute(
        text(
            "UPDATE notifications SET created_at = created_at - interval '2 days' "
            "WHERE user_id = :uid"
        ),
        {"uid": pair.trainer_id},
    )
    db_session.commit()
    notification_service.queue_for_trainer(
        db_session,
        trainer_id=pair.trainer_id,
        kind=notification_service.TRAINER_MESSAGE_KIND,
        title="다른 알림",
    )
    db_session.commit()

    _send_feedback(client, pair, condition="ok")

    rows = _trainer_inbox(client, pair)
    assert rows[0]["category"] == "weekly_feedback"


def test_resubmitting_after_reading_adds_a_revised_alert(client, db_session, pair):
    """이미 읽었으면 트레이너가 본 답과 달라졌다는 것을 한 건 더 알린다."""
    _send_feedback(client, pair, condition="good")
    first = _of(_trainer_inbox(client, pair), "weekly_feedback")[0]
    read = client.post(
        f"/v1/trainer/notifications/{first['id']}/read", headers=pair.headers
    )
    assert read.status_code == 200, read.text

    _send_feedback(client, pair, condition="tired")

    rows = _of(_trainer_inbox(client, pair), "weekly_feedback")
    assert len(rows) == 2
    newest = rows[0]
    assert newest["id"] != first["id"]
    assert newest["title"] == "지수 회원이 주간 피드백을 수정했어요"
    assert newest["read"] is False
    assert newest["args"]["revised"] is True


def test_revised_alert_rewritten_before_reading_stays_revised(client, db_session, pair):
    """읽지 않은 '수정' 알림을 다시 고쳐 써도 '수정' 이다 — 처음 답은 이미 읽었다."""
    _send_feedback(client, pair)
    first = _of(_trainer_inbox(client, pair), "weekly_feedback")[0]
    client.post(f"/v1/trainer/notifications/{first['id']}/read", headers=pair.headers)
    _send_feedback(client, pair, condition="tired")

    _send_feedback(client, pair, condition="bad")

    rows = _of(_trainer_inbox(client, pair), "weekly_feedback")
    assert len(rows) == 2
    assert rows[0]["title"] == "지수 회원이 주간 피드백을 수정했어요"
    assert rows[0]["body"].startswith("컨디션 많이 힘들었어요")


def test_another_week_is_its_own_alert(client, db_session, pair):
    _send_feedback(client, pair, week_start="2026-09-14")
    _send_feedback(client, pair, week_start="2026-09-21")

    rows = _of(_trainer_inbox(client, pair), "weekly_feedback")
    assert sorted(r["target_date"] for r in rows) == ["2026-09-14", "2026-09-21"]


def test_rejected_feedback_creates_no_alert(client, db_session, pair):
    res = client.put(
        "/v1/me/coach/weekly-feedback",
        headers=pair.member_headers,
        json={"week_start": "2026-09-21", "condition": "sleepy", "intensity": "right"},
    )

    assert res.status_code == 422
    assert _of(_trainer_inbox(client, pair), "weekly_feedback") == []


def test_only_the_assigned_trainer_hears(client, db_session, pair, made):
    other = _make_pair(db_session, trainer_name="다른코치", member_name="다른회원")
    made.append(other)

    _send_feedback(client, pair)

    assert len(_of(_trainer_inbox(client, pair), "weekly_feedback")) == 1
    assert _of(_trainer_inbox(client, other), "weekly_feedback") == []


def test_member_never_sees_the_trainer_alert(client, db_session, pair):
    _send_feedback(client, pair)

    assert _of(_member_inbox(client, pair), "weekly_feedback") == []


def test_unread_count_includes_the_feedback_alert(client, db_session, pair):
    before = client.get(
        "/v1/trainer/notifications/unread-count", headers=pair.headers
    ).json()
    _send_feedback(client, pair)
    _send_feedback(client, pair, condition="ok")

    after = client.get(
        "/v1/trainer/notifications/unread-count", headers=pair.headers
    ).json()
    assert after["unread"] == before["unread"] + 1


def test_weekly_feedback_reads_in_english(client, db_session, pair):
    _send_feedback(client, pair, condition="great", intensity="too_easy")

    row = _of(_trainer_inbox(client, pair, "en"), "weekly_feedback")[0]
    assert row["title"] == "지수 sent their weekly feedback"
    assert row["body"] == "Condition: Great · Intensity: Too easy"


def test_saving_still_returns_the_answer(client, db_session, pair):
    out = _send_feedback(client, pair, condition="tired", note="야근")

    assert out["submitted"] is True
    assert out["condition"] == "tired"


# ==========================================================================
# #3028 — 일정 알림 이동과 알림별 목적지
# ==========================================================================


def test_schedule_alerts_open_the_workout_tab(client, db_session, pair):
    created = client.post(
        "/v1/trainer/schedule",
        headers=pair.headers,
        json={
            "date": (clock.today() + timedelta(days=2)).isoformat(),
            "time": "10:00",
            "client_name": "지수",
            "member_id": pair.member_id,
            "type": "1:1 PT",
            "duration_minutes": 50,
            "note": "",
            "program": [],
        },
    )
    assert created.status_code == 201, created.text
    sid = created.json()["id"]
    moved = client.put(
        f"/v1/trainer/schedule/{sid}", headers=pair.headers, json={"time": "15:00"}
    )
    assert moved.status_code == 200, moved.text
    removed = client.delete(f"/v1/trainer/schedule/{sid}", headers=pair.headers)
    assert removed.status_code == 200, removed.text

    rows = _of(_member_inbox(client, pair), notification_service.MEMBER_SCHEDULE)
    assert len(rows) >= 3
    for row in rows:
        assert row["action"] == {"label": "일정 보기", "target": "exercise"}

    en = _of(_member_inbox(client, pair, "en"), notification_service.MEMBER_SCHEDULE)
    assert {r["action"]["label"] for r in en} == {"View schedule"}


def test_detaching_with_upcoming_pts_opens_the_workout_tab(client, db_session, pair):
    """담당 해제로 남은 PT 가 취소되면 일정 갈래다 — 같은 곳으로 간다."""
    created = client.post(
        "/v1/trainer/schedule",
        headers=pair.headers,
        json={
            "date": (clock.today() + timedelta(days=3)).isoformat(),
            "time": "11:00",
            "client_name": "지수",
            "member_id": pair.member_id,
            "type": "1:1 PT",
            "duration_minutes": 50,
            "note": "",
            "program": [],
        },
    )
    assert created.status_code == 201, created.text

    detached = client.delete(
        f"/v1/trainer/clients/{pair.member_id}", headers=pair.headers
    )
    assert detached.status_code == 204, detached.text

    rows = _member_inbox(client, pair)
    disconnect = next(
        r for r in rows if r["template"] == nt.MEMBER_TRAINER_DISCONNECTED
    )
    assert disconnect["category"] == notification_service.MEMBER_SCHEDULE
    assert disconnect["action"] == {"label": "일정 보기", "target": "exercise"}


def test_trainer_left_booking_alert_opens_the_workout_tab(client, db_session, pair):
    """트레이너 탈퇴로 예약이 취소된 알림도 일정 갈래다(`profile.delete_trainer`)."""
    notification_service.queue(
        db_session,
        member_id=pair.member_id,
        kind=notification_service.TRAINER_MESSAGE,
        category=notification_service.MEMBER_SCHEDULE,
        template=nt.MEMBER_TRAINER_LEFT_BOOKING,
        template_args={"trainer_name": "박코치"},
    )
    db_session.commit()

    rows = _of(_member_inbox(client, pair), notification_service.MEMBER_SCHEDULE)
    assert rows[0]["action"] == {"label": "일정 보기", "target": "exercise"}


def test_queue_stores_a_per_alert_target(client, db_session, pair):
    row = notification_service.queue(
        db_session,
        member_id=pair.member_id,
        kind=notification_service.TRAINER_MESSAGE,
        category=notification_service.MEMBER_ROUTINE,
        title="식단도 함께 봐 주세요",
        action_target="diet",
    )
    db_session.commit()
    assert row is not None

    db_session.expire_all()
    assert db_session.get(Notification, row.id).action_target == "diet"
    shown = next(r for r in _member_inbox(client, pair) if r["id"] == row.id)
    # 목적지가 갈래 표와 다르면 그 목적지의 라벨이다(#2690).
    assert shown["action"]["target"] == "diet"
    assert shown["action"]["label"] == "식단 보기"


def test_queue_without_a_target_keeps_the_category_table(client, db_session, pair):
    row = notification_service.queue(
        db_session,
        member_id=pair.member_id,
        kind=notification_service.TRAINER_MESSAGE,
        category=notification_service.MEMBER_ROUTINE,
        title="새 루틴",
    )
    db_session.commit()
    assert row is not None

    db_session.expire_all()
    assert db_session.get(Notification, row.id).action_target is None
    shown = next(r for r in _member_inbox(client, pair) if r["id"] == row.id)
    assert shown["action"] == {"label": "운동 보기", "target": "exercise"}


@pytest.mark.parametrize("bad", ["schedule", "nowhere", "", "Exercise"])
def test_queue_rejects_a_target_the_app_does_not_know(db_session, pair, bad):
    with pytest.raises(ValueError):
        notification_service.queue(
            db_session,
            member_id=pair.member_id,
            kind=notification_service.TRAINER_MESSAGE,
            title="갈 곳 없는 알림",
            action_target=bad,
        )
    db_session.rollback()


def test_queue_rejects_an_unknown_target_even_when_switched_off(client, db_session, pair):
    """수신 설정과 상관없이 호출부의 실수는 드러난다."""
    _turn_off_exercise(client, pair)
    with pytest.raises(ValueError):
        notification_service.queue(
            db_session,
            member_id=pair.member_id,
            kind=notification_service.EXERCISE,
            title="꺼진 알림",
            action_target="nowhere",
        )
    db_session.rollback()


def test_switched_off_alert_with_a_target_is_not_stored(client, db_session, pair):
    _turn_off_exercise(client, pair)

    row = notification_service.queue(
        db_session,
        member_id=pair.member_id,
        kind=notification_service.EXERCISE,
        title="꺼진 알림",
        action_target="exercise",
    )

    assert row is None
