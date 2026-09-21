"""트레이너 프로그램 초안 — 저장·조회·수정·소유권 경계. (#708) DB 필요.

핵심은 **값이 손실되지 않는 것**이다. 편집기의 세트·횟수·중량·시간은 자유
문자열이고, 항목이 AI 제안인지 트레이너가 직접 넣은 것인지도 구분이 남아야
저장한 초안을 다시 열었을 때 화면이 원래대로 그려진다.
"""
from __future__ import annotations

from uuid import uuid4

import pytest


def _headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _login(client, email: str) -> str:
    response = client.post(
        "/v1/auth/login",
        data={"username": email, "password": "oncare123"},
    )
    assert response.status_code == 200, response.text
    return response.json()["access_token"]


@pytest.fixture()
def trainer_token(client) -> str:
    return _login(client, "trainer@oncare.com")


@pytest.fixture()
def cleanup_drafts(client, db_session):
    """테스트가 만든 초안만 지운다."""
    created: list[str] = []
    yield created
    from app.models.models import TrainerProgramDraft

    for draft_id in created:
        draft = db_session.get(TrainerProgramDraft, draft_id)
        if draft is not None:
            db_session.delete(draft)
    db_session.commit()


def _exercise(**overrides) -> dict:
    base = {
        "id": "exercise-2",
        "name": "레그프레스",
        "type": "근력",
        "date": None,
        "duration": None,
        "sets": 4,
        "reps": 12,
        "hold_seconds": None,
        "weight": 60.0,
        "intensity": "moderate",
        "memo": "무릎 각도 확인",
        "source": "trainer",
    }
    base.update(overrides)
    return base


def _session(name: str = "세션 A", exercises: list | None = None, id_: str = "session-1") -> dict:
    return {
        "id": id_,
        "name": name,
        "exercises": [] if exercises is None else exercises,
    }


def _create_draft(client, token: str, **payload) -> dict:
    response = client.post(
        "/v1/trainer/programs", headers=_headers(token), json=payload
    )
    assert response.status_code == 201, response.text
    return response.json()


def test_draft_save_list_detail_update_contract(
    client, trainer_token, cleanup_drafts
):
    """저장 → 목록 → 상세 → 수정이 같은 초안을 가리키고 값이 유지된다."""
    name = f"체중 감량 프로그램 {uuid4().hex[:6]}"
    created = _create_draft(
        client,
        trainer_token,
        name=name,
        goal="체지방 감량",
        period="8주",
        memo="주 3회 기준",
        sessions=[
            _session(
                exercises=[
                    _exercise(),
                    _exercise(
                        id="exercise-3",
                        name="인터벌 유산소",
                        sets=None,
                        weight=None,
                        duration=20,
                        type="유산소",
                        source="ai",
                    ),
                ]
            )
        ],
    )
    cleanup_drafts.append(created["id"])
    assert created["name"] == name
    assert created["sessions"][0]["name"] == "세션 A"
    assert len(created["sessions"][0]["exercises"]) == 2

    listed = client.get("/v1/trainer/programs", headers=_headers(trainer_token))
    assert listed.status_code == 200, listed.text
    summary = next(
        item for item in listed.json() if item["id"] == created["id"]
    )
    assert summary["name"] == name
    assert summary["goal"] == "체지방 감량"
    assert summary["session_count"] == 1
    assert summary["exercise_count"] == 2
    # 목록은 세션·운동 구성을 싣지 않는다.
    assert "sessions" not in summary

    detail = client.get(
        f"/v1/trainer/programs/{created['id']}", headers=_headers(trainer_token)
    )
    assert detail.status_code == 200, detail.text
    assert detail.json() == created

    updated = client.put(
        f"/v1/trainer/programs/{created['id']}",
        headers=_headers(trainer_token),
        json={
            "name": f"{name} (수정)",
            "sessions": [
                _session(
                    exercises=[_exercise(id="exercise-9", name="스쿼트", sets=5)]
                )
            ],
        },
    )
    assert updated.status_code == 200, updated.text
    assert updated.json()["name"] == f"{name} (수정)"
    # sessions 는 통째로 교체된다.
    assert [
        e["name"] for e in updated.json()["sessions"][0]["exercises"]
    ] == ["스쿼트"]
    # 보내지 않은 필드는 그대로다.
    assert updated.json()["period"] == "8주"

    reread = client.get(
        f"/v1/trainer/programs/{created['id']}", headers=_headers(trainer_token)
    ).json()
    assert reread["name"] == f"{name} (수정)"
    assert [e["name"] for e in reread["sessions"][0]["exercises"]] == ["스쿼트"]


def test_reopened_draft_keeps_every_editor_value(
    client, trainer_token, cleanup_drafts
):
    """날짜·세트·횟수·중량·강도·메모와 AI/트레이너 구분이 그대로 돌아온다."""
    written = _exercise(
        id="exercise-7",
        name="루마니안 데드리프트",
        type="근력",
        date="2026-08-24",
        sets=3,
        reps=8,
        weight=40.5,
        intensity="high",
        memo="허리 중립 유지",
        source="ai",
    )
    created = _create_draft(
        client,
        trainer_token,
        name=f"값 보존 {uuid4().hex[:6]}",
        sessions=[_session(name="세션 B", exercises=[written])],
    )
    cleanup_drafts.append(created["id"])

    restored = client.get(
        f"/v1/trainer/programs/{created['id']}", headers=_headers(trainer_token)
    ).json()["sessions"]
    assert restored == [_session(name="세션 B", exercises=[written])]


def test_a_draft_without_exercises_is_saved(
    client, trainer_token, cleanup_drafts
):
    """이름만 잡아 둔 상태도 초안이다 — 저장하지 못하면 기능이 반쪽이 된다."""
    created = _create_draft(
        client, trainer_token, name=f"이름만 {uuid4().hex[:6]}", sessions=[]
    )
    cleanup_drafts.append(created["id"])
    assert created["sessions"] == []

    summary = next(
        item
        for item in client.get(
            "/v1/trainer/programs", headers=_headers(trainer_token)
        ).json()
        if item["id"] == created["id"]
    )
    assert summary["session_count"] == 0
    assert summary["exercise_count"] == 0


def test_draft_delete_removes_it_from_the_list(
    client, trainer_token, cleanup_drafts
):
    created = _create_draft(
        client, trainer_token, name=f"삭제 대상 {uuid4().hex[:6]}"
    )
    cleanup_drafts.append(created["id"])

    deleted = client.delete(
        f"/v1/trainer/programs/{created['id']}", headers=_headers(trainer_token)
    )
    assert deleted.status_code == 200, deleted.text
    assert created["id"] not in [
        item["id"]
        for item in client.get(
            "/v1/trainer/programs", headers=_headers(trainer_token)
        ).json()
    ]
    # 없는 초안을 다시 지우면 404.
    assert client.delete(
        f"/v1/trainer/programs/{created['id']}", headers=_headers(trainer_token)
    ).status_code == 404


def test_invalid_draft_input_is_rejected(client, trainer_token, cleanup_drafts):
    blank_name = client.post(
        "/v1/trainer/programs",
        headers=_headers(trainer_token),
        json={"name": "   "},
    )
    assert blank_name.status_code == 400

    unknown_type = client.post(
        "/v1/trainer/programs",
        headers=_headers(trainer_token),
        json={
            "name": "잘못된 유형",
            "sessions": [_session(exercises=[_exercise(type="Strength")])],
        },
    )
    assert unknown_type.status_code == 422

    unknown_source = client.post(
        "/v1/trainer/programs",
        headers=_headers(trainer_token),
        json={
            "name": "잘못된 출처",
            "sessions": [_session(exercises=[_exercise(source="import")])],
        },
    )
    assert unknown_source.status_code == 422

    created = _create_draft(client, trainer_token, name=f"검증 {uuid4().hex[:6]}")
    cleanup_drafts.append(created["id"])
    empty_update = client.put(
        f"/v1/trainer/programs/{created['id']}",
        headers=_headers(trainer_token),
        json={},
    )
    assert empty_update.status_code == 400
    blank_update = client.put(
        f"/v1/trainer/programs/{created['id']}",
        headers=_headers(trainer_token),
        json={"name": "  "},
    )
    assert blank_update.status_code == 400
    # 명시적 null 은 422(부분 수정 규약 #495).
    null_update = client.put(
        f"/v1/trainer/programs/{created['id']}",
        headers=_headers(trainer_token),
        json={"name": None},
    )
    assert null_update.status_code == 422


def test_another_trainer_cannot_reach_the_draft(
    client, db_session, trainer_token, cleanup_drafts
):
    """남의 초안은 조회·수정·삭제 모두 404 다(없는 초안과 같다)."""
    from app.core.security import create_access_token
    from app.models.models import User

    created = _create_draft(
        client, trainer_token, name=f"남이 보면 안 됨 {uuid4().hex[:6]}"
    )
    cleanup_drafts.append(created["id"])

    other_trainer_id = f"trainer-{uuid4().hex[:10]}"
    other_trainer = User(
        id=other_trainer_id,
        email=f"{other_trainer_id}@oncare.com",
        name="다른 트레이너",
        hashed_password="unused",
        role="trainer",
    )
    db_session.add(other_trainer)
    db_session.commit()
    other_headers = _headers(create_access_token(other_trainer_id))
    try:
        assert client.get(
            f"/v1/trainer/programs/{created['id']}", headers=other_headers
        ).status_code == 404
        assert client.put(
            f"/v1/trainer/programs/{created['id']}",
            headers=other_headers,
            json={"name": "몰래 고치기"},
        ).status_code == 404
        assert client.delete(
            f"/v1/trainer/programs/{created['id']}", headers=other_headers
        ).status_code == 404
        # 목록에도 남의 초안은 없다.
        assert client.get(
            "/v1/trainer/programs", headers=other_headers
        ).json() == []
    finally:
        db_session.delete(other_trainer)
        db_session.commit()


def test_member_cannot_reach_program_drafts(client):
    email = f"member-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register", json={"email": email, "password": "pw!", "name": "u"}
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "pw!"}
    ).json()["access_token"]
    assert client.get(
        "/v1/trainer/programs", headers=_headers(token)
    ).status_code == 403
