"""회원 활성/휴면 관리 상태 — 전환·멱등·소유권 경계. (#707) DB 필요.

핵심은 **휴면이 담당 관계 해제가 아니라는 것**이다. 트레이너 화면의 배지만
바뀌고 회원 앱의 담당 코치·기록·채팅은 그대로 남아야 한다.
"""
from __future__ import annotations

from uuid import uuid4

import pytest


MEMBER_ID = "user-jisu"
TRAINER_ID = "trainer-demo"


def _headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _login(client, email: str) -> str:
    response = client.post(
        "/v1/auth/login",
        data={"username": email, "password": "oncare123"},
    )
    assert response.status_code == 200, response.text
    return response.json()["access_token"]


def _roster_entry(client, token: str, member_id: str) -> dict:
    rows = client.get("/v1/trainer/clients", headers=_headers(token)).json()
    return next(row for row in rows if row["id"] == member_id)


@pytest.fixture()
def trainer_token(client) -> str:
    return _login(client, "trainer@oncare.com")


@pytest.fixture(autouse=True)
def restore_status(client, db_session):
    """관리 상태를 '활성'에서 시작시키고, 테스트가 바꾼 값을 되돌린다.

    시작 상태를 시드에 맡기면 중단된 이전 실행이 남긴 휴면 값 때문에 다음 실행이
    첫 줄부터 깨진다 — 실제로 그렇게 깨졌다.
    """
    from sqlalchemy import select

    from app.models.models import TrainerClient

    def _link(member_id: str) -> TrainerClient | None:
        # 앱 쪽 세션이 커밋한 값을 보려면 캐시를 버려야 한다 — 픽스처 세션은
        # 요청 세션과 별개다.
        db_session.expire_all()
        return db_session.scalar(
            select(TrainerClient).where(
                TrainerClient.trainer_id == TRAINER_ID,
                TrainerClient.member_id == member_id,
            )
        )

    for member_id in (MEMBER_ID,):
        link = _link(member_id)
        if link is not None:
            link.dormant = False
    db_session.commit()
    yield
    for member_id in (MEMBER_ID,):
        link = _link(member_id)
        if link is not None:
            link.dormant = False
    db_session.commit()


def test_active_to_dormant_and_back(client, trainer_token):
    """활성 → 휴면 → 활성. 로스터가 매번 서버 값을 그대로 보여 준다."""
    assert _roster_entry(client, trainer_token, MEMBER_ID)["active"] is True

    to_dormant = client.put(
        f"/v1/trainer/clients/{MEMBER_ID}/status",
        headers=_headers(trainer_token),
        json={"active": False},
    )
    assert to_dormant.status_code == 200, to_dormant.text
    assert to_dormant.json() == {"member_id": MEMBER_ID, "active": False}
    assert _roster_entry(client, trainer_token, MEMBER_ID)["active"] is False

    to_active = client.put(
        f"/v1/trainer/clients/{MEMBER_ID}/status",
        headers=_headers(trainer_token),
        json={"active": True},
    )
    assert to_active.status_code == 200, to_active.text
    assert to_active.json()["active"] is True
    assert _roster_entry(client, trainer_token, MEMBER_ID)["active"] is True


def test_repeating_the_same_status_is_idempotent(client, trainer_token):
    """같은 값을 다시 보내도 200 이고 상태가 흔들리지 않는다(연타·재시도)."""
    for _ in range(3):
        response = client.put(
            f"/v1/trainer/clients/{MEMBER_ID}/status",
            headers=_headers(trainer_token),
            json={"active": False},
        )
        assert response.status_code == 200, response.text
        assert response.json()["active"] is False
    assert _roster_entry(client, trainer_token, MEMBER_ID)["active"] is False


def test_dormant_keeps_the_assignment_and_the_member_data(
    client, trainer_token, db_session
):
    """휴면은 담당 관계 해제가 아니다 — 회원 앱의 코치도, 기록도 그대로다."""
    from sqlalchemy import select

    from app.models.models import TrainerClient

    member_token = _login(client, "jisu@oncare.com")
    coach_before = client.get("/v1/me/coach", headers=_headers(member_token))
    assert coach_before.status_code == 200, coach_before.text
    diet_before = client.get(
        f"/v1/trainer/clients/{MEMBER_ID}/diet", headers=_headers(trainer_token)
    ).json()

    client.put(
        f"/v1/trainer/clients/{MEMBER_ID}/status",
        headers=_headers(trainer_token),
        json={"active": False},
    )

    # 담당 링크는 살아 있고 dormant 만 올라간다.
    db_session.expire_all()
    link = db_session.scalar(
        select(TrainerClient).where(
            TrainerClient.trainer_id == TRAINER_ID,
            TrainerClient.member_id == MEMBER_ID,
        )
    )
    assert link is not None
    assert link.active is True
    assert link.dormant is True

    # 회원 앱은 아무 변화도 느끼지 않는다.
    coach_after = client.get("/v1/me/coach", headers=_headers(member_token))
    assert coach_after.status_code == 200, coach_after.text
    assert coach_after.json()["trainer_id"] == coach_before.json()["trainer_id"]

    # 휴면 회원의 식단·채팅도 트레이너가 그대로 볼 수 있다.
    diet_after = client.get(
        f"/v1/trainer/clients/{MEMBER_ID}/diet", headers=_headers(trainer_token)
    ).json()
    assert diet_after == diet_before
    chat = client.get(
        f"/v1/trainer/clients/{MEMBER_ID}/chat", headers=_headers(trainer_token)
    )
    assert chat.status_code == 200


def test_detached_link_cannot_be_reactivated(client, trainer_token):
    """담당이 해제된 회원은 409 — 활성으로 되돌리는 것은 담당 재배정이다.

    성공으로 응답하면 로스터는 계속 휴면인데 화면만 '저장됨'이 되어 어긋난다.
    """
    # 시드가 담당 해제 상태로 남겨 둔 과거 회원.
    detached = client.put(
        "/v1/trainer/clients/user-sungho/status",
        headers=_headers(trainer_token),
        json={"active": True},
    )
    assert detached.status_code == 409
    assert _roster_entry(client, trainer_token, "user-sungho")["active"] is False


def test_another_trainer_cannot_change_the_status(client, db_session, trainer_token):
    """담당 관계가 없는 트레이너는 404(없는 회원과 같다)."""
    from app.core.security import create_access_token
    from app.models.models import User

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
    try:
        denied = client.put(
            f"/v1/trainer/clients/{MEMBER_ID}/status",
            headers=_headers(create_access_token(other_trainer_id)),
            json={"active": False},
        )
        assert denied.status_code == 404
        # 남의 시도가 실제 상태를 건드리지 않았다.
        assert _roster_entry(client, trainer_token, MEMBER_ID)["active"] is True
    finally:
        db_session.delete(other_trainer)
        db_session.commit()


def test_unknown_member_is_rejected(client, trainer_token):
    missing = client.put(
        "/v1/trainer/clients/no-such-member/status",
        headers=_headers(trainer_token),
        json={"active": False},
    )
    assert missing.status_code == 404


def test_member_cannot_change_client_status(client):
    email = f"member-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register", json={"email": email, "password": "test-pw-1234", "name": "u"}
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "test-pw-1234"}
    ).json()["access_token"]
    denied = client.put(
        f"/v1/trainer/clients/{MEMBER_ID}/status",
        headers=_headers(token),
        json={"active": False},
    )
    assert denied.status_code == 403


def test_status_body_requires_a_boolean(client, trainer_token):
    bad = client.put(
        f"/v1/trainer/clients/{MEMBER_ID}/status",
        headers=_headers(trainer_token),
        json={},
    )
    assert bad.status_code == 422
