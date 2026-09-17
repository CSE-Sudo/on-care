from __future__ import annotations

from datetime import datetime, timedelta, timezone
from uuid import uuid4

import pytest

from app.core import clock
from app.models.models import ConsultationRequest, Place, TrainerProfile, User
from app.schemas.consultation_api import ConsultationOut

TEST_EMAIL_PREFIX = "consult-test-"
TEST_PLACE_PREFIX = "consult-place-"


@pytest.fixture(autouse=True)
def _cleanup_consultation_data(db_session):
    yield
    db_session.rollback()
    user_ids = [
        row[0]
        for row in db_session.query(User.id)
        .filter(User.email.like(f"{TEST_EMAIL_PREFIX}%"))
        .all()
    ]
    if user_ids:
        db_session.query(ConsultationRequest).filter(
            (ConsultationRequest.member_id.in_(user_ids))
            | (ConsultationRequest.trainer_id.in_(user_ids))
        ).delete(synchronize_session=False)
        db_session.query(TrainerProfile).filter(
            TrainerProfile.trainer_id.in_(user_ids)
        ).delete(synchronize_session=False)
        db_session.query(User).filter(User.id.in_(user_ids)).delete(
            synchronize_session=False
        )
    db_session.query(Place).filter(
        Place.id.like(f"{TEST_PLACE_PREFIX}%")
    ).delete(synchronize_session=False)
    db_session.commit()


def _auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _register_member(client) -> tuple[str, str]:
    suffix = uuid4().hex[:10]
    email = f"{TEST_EMAIL_PREFIX}{suffix}@oncare.com"
    response = client.post(
        "/v1/auth/register",
        json={"email": email, "password": "pw!", "name": "상담 테스트 회원"},
    )
    assert response.status_code == 201, response.text
    token_response = client.post(
        "/v1/auth/login",
        data={"username": email, "password": "pw!"},
    )
    assert token_response.status_code == 200, token_response.text
    return response.json()["id"], token_response.json()["access_token"]


def _create_place(db_session, *, category: str = "fitness") -> Place:
    suffix = uuid4().hex[:10]
    place = Place(
        id=f"{TEST_PLACE_PREFIX}{suffix}",
        name="상담 테스트 헬스장",
        category=category,
        address="서울",
    )
    db_session.add(place)
    db_session.commit()
    return place


def _create_trainer(
    db_session,
    *,
    role: str = "trainer",
    active: bool = True,
    with_profile: bool = True,
    with_gym: bool = True,
    gym_category: str = "fitness",
) -> User:
    suffix = uuid4().hex[:10]
    gym = (
        _create_place(db_session, category=gym_category)
        if with_profile and with_gym
        else None
    )
    trainer = User(
        id=f"consult-trainer-{suffix}",
        email=f"{TEST_EMAIL_PREFIX}trainer-{suffix}@oncare.com",
        name="상담 테스트 트레이너",
        role=role,
        is_active=active,
    )
    db_session.add(trainer)
    db_session.flush()
    if with_profile:
        db_session.add(
            TrainerProfile(
                trainer_id=trainer.id,
                gym_id=gym.id if gym is not None else None,
            )
        )
    db_session.commit()
    return trainer


def _payload(*, trainer_id: str | None = None) -> dict:
    """상담 요청 본문. 대상은 트레이너 한 사람뿐이라 trainer_id 만 받는다.

    `target_type` 은 서버 기본값(`trainer`)에 맡긴다 — 값이 하나뿐이라 클라이언트가
    보낼 이유가 없고, 보내지 않아도 만들어져야 한다.
    """
    return {
        "trainer_id": trainer_id,
        # 건강 목표 여덟 종 중 하나. 없앤 `health` 는 더 이상 받지 않는다(#1992).
        "exercise_goal": "fitness",
        "health_purpose_type": "general",
        "health_purpose_detail": "  건강 습관 개선  ",
        "preferred_date": (clock.today() + timedelta(days=1)).isoformat(),
        "preferred_time_slot": "14:30",
        "message": "  상담을 받고 싶습니다.  ",
        "data_sharing_consent": True,
    }


def test_create_consultation_sets_server_fields(client, db_session):
    member_id, token = _register_member(client)
    trainer = _create_trainer(db_session)
    payload = _payload(trainer_id=trainer.id)
    payload["preferred_date"] = clock.today().isoformat()

    response = client.post(
        "/v1/consultations",
        headers=_auth(token),
        json=payload,
    )

    assert response.status_code == 201, response.text
    body = response.json()
    assert body["id"].startswith("consult-")
    assert body["member_id"] == member_id
    # 대상은 언제나 트레이너 한 사람이다 — 응답에 헬스장 자리는 없다.
    assert body["trainer_id"] == trainer.id
    assert "gym_id" not in body
    assert "target_type" not in body
    assert body["status"] == "pending"
    assert body["health_purpose_detail"] == "건강 습관 개선"
    assert body["message"] == "상담을 받고 싶습니다."
    assert body["created_at"]
    assert body["updated_at"]


def test_gym_target_is_no_longer_accepted(client, db_session):
    """헬스장 전체로 보내는 요청은 폐지됐다 — 옛 본문은 422 로 막힌다.

    막지 않으면 소속 트레이너 전원의 인박스에 뜨는 요청이 다시 생기고, 회원은
    자기가 누구에게 상담을 걸었는지 모르는 채로 남는다.
    """
    _, token = _register_member(client)
    gym = _create_place(db_session)
    payload = _payload()
    payload["target_type"] = "gym"
    payload["gym_id"] = gym.id
    del payload["trainer_id"]

    response = client.post(
        "/v1/consultations", headers=_auth(token), json=payload
    )

    assert response.status_code == 422, response.text


@pytest.mark.parametrize("status", ["pending", "accepted", "rejected"])
def test_client_cannot_set_consultation_status(client, db_session, status):
    _, token = _register_member(client)
    trainer = _create_trainer(db_session)
    payload = _payload(trainer_id=trainer.id)
    payload["status"] = status

    response = client.post(
        "/v1/consultations", headers=_auth(token), json=payload
    )

    assert response.status_code == 422


def test_consultation_out_validates_orm_instance():
    """ORM 인스턴스가 응답 스키마로 그대로 검증된다.

    필드가 어긋나면 목록·상세가 통째로 500 이 된다.
    """
    now = datetime.now(timezone.utc)
    consultation = ConsultationRequest(
        id="consult-orm-validation",
        member_id="user-orm-validation",
        target_type="trainer",
        trainer_id="trainer-orm-validation",
        exercise_goal="health",
        health_purpose_type="general",
        health_purpose_detail=None,
        preferred_date=clock.today().isoformat(),
        preferred_time_slot="flexible",
        message=None,
        status="pending",
        created_at=now,
        updated_at=now,
    )

    response = ConsultationOut.model_validate(consultation)

    assert response.id == consultation.id
    assert response.preferred_date == clock.today()


def test_past_preferred_date_is_rejected(client, db_session):
    _, token = _register_member(client)
    trainer = _create_trainer(db_session)
    payload = _payload(trainer_id=trainer.id)
    payload["preferred_date"] = (clock.today() - timedelta(days=1)).isoformat()

    response = client.post(
        "/v1/consultations", headers=_auth(token), json=payload
    )

    assert response.status_code == 422


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("target_type", "hospital"),
        ("exercise_goal", "bulk"),
        # 없앤 `건강 관리`. 여덟 목표 중 하나로 옮길 수 없어 그 회원만 건강
        # 목표가 비어 있었다 — 새 신청으로 다시 들어오지 않게 막는다(#1992).
        ("exercise_goal", "health"),
        ("health_purpose_type", "sleep"),
        ("preferred_time_slot", "night"),
        # 시각 없는 요청은 승인해도 잡을 시간이 없다 — 입력에서 막는다(#1587).
        ("preferred_time_slot", "flexible"),
    ],
)
def test_invalid_limited_value_is_rejected(
    client, db_session, field: str, value: str
):
    _, token = _register_member(client)
    trainer = _create_trainer(db_session)
    payload = _payload(trainer_id=trainer.id)
    payload[field] = value

    response = client.post(
        "/v1/consultations", headers=_auth(token), json=payload
    )

    assert response.status_code == 422


@pytest.mark.parametrize(
    "goal",
    [
        "weight_loss",
        "strength",
        "fitness",
        "posture",
        "rehab",
        "eating",
        "exercise_habit",
        "blood_pressure",
        "other",
    ],
)
def test_every_member_goal_is_accepted(client, db_session, goal: str):
    """상담 운동 목표가 온보딩 건강 목표 여덟 종과 1:1 이다. (#1992)

    폼이 `kHealthFocusOptions` 를 그대로 선택지로 쓰므로, 여덟 중 하나라도
    서버가 422 로 막으면 회원이 고를 수 있는 값으로 신청이 실패한다.
    """
    _, token = _register_member(client)
    trainer = _create_trainer(db_session)
    payload = _payload(trainer_id=trainer.id)
    payload["exercise_goal"] = goal
    # `other` 만 상세가 필요하다.
    payload["health_purpose_type"] = "general"

    response = client.post(
        "/v1/consultations", headers=_auth(token), json=payload
    )

    assert response.status_code == 201, response.text
    assert response.json()["exercise_goal"] == goal


@pytest.mark.parametrize("detail", [None, "", "   "])
def test_other_health_purpose_requires_detail(client, db_session, detail):
    _, token = _register_member(client)
    trainer = _create_trainer(db_session)
    payload = _payload(trainer_id=trainer.id)
    payload["health_purpose_type"] = "other"
    payload["health_purpose_detail"] = detail

    response = client.post(
        "/v1/consultations", headers=_auth(token), json=payload
    )

    assert response.status_code == 422


def test_blank_optional_text_is_normalized_to_null(client, db_session):
    _, token = _register_member(client)
    trainer = _create_trainer(db_session)
    payload = _payload(trainer_id=trainer.id)
    payload["health_purpose_detail"] = " "
    payload["message"] = " "

    response = client.post(
        "/v1/consultations", headers=_auth(token), json=payload
    )

    assert response.status_code == 201, response.text
    assert response.json()["health_purpose_detail"] is None
    assert response.json()["message"] is None


def test_message_length_is_limited(client, db_session):
    _, token = _register_member(client)
    trainer = _create_trainer(db_session)
    payload = _payload(trainer_id=trainer.id)
    payload["message"] = "a" * 2001

    response = client.post(
        "/v1/consultations", headers=_auth(token), json=payload
    )

    assert response.status_code == 422


@pytest.mark.parametrize(
    "trainer_options",
    [
        None,
        {"role": "member"},
        {"active": False},
        {"with_profile": False},
    ],
)
def test_invalid_trainer_target_is_rejected(
    client, db_session, trainer_options
):
    _, token = _register_member(client)
    trainer_id = "consult-trainer-missing"
    if trainer_options is not None:
        trainer_id = _create_trainer(db_session, **trainer_options).id

    response = client.post(
        "/v1/consultations",
        headers=_auth(token),
        json=_payload(trainer_id=trainer_id),
    )

    assert response.status_code == 404


def test_trainer_without_gym_is_rejected(client, db_session):
    _, token = _register_member(client)
    trainer = _create_trainer(db_session, with_gym=False)

    response = client.post(
        "/v1/consultations",
        headers=_auth(token),
        json=_payload(trainer_id=trainer.id),
    )

    assert response.status_code == 404


def test_trainer_at_non_fitness_place_is_rejected(client, db_session):
    _, token = _register_member(client)
    trainer = _create_trainer(db_session, gym_category="medical")

    response = client.post(
        "/v1/consultations",
        headers=_auth(token),
        json=_payload(trainer_id=trainer.id),
    )

    assert response.status_code == 404


@pytest.mark.parametrize(
    "payload_changes",
    [
        # 대상 없는 요청 — 누구에게도 가지 않는 상담은 만들 수 없다.
        {"trainer_id": None},
        {"trainer_id": "   "},
        # 폐지된 헬스장 대상.
        {"target_type": "gym"},
    ],
)
def test_target_id_contract_is_validated(
    client, db_session, payload_changes
):
    _, token = _register_member(client)
    trainer = _create_trainer(db_session)
    payload = _payload(trainer_id=trainer.id)
    payload.update(payload_changes)

    response = client.post(
        "/v1/consultations", headers=_auth(token), json=payload
    )

    assert response.status_code == 422


def test_duplicate_pending_consultation_is_rejected(client, db_session):
    _, token = _register_member(client)
    payload = _payload(trainer_id=_create_trainer(db_session).id)

    first = client.post(
        "/v1/consultations", headers=_auth(token), json=payload
    )
    second = client.post(
        "/v1/consultations", headers=_auth(token), json=payload
    )

    assert first.status_code == 201
    assert second.status_code == 409


def test_partial_unique_index_allows_completed_but_rejects_second_pending(
    client, db_session
):
    from sqlalchemy.exc import IntegrityError

    member_id, _ = _register_member(client)
    common = {
        "member_id": member_id,
        "target_type": "trainer",
        "trainer_id": _create_trainer(db_session).id,
        "exercise_goal": "health",
        "health_purpose_type": "general",
        "preferred_date": clock.today().isoformat(),
        "preferred_time_slot": "flexible",
    }

    db_session.add(
        ConsultationRequest(
            id=f"consult-{uuid4().hex[:12]}",
            status="accepted",
            **common,
        )
    )
    db_session.commit()
    db_session.add(
        ConsultationRequest(
            id=f"consult-{uuid4().hex[:12]}",
            status="pending",
            **common,
        )
    )
    db_session.commit()

    db_session.add(
        ConsultationRequest(
            id=f"consult-{uuid4().hex[:12]}",
            status="pending",
            **common,
        )
    )
    with pytest.raises(IntegrityError):
        db_session.commit()
    db_session.rollback()


def test_pending_requests_to_different_trainers_are_independent(
    client, db_session
):
    """대기 요청은 트레이너별로 하나다 — 다른 트레이너에게는 걸 수 있어야 한다.

    회원 한 명이 대기 요청을 통틀어 하나만 갖게 막으면, 답 없는 트레이너 한 명이
    회원을 무기한 묶어 둔다.
    """
    _, token = _register_member(client)

    first = client.post(
        "/v1/consultations",
        headers=_auth(token),
        json=_payload(trainer_id=_create_trainer(db_session).id),
    )
    second = client.post(
        "/v1/consultations",
        headers=_auth(token),
        json=_payload(trainer_id=_create_trainer(db_session).id),
    )

    assert first.status_code == 201, first.text
    assert second.status_code == 201, second.text


def test_list_returns_only_current_member_in_latest_order(client, db_session):
    first_member_id, first_token = _register_member(client)
    _, second_token = _register_member(client)
    first_trainer = _create_trainer(db_session)
    second_trainer = _create_trainer(db_session)

    first = client.post(
        "/v1/consultations",
        headers=_auth(first_token),
        json=_payload(trainer_id=first_trainer.id),
    )
    assert first.status_code == 201
    first_row = db_session.get(ConsultationRequest, first.json()["id"])
    first_row.created_at = datetime.now(timezone.utc) - timedelta(days=1)
    db_session.commit()

    second = client.post(
        "/v1/consultations",
        headers=_auth(first_token),
        json=_payload(trainer_id=second_trainer.id),
    )
    assert second.status_code == 201
    other = client.post(
        "/v1/consultations",
        headers=_auth(second_token),
        json=_payload(trainer_id=first_trainer.id),
    )
    assert other.status_code == 201

    response = client.get(
        "/v1/consultations/me", headers=_auth(first_token)
    )

    assert response.status_code == 200
    body = response.json()
    assert [row["id"] for row in body] == [
        second.json()["id"],
        first.json()["id"],
    ]
    assert {row["member_id"] for row in body} == {first_member_id}


def test_get_returns_own_consultation(client, db_session):
    _, token = _register_member(client)
    trainer = _create_trainer(db_session)
    created = client.post(
        "/v1/consultations",
        headers=_auth(token),
        json=_payload(trainer_id=trainer.id),
    )

    response = client.get(
        f"/v1/consultations/{created.json()['id']}",
        headers=_auth(token),
    )

    assert response.status_code == 200
    assert response.json()["id"] == created.json()["id"]


def test_other_members_consultation_is_hidden(client, db_session):
    _, owner_token = _register_member(client)
    _, other_token = _register_member(client)
    trainer = _create_trainer(db_session)
    created = client.post(
        "/v1/consultations",
        headers=_auth(owner_token),
        json=_payload(trainer_id=trainer.id),
    )

    response = client.get(
        f"/v1/consultations/{created.json()['id']}",
        headers=_auth(other_token),
    )

    assert response.status_code == 404


def test_missing_consultation_returns_404(client):
    _, token = _register_member(client)

    response = client.get(
        "/v1/consultations/consult-missing",
        headers=_auth(token),
    )

    assert response.status_code == 404


@pytest.mark.parametrize(
    ("method", "path"),
    [
        ("post", "/v1/consultations"),
        ("get", "/v1/consultations/me"),
        ("get", "/v1/consultations/consult-any"),
    ],
)
def test_consultation_endpoints_require_authentication(
    client, method: str, path: str
):
    kwargs = {"json": _payload(trainer_id="consult-trainer-any")} if method == "post" else {}

    response = getattr(client, method)(path, **kwargs)

    assert response.status_code == 401


def test_trainer_cannot_access_consultation_endpoints(client):
    token_response = client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    )
    assert token_response.status_code == 200
    headers = _auth(token_response.json()["access_token"])

    assert client.get("/v1/consultations/me", headers=headers).status_code == 403


def test_consultation_out_carries_target_names(client, db_session):
    """목록 카드가 이름을 렌더한다 — id 만 주면 앱이 대상마다 상세를 다시 조회해야
    하고, 대상이 지워지면 이름을 영영 못 만든다(#327)."""
    token = _register_member(client)[1]
    trainer = _create_trainer(db_session)
    created = client.post(
        "/v1/consultations",
        headers=_auth(token),
        json=_payload(trainer_id=trainer.id),
    )
    assert created.status_code == 201, created.text
    assert created.json()["trainer_name"] == trainer.name

    listed = client.get("/v1/consultations/me", headers=_auth(token)).json()
    assert listed[0]["trainer_name"] == trainer.name
    # 대상은 트레이너뿐이라 응답에 헬스장 자리가 없다.
    assert "gym_name" not in listed[0]

    detail = client.get(
        f"/v1/consultations/{created.json()['id']}", headers=_auth(token)
    ).json()
    assert detail["trainer_name"] == trainer.name


def test_legacy_preferred_time_slot_values_still_read(client, db_session):
    """예전 morning/afternoon/evening 값으로 저장된 행도 조회는 그대로 된다(#1256).

    입력(`ConsultationCreate`)만 `HH:MM` 으로 좁혔다(#1587) — 이미 저장된 행까지
    좁히면 목록·상세 조회가 그 행에서 500 으로 죽는다. 컬럼이 `String(20)` 그대로라
    마이그레이션 없이 값 형식만 바뀌었으므로, 과거 값이 여전히 읽혀야 한다.
    """
    member_id, token = _register_member(client)
    trainer = _create_trainer(db_session)
    legacy = ConsultationRequest(
        id=f"consult-{uuid4().hex[:12]}",
        member_id=member_id,
        target_type="trainer",
        trainer_id=trainer.id,
        exercise_goal="health",
        health_purpose_type="general",
        preferred_date=clock.today().isoformat(),
        preferred_time_slot="morning",
        status="pending",
    )
    db_session.add(legacy)
    db_session.commit()

    response = client.get("/v1/consultations/me", headers=_auth(token))

    assert response.status_code == 200, response.text
    body = response.json()
    assert body[0]["preferred_time_slot"] == "morning"
    # 없앤 `건강 관리` 도 같은 이유로 응답에 그대로 실린다 — 백필하지 않으므로
    # 응답에서까지 좁히면 이 행에서 목록이 500 으로 죽는다(#1992).
    assert body[0]["exercise_goal"] == "health"
