"""가입한 트레이너가 상담을 받는 이음매. (#485)

#467(상담 승인)과 #475(트레이너 가입)는 각각 테스트가 있지만, 두 기능이 만나는
지점은 어디에서도 확인되지 않았다. 상담 테스트가 쓰는 트레이너는 가입
엔드포인트를 통과한 계정이 아니라 DB 에 직접 넣은 행이고, 가입 테스트는
`/trainer/me` 가 200 을 주는 것까지만 본다.

깨질 수 있는 실제 경로가 있다: 인박스 조회는 `TrainerProfile.gym_id` 로 헬스장
문의를 찾는데, 가입이 그 값을 채우는 방식이 바뀌면 인박스가 조용히 빈다. 양쪽
테스트는 그대로 통과한다.

**의도적으로 이음매만 본다.** 각 단계는 이미 단위 테스트가 덮고 있어, 전체를 다시
검증하는 큰 테스트는 중복이 되고 깨졌을 때 원인을 가리키지 못한다.

DB 가 필요하므로 로컬에서는 skip 되고 CI(Postgres) 에서 실행된다.
"""
from __future__ import annotations

from datetime import timedelta
from uuid import uuid4

import pytest

from app.core import clock
from app.models.models import (
    ConsultationRequest,
    MemberGym,
    Notification,
    Place,
    TrainerClient,
    TrainerInviteCode,
    TrainerProfile,
    User,
)

EMAIL_PREFIX = "seam-test-"
PLACE_PREFIX = "seam-place-"
CODE_PREFIX = "SEAMTEST"
PASSWORD = "seam-pw-1234"


@pytest.fixture(autouse=True)
def _cleanup(db_session):
    yield
    db_session.rollback()
    user_ids = [
        row[0]
        for row in db_session.query(User.id)
        .filter(User.email.like(f"{EMAIL_PREFIX}%"))
        .all()
    ]
    db_session.query(TrainerInviteCode).filter(
        TrainerInviteCode.code.like(f"{CODE_PREFIX}%")
    ).delete(synchronize_session=False)
    if user_ids:
        db_session.query(ConsultationRequest).filter(
            (ConsultationRequest.member_id.in_(user_ids))
            | (ConsultationRequest.trainer_id.in_(user_ids))
            | (ConsultationRequest.decided_by.in_(user_ids))
        ).delete(synchronize_session=False)
        db_session.query(TrainerClient).filter(
            (TrainerClient.trainer_id.in_(user_ids))
            | (TrainerClient.member_id.in_(user_ids))
        ).delete(synchronize_session=False)
        db_session.query(Notification).filter(
            Notification.user_id.in_(user_ids)
        ).delete(synchronize_session=False)
        db_session.query(MemberGym).filter(
            MemberGym.member_id.in_(user_ids)
        ).delete(synchronize_session=False)
        db_session.query(TrainerProfile).filter(
            TrainerProfile.trainer_id.in_(user_ids)
        ).delete(synchronize_session=False)
        db_session.query(User).filter(User.id.in_(user_ids)).delete(
            synchronize_session=False
        )
    db_session.query(Place).filter(Place.id.like(f"{PLACE_PREFIX}%")).delete(
        synchronize_session=False
    )
    db_session.commit()


def _auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _login(client, email: str) -> str:
    response = client.post(
        "/v1/auth/login", data={"username": email, "password": PASSWORD}
    )
    assert response.status_code == 200, response.text
    return response.json()["access_token"]


def _gym(db_session) -> Place:
    place = Place(
        id=f"{PLACE_PREFIX}{uuid4().hex[:10]}",
        name="이음매 테스트 헬스장",
        category="fitness",
        address="서울",
    )
    db_session.add(place)
    db_session.commit()
    return place


def _invite_code(db_session, gym: Place) -> str:
    code = TrainerInviteCode(
        code=f"{CODE_PREFIX}{uuid4().hex[:8].upper()}", gym_id=gym.id
    )
    db_session.add(code)
    db_session.commit()
    return code.code


def _sign_up_trainer(client, code: str) -> tuple[str, str]:
    """가입 엔드포인트로 트레이너를 만든다. (id, token)

    DB 직접 삽입이 아니라 이 경로를 쓰는 것이 이 테스트의 핵심이다.
    """
    email = f"{EMAIL_PREFIX}trainer-{uuid4().hex[:10]}@oncare.com"
    response = client.post(
        "/v1/auth/trainer/register",
        json={
            "email": email,
            "password": PASSWORD,
            "name": "가입 트레이너",
            "invite_code": code,
        },
    )
    assert response.status_code == 201, response.text
    return response.json()["id"], _login(client, email)


def _member(client) -> tuple[str, str]:
    email = f"{EMAIL_PREFIX}member-{uuid4().hex[:10]}@oncare.com"
    response = client.post(
        "/v1/auth/register",
        json={"email": email, "password": PASSWORD, "name": "이음매 회원"},
    )
    assert response.status_code == 201, response.text
    return response.json()["id"], _login(client, email)


def _request_consultation(client, token: str, trainer_id: str) -> str:
    """회원이 그 트레이너의 빈 자리를 골라 상담을 신청한다. (#1873)"""
    from tests.test_consultation_decision import _open_slot

    response = client.post(
        "/v1/consultations",
        headers=_auth(token),
        json={
            "trainer_id": trainer_id,
            "exercise_goal": "strength",
            "health_purpose_type": "general",
            "health_purpose_detail": None,
            "slot_id": _open_slot(trainer_id).id,
            "message": "상담 부탁드립니다.",
            "data_sharing_consent": True,
        },
    )
    assert response.status_code == 201, response.text
    return response.json()["id"]


def test_a_signed_up_trainer_can_receive_and_accept_a_consultation(
    client, db_session
):
    """가입 → 상담 요청 → 인박스 → 승인 → 로스터.

    여기서 확인하는 것은 각 단계의 동작이 아니라 **초대 코드가 채운 소속이 상담
    대상 조건과 실제로 이어지는가**다. 상담은 헬스장 소속 트레이너에게만 걸 수
    있어(`_validate_target`), 그 연결이 끊기면 새로 가입한 트레이너는 회원이 고를
    수 없는 사람이 되고 양쪽 단위 테스트는 모두 통과한다.
    """
    gym = _gym(db_session)
    code = _invite_code(db_session, gym)

    trainer_id, trainer_token = _sign_up_trainer(client, code)
    member_id, member_token = _member(client)
    consultation_id = _request_consultation(client, member_token, trainer_id)

    inbox = client.get("/v1/trainer/consultations", headers=_auth(trainer_token))
    assert inbox.status_code == 200, inbox.text
    assert consultation_id in {item["id"] for item in inbox.json()}, (
        "가입한 트레이너의 인박스에 자기 앞으로 온 요청이 오지 않았다"
    )

    accepted = client.post(
        f"/v1/trainer/consultations/{consultation_id}/accept",
        headers=_auth(trainer_token),
        json={},
    )
    assert accepted.status_code == 200, accepted.text
    assert accepted.json()["decided_by"] == trainer_id

    roster = client.get("/v1/trainer/clients", headers=_auth(trainer_token))
    assert roster.status_code == 200, roster.text
    assert member_id in {c["id"] for c in roster.json()}


def test_a_signed_up_trainer_sees_only_their_own_requests(client, db_session):
    """가입한 트레이너의 인박스가 자기 앞으로 온 요청으로 좁혀져 있다.

    위 테스트만 있으면 "인박스가 모든 요청을 준다"는 잘못된 구현도 통과한다.
    같은 헬스장 동료에게 간 요청까지 보이면 안 된다.
    """
    gym = _gym(db_session)
    _, trainer_token = _sign_up_trainer(client, _invite_code(db_session, gym))
    other_trainer_id, _ = _sign_up_trainer(client, _invite_code(db_session, gym))
    _, member_token = _member(client)

    foreign_id = _request_consultation(client, member_token, other_trainer_id)

    inbox = client.get("/v1/trainer/consultations", headers=_auth(trainer_token))

    assert inbox.status_code == 200, inbox.text
    assert foreign_id not in {item["id"] for item in inbox.json()}
