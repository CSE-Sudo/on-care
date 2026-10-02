"""코칭 화면의 회원별 자동 보관 — 초안의 `member_id`·`workspace`. (#2873)

트레이너 웹은 작성 중인 내용을 회원별로 프로그램 초안 표에 자동 보관하고, 새로
고침 뒤 그 회원의 것을 찾아 `이어서 쓰기` 로 되살린다. 여기서는 그 계약을 본다.

- 회원을 실어 저장하면 상세·목록에 그 회원이 돌아오고, 목록은 회원으로 거를 수 있다.
- 작성 상태(`workspace`)는 받은 객체 그대로 돌아오고, 수정은 통째로 교체한다.
- 담당이 아닌 회원으로는 저장할 수 없다(다른 회원 경로와 같은 404).
- 회원 없는 초안(#708)은 지금과 같다.

DB 가 필요한 테스트와, 스키마·마이그레이션만 보는 테스트가 섞여 있다.
"""
from __future__ import annotations

from pathlib import Path
from uuid import uuid4

import pytest
from pydantic import ValidationError

from app.schemas.trainer_api import (
    PROGRAM_WORKSPACE_MAX_CHARS,
    TrainerProgramDraftCreate,
    TrainerProgramDraftUpdate,
)

MIGRATION = (
    Path(__file__).resolve().parents[1]
    / "migrations"
    / "versions"
    / "0140_program_draft_member.py"
)


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
def member_id(client, trainer_token) -> str:
    roster = client.get("/v1/trainer/clients", headers=_headers(trainer_token))
    assert roster.status_code == 200, roster.text
    assert roster.json(), "시드 트레이너에게 담당 회원이 있어야 한다"
    return roster.json()[0]["id"]


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
        "id": "exercise-1",
        "name": "스쿼트",
        "type": "근력",
        "date": None,
        "duration": None,
        "duration_seconds": None,
        "sets": 3,
        "reps": 10,
        "hold_seconds": None,
        "weight": 20.0,
        "intensity": "moderate",
        "memo": "",
        "source": "ai",
        "effect": "",
    }
    base.update(overrides)
    return base


def _workspace(**overrides) -> dict:
    """코칭 화면이 싣는 작성 상태의 모양 — 서버는 해석하지 않는다."""
    base = {
        "version": 1,
        "phase": "wizard",
        "routine_only": False,
        "personal_routines": [
            {"name": "걷기", "minutes": 30, "type": "유산소", "suggestion_id": "s-1"}
        ],
        "wizard": {
            "stage": 1,
            "selected_key": "B",
            "prompt": "하체 부담 적게",
            "trainer_memo": "무릎 상태 확인",
        },
    }
    base.update(overrides)
    return base


def _create(client, token: str, **payload) -> dict:
    response = client.post(
        "/v1/trainer/programs", headers=_headers(token), json=payload
    )
    assert response.status_code == 201, response.text
    return response.json()


# ---- DB 계약 ----


def test_member_draft_round_trips_member_and_workspace(
    client, trainer_token, member_id, cleanup_drafts
):
    """회원과 작성 상태를 실어 저장하면 상세에 그대로 돌아온다."""
    workspace = _workspace()
    created = _create(
        client,
        trainer_token,
        name=f"작성 중 {uuid4().hex[:6]}",
        memo="회원에게 보낼 메모",
        sessions=[
            {"id": "session-1", "name": "세션 A", "exercises": [_exercise()]}
        ],
        member_id=member_id,
        workspace=workspace,
    )
    cleanup_drafts.append(created["id"])
    assert created["member_id"] == member_id
    assert created["workspace"] == workspace

    detail = client.get(
        f"/v1/trainer/programs/{created['id']}", headers=_headers(trainer_token)
    )
    assert detail.status_code == 200, detail.text
    assert detail.json() == created


def test_list_filters_by_member(
    client, trainer_token, member_id, cleanup_drafts
):
    """`member_id` 로 거르면 그 회원에게 자동 보관한 것만 온다."""
    for_member = _create(
        client,
        trainer_token,
        name=f"회원 초안 {uuid4().hex[:6]}",
        member_id=member_id,
        workspace=_workspace(),
    )
    plain = _create(client, trainer_token, name=f"일반 초안 {uuid4().hex[:6]}")
    cleanup_drafts.extend([for_member["id"], plain["id"]])

    filtered = client.get(
        "/v1/trainer/programs",
        headers=_headers(trainer_token),
        params={"member_id": member_id},
    )
    assert filtered.status_code == 200, filtered.text
    ids = [item["id"] for item in filtered.json()]
    assert for_member["id"] in ids
    assert plain["id"] not in ids
    assert all(item["member_id"] == member_id for item in filtered.json())

    # 거르지 않은 목록은 지금처럼 전부이고, 회원 없는 초안은 비어 있다.
    everything = client.get(
        "/v1/trainer/programs", headers=_headers(trainer_token)
    ).json()
    by_id = {item["id"]: item for item in everything}
    assert by_id[for_member["id"]]["member_id"] == member_id
    assert by_id[plain["id"]]["member_id"] is None


def test_list_for_unknown_member_is_empty(client, trainer_token):
    """내 초안만 거르므로, 모르는 회원 id 는 빈 목록이다(존재를 드러내지 않는다)."""
    response = client.get(
        "/v1/trainer/programs",
        headers=_headers(trainer_token),
        params={"member_id": f"nobody-{uuid4().hex[:8]}"},
    )
    assert response.status_code == 200, response.text
    assert response.json() == []


def test_update_replaces_workspace_and_keeps_member(
    client, trainer_token, member_id, cleanup_drafts
):
    """작성 상태는 통째로 교체되고, 회원은 그대로 남는다."""
    created = _create(
        client,
        trainer_token,
        name=f"교체 {uuid4().hex[:6]}",
        member_id=member_id,
        workspace=_workspace(),
    )
    cleanup_drafts.append(created["id"])

    next_workspace = {"version": 1, "phase": "editor", "routine_only": True}
    updated = client.put(
        f"/v1/trainer/programs/{created['id']}",
        headers=_headers(trainer_token),
        json={"workspace": next_workspace, "memo": "고친 메모"},
    )
    assert updated.status_code == 200, updated.text
    body = updated.json()
    assert body["workspace"] == next_workspace
    assert body["member_id"] == member_id
    assert body["memo"] == "고친 메모"
    # 보내지 않은 칸은 그대로다.
    assert body["name"] == created["name"]


def test_member_draft_requires_a_linked_member(
    client, trainer_token, cleanup_drafts
):
    """담당이 아닌 회원으로는 저장할 수 없다 — 다른 회원 경로와 같은 404."""
    response = client.post(
        "/v1/trainer/programs",
        headers=_headers(trainer_token),
        json={
            "name": f"남의 회원 {uuid4().hex[:6]}",
            "member_id": f"nobody-{uuid4().hex[:8]}",
            "workspace": _workspace(),
        },
    )
    assert response.status_code == 404, response.text


def test_plain_draft_has_no_member_and_empty_workspace(
    client, trainer_token, cleanup_drafts
):
    """회원 없는 초안(#708)은 지금과 같다 — 회원 비고 작성 상태는 빈 객체."""
    created = _create(client, trainer_token, name=f"일반 {uuid4().hex[:6]}")
    cleanup_drafts.append(created["id"])
    assert created["member_id"] is None
    assert created["workspace"] == {}


def test_deleting_member_draft(client, trainer_token, member_id, cleanup_drafts):
    """전송·템플릿 저장 뒤 화면이 지우는 경로 — 지우면 회원 목록에서 빠진다."""
    created = _create(
        client,
        trainer_token,
        name=f"지울 초안 {uuid4().hex[:6]}",
        member_id=member_id,
        workspace=_workspace(),
    )
    cleanup_drafts.append(created["id"])

    deleted = client.delete(
        f"/v1/trainer/programs/{created['id']}", headers=_headers(trainer_token)
    )
    assert deleted.status_code == 200, deleted.text
    remaining = client.get(
        "/v1/trainer/programs",
        headers=_headers(trainer_token),
        params={"member_id": member_id},
    ).json()
    assert created["id"] not in [item["id"] for item in remaining]


# ---- 스키마 (DB 불필요) ----


def test_workspace_size_is_capped_on_create():
    """작성 상태가 상한을 넘으면 저장 입력이 거절된다."""
    too_big = {"blob": "가" * (PROGRAM_WORKSPACE_MAX_CHARS + 1)}
    with pytest.raises(ValidationError):
        TrainerProgramDraftCreate(name="초안", workspace=too_big)


def test_workspace_size_is_capped_on_update():
    too_big = {"blob": "a" * (PROGRAM_WORKSPACE_MAX_CHARS + 1)}
    with pytest.raises(ValidationError):
        TrainerProgramDraftUpdate(workspace=too_big)


def test_workspace_within_cap_is_accepted():
    payload = TrainerProgramDraftCreate(
        name="초안", member_id="member-1", workspace=_workspace()
    )
    assert payload.workspace == _workspace()
    assert payload.member_id == "member-1"


def test_update_does_not_accept_member_change():
    """회원은 바꾸지 않는다 — 다른 회원에게 짜던 내용이 되면 새 초안이다."""
    assert "member_id" not in TrainerProgramDraftUpdate.model_fields


def test_update_rejects_null_workspace():
    """부분 수정에서 null 은 '지운다' 가 아니라 잘못된 입력이다."""
    with pytest.raises(ValidationError):
        TrainerProgramDraftUpdate.model_validate({"workspace": None})


def test_migration_defines_member_columns():
    """새 마이그레이션이 회원·작성 상태 칸과 회원 인덱스를 만든다.

    앞 리비전 연결(머리 1개)은 CI 의 Alembic head 검사가 따로 확인한다.
    """
    text = MIGRATION.read_text(encoding="utf-8")
    assert 'revision: str = "0140_program_draft_member"' in text
    assert '"member_id"' in text and '"workspace_json"' in text
    assert "ix_trainer_program_drafts_member_id" in text
