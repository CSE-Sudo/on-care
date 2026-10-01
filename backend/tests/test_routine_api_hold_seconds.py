"""단건 배정·AI 제안 생성·제안 승인 API 의 버티기 시간(`hold_seconds`). (#2753) DB 필요.

세 라우터가 요청의 `hold_seconds` 를 서비스로 넘기지 않아, `플랭크 3세트 60초`
가 세트만 남고 시간·횟수가 모두 빈 채 저장됐다. 트레이너 웹은 버티기면 `reps`
를 빼고 `hold_seconds` 만 보내므로 둘이 함께 사라진다.
"""
from __future__ import annotations

from uuid import uuid4

import pytest

MEMBER = "user-jisu"


def _tok(client) -> str:
    return client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    ).json()["access_token"]


def _member_tok(client) -> str:
    return client.post(
        "/v1/auth/login",
        data={"username": "jisu@oncare.com", "password": "oncare123"},
    ).json()["access_token"]


def _h(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture()
def trainer(client):
    token = _tok(client)
    created: list[str] = []
    yield token, created
    for rid in created:
        client.delete(
            f"/v1/trainer/clients/{MEMBER}/routines/{rid}", headers=_h(token)
        )


def _plank(**extra) -> dict:
    body = {
        "name": f"플랭크 {uuid4().hex[:6]}",
        "type": "근력",
        "sets": 3,
        "hold_seconds": 60,
        "reason": "",
    }
    body.update(extra)
    return body


def _assign(client, token, created, **body) -> dict:
    r = client.post(
        f"/v1/trainer/clients/{MEMBER}/routines",
        headers=_h(token),
        json=_plank(**body),
    )
    assert r.status_code == 201, r.text
    created.append(r.json()["id"])
    return r.json()


def _suggest(client, token, created, **body) -> dict:
    r = client.post(
        f"/v1/trainer/clients/{MEMBER}/routine-suggestions",
        headers=_h(token),
        json=_plank(**body),
    )
    assert r.status_code == 201, r.text
    created.append(r.json()["id"])
    return r.json()


def test_assign_saves_hold_seconds(client, trainer):
    token, created = trainer
    row = _assign(client, token, created)

    assert row["sets"] == 3
    assert row["hold_seconds"] == 60
    assert row["reps"] is None


def test_assigned_hold_seconds_come_back_on_the_list(client, trainer):
    token, created = trainer
    row = _assign(client, token, created, hold_seconds=45)

    listed = client.get(
        f"/v1/trainer/clients/{MEMBER}/routines", headers=_h(token)
    ).json()

    assert next(r for r in listed if r["id"] == row["id"])["hold_seconds"] == 45


def test_assigned_hold_seconds_reach_the_member(client, trainer):
    """회원 앱이 `플랭크 3세트` 만 보던 원인이 이 값이었다."""
    token, created = trainer
    row = _assign(client, token, created)

    mine = client.get("/v1/me/coach/routines", headers=_h(_member_tok(client)))

    assert mine.status_code == 200, mine.text
    assert next(r for r in mine.json() if r["id"] == row["id"])["hold_seconds"] == 60


def test_assign_with_reps_still_works(client, trainer):
    token, created = trainer
    row = _assign(client, token, created, hold_seconds=None, reps=12)

    assert row["reps"] == 12
    assert row["hold_seconds"] is None


def test_suggestion_saves_hold_seconds(client, trainer):
    token, created = trainer
    row = _suggest(client, token, created)

    assert row["hold_seconds"] == 60
    assert row["reps"] is None


def test_approve_applies_edited_hold_seconds(client, trainer):
    token, created = trainer
    row = _suggest(client, token, created, hold_seconds=None, reps=10)

    approved = client.post(
        f"/v1/trainer/routine-suggestions/{row['id']}/approve",
        headers=_h(token),
        json={"hold_seconds": 40},
    )

    assert approved.status_code == 200, approved.text
    assert approved.json()["hold_seconds"] == 40
    # 버티기로 승인하면 횟수를 비운다(#1969).
    assert approved.json()["reps"] is None


def test_approve_without_hold_seconds_keeps_the_original(client, trainer):
    """보낸 필드만 덮어쓴다 — 본문에 없으면 제안의 값을 그대로 쓴다."""
    token, created = trainer
    row = _suggest(client, token, created, hold_seconds=50)

    approved = client.post(
        f"/v1/trainer/routine-suggestions/{row['id']}/approve",
        headers=_h(token),
        json={"sets": 4},
    )

    assert approved.status_code == 200, approved.text
    assert approved.json()["sets"] == 4
    assert approved.json()["hold_seconds"] == 50
