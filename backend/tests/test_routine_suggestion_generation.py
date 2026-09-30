"""AI 개인운동 후보 준비. (#790) 순수 규칙 테스트는 DB 없이 실행된다.

승인 흐름만으로는 검토할 것이 생기지 않는다 — AI 가 먼저 후보를 준비해야
트레이너가 판단만 하고 넘어갈 수 있다. 여기서 지키는 계약은 셋이다.

1. 트레이너가 프로그램 탭을 열면 후보가 준비돼 있다(그리고 같은 날 몇 번 열어도
   늘지 않는다).
2. 준비된 후보는 승인 전까지 회원에게 닿지 않는다.
3. 준비하는 운동은 회복 범위이고, 트레이너 노트 원문은 옮기지 않는다.
"""
from __future__ import annotations

import pytest
from sqlalchemy import select

from app.db.session import SessionLocal
from app.models.models import TrainerRoutine
from app.services import routine_suggestion_service as suggestions

MEMBER = "user-jisu"
#: 혈압 관리가 필요한 시드 회원 — 근거 표시가 데이터에서 나오는지 본다.
BP_MEMBER = "user-7d4e9a2c5f18"
TRAINER = "trainer-demo"


def _trainer_token(client) -> str:
    return client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    ).json()["access_token"]


def _member_token(client) -> str:
    return client.post(
        "/v1/auth/login",
        data={"username": "jisu@oncare.com", "password": "oncare123"},
    ).json()["access_token"]


def _h(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _clear_prepared(member_id: str) -> None:
    """준비된 후보를 지워 '아직 준비 안 됨' 상태로 되돌린다."""
    db = SessionLocal()
    try:
        for row in db.scalars(
            select(TrainerRoutine).where(
                TrainerRoutine.member_id == member_id,
                TrainerRoutine.client_request_id.like("sug-%"),
            )
        ).all():
            db.delete(row)
        db.commit()
    finally:
        db.close()


@pytest.fixture()
def fresh(client):
    """매 테스트를 '오늘 아직 준비하지 않은' 상태에서 시작한다.

    준비는 하루 한 번이라, 앞선 테스트가 이미 만들어 둔 후보가 남아 있으면 그
    뒤의 테스트는 준비 경로를 지나지 않는다.
    """
    for member_id in (MEMBER, BP_MEMBER):
        _clear_prepared(member_id)
    yield _trainer_token(client)
    for member_id in (MEMBER, BP_MEMBER):
        _clear_prepared(member_id)


def _review_list(client, token: str, member_id: str = MEMBER):
    res = client.get(
        f"/v1/trainer/clients/{member_id}/routine-suggestions", headers=_h(token)
    )
    assert res.status_code == 200, res.text
    return res.json()


def test_opening_the_review_list_prepares_candidates(client, fresh):
    """트레이너가 목록을 열면 후보가 준비돼 있다 — 직접 요청하지 않아도."""
    rows = _review_list(client, fresh)

    assert rows, "최근 PT 기록이 있는 회원인데 준비된 후보가 없다"
    assert all(row["source"] == "ai" for row in rows)
    # 근거 없는 후보는 트레이너에게 판단 재료를 주지 못한다.
    assert all(row["evidence"] for row in rows)


def test_preparing_twice_in_a_day_does_not_grow_the_list(client, fresh):
    first = _review_list(client, fresh)
    second = _review_list(client, fresh)

    assert [row["id"] for row in first] == [row["id"] for row in second]


def test_prepared_candidates_are_invisible_to_the_member(client, fresh):
    prepared = {row["id"] for row in _review_list(client, fresh)}
    assert prepared

    mine = client.get("/v1/me/coach/routines", headers=_h(_member_token(client)))

    assert prepared.isdisjoint({row["id"] for row in mine.json()})


def test_approving_a_prepared_candidate_reaches_the_member(client, fresh):
    prepared = _review_list(client, fresh)[0]

    approved = client.post(
        f"/v1/trainer/routine-suggestions/{prepared['id']}/approve",
        headers=_h(fresh),
        json={},
    )
    assert approved.status_code == 200, approved.text

    mine = client.get("/v1/me/coach/routines", headers=_h(_member_token(client)))
    assert prepared["id"] in {row["id"] for row in mine.json()}


def test_the_member_response_does_not_carry_the_review_evidence(client, fresh):
    """근거는 트레이너의 판단 재료다 — 승인해도 회원 응답에는 싣지 않는다."""
    prepared = _review_list(client, fresh)[0]
    assert prepared["evidence"], "트레이너 목록에는 근거가 있어야 한다"

    client.post(
        f"/v1/trainer/routine-suggestions/{prepared['id']}/approve",
        headers=_h(fresh),
        json={},
    )

    mine = client.get("/v1/me/coach/routines", headers=_h(_member_token(client)))
    delivered = [
        row for row in mine.json() if row["id"] == prepared["id"]
    ]
    assert delivered, "승인한 운동은 회원에게 가야 한다"
    assert delivered[0]["evidence"] == []


def test_dismissed_candidates_are_not_prepared_again(client, fresh):
    """추천하지 않기로 한 후보가 새로고침마다 되살아나면 거절이 의미를 잃는다."""
    for row in _review_list(client, fresh):
        dismissed = client.post(
            f"/v1/trainer/routine-suggestions/{row['id']}/dismiss",
            headers=_h(fresh),
        )
        assert dismissed.status_code == 200, dismissed.text

    assert _review_list(client, fresh) == []


def test_prepared_candidates_stay_in_the_recovery_range(client, fresh):
    """기록만 보고 고강도 운동을 새로 처방하지 않는다.

    근력은 맨몸(0kg) 한 건만 들어간다(#2703) — 무게는 트레이너가 회원에 맞춰
    올린다.
    """
    rows = _review_list(client, fresh)

    assert rows
    strength = [row for row in rows if row["type"] == "근력"]
    assert len(strength) <= 1
    for row in strength:
        assert row["sets"] and (row["reps"] or row["hold_seconds"])
        assert not row["weight"]
    for row in rows:
        assert row["type"] in {"스트레칭", "유산소", "근력"}
        # PT 사이를 메우는 짧은 단위다 — 프로그램이 아니다.
        assert 0 < row["minutes"] <= 30


def test_evidence_does_not_carry_the_trainer_note_verbatim(client, fresh):
    """PT 노트는 트레이너가 자신을 위해 쓴 글이고, 승인하면 이유는 회원이 읽는다."""
    rows = _review_list(client, fresh)

    # 시드 PT 노트("데드리프트 자세 안정적. 다음 세션 60kg 도전.")의 특징적인
    # 조각이 회원용 문구나 근거로 새지 않아야 한다.
    for row in rows:
        assert "데드리프트" not in row["reason"]
        assert "60kg" not in row["reason"]
        for item in row["evidence"]:
            assert "데드리프트" not in item
            assert "60kg" not in item


def test_blood_pressure_shows_up_as_the_evidence_for_walking(client, fresh):
    rows = _review_list(client, fresh, BP_MEMBER)

    walking = [row for row in rows if row["name"] == "저강도 걷기"]
    assert walking, f"혈압 관리 회원인데 걷기 후보가 없다: {rows}"
    assert suggestions.EV_BLOOD_PRESSURE in walking[0]["evidence"]


def test_a_backlog_of_pending_reviews_stops_preparation(client, fresh):
    """트레이너가 며칠 검토하지 않았을 때 후보가 계속 쌓이면 안 된다."""
    db = SessionLocal()
    try:
        for index in range(suggestions.MAX_PENDING_BACKLOG):
            db.add(
                TrainerRoutine(
                    id=f"backlog-{index}",
                    trainer_id=TRAINER,
                    member_id=MEMBER,
                    name=f"밀린 제안 {index}",
                    minutes=10,
                    type="스트레칭",
                    reason="",
                    source="ai",
                    status=suggestions.ROUTINE_PENDING,
                    # 준비 키(`sug-`)와 다른 키를 써야 '오늘은 아직 준비 안 됨'
                    # 상태에서 백로그 규칙만 검증한다.
                    client_request_id=f"backlog-{index}",
                )
            )
        db.commit()

        rows = _review_list(client, fresh)
        assert len(rows) == suggestions.MAX_PENDING_BACKLOG
        assert not any(row["id"].startswith("sug-") for row in rows)
    finally:
        for index in range(suggestions.MAX_PENDING_BACKLOG):
            row = db.get(TrainerRoutine, f"backlog-{index}")
            if row is not None:
                db.delete(row)
        db.commit()
        db.close()


# ---- 규칙만 보는 순수 테스트 (DB 불필요) ----


def test_no_signals_means_no_candidates():
    """근거가 없으면 후보도 없다 — 검토 목록만 채우는 후보는 만들지 않는다."""
    assert suggestions._candidates_for(suggestions._Signals()) == []


def test_strength_heavy_records_get_a_recovery_stretch():
    candidates = suggestions._candidates_for(
        suggestions._Signals(strength_heavy=True, has_records=True)
    )

    assert [c.type for c in candidates] == ["스트레칭"]
    assert suggestions.EV_STRENGTH_HEAVY in candidates[0].evidence


def test_recent_pt_with_feedback_is_marked_as_such():
    candidates = suggestions._candidates_for(
        suggestions._Signals(
            pt_just_finished=True, trainer_feedback=True, has_records=True
        )
    )

    assert suggestions.EV_RECENT_PT in candidates[0].evidence


def test_at_most_the_cap_is_prepared():
    """모든 신호가 켜져도 개인운동은 할 일 목록이 되지 않는다."""
    candidates = suggestions._suggestions_for(
        suggestions._Signals(
            pt_just_finished=True,
            trainer_feedback=True,
            strength_heavy=True,
            low_cardio=True,
            blood_pressure=True,
            has_records=True,
        )
    )

    assert len(candidates) <= suggestions.MAX_NEW_SUGGESTIONS


def test_records_without_a_clear_signal_get_the_lightest_option():
    candidates = suggestions._candidates_for(
        suggestions._Signals(has_records=True)
    )

    assert len(candidates) == 1
    assert candidates[0].type == "스트레칭"
    assert candidates[0].minutes <= 10


def test_a_strength_candidate_with_sets_comes_last():
    """회복·유산소 뒤에 세트·횟수·중량이 있는 근력 후보 하나 (#2703).

    트레이너 웹 데모처럼 세 건이고, 개인운동 단계의 근력 칸이 채워져 보인다.
    """
    candidates = suggestions._suggestions_for(
        suggestions._Signals(
            pt_just_finished=True,
            trainer_feedback=True,
            strength_heavy=True,
            low_cardio=True,
            has_records=True,
            total_minutes=240,
            strength_minutes=190,
        )
    )

    assert len(candidates) == suggestions.MAX_NEW_SUGGESTIONS == 3
    strength = candidates[-1]
    assert strength.type == "근력"
    assert strength.name == "힙 브리지"
    assert (strength.sets, strength.reps, strength.weight) == (3, 15, 0.0)
    assert suggestions.EV_STRENGTH_HEAVY in strength.evidence
    assert [c for c in candidates if c.type == "근력"] == [strength]


def test_blood_pressure_members_get_a_breath_friendly_strength_move():
    (*_, strength) = suggestions._suggestions_for(
        suggestions._Signals(blood_pressure=True, has_records=True)
    )
    assert strength.name == "벽 푸시업"
    assert strength.evidence == (suggestions.EV_BLOOD_PRESSURE,)


def test_no_signal_means_no_strength_candidate_either():
    assert suggestions._suggestions_for(suggestions._Signals()) == []


def test_the_backlog_stops_after_two_days_of_suggestions():
    assert suggestions.MAX_PENDING_BACKLOG == 2 * suggestions.MAX_NEW_SUGGESTIONS
