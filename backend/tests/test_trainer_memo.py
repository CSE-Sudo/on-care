"""회원별 트레이너 메모 — 계약·중복 방지·소유권 경계. (#706) DB 필요."""
from __future__ import annotations

from uuid import uuid4

import pytest


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


def _create_memo(client, token: str, **payload) -> dict:
    """메모 하나를 만들고 응답 본문을 돌려준다.

    상태 확인 없이 바로 `.json()` 을 쓰면 생성이 4xx 로 실패했을 때 뒤에서
    `KeyError` 가 나고 실패 이유가 로그에 남지 않는다.
    """
    response = client.post(
        f"/v1/trainer/clients/{MEMBER_ID}/memos",
        headers=_headers(token),
        json=payload,
    )
    assert response.status_code == 201, response.text
    return response.json()


@pytest.fixture()
def cleanup_memos(client, db_session):
    """테스트가 만든 메모만 지운다 — 데모 시드 메모는 건드리지 않는다."""
    created: list[str] = []
    yield created
    from app.models.models import TrainerClientMemo

    for memo_id in created:
        memo = db_session.get(TrainerClientMemo, memo_id)
        if memo is not None:
            db_session.delete(memo)
    db_session.commit()


def test_memo_create_read_update_contract(client, trainer_token, cleanup_memos):
    """작성 → 조회 → 수정이 같은 메모를 가리킨다(다시 조회해도 유지)."""
    body = f"무릎 통증 경과 관찰 {uuid4().hex[:6]}"
    memo = _create_memo(client, trainer_token, body=body)
    cleanup_memos.append(memo["id"])
    assert memo["body"] == body
    assert memo["source"] == "trainer"
    assert memo["insight_id"] is None

    listed = client.get(
        f"/v1/trainer/clients/{MEMBER_ID}/memos", headers=_headers(trainer_token)
    )
    assert listed.status_code == 200, listed.text
    assert memo["id"] in [item["id"] for item in listed.json()]

    updated = client.put(
        f"/v1/trainer/clients/{MEMBER_ID}/memos/{memo['id']}",
        headers=_headers(trainer_token),
        json={"body": f"{body} (수정)"},
    )
    assert updated.status_code == 200, updated.text
    assert updated.json()["body"] == f"{body} (수정)"
    # 출처는 수정 대상이 아니다.
    assert updated.json()["source"] == "trainer"

    # 재조회해도 수정본이 남는다 — 서버가 실제로 저장했다는 확인.
    reread = client.get(
        f"/v1/trainer/clients/{MEMBER_ID}/memos", headers=_headers(trainer_token)
    ).json()
    stored = next(item for item in reread if item["id"] == memo["id"])
    assert stored["body"] == f"{body} (수정)"


def test_memo_delete_removes_it_from_the_list(
    client, trainer_token, cleanup_memos
):
    created = _create_memo(
        client, trainer_token, body=f"삭제 대상 {uuid4().hex[:6]}"
    )
    # 삭제 단정이 먼저 실패해도 이 메모가 DB 에 남아 다른 테스트의 목록·정렬을
    # 흔들지 않도록 정리 대상에 올려 둔다.
    cleanup_memos.append(created["id"])

    deleted = client.delete(
        f"/v1/trainer/clients/{MEMBER_ID}/memos/{created['id']}",
        headers=_headers(trainer_token),
    )
    assert deleted.status_code == 200, deleted.text

    listed = client.get(
        f"/v1/trainer/clients/{MEMBER_ID}/memos", headers=_headers(trainer_token)
    ).json()
    assert created["id"] not in [item["id"] for item in listed]

    # 이미 지운 메모를 다시 지우면 404(없는 메모와 같다).
    again = client.delete(
        f"/v1/trainer/clients/{MEMBER_ID}/memos/{created['id']}",
        headers=_headers(trainer_token),
    )
    assert again.status_code == 404


def test_same_chat_insight_saved_twice_keeps_one_memo(
    client, trainer_token, cleanup_memos
):
    """채팅 인사이트는 insight_id 로 멱등하다 — 반복 저장해도 메모가 늘지 않는다."""
    insight_id = f"msg-{uuid4().hex[:8]}:discomfort"
    payload = {
        "body": "무릎이 아파요",
        "source": "chat_insight",
        "insight_id": insight_id,
        "insight_kind": "discomfort",
    }
    first = _create_memo(client, trainer_token, **payload)
    cleanup_memos.append(first["id"])

    second = _create_memo(client, trainer_token, **payload)
    assert second["id"] == first["id"]

    listed = client.get(
        f"/v1/trainer/clients/{MEMBER_ID}/memos", headers=_headers(trainer_token)
    ).json()
    same_insight = [item for item in listed if item["insight_id"] == insight_id]
    assert len(same_insight) == 1
    assert same_insight[0]["insight_kind"] == "discomfort"


def test_chat_insight_and_manual_memos_share_one_list(
    client, trainer_token, cleanup_memos
):
    """회원 상세 목록이 두 출처를 함께 보여 준다 — 같은 데이터 소스."""
    manual = _create_memo(
        client, trainer_token, body=f"직접 작성 {uuid4().hex[:6]}"
    )
    cleanup_memos.append(manual["id"])
    insight = _create_memo(
        client,
        trainer_token,
        body="어깨가 결려요",
        source="chat_insight",
        insight_id=f"msg-{uuid4().hex[:8]}:discomfort",
        insight_kind="discomfort",
    )
    cleanup_memos.append(insight["id"])

    listed = client.get(
        f"/v1/trainer/clients/{MEMBER_ID}/memos", headers=_headers(trainer_token)
    ).json()
    ids = [item["id"] for item in listed]
    assert manual["id"] in ids
    assert insight["id"] in ids
    # 최신 먼저 — 나중에 저장한 인사이트 메모가 직접 작성 메모보다 앞에 온다.
    assert ids.index(insight["id"]) < ids.index(manual["id"])


def test_blank_memo_is_rejected(client, trainer_token, cleanup_memos):
    blank = client.post(
        f"/v1/trainer/clients/{MEMBER_ID}/memos",
        headers=_headers(trainer_token),
        json={"body": "   "},
    )
    assert blank.status_code == 400

    created = _create_memo(client, trainer_token, body="내용 있음")
    cleanup_memos.append(created["id"])
    empty_update = client.put(
        f"/v1/trainer/clients/{MEMBER_ID}/memos/{created['id']}",
        headers=_headers(trainer_token),
        json={},
    )
    assert empty_update.status_code == 400
    blank_update = client.put(
        f"/v1/trainer/clients/{MEMBER_ID}/memos/{created['id']}",
        headers=_headers(trainer_token),
        json={"body": " "},
    )
    assert blank_update.status_code == 400
    # 명시적 null 은 422(부분 수정 규약 #495).
    null_update = client.put(
        f"/v1/trainer/clients/{MEMBER_ID}/memos/{created['id']}",
        headers=_headers(trainer_token),
        json={"body": None},
    )
    assert null_update.status_code == 422


def test_mismatched_source_and_insight_id_are_rejected(client, trainer_token):
    """출처와 중복 방지 키가 어긋난 조합은 422 다.

    키 없는 인사이트 메모는 반복 저장 때마다 늘어나고, 직접 쓴 메모가
    `insight_id` 를 가지면 그 인사이트의 유니크 키를 대신 차지한다.
    """
    missing_key = client.post(
        f"/v1/trainer/clients/{MEMBER_ID}/memos",
        headers=_headers(trainer_token),
        json={"body": "무릎이 아파요", "source": "chat_insight"},
    )
    assert missing_key.status_code == 422

    stray_key = client.post(
        f"/v1/trainer/clients/{MEMBER_ID}/memos",
        headers=_headers(trainer_token),
        json={
            "body": "직접 작성",
            "source": "trainer",
            "insight_id": f"msg-{uuid4().hex[:8]}:discomfort",
        },
    )
    assert stray_key.status_code == 422

    unknown_source = client.post(
        f"/v1/trainer/clients/{MEMBER_ID}/memos",
        headers=_headers(trainer_token),
        json={"body": "출처 미상", "source": "legacy"},
    )
    assert unknown_source.status_code == 422


def test_unassigned_trainer_cannot_touch_member_memos(
    client, db_session, trainer_token
):
    """담당 관계가 없는 트레이너는 조회·수정·삭제 모두 404 다."""
    from app.core.security import create_access_token
    from app.models.models import User

    memo = _create_memo(
        client, trainer_token, body=f"남이 보면 안 되는 메모 {uuid4().hex[:6]}"
    )

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
            f"/v1/trainer/clients/{MEMBER_ID}/memos", headers=other_headers
        ).status_code == 404
        assert client.post(
            f"/v1/trainer/clients/{MEMBER_ID}/memos",
            headers=other_headers,
            json={"body": "몰래 쓰기"},
        ).status_code == 404
        assert client.put(
            f"/v1/trainer/clients/{MEMBER_ID}/memos/{memo['id']}",
            headers=other_headers,
            json={"body": "몰래 고치기"},
        ).status_code == 404
        assert client.delete(
            f"/v1/trainer/clients/{MEMBER_ID}/memos/{memo['id']}",
            headers=other_headers,
        ).status_code == 404
    finally:
        db_session.delete(other_trainer)
        db_session.commit()
        client.delete(
            f"/v1/trainer/clients/{MEMBER_ID}/memos/{memo['id']}",
            headers=_headers(trainer_token),
        )


def test_assigned_trainer_cannot_touch_another_members_memo(
    client, db_session, trainer_token
):
    """담당 회원이 여럿이어도 메모는 회원별로 갈린다 — 경로의 회원이 달라지면 404."""
    roster = client.get(
        "/v1/trainer/clients", headers=_headers(trainer_token)
    ).json()
    other_member = next(
        item["id"] for item in roster if item["id"] != MEMBER_ID
    )

    memo = _create_memo(
        client, trainer_token, body=f"회원 경계 확인 {uuid4().hex[:6]}"
    )
    try:
        crossed = client.put(
            f"/v1/trainer/clients/{other_member}/memos/{memo['id']}",
            headers=_headers(trainer_token),
            json={"body": "다른 회원 경로로 수정"},
        )
        assert crossed.status_code == 404
        assert memo["id"] not in [
            item["id"]
            for item in client.get(
                f"/v1/trainer/clients/{other_member}/memos",
                headers=_headers(trainer_token),
            ).json()
        ]
    finally:
        client.delete(
            f"/v1/trainer/clients/{MEMBER_ID}/memos/{memo['id']}",
            headers=_headers(trainer_token),
        )


def test_member_cannot_reach_trainer_memos(client):
    """회원 앱에서 트레이너 메모에 닿을 수 없다(범위 밖 기능)."""
    email = f"member-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register", json={"email": email, "password": "test-pw-1234", "name": "u"}
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "test-pw-1234"}
    ).json()["access_token"]
    denied = client.get(
        f"/v1/trainer/clients/{MEMBER_ID}/memos", headers=_headers(token)
    )
    assert denied.status_code == 403
