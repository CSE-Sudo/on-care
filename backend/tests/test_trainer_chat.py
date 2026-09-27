"""트레이너 채팅 + 루틴 배정(#251). DB 필요(로컬 skip, CI 실행)."""
from __future__ import annotations

from datetime import datetime as _datetime

import pytest


@pytest.fixture(autouse=True)
def _reset_seeded_threads(db_session):
    """시드 회원의 스레드를 매 테스트마다 시드 상태로 되돌린다. (#484)

    `build_chat_thread` 는 최신 `limit`(기본 50)건만 준다. 그런데 메시지를 보내는
    테스트가 시드 회원 스레드에 남긴 메시지를 지우지 않아, 실행을 거듭할수록 창이
    테스트 잔여물로 채워졌다. 결국 시드 첫 메시지가 창 밖으로 밀려나
    `test_chat_thread_seeded_and_sender_mapped` 가 간헐적으로 깨졌다 — 한 로컬
    DB 에서는 `user-jisu` 스레드가 89건(시드 3건, 잔여물 86건)까지 불어 있었다.

    CI 는 매 실행마다 DB 가 새것이라 초록불이었고, 그래서 로컬에서 반복 실행하는
    사람에게만 걸렸다.

    시드 행은 결정론적 id(`seed-chat-…` / `seed-routine-…`)를 갖는다. 그 밖의 것만
    지우므로 시드는 그대로 남는다. **테스트 전에도** 지우는 이유: 이미 잔여물이
    쌓인 DB 에서도 첫 실행부터 통과해야 한다.

    루틴도 같은 방식으로 누적된다(한 로컬 DB 에서 `user-jisu` 55건). 지금은 단언이
    최신 항목만 보지만, 목록에 limit 이 생기면 같은 방식으로 깨진다.
    """
    _purge(db_session)
    yield
    _purge(db_session)


def _purge(db_session) -> None:
    """시드 회원의 비시드 채팅·루틴을 지운다.

    범위를 **시드 회원(`_MEMBERS`)으로 한정**한다. `trainer_id` 만 걸면 페이지네이션
    테스트가 즉석에서 만드는 회원(`pgmember-…`)처럼 다른 테스트가 자기 책임으로
    만들고 지우는 데이터까지 함께 지운다 — 그건 이 픽스처가 관여할 범위가 아니다
    (리뷰).
    """
    from app.db.seed_trainer import _MEMBERS, TRAINER_ID
    from app.models.models import ChatMessage, TrainerRoutine

    seeded_members = [member_id for member_id, *_ in _MEMBERS]

    db_session.rollback()
    db_session.query(ChatMessage).filter(
        ChatMessage.trainer_id == TRAINER_ID,
        ChatMessage.member_id.in_(seeded_members),
        ~ChatMessage.id.like("seed-chat-%"),
    ).delete(synchronize_session=False)
    db_session.query(TrainerRoutine).filter(
        TrainerRoutine.trainer_id == TRAINER_ID,
        TrainerRoutine.member_id.in_(seeded_members),
        ~TrainerRoutine.id.like("seed-routine-%"),
    ).delete(synchronize_session=False)
    db_session.commit()


def _tok(client) -> str:
    return client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    ).json()["access_token"]


def _h(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def test_chat_thread_seeded_and_sender_mapped(client):
    token = _tok(client)
    r = client.get("/v1/trainer/clients/user-jisu/chat", headers=_h(token))
    assert r.status_code == 200, r.text
    msgs = r.json()
    assert len(msgs) >= 3
    # 오래된→최신, sender 는 trainer|client 로 노출(member→client 매핑)
    assert msgs[0]["sender"] == "trainer"
    assert any(m["sender"] == "client" for m in msgs)
    assert all(m["sender"] in ("trainer", "client") for m in msgs)


def test_send_message_reflects_in_thread_and_roster(client):
    token = _tok(client)
    r = client.post(
        "/v1/trainer/clients/user-jisu/chat",
        json={"text": "  다음 주 루틴 보냈어요!  "},
        headers=_h(token),
    )
    assert r.status_code == 201, r.text
    assert r.json()["sender"] == "trainer"
    assert r.json()["body"] == "다음 주 루틴 보냈어요!"  # trim 확인

    # 스레드 마지막에 반영
    thread = client.get("/v1/trainer/clients/user-jisu/chat", headers=_h(token)).json()
    assert thread[-1]["body"] == "다음 주 루틴 보냈어요!"

    # 로스터 last_message 가 방금 보낸 메시지로 갱신(자동 반영)
    roster = client.get("/v1/trainer/clients", headers=_h(token)).json()
    jisu = next(c for c in roster if c["id"] == "user-jisu")
    assert jisu["last_message"] == "다음 주 루틴 보냈어요!"
    # 상대 시각 라벨이 아닌 실제 정렬 키를 로스터가 내려 준다.
    assert _datetime.fromisoformat(jisu["last_message_at"]) == _datetime.fromisoformat(
        thread[-1]["created_at"]
    )


def test_empty_message_rejected(client):
    token = _tok(client)
    r = client.post(
        "/v1/trainer/clients/user-jisu/chat", json={"text": "   "}, headers=_h(token)
    )
    assert r.status_code == 400


def test_unread_and_mark_read(client, db_session):
    from datetime import datetime, timezone
    from uuid import uuid4

    from app.db.seed_trainer import TRAINER_ID
    from app.models.models import ChatMessage

    # 담당 중인 회원으로 본다 — 시드의 user-sungho 는 해제된 과거 회원이라
    # 읽음 처리 자체가 404 다(#2281).
    cid = f"chat-unreadtest-{uuid4().hex[:6]}"
    db_session.add(ChatMessage(
        id=cid, trainer_id=TRAINER_ID, member_id="user-hayun",
        sender="member", body="확인 부탁드려요", created_at=datetime.now(timezone.utc),
    ))
    db_session.commit()
    try:
        token = _tok(client)
        unread = client.get("/v1/trainer/chat/unread", headers=_h(token)).json()
        assert unread.get("user-hayun", 0) >= 1

        rd = client.post("/v1/trainer/clients/user-hayun/chat/read", headers=_h(token))
        assert rd.status_code == 200
        assert rd.json()["marked_read"] >= 1

        unread2 = client.get("/v1/trainer/chat/unread", headers=_h(token)).json()
        assert unread2.get("user-hayun", 0) == 0
    finally:
        db_session.query(ChatMessage).filter(ChatMessage.id == cid).delete()
        db_session.commit()


def test_routines_seeded_and_assign_updates_last_routine(client):
    token = _tok(client)
    # 시드된 AI 루틴
    r = client.get("/v1/trainer/clients/user-jisu/routines", headers=_h(token))
    assert r.status_code == 200, r.text
    routines = r.json()
    assert len(routines) >= 3
    assert all(rt["type"] in ("유산소", "근력", "스트레칭") for rt in routines)
    assert any(rt["source"] == "ai" for rt in routines)

    # 트레이너가 직접 배정
    a = client.post(
        "/v1/trainer/clients/user-jisu/routines",
        json={"name": "코어 서킷", "minutes": 12, "type": "근력", "reason": "복부 안정화"},
        headers=_h(token),
    )
    assert a.status_code == 201, a.text
    assert a.json()["source"] == "trainer"

    after = client.get("/v1/trainer/clients/user-jisu/routines", headers=_h(token)).json()
    assert any(rt["name"] == "코어 서킷" for rt in after)

    # 로스터 last_routine 이 "오늘"로 갱신(방금 배정)
    roster = client.get("/v1/trainer/clients", headers=_h(token)).json()
    jisu = next(c for c in roster if c["id"] == "user-jisu")
    assert jisu["last_routine"] == "오늘"


def test_chat_routine_ownership_and_role(client):
    token = _tok(client)
    # 미담당 회원 → 404
    assert client.get("/v1/trainer/clients/user-nobody/chat", headers=_h(token)).status_code == 404
    assert client.get(
        "/v1/trainer/clients/user-nobody/routines", headers=_h(token)
    ).status_code == 404

    # 회원 계정 → 403
    from uuid import uuid4
    email = f"m-{uuid4().hex[:8]}@oncare.com"
    client.post("/v1/auth/register", json={"email": email, "password": "test-pw-1234", "name": "u"})
    mtok = client.post(
        "/v1/auth/login", data={"username": email, "password": "test-pw-1234"}
    ).json()["access_token"]
    assert client.get("/v1/trainer/clients/user-jisu/chat", headers=_h(mtok)).status_code == 403


def test_routine_assign_input_validation(client):
    token = _tok(client)
    url = "/v1/trainer/clients/user-jisu/routines"
    base = {"name": "테스트 루틴", "minutes": 10, "type": "근력", "reason": "x"}
    # 잘못된 type / source → 422 (DB 500 아님)
    assert client.post(url, json={**base, "type": "파워"}, headers=_h(token)).status_code == 422
    assert client.post(url, json={**base, "source": "bot"}, headers=_h(token)).status_code == 422
    # minutes 음수/과대 → 422
    assert client.post(url, json={**base, "minutes": -5}, headers=_h(token)).status_code == 422
    assert client.post(url, json={**base, "minutes": 9999}, headers=_h(token)).status_code == 422
    # name 100자 초과 / reason 200자 초과 → 422
    assert client.post(url, json={**base, "name": "가" * 101}, headers=_h(token)).status_code == 422
    assert client.post(url, json={**base, "reason": "가" * 201}, headers=_h(token)).status_code == 422
    # 정상 입력은 201
    assert client.post(url, json=base, headers=_h(token)).status_code == 201


def test_chat_thread_is_paginated(client, db_session):
    from datetime import datetime, timedelta, timezone

    from app.db.seed_trainer import TRAINER_ID
    from app.models.models import ChatMessage

    # 오래된 메시지 60건 삽입(하루 전, 초 간격)
    base = datetime.now(timezone.utc) - timedelta(days=1)
    ids = [f"chat-page-{i}" for i in range(60)]
    for i, cid in enumerate(ids):
        db_session.add(ChatMessage(
            id=cid, trainer_id=TRAINER_ID, member_id="user-7d4e9a2c5f18",
            sender="member", body=f"m{i}", created_at=base + timedelta(seconds=i),
        ))
    db_session.commit()
    try:
        token = _tok(client)
        # 기본 제한 50 이하 — 오래된 메시지가 60건 있어도 한 번에 다 오지 않는다
        msgs = client.get("/v1/trainer/clients/user-7d4e9a2c5f18/chat", headers=_h(token)).json()
        assert len(msgs) <= 50
        # limit 쿼리 존중
        r10 = client.get("/v1/trainer/clients/user-7d4e9a2c5f18/chat?limit=10", headers=_h(token))
        assert len(r10.json()) == 10
        # 잘못된 before → 422
        bad = client.get("/v1/trainer/clients/user-7d4e9a2c5f18/chat?before=notadate", headers=_h(token))
        assert bad.status_code == 422
    finally:
        db_session.query(ChatMessage).filter(
            ChatMessage.id.in_(ids)
        ).delete(synchronize_session=False)
        db_session.commit()


def test_chat_pagination_two_pages_contiguous(client, db_session):
    """(created_at, id) 복합 커서로 연속 페이지 조회 시 중복·누락 없이 전체가 이어진다."""
    from datetime import datetime, timedelta, timezone
    from uuid import uuid4

    from app.db.seed_trainer import TRAINER_ID
    from app.models.models import ChatMessage, TrainerClient, User

    mid = f"pgmember-{uuid4().hex[:6]}"
    db_session.add(User(id=mid, email=f"{mid}@oncare.com", name="페이지회원", role="member"))
    db_session.flush()
    db_session.add(TrainerClient(
        id=f"tc-pg-{mid}", trainer_id=TRAINER_ID, member_id=mid,
        goal="x", active=True, sort_order=999,
    ))
    base = datetime(2021, 1, 1, tzinfo=timezone.utc)
    ids = [f"pgc-{mid}-{i:03d}" for i in range(60)]
    for i, cid in enumerate(ids):
        db_session.add(ChatMessage(
            id=cid, trainer_id=TRAINER_ID, member_id=mid, sender="member",
            body=f"m{i}", created_at=base + timedelta(minutes=i // 2),  # 짝수쌍은 같은 created_at
        ))
    db_session.commit()
    try:
        token = _tok(client)
        url = f"/v1/trainer/clients/{mid}/chat"
        p1 = client.get(url, params={"limit": 25}, headers=_h(token)).json()
        assert len(p1) == 25
        # 이전 페이지 커서 = 이번 페이지 가장 오래된 메시지(p1[0]) 의 (created_at, id).
        # params= 로 넘겨야 타임존 오프셋 '+' 가 올바로 인코딩된다.
        cur = p1[0]
        p2 = client.get(
            url,
            params={"limit": 25, "before": cur["created_at"], "before_id": cur["id"]},
            headers=_h(token),
        ).json()
        assert len(p2) == 25
        cur2 = p2[0]
        p3 = client.get(
            url,
            params={"limit": 25, "before": cur2["created_at"], "before_id": cur2["id"]},
            headers=_h(token),
        ).json()
        assert len(p3) == 10  # 60 = 25 + 25 + 10

        got = [m["id"] for m in p3] + [m["id"] for m in p2] + [m["id"] for m in p1]
        assert len(set(got)) == 60          # 중복 없음
        assert set(got) == set(ids)          # 누락 없음
    finally:
        db_session.query(ChatMessage).filter(ChatMessage.member_id == mid).delete()
        db_session.query(TrainerClient).filter(TrainerClient.member_id == mid).delete()
        db_session.query(User).filter(User.id == mid).delete()
        db_session.commit()
