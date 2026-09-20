"""채팅 이모티콘 — 24시간 이용권과 전송 규칙. (#2020) DB 필요(로컬 skip, CI 실행).

이용권은 회원이 포인트로 사는 것이고, 트레이너는 이용권 없이 보낸다. 산 뒤
24시간 동안 모든 이모티콘을 쓰고, 끝나면 **새로 보내는 것만** 막힌다 — 이미 보낸
이모티콘은 대화에 그대로 남는다.
"""
from __future__ import annotations

from datetime import timedelta
from uuid import uuid4

from sqlalchemy import select

from app.core import clock
from app.core.security import create_access_token
from app.models.models import EmotePass, HealthProfile, TrainerClient, User
from app.services import emote_service

EMOTE = "oni_owoon"


def _new_member(client, db_session, points: int = 0) -> tuple[str, dict[str, str]]:
    email = f"emo-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register", json={"email": email, "password": "pw!", "name": "u"}
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "pw!"}
    ).json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    member_id = client.get("/v1/users/me", headers=headers).json()["id"]
    db_session.expire_all()
    profile = db_session.scalar(
        select(HealthProfile).where(HealthProfile.user_id == member_id)
    )
    if profile is None:
        db_session.add(HealthProfile(user_id=member_id, activity_points=points))
    else:
        profile.activity_points = points
    db_session.commit()
    return member_id, headers


def _with_trainer(client, db_session, points: int = 0):
    """담당 트레이너가 붙은 회원. 이모티콘은 트레이너 채팅에만 있다."""
    member_id, headers = _new_member(client, db_session, points)
    trainer_id = f"trainer-{uuid4().hex[:10]}"
    db_session.add(
        User(
            id=trainer_id,
            email=f"{trainer_id}@oncare.com",
            name="김트레이너",
            hashed_password="unused",
            role="trainer",
        )
    )
    db_session.commit()
    db_session.add(
        TrainerClient(
            id=f"tc-{uuid4().hex[:12]}",
            trainer_id=trainer_id,
            member_id=member_id,
            active=True,
        )
    )
    db_session.commit()
    trainer_headers = {"Authorization": f"Bearer {create_access_token(trainer_id)}"}
    return member_id, headers, trainer_id, trainer_headers


def test_pass_costs_points_and_lasts_a_day(client, db_session):
    member_id, headers = _new_member(client, db_session, points=1000)

    before = client.get("/v1/me/emotes", headers=headers).json()
    assert before["pass"] is None
    assert before["cost"] == emote_service.COST
    assert before["hours"] == emote_service.HOURS

    bought = client.post("/v1/me/emotes/pass", json={}, headers=headers)
    assert bought.status_code == 200, bought.text
    state = bought.json()
    assert state["balance"] == 1000 - emote_service.COST
    # 남은 시간은 서버가 초로 준다 — 기기 시계가 틀어져도 어긋나지 않는다.
    assert 23 * 3600 < state["pass"]["remaining_seconds"] <= 24 * 3600


def test_buying_twice_is_blocked_while_the_pass_is_alive(client, db_session):
    _, headers = _new_member(client, db_session, points=1000)
    client.post("/v1/me/emotes/pass", json={}, headers=headers)

    again = client.post("/v1/me/emotes/pass", json={}, headers=headers)

    # 남은 시간을 두고 또 사면 같은 하루를 두 번 산 셈이 된다.
    assert again.status_code == 409
    assert client.get("/v1/me/emotes", headers=headers).json()["balance"] == 700


def test_retrying_the_same_purchase_spends_once(client, db_session):
    _, headers = _new_member(client, db_session, points=1000)
    key = uuid4().hex

    first = client.post(
        "/v1/me/emotes/pass", json={"client_request_id": key}, headers=headers
    )
    second = client.post(
        "/v1/me/emotes/pass", json={"client_request_id": key}, headers=headers
    )

    assert first.status_code == 200 and second.status_code == 200
    assert second.json()["balance"] == 1000 - emote_service.COST


def test_not_enough_points(client, db_session):
    _, headers = _new_member(client, db_session, points=10)

    r = client.post("/v1/me/emotes/pass", json={}, headers=headers)

    assert r.status_code == 400
    assert client.get("/v1/me/emotes", headers=headers).json()["pass"] is None


def test_member_needs_a_pass_to_send(client, db_session):
    _, headers, _, _ = _with_trainer(client, db_session, points=1000)

    blocked = client.post(
        "/v1/me/coach/chat", json={"text": "", "emote_id": EMOTE}, headers=headers
    )
    assert blocked.status_code == 402

    client.post("/v1/me/emotes/pass", json={}, headers=headers)
    sent = client.post(
        "/v1/me/coach/chat", json={"text": "", "emote_id": EMOTE}, headers=headers
    )

    assert sent.status_code == 201, sent.text
    assert sent.json()["emote_id"] == EMOTE
    # 본문은 이모티콘을 그리지 못하는 자리(알림·로스터)가 읽는다.
    assert sent.json()["body"]


def test_unknown_emote_is_refused(client, db_session):
    _, headers, _, _ = _with_trainer(client, db_session, points=1000)
    client.post("/v1/me/emotes/pass", json={}, headers=headers)

    r = client.post(
        "/v1/me/coach/chat", json={"text": "", "emote_id": "made_up"}, headers=headers
    )

    # 모르는 id 를 저장하면 앱이 그리지 못하는 빈 말풍선이 대화에 남는다.
    assert r.status_code == 400


def test_sent_emotes_stay_after_the_pass_ends(client, db_session):
    member_id, headers, _, _ = _with_trainer(client, db_session, points=1000)
    client.post("/v1/me/emotes/pass", json={}, headers=headers)
    client.post(
        "/v1/me/coach/chat", json={"text": "", "emote_id": EMOTE}, headers=headers
    )

    # 이용권을 어제로 되돌린다 — 스케줄러 없이 시각만 비교하므로 이것으로 끝난다.
    db_session.expire_all()
    row = db_session.scalar(select(EmotePass).where(EmotePass.user_id == member_id))
    row.expires_at = clock.now() - timedelta(minutes=1)
    db_session.commit()

    thread = client.get("/v1/me/coach/chat", headers=headers).json()
    assert [m["emote_id"] for m in thread if m["emote_id"]] == [EMOTE]
    # 새로 보내는 것만 막힌다.
    assert (
        client.post(
            "/v1/me/coach/chat", json={"text": "", "emote_id": EMOTE}, headers=headers
        ).status_code
        == 402
    )


def test_trainer_sends_without_a_pass(client, db_session):
    member_id, headers, _, trainer_headers = _with_trainer(client, db_session)

    sent = client.post(
        f"/v1/trainer/clients/{member_id}/chat",
        json={"text": "", "emote_id": "dog_love"},
        headers=trainer_headers,
    )

    # 이용권은 회원이 포인트를 쓰는 자리다 — 트레이너에게는 포인트가 없다.
    assert sent.status_code == 201, sent.text
    assert sent.json()["emote_id"] == "dog_love"
    thread = client.get("/v1/me/coach/chat", headers=headers).json()
    assert thread[-1]["emote_id"] == "dog_love"


def test_points_shop_sells_the_pass_and_hides_it_while_active(client, db_session):
    _, headers = _new_member(client, db_session, points=1000)

    items = {i["id"]: i for i in client.get("/v1/me/points/shop", headers=headers).json()["items"]}
    assert items[emote_service.ITEM_ID]["cost"] == emote_service.COST
    assert items[emote_service.ITEM_ID]["available"] is True

    # MY 탭에서도 같은 항목으로 산다.
    r = client.post(
        "/v1/me/points/exchange",
        json={"item": emote_service.ITEM_ID},
        headers=headers,
    )
    assert r.status_code in (200, 201), r.text
    assert client.get("/v1/me/emotes", headers=headers).json()["pass"] is not None

    after = {i["id"]: i for i in client.get("/v1/me/points/shop", headers=headers).json()["items"]}
    assert after[emote_service.ITEM_ID]["available"] is False
    assert after[emote_service.ITEM_ID]["blocked_reason"] == "active_pass"
