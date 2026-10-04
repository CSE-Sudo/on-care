"""회원측 트레이너 미러(#253) — 내 코치/받은 루틴/세션/양방향 채팅. DB 필요."""
from __future__ import annotations

from uuid import uuid4

from app.db.seed_trainer import TRAINER_NAME


def _h(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _member_tok(client) -> str:
    # user-jisu 는 시드가 demo_login_password(oncare123)로 생성 + 트레이너 링크 보유
    return client.post(
        "/v1/auth/login", data={"username": "jisu@oncare.com", "password": "oncare123"}
    ).json()["access_token"]


def _trainer_tok(client) -> str:
    return client.post(
        "/v1/auth/login", data={"username": "trainer@oncare.com", "password": "oncare123"}
    ).json()["access_token"]


def test_one_active_coach_per_member_enforced(client, db_session):
    """회원측 API 는 '현재 담당 코치 1명'을 전제하므로, 회원당 active 담당 링크는 DB
    partial unique index 로 최대 1개만 허용된다(복수 트레이너 동시 배정 방지)."""
    import pytest
    from sqlalchemy.exc import IntegrityError

    from app.models import models

    tid = f"trainer-{uuid4().hex[:8]}"
    db_session.add(models.User(
        id=tid, email=f"{tid}@oncare.com", name="T2", hashed_password="x", role="trainer",
    ))
    db_session.commit()
    try:
        # user-jisu 는 시드로 이미 active 담당(trainer-demo)이 있다. 두 번째 active 담당 추가 → 실패
        db_session.add(models.TrainerClient(
            id=f"tc-{tid}-jisu", trainer_id=tid, member_id="user-jisu", active=True,
        ))
        with pytest.raises(IntegrityError):
            db_session.commit()
        db_session.rollback()
        # 반면 휴면(active=False) 링크는 여러 개 허용된다
        db_session.add(models.TrainerClient(
            id=f"tc-{tid}-jisu", trainer_id=tid, member_id="user-jisu", active=False,
        ))
        db_session.commit()
    finally:
        db_session.rollback()
        for row in db_session.query(models.TrainerClient).filter_by(trainer_id=tid).all():
            db_session.delete(row)
        db_session.delete(db_session.get(models.User, tid))
        db_session.commit()


def test_my_coach(client):
    t = _member_tok(client)
    r = client.get("/v1/me/coach", headers=_h(t))
    assert r.status_code == 200, r.text
    body = r.json()
    # 이름을 글자로 박지 않는다 — 시드의 원본을 읽는다(#2062).
    assert body["name"] == TRAINER_NAME
    assert body["career"] == "7년"
    assert body["gym"]["name"] == "온케어짐 신촌점"
    # 트레이너가 따로 적던 문장이 아니라 회원 건강 목표다(#1818).
    assert body["goal"] == "체중 감량 · 체력 강화"


def test_my_routines_and_sessions(client):
    t = _member_tok(client)
    routines = client.get("/v1/me/coach/routines", headers=_h(t)).json()
    assert len(routines) >= 3
    assert all(rt["type"] in ("유산소", "근력", "스트레칭") for rt in routines)

    sessions = client.get("/v1/me/coach/sessions", headers=_h(t)).json()
    # 시드 스케줄에 이지수(user-jisu) 12:00 완료 세션이 있다
    assert any(s["status"] == "완료" for s in sessions)


def test_member_sessions_carry_note_only_for_done_pt(client, db_session):
    """회원 응답에는 완료된 PT 의 `note`(트레이너 피드백)만 실린다(#2515).

    예정·취소·노쇼 PT 에 적힌 글과 상담 기록(메모)은 회원에게 가지 않는다.
    트레이너 응답은 그대로 전부 보인다.
    """
    from app.models import models

    tag = uuid4().hex[:6]
    day = "2031-03-04"
    rows = {
        "done": ("1:1 PT", "완료"),
        "upcoming": ("1:1 PT", "예정"),
        "cancelled": ("1:1 PT", "취소"),
        "no_show": ("1:1 PT", "노쇼"),
        "consult_done": ("상담", "완료"),
        "consult_upcoming": ("상담", "예정"),
    }
    ids = {key: f"sched-2515-{key}-{tag}" for key in rows}
    for i, (key, (type_, status)) in enumerate(rows.items()):
        db_session.add(models.TrainerSchedule(
            id=ids[key], trainer_id="trainer-demo", member_id="user-jisu",
            date=day, time=f"{6 + i:02d}:00", client_name="이지수",
            type=type_, duration_minutes=50, status=status,
            note=f"메모-{key}-{tag}", program_json="[]", sort_order=0,
        ))
    db_session.commit()
    try:
        sessions = client.get("/v1/me/coach/sessions", headers=_h(_member_tok(client))).json()
        notes = {s["id"]: s["note"] for s in sessions if s["id"] in ids.values()}
        assert notes == {
            ids["done"]: f"메모-done-{tag}",
            ids["upcoming"]: "",
            ids["cancelled"]: "",
            ids["no_show"]: "",
            ids["consult_done"]: "",
            ids["consult_upcoming"]: "",
        }

        trainer = client.get(
            "/v1/trainer/schedule",
            params={"date": day, "member_id": "user-jisu"},
            headers=_h(_trainer_tok(client)),
        ).json()
        trainer_notes = {s["id"]: s["note"] for s in trainer if s["id"] in ids.values()}
        assert trainer_notes == {ids[key]: f"메모-{key}-{tag}" for key in rows}
    finally:
        db_session.rollback()
        for sid in ids.values():
            row = db_session.get(models.TrainerSchedule, sid)
            if row is not None:
                db_session.delete(row)
        db_session.commit()


def test_member_sessions_number_done_pt_in_order(client, db_session):
    """완료 PT 에만 담당 트레이너와의 회차가 실린다(#2697).

    회차는 날짜·시각 순으로 처음부터 센다 — 뒤 수업이 앞 수업보다 하나 크다.
    상담·예정·취소는 세지 않고 null 이다. 트레이너 응답에는 싣지 않는다.
    """
    from app.models import models

    tag = uuid4().hex[:6]
    rows = {
        "first": ("2031-05-06", "07:00", "1:1 PT", "완료"),
        "consult": ("2031-05-07", "07:00", "상담", "완료"),
        "cancelled": ("2031-05-08", "07:00", "1:1 PT", "취소"),
        "second": ("2031-05-13", "07:00", "1:1 PT", "완료"),
        "upcoming": ("2031-05-20", "07:00", "1:1 PT", "예정"),
    }
    ids = {key: f"sched-2697-{key}-{tag}" for key in rows}
    for key, (day, time, type_, status) in rows.items():
        db_session.add(models.TrainerSchedule(
            id=ids[key], trainer_id="trainer-demo", member_id="user-jisu",
            date=day, time=time, client_name="이지수",
            type=type_, duration_minutes=50, status=status,
            note="", program_json="[]", sort_order=0,
        ))
    db_session.commit()
    try:
        sessions = client.get("/v1/me/coach/sessions", headers=_h(_member_tok(client))).json()
        numbers = {s["id"]: s["session_number"] for s in sessions if s["id"] in ids.values()}
        assert numbers[ids["first"]] is not None
        assert numbers[ids["second"]] == numbers[ids["first"]] + 1
        assert numbers[ids["consult"]] is None
        assert numbers[ids["cancelled"]] is None
        assert numbers[ids["upcoming"]] is None
        # 2031 년 수업이 가장 늦은 완료 PT 라, 그 번호가 곧 완료 PT 전체 수다.
        done_pt = sum(
            1 for s in sessions if s["status"] == "완료" and s["type"] != "상담"
        )
        if len(sessions) < 100:
            assert numbers[ids["second"]] == done_pt

        trainer = client.get(
            "/v1/trainer/schedule",
            params={"date": "2031-05-13", "member_id": "user-jisu"},
            headers=_h(_trainer_tok(client)),
        ).json()
        assert all(
            s.get("session_number") is None for s in trainer if s["id"] in ids.values()
        )
    finally:
        db_session.rollback()
        for sid in ids.values():
            row = db_session.get(models.TrainerSchedule, sid)
            if row is not None:
                db_session.delete(row)
        db_session.commit()


def test_member_send_reflects_in_trainer_roster(client):
    mt = _member_tok(client)
    r = client.post(
        "/v1/me/coach/chat", json={"text": "코치님 오늘 운동 힘들었어요"}, headers=_h(mt)
    )
    assert r.status_code == 201, r.text
    assert r.json()["sender"] == "me"

    # 회원 스레드 마지막이 내 메시지(관점 me)
    thread = client.get("/v1/me/coach/chat", headers=_h(mt)).json()
    assert thread[-1]["sender"] == "me"
    assert thread[-1]["body"] == "코치님 오늘 운동 힘들었어요"

    # 트레이너 로스터 last_message 에 회원 발신이 반영(양방향)
    tt = _trainer_tok(client)
    roster = client.get("/v1/trainer/clients", headers=_h(tt)).json()
    jisu = next(c for c in roster if c["id"] == "user-jisu")
    assert jisu["last_message"] == "코치님 오늘 운동 힘들었어요"


def test_member_unread_and_read(client):
    tt = _trainer_tok(client)
    client.post(
        "/v1/trainer/clients/user-jisu/chat",
        json={"text": "내일 PT 잊지마세요"}, headers=_h(tt),
    )
    mt = _member_tok(client)
    u = client.get("/v1/me/coach/chat/unread", headers=_h(mt)).json()
    assert u["unread"] >= 1

    rd = client.post("/v1/me/coach/chat/read", headers=_h(mt))
    assert rd.status_code == 200
    u2 = client.get("/v1/me/coach/chat/unread", headers=_h(mt)).json()
    assert u2["unread"] == 0


def test_member_without_coach_404(client):
    email = f"m-{uuid4().hex[:8]}@oncare.com"
    client.post("/v1/auth/register", json={"email": email, "password": "test-pw-1234", "name": "u"})
    tok = client.post(
        "/v1/auth/login", data={"username": email, "password": "test-pw-1234"}
    ).json()["access_token"]
    # 담당 트레이너가 없는 회원
    assert client.get("/v1/me/coach", headers=_h(tok)).status_code == 404
    assert client.post(
        "/v1/me/coach/chat", json={"text": "hi"}, headers=_h(tok)
    ).status_code == 404
    # 루틴은 에러가 아니다. 예전에는 빈 목록이었지만, 지금은 담당이 없는 회원에게
    # AI 가 안전 범위에서 직접 준비해 준다(#782) — 트레이너가 배정한 것은 없다.
    routines = client.get("/v1/me/coach/routines", headers=_h(tok))
    assert routines.status_code == 200
    assert all(r["source"] == "ai" for r in routines.json())


def test_trainer_token_rejected_on_member_coach(client):
    tt = _trainer_tok(client)
    # 회원 전용 API — 트레이너 토큰은 403(CurrentUser 가 트레이너 차단)
    assert client.get("/v1/me/coach", headers=_h(tt)).status_code == 403
    assert client.get("/v1/me/coach/routines", headers=_h(tt)).status_code == 403


def test_inactive_link_member_has_no_current_coach(client):
    """비활성(휴면) 링크만 가진 회원은 현재 담당 코치가 없다(리뷰 재-#3).

    user-sungho 는 시드가 active=False 로 생성한다(트레이너 로스터엔 휴면으로 보이지만,
    회원측 '내 코치'로는 선택되지 않아야 한다).
    """
    tok = client.post(
        "/v1/auth/login", data={"username": "sungho@oncare.com", "password": "oncare123"}
    ).json()["access_token"]
    assert client.get("/v1/me/coach", headers=_h(tok)).status_code == 404
    # 휴면 링크만 있는 회원도 '담당 없음'이라, 트레이너 배정 대신 AI 자동 추천을
    # 받는다(#782). 배정된 것이 새어 나오지 않는지가 이 줄의 관심사다.
    routines = client.get("/v1/me/coach/routines", headers=_h(tok))
    assert routines.status_code == 200
    assert all(r["source"] == "ai" for r in routines.json())
    assert client.post(
        "/v1/me/coach/chat", json={"text": "안녕하세요"}, headers=_h(tok)
    ).status_code == 404


def test_member_with_a_trainer_cannot_cancel_an_assigned_routine(client):
    """담당이 있으면 취소는 트레이너의 일이다 — 404 가 아니라 403. (#1020)

    루틴은 분명히 있고 회원 화면에도 보인다. 없는 척하면 앱이 목록에서 사라진
    줄 알고 잘못 갱신한다.
    """
    member = _h(_member_tok(client))
    routines = client.get("/v1/me/coach/routines", headers=member).json()
    assert routines, "시드 회원에게 배정된 루틴이 있어야 한다"

    routine_id = routines[0]["id"]
    refused = client.delete(f"/v1/me/coach/routines/{routine_id}", headers=member)
    assert refused.status_code == 403, refused.text

    still_there = client.get("/v1/me/coach/routines", headers=member).json()
    assert routine_id in [row["id"] for row in still_there]


def test_cancelling_an_unknown_routine_is_404(client):
    """담당이 없는 회원이 없는 루틴을 지우려 하면 404. (#1020)"""
    solo = client.post(
        "/v1/auth/register",
        json={
            "email": f"solo-{uuid4().hex[:8]}@oncare.com",
            "password": "oncare123",
            "name": "혼자",
        },
    )
    assert solo.status_code in (200, 201), solo.text
    token = client.post(
        "/v1/auth/login",
        data={"username": solo.json()["email"], "password": "oncare123"},
    ).json()["access_token"]

    missing = client.delete("/v1/me/coach/routines/nope", headers=_h(token))
    assert missing.status_code == 404, missing.text


def test_accepting_a_coach_invite_requires_data_sharing_consent(client, db_session):
    """동의 없이 수락하면 400 — 수락하는 순간 트레이너가 건강 기록을 읽는다. (#1022)"""
    from app.models import models

    member = _h(_member_tok(client))
    # 시드 회원은 이미 담당이 있다. 담당이 없는 회원을 새로 만들어 초대를 건다.
    email = f"consent-{uuid4().hex[:8]}@oncare.com"
    created = client.post(
        "/v1/auth/register",
        json={"email": email, "password": "oncare123", "name": "동의"},
    )
    assert created.status_code in (200, 201), created.text
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "oncare123"}
    ).json()["access_token"]
    new_member_id = client.get("/v1/users/me", headers=_h(token)).json()["id"]

    # 시드 트레이너(trainer-demo)를 쓰지 않는다 — 담당이 하나 늘면 시드 로스터
    # 개수를 검사하는 다른 테스트가 깨진다.
    trainer_id = f"trainer-{uuid4().hex[:8]}"
    db_session.add(
        models.User(
            id=trainer_id,
            email=f"{trainer_id}@oncare.com",
            name="동의 트레이너",
            hashed_password="x",
            role="trainer",
        )
    )
    # 트레이너 행이 먼저 커밋돼야 프로필·초대의 외래키가 걸린다.
    db_session.commit()
    db_session.add(models.TrainerProfile(trainer_id=trainer_id))
    db_session.commit()

    invite_id = f"invite-{uuid4().hex[:8]}"
    db_session.add(
        models.TrainerClientInvite(
            id=invite_id,
            trainer_id=trainer_id,
            member_id=new_member_id,
            status="pending",
        )
    )
    db_session.commit()

    refused = client.post(
        f"/v1/me/coach/invites/{invite_id}/accept",
        headers=_h(token),
        json={"data_sharing_consent": False},
    )
    assert refused.status_code == 400, refused.text

    # 동의하면 연결되고, 동의 시각이 링크에 남는다.
    accepted = client.post(
        f"/v1/me/coach/invites/{invite_id}/accept",
        headers=_h(token),
        json={"data_sharing_consent": True},
    )
    assert accepted.status_code == 200, accepted.text

    link = db_session.query(models.TrainerClient).filter_by(
        member_id=new_member_id, active=True
    ).one()
    assert link.data_consent_at is not None
    assert member  # 시드 회원 토큰은 대역 준비용이다.
