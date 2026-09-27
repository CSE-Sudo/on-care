"""고객 후속 관리 할 일 — 계약·기한 범위·멱등·소유권 경계. (#869) DB 필요."""
from __future__ import annotations

from datetime import timedelta
from uuid import uuid4

import pytest

from app.core import clock
from app.core.security import create_access_token
from app.models.models import TrainerClient, TrainerFollowUpTask, User


MEMBER_ID = "user-jisu"


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
def cleanup_tasks(client, db_session):
    """테스트가 만든 할 일만 지운다 — 데모 시드는 건드리지 않는다."""
    created: list[str] = []
    yield created
    for task_id in created:
        task = db_session.get(TrainerFollowUpTask, task_id)
        if task is not None:
            db_session.delete(task)
    db_session.commit()


def _iso(offset_days: int) -> str:
    """오늘(KST)에서 며칠 떨어진 날짜. 서버와 같은 기준으로 만든다."""
    return (clock.today() + timedelta(days=offset_days)).isoformat()


def _create(client, token: str, **payload) -> dict:
    """할 일 하나를 만들고 응답 본문을 돌려준다.

    상태 확인 없이 `.json()` 을 쓰면 생성이 4xx 로 실패했을 때 뒤에서 `KeyError`
    가 나고 실패 이유가 로그에 남지 않는다.
    """
    payload.setdefault("title", f"후속 확인 {uuid4().hex[:6]}")
    payload.setdefault("due_date", _iso(0))
    response = client.post(
        f"/v1/trainer/clients/{MEMBER_ID}/follow-ups",
        headers=_headers(token),
        json=payload,
    )
    assert response.status_code == 201, response.text
    return response.json()


def test_create_read_complete_contract(client, trainer_token, cleanup_tasks):
    """등록 → 고객 목록·대시보드 노출 → 완료 → 미완료 목록에서 빠진다."""
    title = f"최근 식단 나트륨 다시 확인 {uuid4().hex[:6]}"
    task = _create(client, trainer_token, title=title, context_type="diet")
    cleanup_tasks.append(task["id"])
    assert task["status"] == "pending"
    assert task["completed_at"] is None
    assert task["member_id"] == MEMBER_ID
    # 대시보드가 "누구의 할 일인가"를 회원을 다시 조회하지 않고 그릴 수 있어야 한다.
    assert task["member_name"]

    listed = client.get(
        f"/v1/trainer/clients/{MEMBER_ID}/follow-ups", headers=_headers(trainer_token)
    )
    assert listed.status_code == 200, listed.text
    assert task["id"] in [item["id"] for item in listed.json()]

    due = client.get("/v1/trainer/follow-ups", headers=_headers(trainer_token))
    assert due.status_code == 200, due.text
    assert task["id"] in [item["id"] for item in due.json()]

    completed = client.post(
        f"/v1/trainer/follow-ups/{task['id']}/complete",
        headers=_headers(trainer_token),
    )
    assert completed.status_code == 200, completed.text
    assert completed.json()["status"] == "completed"
    assert completed.json()["completed_at"] is not None

    # 완료한 항목은 오늘 할 일에도, 고객 상세의 남은 일에도 다시 나오지 않는다.
    after_due = client.get(
        "/v1/trainer/follow-ups", headers=_headers(trainer_token)
    ).json()
    assert task["id"] not in [item["id"] for item in after_due]
    after_client = client.get(
        f"/v1/trainer/clients/{MEMBER_ID}/follow-ups", headers=_headers(trainer_token)
    ).json()
    assert task["id"] not in [item["id"] for item in after_client]

    # 완료 이력은 지워진 것이 아니라 남아 있다.
    with_completed = client.get(
        f"/v1/trainer/clients/{MEMBER_ID}/follow-ups",
        headers=_headers(trainer_token),
        params={"include_completed": "true"},
    ).json()
    stored = next(item for item in with_completed if item["id"] == task["id"])
    assert stored["status"] == "completed"


def test_due_scope_keeps_overdue_and_hides_future(
    client, trainer_token, cleanup_tasks
):
    """기한이 지난 미완료는 남고, 앞으로의 할 일은 오늘 목록에 끼지 않는다."""
    overdue = _create(client, trainer_token, due_date=_iso(-3))
    today = _create(client, trainer_token, due_date=_iso(0))
    future = _create(client, trainer_token, due_date=_iso(7))
    cleanup_tasks.extend([overdue["id"], today["id"], future["id"]])

    due_ids = [
        item["id"]
        for item in client.get(
            "/v1/trainer/follow-ups", headers=_headers(trainer_token)
        ).json()
    ]
    assert overdue["id"] in due_ids
    assert today["id"] in due_ids
    assert future["id"] not in due_ids
    # 지난 항목이 앞에 온다 — 화면이 따로 가르지 않아도 위에 쌓인다.
    assert due_ids.index(overdue["id"]) < due_ids.index(today["id"])

    open_ids = [
        item["id"]
        for item in client.get(
            "/v1/trainer/follow-ups",
            headers=_headers(trainer_token),
            params={"scope": "open"},
        ).json()
    ]
    assert future["id"] in open_ids


def test_same_client_request_id_creates_one_task(
    client, trainer_token, cleanup_tasks
):
    """끊긴 응답으로 재시도한 등록이 같은 할 일을 두 번 만들지 않는다."""
    request_id = f"req-{uuid4().hex[:10]}"
    first = _create(client, trainer_token, client_request_id=request_id)
    cleanup_tasks.append(first["id"])
    second = _create(client, trainer_token, client_request_id=request_id)
    assert second["id"] == first["id"]

    listed = client.get(
        f"/v1/trainer/clients/{MEMBER_ID}/follow-ups", headers=_headers(trainer_token)
    ).json()
    assert [item["id"] for item in listed].count(first["id"]) == 1


def test_completing_twice_keeps_the_first_completed_at(
    client, trainer_token, cleanup_tasks
):
    """같은 완료 요청을 반복해도 상태가 꼬이지 않는다(대시보드 중복 클릭)."""
    task = _create(client, trainer_token)
    cleanup_tasks.append(task["id"])
    first = client.post(
        f"/v1/trainer/follow-ups/{task['id']}/complete",
        headers=_headers(trainer_token),
    ).json()
    second = client.post(
        f"/v1/trainer/follow-ups/{task['id']}/complete",
        headers=_headers(trainer_token),
    )
    assert second.status_code == 200, second.text
    assert second.json()["completed_at"] == first["completed_at"]


def test_update_changes_title_and_due_date_only(
    client, trainer_token, cleanup_tasks
):
    task = _create(client, trainer_token)
    cleanup_tasks.append(task["id"])

    updated = client.put(
        f"/v1/trainer/follow-ups/{task['id']}",
        headers=_headers(trainer_token),
        json={"title": "다음 PT 에서 무릎 통증 확인", "due_date": _iso(2)},
    )
    assert updated.status_code == 200, updated.text
    assert updated.json()["title"] == "다음 PT 에서 무릎 통증 확인"
    assert updated.json()["due_date"] == _iso(2)
    assert updated.json()["status"] == "pending"

    assert client.put(
        f"/v1/trainer/follow-ups/{task['id']}",
        headers=_headers(trainer_token),
        json={},
    ).status_code == 400
    assert client.put(
        f"/v1/trainer/follow-ups/{task['id']}",
        headers=_headers(trainer_token),
        json={"title": "   "},
    ).status_code == 400
    # 명시적 null 은 422(부분 수정 규약 #495).
    assert client.put(
        f"/v1/trainer/follow-ups/{task['id']}",
        headers=_headers(trainer_token),
        json={"title": None},
    ).status_code == 422


def test_invalid_due_date_or_context_is_rejected(client, trainer_token):
    """달력에 없는 날짜와 앱이 모르는 갈래는 저장 전에 막는다."""
    for payload in (
        {"title": "확인", "due_date": "2026-02-31"},
        {"title": "확인", "due_date": "내일"},
        {"title": "확인", "due_date": _iso(0), "context_type": "billing"},
    ):
        response = client.post(
            f"/v1/trainer/clients/{MEMBER_ID}/follow-ups",
            headers=_headers(trainer_token),
            json=payload,
        )
        assert response.status_code == 422, response.text


def test_unmanaged_client_cannot_get_a_task(client, trainer_token, db_session):
    """담당하지 않는 회원에게는 할 일을 남길 수 없다(없는 회원과 같은 404)."""
    stranger_id = f"user-{uuid4().hex[:10]}"
    stranger = User(
        id=stranger_id,
        email=f"{stranger_id}@oncare.com",
        name="담당 아님",
        hashed_password="unused",
        role="member",
    )
    db_session.add(stranger)
    db_session.commit()
    try:
        response = client.post(
            f"/v1/trainer/clients/{stranger_id}/follow-ups",
            headers=_headers(trainer_token),
            json={"title": "보이면 안 됨", "due_date": _iso(0)},
        )
        assert response.status_code == 404
        listed = client.get(
            f"/v1/trainer/clients/{stranger_id}/follow-ups",
            headers=_headers(trainer_token),
        )
        assert listed.status_code == 404
    finally:
        db_session.delete(stranger)
        db_session.commit()


def test_another_trainer_cannot_read_or_complete_my_task(
    client, trainer_token, cleanup_tasks, db_session
):
    """트레이너별로 할 일이 격리된다 — 남의 할 일은 없는 할 일과 같다."""
    task = _create(client, trainer_token)
    cleanup_tasks.append(task["id"])

    other_id = f"trainer-{uuid4().hex[:10]}"
    other = User(
        id=other_id,
        email=f"{other_id}@oncare.com",
        name="다른 트레이너",
        hashed_password="unused",
        role="trainer",
    )
    db_session.add(other)
    db_session.flush()  # TrainerClient.trainer_id FK 부모를 먼저 반영한다.
    link = TrainerClient(
        id=f"tc-{uuid4().hex[:12]}",
        trainer_id=other_id,
        member_id=MEMBER_ID,
        # 회원 하나에 활성 담당은 한 명뿐이다(`uq_trainer_client_active_member`).
        # 그래서 같은 회원을 예전에 담당했던 트레이너로 둔다.
        active=False,
    )
    db_session.add(link)
    db_session.commit()
    try:
        other_headers = _headers(create_access_token(other_id))
        # 해제된 담당은 담당이 아니다 — 그 회원의 할 일 목록 자체가 404 다. (#2281)
        listed = client.get(
            f"/v1/trainer/clients/{MEMBER_ID}/follow-ups", headers=other_headers
        )
        assert listed.status_code == 404, listed.text
        # 내 할 일 전체 목록에도 남의 업무는 섞이지 않는다.
        for scope in ("due", "open"):
            mine = client.get(
                "/v1/trainer/follow-ups",
                params={"scope": scope},
                headers=other_headers,
            )
            assert mine.status_code == 200, mine.text
            assert task["id"] not in [item["id"] for item in mine.json()]

        denied = client.post(
            f"/v1/trainer/follow-ups/{task['id']}/complete", headers=other_headers
        )
        assert denied.status_code == 404
        denied_update = client.put(
            f"/v1/trainer/follow-ups/{task['id']}",
            headers=other_headers,
            json={"title": "남의 업무 수정"},
        )
        assert denied_update.status_code == 404
    finally:
        db_session.delete(link)
        db_session.delete(other)
        db_session.commit()
