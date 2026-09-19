"""트레이너 소속 헬스장 설정·변경·해제 (`/trainer/me/gym`). (#452)

시드(`seed_gyms`)의 이름 매칭 백필 말고 운영 중에 `TrainerProfile.gym_id` 를 바꾸는
유일한 경로다. 데모 트레이너(trainer-demo)는 다른 테스트가 소속을 전제하므로 건드리지
않고, 테스트마다 자기 트레이너를 만들어 쓴다.
"""
from __future__ import annotations

from uuid import uuid4

import pytest

#: 시드 제휴 헬스장 — `_PARTNER_GYMS` 와 같은 값(부가 정보까지 있다).
HEALTHMATE = {
    "id": "gym-healthmate",
    "name": "헬스메이트 신촌점",
    "address": "서울 서대문구 신촌로 83",
    "hours": "05:30 - 24:00",
    "phone": "02-2345-6789",
}
ONCARE = {"id": "gym-oncare-sinchon", "name": "온케어짐 신촌점"}
#: 카카오에서 발견한 실재 헬스장 — 부가 정보(GymProfile)가 없다.
DISCOVERED_GYM_ID = "328969863"
#: 시드 데모의 medical 장소 — 헬스장이 아니다.
MEDICAL_PLACE_ID = "place-1"


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def trainer(client, db_session):
    """소속이 없는 트레이너 계정 하나. (token, trainer_id)

    데모 트레이너를 재사용하면 소속을 바꾸는 순간 `/trainer/me`·코치 카드·헬스장별
    트레이너 목록을 검증하는 다른 테스트가 함께 흔들린다.
    """
    from app.core.security import hash_password
    from app.models import models

    trainer_id = f"trainer-gym-{uuid4().hex[:10]}"
    email = f"{trainer_id}@oncare.test"
    db_session.add(models.User(
        id=trainer_id,
        email=email,
        name=f"소속테스트 {trainer_id[-6:]}",
        hashed_password=hash_password("pw!"),
        role="trainer",
    ))
    db_session.flush()
    db_session.add(models.TrainerProfile(
        trainer_id=trainer_id,
        specialty="퍼스널 트레이너",
        career_years=3,
    ))
    db_session.commit()

    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "pw!"}
    ).json()["access_token"]

    yield token, trainer_id

    db_session.query(models.TrainerProfile).filter(
        models.TrainerProfile.trainer_id == trainer_id
    ).delete()
    db_session.query(models.User).filter(models.User.id == trainer_id).delete()
    db_session.commit()


# ---- 설정 · 변경 ----

def test_set_gym_links_the_place_and_syncs_the_texts(client, trainer):
    token, _trainer_id = trainer
    before = client.get("/v1/trainer/me", headers=_auth(token)).json()
    assert before["gym"]["id"] is None, "픽스처 트레이너는 소속이 없어야 한다"

    r = client.put(
        "/v1/trainer/me/gym", json={"gym_id": HEALTHMATE["id"]}, headers=_auth(token)
    )
    assert r.status_code == 200, r.text
    gym = r.json()["gym"]

    assert gym["id"] == HEALTHMATE["id"]
    # 호환 문자열은 소속에서 파생된다 — 트레이너 웹이 아직 이 값들만 읽는다.
    assert gym["name"] == HEALTHMATE["name"]
    assert gym["address"] == HEALTHMATE["address"]
    assert gym["hours"] == HEALTHMATE["hours"]
    assert gym["phone"] == HEALTHMATE["phone"]


def test_set_gym_persists(client, trainer):
    """응답만 맞고 저장이 안 되면 새로고침에서 되돌아간다."""
    token, _trainer_id = trainer
    client.put(
        "/v1/trainer/me/gym", json={"gym_id": HEALTHMATE["id"]}, headers=_auth(token)
    )

    gym = client.get("/v1/trainer/me", headers=_auth(token)).json()["gym"]
    assert gym["id"] == HEALTHMATE["id"]
    assert gym["name"] == HEALTHMATE["name"]


def test_changing_gym_replaces_the_previous_one(client, trainer):
    """이적 — 소속은 한 곳이므로 이전 값이 남으면 안 된다."""
    token, _trainer_id = trainer
    client.put(
        "/v1/trainer/me/gym", json={"gym_id": HEALTHMATE["id"]}, headers=_auth(token)
    )

    r = client.put(
        "/v1/trainer/me/gym", json={"gym_id": ONCARE["id"]}, headers=_auth(token)
    )
    assert r.status_code == 200, r.text
    gym = r.json()["gym"]
    assert gym["id"] == ONCARE["id"]
    assert gym["name"] == ONCARE["name"]


def test_set_gym_copies_only_what_the_gym_actually_has(client, trainer):
    """카카오 발견 헬스장은 영업시간을 모른다 — 지어내지 않고 비워 둔다."""
    token, _trainer_id = trainer
    r = client.put(
        "/v1/trainer/me/gym", json={"gym_id": DISCOVERED_GYM_ID}, headers=_auth(token)
    )
    assert r.status_code == 200, r.text
    gym = r.json()["gym"]

    assert gym["id"] == DISCOVERED_GYM_ID
    assert gym["name"] == "빌드업짐 PT 신촌점"
    assert gym["phone"] == "0502-5552-4212"  # 카카오 실데이터는 그대로 싣는다
    assert gym["hours"] == ""


# ---- 해제 ----

def test_clear_gym_releases_the_affiliation(client, trainer):
    token, _trainer_id = trainer
    client.put(
        "/v1/trainer/me/gym", json={"gym_id": HEALTHMATE["id"]}, headers=_auth(token)
    )

    r = client.delete("/v1/trainer/me/gym", headers=_auth(token))
    assert r.status_code == 200, r.text
    gym = r.json()["gym"]

    assert gym["id"] is None
    # 떠난 헬스장 이름을 남겨 두면 회원 쪽 코치 카드가 그 값으로 폴백한다.
    assert gym["name"] == ""
    assert gym["address"] == ""
    assert gym["hours"] == ""
    assert gym["phone"] == ""


def test_clear_gym_is_idempotent(client, trainer):
    """소속이 없어도 오류가 아니다 — 두 번 눌러도 오류 화면이 뜨면 안 된다."""
    token, _trainer_id = trainer
    assert client.delete("/v1/trainer/me/gym", headers=_auth(token)).status_code == 200
    assert client.delete("/v1/trainer/me/gym", headers=_auth(token)).status_code == 200


# ---- 유효하지 않은 관계 ----

def test_unknown_gym_is_rejected(client, trainer):
    token, _trainer_id = trainer
    r = client.put(
        "/v1/trainer/me/gym", json={"gym_id": "no-such-gym"}, headers=_auth(token)
    )
    assert r.status_code == 404, r.text


def test_non_fitness_place_is_rejected(client, trainer):
    """place-1 은 medical 이다 — FK 만으로는 카테고리를 막을 수 없다."""
    token, _trainer_id = trainer
    r = client.put(
        "/v1/trainer/me/gym", json={"gym_id": MEDICAL_PLACE_ID}, headers=_auth(token)
    )
    assert r.status_code == 404, r.text


def test_rejected_change_keeps_the_current_affiliation(client, trainer):
    """실패한 변경이 기존 소속까지 날리면 트레이너가 회원 화면에서 사라진다."""
    token, _trainer_id = trainer
    client.put(
        "/v1/trainer/me/gym", json={"gym_id": HEALTHMATE["id"]}, headers=_auth(token)
    )

    client.put(
        "/v1/trainer/me/gym", json={"gym_id": MEDICAL_PLACE_ID}, headers=_auth(token)
    )

    gym = client.get("/v1/trainer/me", headers=_auth(token)).json()["gym"]
    assert gym["id"] == HEALTHMATE["id"]
    assert gym["name"] == HEALTHMATE["name"]


def test_blank_gym_id_is_rejected(client, trainer):
    """빈 문자열을 해제로 해석하면 '안 보냈다'와 '지워라'가 섞인다 — 해제는 DELETE."""
    token, _trainer_id = trainer
    r = client.put("/v1/trainer/me/gym", json={"gym_id": ""}, headers=_auth(token))
    assert r.status_code == 422, r.text


# ---- 권한 ----

def test_member_cannot_set_a_gym(client):
    email = f"member-{uuid4().hex[:8]}@oncare.com"
    client.post("/v1/auth/register", json={"email": email, "password": "pw!", "name": "u"})
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "pw!"}
    ).json()["access_token"]

    r = client.put(
        "/v1/trainer/me/gym", json={"gym_id": HEALTHMATE["id"]}, headers=_auth(token)
    )
    assert r.status_code == 403, r.text
    assert client.delete("/v1/trainer/me/gym", headers=_auth(token)).status_code == 403


def test_unauthenticated_is_rejected(client):
    assert client.put(
        "/v1/trainer/me/gym", json={"gym_id": HEALTHMATE["id"]}
    ).status_code == 401
    assert client.delete("/v1/trainer/me/gym").status_code == 401


# ---- 호환 문자열 동기화 기준 ----

def test_gym_texts_are_locked_while_affiliated(client, trainer):
    """소속이 있으면 문자열만 따로 못 바꾼다 — 소속과 화면이 어긋난다."""
    token, _trainer_id = trainer
    client.put(
        "/v1/trainer/me/gym", json={"gym_id": HEALTHMATE["id"]}, headers=_auth(token)
    )

    r = client.put(
        "/v1/trainer/me", json={"gym_name": "직접 적은 헬스장"}, headers=_auth(token)
    )
    assert r.status_code == 409, r.text
    # 거절된 요청이 다른 필드를 흘려보내면 안 된다.
    assert client.get(
        "/v1/trainer/me", headers=_auth(token)
    ).json()["gym"]["name"] == HEALTHMATE["name"]


def test_other_profile_fields_are_still_editable_while_affiliated(client, trainer):
    token, _trainer_id = trainer
    client.put(
        "/v1/trainer/me/gym", json={"gym_id": HEALTHMATE["id"]}, headers=_auth(token)
    )

    r = client.put(
        "/v1/trainer/me", json={"phone": "010-1111-2222"}, headers=_auth(token)
    )
    assert r.status_code == 200, r.text
    assert r.json()["phone"] == "010-1111-2222"


def test_gym_texts_stay_editable_without_an_affiliation(client, trainer):
    """소속이 없는(레거시·해제) 프로필은 예전처럼 직접 적는다 — 기존 경로 유지."""
    token, _trainer_id = trainer
    r = client.put(
        "/v1/trainer/me",
        json={"gym_name": "직접 적은 헬스장", "gym_phone": "02-0000-0000"},
        headers=_auth(token),
    )
    assert r.status_code == 200, r.text
    gym = r.json()["gym"]
    assert gym["id"] is None
    assert gym["name"] == "직접 적은 헬스장"
    assert gym["phone"] == "02-0000-0000"


# ---- 회원 쪽에서 본 결과 ----

def test_trainer_me_response_contract_is_unchanged(client, trainer):
    token, _trainer_id = trainer
    client.put(
        "/v1/trainer/me/gym", json={"gym_id": HEALTHMATE["id"]}, headers=_auth(token)
    )

    body = client.get("/v1/trainer/me", headers=_auth(token)).json()
    assert set(body) == {
        "id", "name", "email", "phone", "specialty", "career", "intro",
        "certifications", "gym",
    }
    # 트레이너 웹의 gym 계약 — 필드가 사라지면 화면이 빈다.
    assert set(body["gym"]) == {"id", "name", "address", "hours", "phone"}


def test_affiliated_trainer_shows_up_under_that_gym(client, trainer):
    """소속을 설정하면 회원앱의 헬스장 상세 '소속 트레이너'에 나온다."""
    token, trainer_id = trainer
    client.put(
        "/v1/trainer/me/gym", json={"gym_id": HEALTHMATE["id"]}, headers=_auth(token)
    )

    listed = client.get(f"/v1/gyms/{HEALTHMATE['id']}/trainers").json()
    assert trainer_id in {t["id"] for t in listed}


def test_setting_a_gym_makes_the_trainer_consultable(client, trainer):
    """소속이 없으면 상담 대상이 아니다(#443). 설정하면 그때부터 받는다."""
    from tests.test_consultation_decision import _open_slot
    from tests.test_consultations import _payload, _register_member

    token, trainer_id = trainer
    _member_id, member_token = _register_member(client)
    # 상담은 트레이너가 연 자리를 고른다(#1873). 소속 여부만 보려는 테스트라 자리는
    # 처음부터 열어 두고, 달라지는 것은 소속 하나뿐이게 한다. 자리는 트레이너가
    # 지워질 때 함께 지워진다(`ondelete=CASCADE`).
    payload = _payload(trainer_id=trainer_id, slot_id=_open_slot(trainer_id).id)

    before = client.post("/v1/consultations", headers=_auth(member_token), json=payload)
    assert before.status_code == 404, before.text

    client.put(
        "/v1/trainer/me/gym", json={"gym_id": HEALTHMATE["id"]}, headers=_auth(token)
    )
    after = client.post("/v1/consultations", headers=_auth(member_token), json=payload)
    assert after.status_code == 201, after.text
