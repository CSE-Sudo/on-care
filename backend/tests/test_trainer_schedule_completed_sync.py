"""완료 PT 의 파생 기록이 완료 뒤 수정·삭제·되돌리기를 따라간다 (#3093). DB 필요.

완료는 트레이너 이력(`sched-hist-{id}`)과 회원 운동 기록(`sched-ex-{id}`)을 한
번 만든다. 완료 뒤 프로그램·메모를 고칠 수 있게 된 뒤로(#2754), 그 두 행과 코치
근거 문서가 완료 시점 값에 머물러 회원 기록·주간 집계·트레이너 이력·AI 코치가
고친 프로그램을 몰랐다.
"""
from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import select

from app.core import clock
from app.models.models import (
    CoachDocument,
    ExerciseSession,
    RoutineHistory,
    TrainerSchedule,
)
from app.services.coach import personal_ingest

_SQUAT = {"name": "스쿼트", "type": "근력", "sets": 5, "reps": 5, "weight": 80}
_TREADMILL = {
    "name": "러닝머신",
    "type": "유산소",
    "duration": 20,
    "duration_seconds": 1200,
}


def _login(client, email: str = "trainer@oncare.com") -> str:
    response = client.post(
        "/v1/auth/login", data={"username": email, "password": "oncare123"}
    )
    assert response.status_code == 200, response.text
    return response.json()["access_token"]


def _h(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture()
def make_session(client):
    """일정을 만들고 테스트 끝에 지우는 팩토리(쌓이면 다른 테스트가 깨진다, #558)."""
    created: list[tuple[str, str]] = []

    def _make(token: str, **over) -> str:
        body = {
            "date": clock.today().isoformat(),
            "time": "20:00",
            "client_name": "이지수",
            "member_id": "user-jisu",
            "type": "1:1 PT",
            "duration_minutes": 50,
        }
        body.update(over)
        response = client.post("/v1/trainer/schedule", json=body, headers=_h(token))
        assert response.status_code == 201, response.text
        created.append((response.json()["id"], token))
        return response.json()["id"]

    yield _make

    for session_id, token in created:
        client.delete(f"/v1/trainer/schedule/{session_id}", headers=_h(token))


def _complete(client, token: str, sid: str, note: str = "") -> None:
    done = client.post(
        f"/v1/trainer/schedule/{sid}/complete", json={"note": note}, headers=_h(token)
    )
    assert done.status_code == 200, done.text


def _edit(client, token: str, sid: str, **fields):
    return client.put(f"/v1/trainer/schedule/{sid}", json=fields, headers=_h(token))


def _rows(db_session, sid: str) -> tuple[RoutineHistory | None, ExerciseSession | None]:
    db_session.expire_all()
    return (
        db_session.get(RoutineHistory, f"sched-hist-{sid}"),
        db_session.get(ExerciseSession, f"sched-ex-{sid}"),
    )


def _docs(db_session, ref: str) -> list[CoachDocument]:
    db_session.expire_all()
    return list(
        db_session.scalars(
            select(CoachDocument).where(CoachDocument.source_ref == ref)
        ).all()
    )


# ---- 프로그램·메모 수정 ----


def test_program_written_after_completion_rewrites_both_records(
    client, db_session, make_session
):
    token = _login(client)
    sid = make_session(token)
    _complete(client, token, sid)
    hist, ex = _rows(db_session, sid)
    assert json.loads(hist.exercises_json) == []
    assert (ex.minutes, ex.type, ex.name, ex.sets) == (50, "strength", "", None)
    created_id, calories_before = ex.id, ex.calories

    saved = _edit(client, token, sid, program=[_SQUAT])

    assert saved.status_code == 200, saved.text
    hist, ex = _rows(db_session, sid)
    assert [e["name"] for e in json.loads(hist.exercises_json)] == ["스쿼트"]
    assert ex.id == created_id
    assert ex.name == "스쿼트"
    assert ex.type == "strength"
    assert (ex.sets, ex.reps, ex.weight) == (5, 5, 80)
    assert ex.minutes != 50
    assert ex.calories != calories_before
    assert ex.source == "trainer_pt"


def test_member_week_counts_the_edited_program(client, db_session, make_session):
    token = _login(client)
    member = _login(client, "jisu@oncare.com")
    sid = make_session(token)
    _complete(client, token, sid)

    assert _edit(client, token, sid, program=[_TREADMILL]).status_code == 200

    _, ex = _rows(db_session, sid)
    assert (ex.type, ex.minutes, ex.duration_seconds) == ("cardio", 20, 1200)
    week = client.get(
        "/v1/exercise/weeks/current",
        params={"week_start": ex.week_start},
        headers=_h(member),
    )
    assert week.status_code == 200, week.text
    hit = next(s for s in week.json()["sessions"] if s["id"] == f"sched-ex-{sid}")
    assert hit["minutes"] == 20
    assert hit["calories"] == ex.calories
    assert hit["name"] == "러닝머신"


def test_note_only_edit_rewrites_history_note(client, db_session, make_session):
    token = _login(client)
    sid = make_session(token, program=[_SQUAT])
    _complete(client, token, sid, note="완료 때 메모")
    _, ex_before = _rows(db_session, sid)
    calories_before = ex_before.calories

    assert _edit(client, token, sid, note="끝난 뒤 남긴 메모").status_code == 200

    hist, ex = _rows(db_session, sid)
    assert hist.trainer_note == "끝난 뒤 남긴 메모"
    assert [e["name"] for e in json.loads(hist.exercises_json)] == ["스쿼트"]
    assert ex.calories == calories_before


def test_program_only_edit_keeps_history_note(client, db_session, make_session):
    token = _login(client)
    sid = make_session(token)
    _complete(client, token, sid, note="완료 때 메모")

    assert _edit(client, token, sid, program=[_SQUAT]).status_code == 200

    hist, _ = _rows(db_session, sid)
    assert hist.trainer_note == "완료 때 메모"


def test_sent_program_change_is_rejected_and_records_stay(
    client, db_session, make_session
):
    token = _login(client)
    sid = make_session(token, program=[_SQUAT])
    _complete(client, token, sid, note="완료 때 메모")
    stored = db_session.get(TrainerSchedule, sid)
    stored.program_sent_at = datetime.now(timezone.utc)
    db_session.commit()
    hist, ex = _rows(db_session, sid)
    before = (hist.exercises_json, hist.trainer_note, ex.name, ex.minutes)

    rejected = _edit(client, token, sid, program=[{**_SQUAT, "name": "런지"}])

    assert rejected.status_code == 409, rejected.text
    hist, ex = _rows(db_session, sid)
    assert (hist.exercises_json, hist.trainer_note, ex.name, ex.minutes) == before


def test_completed_consultation_edit_creates_no_member_record(
    client, db_session, make_session
):
    token = _login(client)
    sid = make_session(token, type="상담")
    _complete(client, token, sid)

    assert _edit(client, token, sid, program=[_SQUAT], note="상담 메모").status_code == 200

    hist, ex = _rows(db_session, sid)
    assert ex is None
    assert hist.trainer_note == "상담 메모"


@pytest.mark.parametrize("how", ["cancel", "no-show"])
def test_unfinished_session_note_creates_no_records(
    client, db_session, make_session, how
):
    token = _login(client)
    sid = make_session(token, time="21:00")
    body = {"json": {"source": "member"}} if how == "cancel" else {}
    finished = client.post(
        f"/v1/trainer/schedule/{sid}/{how}", headers=_h(token), **body
    )
    assert finished.status_code == 200, finished.text

    assert _edit(client, token, sid, note="끝난 뒤 메모", program=[_SQUAT]).status_code == 200

    assert _rows(db_session, sid) == (None, None)


# ---- 코치 근거(개인 RAG) ----


def test_program_edit_replaces_coach_evidence(client, db_session, make_session):
    token = _login(client)
    sid = make_session(token)
    _complete(client, token, sid)
    ref = f"sched-ex-{sid}"
    assert any("50분" in d.content for d in _docs(db_session, ref))

    assert _edit(client, token, sid, program=[_TREADMILL]).status_code == 200

    docs = _docs(db_session, ref)
    assert any("20분" in d.content for d in docs)
    assert all("50분" not in d.content for d in docs)


def test_delete_forgets_coach_evidence(client, db_session, make_session):
    token = _login(client)
    sid = make_session(token)
    _complete(client, token, sid)
    ref = f"sched-ex-{sid}"
    assert _docs(db_session, ref)

    gone = client.delete(f"/v1/trainer/schedule/{sid}", headers=_h(token))

    assert gone.status_code == 200, gone.text
    assert _docs(db_session, ref) == []


def test_reopen_forgets_coach_evidence(client, db_session, make_session):
    token = _login(client)
    sid = make_session(token)
    _complete(client, token, sid)
    ref = f"sched-ex-{sid}"
    assert _docs(db_session, ref)

    reopened = client.post(
        f"/v1/trainer/schedule/{sid}/reopen",
        json={
            "date": (clock.today() + timedelta(days=44)).isoformat(),
            "time": "06:00",
        },
        headers=_h(token),
    )

    assert reopened.status_code == 200, reopened.text
    assert _docs(db_session, ref) == []


def test_ingest_failure_does_not_break_edit_or_delete(
    client, db_session, make_session, monkeypatch
):
    token = _login(client)
    sid = make_session(token)
    _complete(client, token, sid)

    def _boom(*_args, **_kwargs):
        raise RuntimeError("embedder down")

    monkeypatch.setattr(personal_ingest, "replace_personal_text", _boom)

    saved = _edit(client, token, sid, program=[_SQUAT])
    assert saved.status_code == 200, saved.text
    _, ex = _rows(db_session, sid)
    assert ex.name == "스쿼트"

    gone = client.delete(f"/v1/trainer/schedule/{sid}", headers=_h(token))
    assert gone.status_code == 200, gone.text
    assert _rows(db_session, sid) == (None, None)
