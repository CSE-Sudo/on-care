"""채팅 이모티콘 — 하나씩 사서 7일 동안 쓰기와 전송 규칙. (#2020, #2153)
DB 필요(로컬 skip, CI 실행).

이모티콘은 회원이 포인트로 하나씩 사는 것이고, 트레이너는 사지 않고 보낸다. 산 뒤
7일 동안 그 이모티콘만 쓰고, 끝나면 **새로 보내는 것만** 막힌다 — 이미 보낸
이모티콘은 대화에 그대로 남는다.
"""
from __future__ import annotations

from datetime import timedelta
from uuid import uuid4

from sqlalchemy import select

from app.core import clock
from app.core.security import create_access_token
from app.models.models import (
    EmotePass,
    EmoteUnlock,
    HealthProfile,
    TrainerClient,
    User,
)
from app.services import emote_service

EMOTE = "oni_owoon"
OTHER = "dog_love"


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


def _unlock(client, headers, emote_id: str = EMOTE, **payload):
    return client.post(f"/v1/me/emotes/{emote_id}/unlock", json=payload, headers=headers)


def _send(client, headers, emote_id: str = EMOTE):
    return client.post(
        "/v1/me/coach/chat", json={"text": "", "emote_id": emote_id}, headers=headers
    )


def test_one_emote_costs_points_and_lasts_a_week(client, db_session):
    _, headers, _, _ = _with_trainer(client, db_session, points=1000)

    before = client.get("/v1/me/emotes", headers=headers).json()
    assert before["unlocked"] == []
    assert before["cost"] == emote_service.COST == 50
    assert before["days"] == emote_service.DAYS == 7

    bought = _unlock(client, headers)
    assert bought.status_code == 200, bought.text
    state = bought.json()
    assert state["balance"] == 1000 - emote_service.COST
    # 산 이모티콘 하나만 열린다.
    assert [u["emote_id"] for u in state["unlocked"]] == [EMOTE]
    # 남은 기간은 서버가 초로 준다 — 기기 시계가 틀어져도 어긋나지 않는다.
    week = 7 * 24 * 3600
    assert week - 3600 < state["unlocked"][0]["remaining_seconds"] <= week


def test_buying_the_same_emote_twice_is_blocked_while_alive(client, db_session):
    _, headers, _, _ = _with_trainer(client, db_session, points=1000)
    _unlock(client, headers)

    again = _unlock(client, headers)

    # 남은 기간을 두고 또 사면 같은 주를 두 번 산 셈이 된다.
    assert again.status_code == 409
    # 다른 이모티콘은 따로 산다.
    other = _unlock(client, headers, OTHER)
    assert other.status_code == 200, other.text
    assert {u["emote_id"] for u in other.json()["unlocked"]} == {EMOTE, OTHER}
    assert client.get("/v1/me/emotes", headers=headers).json()["balance"] == 900


def test_retrying_the_same_purchase_spends_once(client, db_session):
    _, headers, _, _ = _with_trainer(client, db_session, points=1000)
    key = uuid4().hex

    first = _unlock(client, headers, client_request_id=key)
    second = _unlock(client, headers, client_request_id=key)

    assert first.status_code == 200 and second.status_code == 200
    assert second.json()["balance"] == 1000 - emote_service.COST


def test_not_enough_points(client, db_session):
    _, headers, _, _ = _with_trainer(client, db_session, points=10)

    r = _unlock(client, headers)

    assert r.status_code == 400
    assert client.get("/v1/me/emotes", headers=headers).json()["unlocked"] == []


def test_unknown_emote_cannot_be_bought(client, db_session):
    _, headers, _, _ = _with_trainer(client, db_session, points=1000)

    r = _unlock(client, headers, "made_up")

    assert r.status_code == 404
    assert client.get("/v1/me/emotes", headers=headers).json()["balance"] == 1000


def test_member_sends_only_the_emotes_they_bought(client, db_session):
    _, headers, _, _ = _with_trainer(client, db_session, points=1000)

    assert _send(client, headers).status_code == 402

    _unlock(client, headers)
    sent = _send(client, headers)

    assert sent.status_code == 201, sent.text
    assert sent.json()["emote_id"] == EMOTE
    # 본문은 이모티콘을 그리지 못하는 자리(알림·로스터)가 읽는다.
    assert sent.json()["body"]
    # 사지 않은 이모티콘은 여전히 막힌다.
    assert _send(client, headers, OTHER).status_code == 402


def test_unknown_emote_is_refused(client, db_session):
    _, headers, _, _ = _with_trainer(client, db_session, points=1000)
    _unlock(client, headers)

    r = _send(client, headers, "made_up")

    # 모르는 id 를 저장하면 앱이 그리지 못하는 빈 말풍선이 대화에 남는다.
    assert r.status_code == 400


def test_sent_emotes_stay_after_the_week_ends(client, db_session):
    member_id, headers, _, _ = _with_trainer(client, db_session, points=1000)
    _unlock(client, headers)
    _send(client, headers)

    # 기간을 방금 전으로 되돌린다 — 스케줄러 없이 시각만 비교하므로 이것으로 끝난다.
    db_session.expire_all()
    row = db_session.scalar(select(EmoteUnlock).where(EmoteUnlock.user_id == member_id))
    row.expires_at = clock.now() - timedelta(minutes=1)
    db_session.commit()

    thread = client.get("/v1/me/coach/chat", headers=headers).json()
    assert [m["emote_id"] for m in thread if m["emote_id"]] == [EMOTE]
    # 새로 보내는 것만 막히고, 끝난 이모티콘은 다시 산다.
    assert _send(client, headers).status_code == 402
    assert client.get("/v1/me/emotes", headers=headers).json()["unlocked"] == []
    assert _unlock(client, headers).status_code == 200


def test_pass_bought_before_the_change_still_opens_every_emote(client, db_session):
    """바뀌기 전에 산 24시간 이용권은 남은 시간 동안 모든 이모티콘을 쓴다."""
    member_id, headers, _, _ = _with_trainer(client, db_session, points=1000)
    db_session.add(
        EmotePass(
            id=f"emp-{uuid4().hex[:12]}",
            user_id=member_id,
            cost=300,
            expires_at=clock.now() + timedelta(hours=5),
        )
    )
    db_session.commit()

    state = client.get("/v1/me/emotes", headers=headers).json()
    assert {u["emote_id"] for u in state["unlocked"]} == set(emote_service.EMOTE_IDS)
    assert all(u["remaining_seconds"] <= 5 * 3600 for u in state["unlocked"])
    assert _send(client, headers, OTHER).status_code == 201
    # 이용권으로 쓰고 있는 동안에는 따로 사지 않는다.
    assert _unlock(client, headers).status_code == 409


def test_trainer_sends_without_buying(client, db_session):
    member_id, headers, _, trainer_headers = _with_trainer(client, db_session)

    sent = client.post(
        f"/v1/trainer/clients/{member_id}/chat",
        json={"text": "", "emote_id": "dog_love"},
        headers=trainer_headers,
    )

    # 이모티콘 구매는 회원이 포인트를 쓰는 자리다 — 트레이너에게는 포인트가 없다.
    assert sent.status_code == 201, sent.text
    assert sent.json()["emote_id"] == "dog_love"
    thread = client.get("/v1/me/coach/chat", headers=headers).json()
    assert thread[-1]["emote_id"] == "dog_love"


def test_points_shop_no_longer_sells_emotes(client, db_session):
    """무엇을 사는지는 채팅의 이모티콘 창에서 봐야 알 수 있다(#2153)."""
    _, headers, _, _ = _with_trainer(client, db_session, points=1000)

    items = client.get("/v1/me/points/shop", headers=headers).json()["items"]
    assert "emote_pass_24h" not in {i["id"] for i in items}
    r = client.post(
        "/v1/me/points/exchange", json={"item": "emote_pass_24h"}, headers=headers
    )
    assert r.status_code == 404
    assert client.get("/v1/me/emotes", headers=headers).json()["balance"] == 1000


def test_member_without_a_trainer_cannot_buy(client, db_session):
    """이모티콘은 트레이너 채팅에만 있다 — 담당이 없으면 사지 못한다(#2142)."""
    _, headers = _new_member(client, db_session, points=1000)

    assert _unlock(client, headers).status_code == 409
    assert client.get("/v1/me/emotes", headers=headers).json()["balance"] == 1000


def test_spending_shows_in_points_history(client, db_session):
    _, headers, _, _ = _with_trainer(client, db_session, points=1000)
    _unlock(client, headers)

    items = client.get("/v1/me/points/history", headers=headers).json()["items"]

    assert (items[0]["reason"], items[0]["delta"]) == (
        emote_service.REASON_EMOTE_UNLOCK,
        -emote_service.COST,
    )
