"""트레이너가 소속 헬스장 영업시간·전화·태그를 고친다 (`/trainer/me/gym/profile`). (#2700)

권한은 **소속 트레이너 누구나**다 — 헬스장에 대표 트레이너 개념이 없고, 마지막에
저장한 값이 남는다. 시드 헬스장을 고치면 다른 테스트(목록·상세·코치 카드)가 흔들리므로
테스트마다 자기 헬스장(`places` 행만, `gym_profiles` 없음 — 카카오 발견분과 같은 꼴)과
트레이너를 만들어 쓴다.
"""
from __future__ import annotations

from uuid import uuid4

import pytest

URL = "/v1/trainer/me/gym/profile"


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def gym(db_session):
    """`gym_profiles` 행이 없는 헬스장 하나 — 카카오에서 발견해 등록한 곳과 같다."""
    from app.models import models

    place_id = f"gym-edit-{uuid4().hex[:10]}"
    db_session.add(models.Place(
        id=place_id, name=f"수정테스트짐 {place_id[-6:]}", category="fitness",
        address="서울 서대문구 이화여대길 52", lat=37.56, lng=126.94,
    ))
    db_session.commit()

    yield place_id

    db_session.query(models.TrainerProfile).filter(
        models.TrainerProfile.gym_id == place_id
    ).update({"gym_id": None})
    db_session.query(models.GymProfile).filter(
        models.GymProfile.place_id == place_id
    ).delete()
    db_session.query(models.Place).filter(models.Place.id == place_id).delete()
    db_session.commit()


@pytest.fixture
def make_trainer(client, db_session):
    """트레이너 계정을 만든다. `gym_id` 를 주면 그 헬스장 소속. → (token, trainer_id)"""
    from app.core.security import hash_password
    from app.models import models

    created: list[str] = []

    def _make(gym_id: str | None = None) -> tuple[str, str]:
        trainer_id = f"trainer-gp-{uuid4().hex[:10]}"
        email = f"{trainer_id}@oncare.test"
        db_session.add(models.User(
            id=trainer_id, email=email, name=f"정보수정 {trainer_id[-6:]}",
            hashed_password=hash_password("test-pw-1234"), role="trainer",
        ))
        db_session.flush()
        db_session.add(models.TrainerProfile(
            trainer_id=trainer_id, specialty="퍼스널 트레이너", career_years=2,
        ))
        db_session.commit()
        created.append(trainer_id)
        token = client.post(
            "/v1/auth/login", data={"username": email, "password": "test-pw-1234"}
        ).json()["access_token"]
        if gym_id is not None:
            r = client.put("/v1/trainer/me/gym", json={"gym_id": gym_id}, headers=_auth(token))
            assert r.status_code == 200, r.text
        return token, trainer_id

    yield _make

    for trainer_id in created:
        db_session.query(models.TrainerProfile).filter(
            models.TrainerProfile.trainer_id == trainer_id
        ).delete()
        db_session.query(models.User).filter(models.User.id == trainer_id).delete()
    db_session.commit()


FULL = {
    "weekday_hours": "06:00 - 23:00",
    "weekend_hours": "09:00 - 18:00",
    "phone": "02-332-1720",
    "tags": ["PT 전문", "샤워실", "주차 가능"],
}


# ---- 조회 · 저장 ----

def test_get_returns_empty_values_for_a_gym_without_a_profile_row(client, gym, make_trainer):
    token, _ = make_trainer(gym)
    r = client.get(URL, headers=_auth(token))
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["gym_id"] == gym
    assert body["name"].startswith("수정테스트짐")
    assert (body["weekday_hours"], body["weekend_hours"], body["phone"], body["tags"]) == (
        "", "", "", []
    )


def test_update_creates_the_missing_profile_row(client, db_session, gym, make_trainer):
    from app.models import models

    token, _ = make_trainer(gym)
    assert db_session.get(models.GymProfile, gym) is None

    r = client.put(URL, json=FULL, headers=_auth(token))
    assert r.status_code == 200, r.text
    body = r.json()
    for key, value in FULL.items():
        assert body[key] == value

    db_session.expire_all()
    row = db_session.get(models.GymProfile, gym)
    assert row is not None
    # 평점은 트레이너가 정하지 않는다 — 새로 만든 행도 비어 있다.
    assert row.rating is None
    assert row.is_partner is False


def test_partial_update_keeps_the_other_fields(client, gym, make_trainer):
    token, _ = make_trainer(gym)
    client.put(URL, json=FULL, headers=_auth(token))

    r = client.put(URL, json={"weekend_hours": "휴무"}, headers=_auth(token))
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["weekend_hours"] == "휴무"
    assert body["weekday_hours"] == FULL["weekday_hours"]
    assert body["phone"] == FULL["phone"]
    assert body["tags"] == FULL["tags"]


def test_empty_values_clear_the_fields(client, gym, make_trainer):
    token, _ = make_trainer(gym)
    client.put(URL, json=FULL, headers=_auth(token))

    r = client.put(URL, json={"phone": "", "tags": []}, headers=_auth(token))
    assert r.status_code == 200, r.text
    assert r.json()["phone"] == ""
    assert r.json()["tags"] == []


def test_tags_are_trimmed_and_deduplicated(client, gym, make_trainer):
    token, _ = make_trainer(gym)
    r = client.put(
        URL, json={"tags": [" 샤워실 ", "샤워실", "24시간"]}, headers=_auth(token)
    )
    assert r.status_code == 200, r.text
    assert r.json()["tags"] == ["샤워실", "24시간"]


# ---- 회원 앱에 그대로 나간다 ----

def test_member_gym_endpoints_show_the_saved_values(client, gym, make_trainer):
    token, _ = make_trainer(gym)
    client.put(URL, json=FULL, headers=_auth(token))

    detail = client.get(f"/v1/gyms/{gym}", headers=_auth(token)).json()
    assert detail["weekday_hours"] == FULL["weekday_hours"]
    assert detail["weekend_hours"] == FULL["weekend_hours"]
    assert detail["phone"] == FULL["phone"]
    assert detail["tags"] == FULL["tags"]
    # 평점은 없는 그대로 — 프론트는 0 이면 뱃지를 감춘다(#329).
    assert detail["rating"] == 0.0

    listed = [g for g in client.get("/v1/gyms", headers=_auth(token)).json() if g["id"] == gym]
    assert listed and listed[0]["tags"] == FULL["tags"]


# ---- 같은 헬스장 소속 트레이너 복사본 ----

def test_update_syncs_every_affiliated_trainers_copy(client, gym, make_trainer):
    """소속을 정할 때 복사한 `gym.hours`·`gym.phone` 이 동료에게도 바뀐다."""
    editor_token, _ = make_trainer(gym)
    colleague_token, _ = make_trainer(gym)

    client.put(URL, json=FULL, headers=_auth(editor_token))

    for token in (editor_token, colleague_token):
        me_gym = client.get("/v1/trainer/me", headers=_auth(token)).json()["gym"]
        assert me_gym["id"] == gym
        assert me_gym["hours"] == FULL["weekday_hours"]
        assert me_gym["phone"] == FULL["phone"]


def test_any_affiliated_trainer_can_edit_and_the_last_save_wins(client, gym, make_trainer):
    first_token, _ = make_trainer(gym)
    second_token, _ = make_trainer(gym)

    client.put(URL, json={"phone": "02-1111-2222"}, headers=_auth(first_token))
    r = client.put(URL, json={"phone": "02-3333-4444"}, headers=_auth(second_token))
    assert r.status_code == 200, r.text

    assert client.get(URL, headers=_auth(first_token)).json()["phone"] == "02-3333-4444"


def test_other_gyms_trainers_are_not_touched(client, gym, make_trainer):
    """다른 헬스장 소속 트레이너의 복사본은 그대로다."""
    token, _ = make_trainer(gym)
    other_token, _ = make_trainer("gym-healthmate")
    before = client.get("/v1/trainer/me", headers=_auth(other_token)).json()["gym"]

    client.put(URL, json=FULL, headers=_auth(token))

    after = client.get("/v1/trainer/me", headers=_auth(other_token)).json()["gym"]
    assert after == before


# ---- 거절 ----

def test_without_an_affiliation_is_409(client, make_trainer):
    token, _ = make_trainer()
    assert client.get(URL, headers=_auth(token)).status_code == 409
    r = client.put(URL, json={"phone": "02-1234-5678"}, headers=_auth(token))
    assert r.status_code == 409, r.text


def test_rating_is_not_accepted(client, gym, make_trainer):
    token, _ = make_trainer(gym)
    r = client.put(URL, json={"rating": 5.0}, headers=_auth(token))
    assert r.status_code == 422, r.text


def test_empty_body_is_400(client, gym, make_trainer):
    token, _ = make_trainer(gym)
    assert client.put(URL, json={}, headers=_auth(token)).status_code == 400


@pytest.mark.parametrize("body", [
    {"weekday_hours": None},
    {"weekday_hours": "가" * 51},
    {"weekend_hours": "가" * 51},
    {"phone": "0" * 21},
    {"tags": ["가" * 21]},
    {"tags": ["  "]},
    {"tags": [f"태그{i}" for i in range(11)]},
])
def test_invalid_values_are_422(client, gym, make_trainer, body):
    token, _ = make_trainer(gym)
    r = client.put(URL, json=body, headers=_auth(token))
    assert r.status_code == 422, r.text


def test_landline_style_phone_is_accepted(client, gym, make_trainer):
    """대표번호에는 휴대전화 규칙을 걸지 않는다(#1914)."""
    token, _ = make_trainer(gym)
    for phone in ("02-332-1720", "0502-5552-4212", "1588-0000"):
        r = client.put(URL, json={"phone": phone}, headers=_auth(token))
        assert r.status_code == 200, r.text
        assert r.json()["phone"] == phone


def test_member_cannot_edit_gym_profile(client):
    email = f"member-{uuid4().hex[:8]}@oncare.com"
    client.post("/v1/auth/register", json={"email": email, "password": "test-pw-1234", "name": "u"})
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "test-pw-1234"}
    ).json()["access_token"]
    assert client.put(URL, json={"phone": "02-1234-5678"}, headers=_auth(token)).status_code == 403


def test_unauthenticated_is_rejected(client):
    assert client.put(URL, json={"phone": "02-1234-5678"}).status_code == 401
    assert client.get(URL).status_code == 401
