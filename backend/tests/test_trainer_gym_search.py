"""트레이너 소속 헬스장 찾기 — 카카오 장소 검색으로 고르기. (#2543)

- `docs_to_gyms` 파싱은 순수(로컬 실행).
- 엔드포인트는 DB 필요(로컬 skip, CI 실행). 카카오 호출은 `kakao.search_gyms` 를
  바꿔 끼워 네트워크 없이 돈다.
"""
from __future__ import annotations

import random
from uuid import uuid4

import pytest

#: 시드 제휴 헬스장 — 카카오에는 없다.
HEALTHMATE_ID = "gym-healthmate"
#: 시드의 카카오 발견 헬스장 — `places.id` 가 카카오 장소 id 다.
DISCOVERED_GYM_ID = "gym-demo-ptlab"
#: 시드 데모의 medical 장소.
MEDICAL_PLACE_ID = "place-1"


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _kakao_doc(place_id: str, name: str, *, category: str = "스포츠,레저 > 스포츠시설 > 헬스클럽") -> dict:
    return {
        "id": place_id,
        "place_name": name,
        "category_name": category,
        "road_address_name": f"서울 마포구 {name}로 1",
        "address_name": "서울 마포구 지번",
        "x": "126.93",
        "y": "37.55",
        "phone": "02-111-2222",
        "distance": "320",
    }


def _new_kakao_id() -> str:
    # 실제 카카오 id 와 겹치지 않을 긴 숫자.
    return str(random.randint(10**14, 10**15 - 1))


# ---- 파싱 (순수) ----

def test_docs_to_gyms_keeps_only_sports_facilities():
    from app.services.places import kakao

    docs = [
        _kakao_doc("1", "헬스장A"),
        _kakao_doc("2", "필라테스B", category="스포츠,레저 > 스포츠시설 > 요가,필라테스"),
        _kakao_doc("3", "헬스식당", category="음식점 > 한식"),
        {**_kakao_doc("4", "좌표없음"), "x": None},
        {**_kakao_doc("", "id없음")},
    ]
    out = kakao.docs_to_gyms(docs)

    assert [g["id"] for g in out] == ["1", "2"]
    first = out[0]
    assert first["address"] == "서울 마포구 헬스장A로 1"  # 도로명 우선
    assert first["phone"] == "02-111-2222"
    assert first["distance_meters"] == 320
    assert (first["lat"], first["lng"]) == (37.55, 126.93)


def test_docs_to_gyms_distance_is_none_without_coordinates():
    from app.services.places import kakao

    doc = {**_kakao_doc("1", "헬스장A"), "distance": ""}
    assert kakao.docs_to_gyms([doc])[0]["distance_meters"] is None


# ---- 검색어 비교 규칙 (순수, #3223) ----

def test_search_terms_split_on_any_whitespace():
    from app.services import trainer_gym_search

    assert trainer_gym_search.search_terms("  신촌\t헬스메이트  ") == ["신촌", "헬스메이트"]
    assert trainer_gym_search.search_terms("   ") == []


def test_like_escape_neutralises_wildcards():
    from app.services import trainer_gym_search

    assert trainer_gym_search._like_escape("100%") == "100\\%"
    assert trainer_gym_search._like_escape("a_b") == "a\\_b"
    assert trainer_gym_search._like_escape("a\\b") == "a\\\\b"
    assert trainer_gym_search._like_escape("헬스") == "헬스"


# ---- 픽스처 ----

@pytest.fixture
def trainer(client, db_session):
    """소속이 없는 트레이너 하나. (token, trainer_id)"""
    from app.core.security import hash_password
    from app.models import models

    trainer_id = f"trainer-gsearch-{uuid4().hex[:10]}"
    email = f"{trainer_id}@oncare.test"
    db_session.add(models.User(
        id=trainer_id, email=email, name=f"검색테스트 {trainer_id[-6:]}",
        hashed_password=hash_password("test-pw-1234"), role="trainer",
    ))
    db_session.flush()
    db_session.add(models.TrainerProfile(
        trainer_id=trainer_id, specialty="퍼스널 트레이너", career_years=3,
    ))
    db_session.commit()

    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "test-pw-1234"}
    ).json()["access_token"]

    yield token, trainer_id

    db_session.rollback()
    db_session.query(models.TrainerProfile).filter(
        models.TrainerProfile.trainer_id == trainer_id
    ).delete()
    db_session.query(models.User).filter(models.User.id == trainer_id).delete()
    db_session.commit()


@pytest.fixture
def created_places(db_session):
    """테스트가 만든 카카오 헬스장 id — 끝나면 지운다."""
    from app.models import models

    ids: list[str] = []
    yield ids
    db_session.rollback()
    if ids:
        db_session.query(models.TrainerProfile).filter(
            models.TrainerProfile.gym_id.in_(ids)
        ).update({"gym_id": None}, synchronize_session=False)
        db_session.query(models.GymProfile).filter(
            models.GymProfile.place_id.in_(ids)
        ).delete(synchronize_session=False)
        db_session.query(models.Place).filter(
            models.Place.id.in_(ids)
        ).delete(synchronize_session=False)
        db_session.commit()


@pytest.fixture
def fake_kakao(monkeypatch):
    """카카오를 켠 것으로 두고, 검색 결과를 테스트가 정한다.

    `docs` 에 카카오 원문을 넣으면 실제 파서(`docs_to_gyms`)를 거쳐 돌려준다.
    `fail=True` 면 호출이 예외를 던진다. `calls` 에 받은 검색어가 쌓인다.
    """
    from app.services import trainer_gym_search
    from app.services.places import kakao

    state = {"docs": [], "fail": False, "calls": []}

    async def fake_search_gyms(query, lat, lng, api_key, timeout=3.0):
        state["calls"].append(query)
        if state["fail"]:
            raise RuntimeError("kakao down")
        return kakao.docs_to_gyms(state["docs"])

    monkeypatch.setattr(trainer_gym_search, "kakao_enabled", lambda: True)
    monkeypatch.setattr(kakao, "search_gyms", fake_search_gyms)
    return state


@pytest.fixture
def kakao_off(monkeypatch):
    from app.services import trainer_gym_search

    monkeypatch.setattr(trainer_gym_search, "kakao_enabled", lambda: False)


# ---- 검색 ----

def test_search_without_kakao_returns_registered_gyms(client, trainer, kakao_off):
    token, _ = trainer
    r = client.get(
        "/v1/trainer/gyms/search", params={"query": "헬스메이트"}, headers=_auth(token)
    )
    assert r.status_code == 200, r.text
    rows = r.json()
    assert HEALTHMATE_ID in {g["id"] for g in rows}
    assert all(g["registered"] for g in rows)


def test_search_merges_kakao_results_after_registered_ones(client, trainer, fake_kakao):
    token, _ = trainer
    new_id = _new_kakao_id()
    fake_kakao["docs"] = [
        _kakao_doc(DISCOVERED_GYM_ID, "이미 있는 헬스장"),
        _kakao_doc(new_id, "새 헬스장"),
    ]

    r = client.get(
        "/v1/trainer/gyms/search",
        params={"query": "헬스메이트", "lat": 37.55, "lng": 126.93},
        headers=_auth(token),
    )
    assert r.status_code == 200, r.text
    rows = r.json()
    ids = [g["id"] for g in rows]

    # 등록된 이름 일치가 먼저, 카카오 결과는 그 뒤.
    assert ids[0] == HEALTHMATE_ID
    assert ids.index(new_id) > ids.index(HEALTHMATE_ID)
    # 이미 places 에 있는 카카오 결과는 registered 로 한 번만.
    assert ids.count(DISCOVERED_GYM_ID) == 1
    by_id = {g["id"]: g for g in rows}
    assert by_id[DISCOVERED_GYM_ID]["registered"] is True
    new = by_id[new_id]
    assert new["registered"] is False
    assert new["distance_meters"] == 320
    assert (new["lat"], new["lng"]) == (37.55, 126.93)


def test_search_survives_kakao_failure(client, trainer, fake_kakao):
    token, _ = trainer
    fake_kakao["fail"] = True
    r = client.get(
        "/v1/trainer/gyms/search", params={"query": "헬스메이트"}, headers=_auth(token)
    )
    assert r.status_code == 200, r.text
    assert HEALTHMATE_ID in {g["id"] for g in r.json()}


@pytest.mark.parametrize("params", [
    {"query": ""},
    {"query": "   "},
    {"query": "헬스", "lat": 37.5},
])
def test_search_rejects_bad_params(client, trainer, kakao_off, params):
    token, _ = trainer
    r = client.get("/v1/trainer/gyms/search", params=params, headers=_auth(token))
    assert r.status_code == 422, r.text


def test_member_cannot_search(client):
    email = f"member-{uuid4().hex[:8]}@oncare.com"
    client.post("/v1/auth/register", json={"email": email, "password": "test-pw-1234", "name": "u"})
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "test-pw-1234"}
    ).json()["access_token"]
    r = client.get(
        "/v1/trainer/gyms/search", params={"query": "헬스"}, headers=_auth(token)
    )
    assert r.status_code == 403, r.text


# ---- 등록 헬스장 매칭 — 띄어쓰기·단어 순서 (#3223) ----

def _search_ids(client, token: str, query: str) -> list[str]:
    r = client.get(
        "/v1/trainer/gyms/search", params={"query": query}, headers=_auth(token)
    )
    assert r.status_code == 200, r.text
    return [g["id"] for g in r.json()]


@pytest.mark.parametrize("query", [
    "헬스메이트신촌",      # 붙여 쓴 이름 — 저장된 이름은 `헬스메이트 신촌점`
    "신촌 헬스메이트",     # 단어 순서가 다르다
    "헬스메이트   신촌점",  # 띄어쓰기가 여러 칸
    "헬스메이트 신촌점",   # 대조군: 저장된 이름 그대로
    "신촌로 헬스메이트",   # 주소 단어 + 이름 단어
])
def test_registered_search_ignores_spacing_and_word_order(
    client, trainer, kakao_off, query
):
    token, _ = trainer
    assert HEALTHMATE_ID in _search_ids(client, token, query)


def test_registered_search_requires_every_word(client, trainer, kakao_off):
    """단어 하나라도 이름·주소에 없으면 그 헬스장은 빠진다 — 아무 단어나 걸리면
    결과가 너무 넓어진다."""
    token, _ = trainer
    assert HEALTHMATE_ID not in _search_ids(client, token, "헬스메이트 없는동네이름")


def test_registered_search_is_case_insensitive(client, trainer, kakao_off, db_session):
    from app.models import models

    place_id = f"gym-case-{uuid4().hex[:8]}"
    db_session.add(models.Place(
        id=place_id, name="OnCare Fit Studio", category="fitness",
        address="서울 마포구 테스트로 1", lat=37.55, lng=126.93,
    ))
    db_session.commit()
    try:
        token, _ = trainer
        assert place_id in _search_ids(client, token, "oncarefit")
        assert place_id in _search_ids(client, token, "STUDIO oncare")
    finally:
        db_session.query(models.Place).filter(models.Place.id == place_id).delete()
        db_session.commit()


@pytest.mark.parametrize("query", ["%", "_", "%%", "헬스%"])
def test_registered_search_treats_wildcards_literally(client, trainer, kakao_off, query):
    """`%`·`_` 는 글자 그대로 비교한다 — 와일드카드로 읽으면 모든 헬스장이 걸린다."""
    token, _ = trainer
    assert _search_ids(client, token, query) == []


# ---- 카카오 결과로 소속 설정 ----

def test_selecting_a_new_kakao_gym_registers_it_and_links_the_trainer(
    client, trainer, fake_kakao, created_places, db_session
):
    from app.models import models

    token, trainer_id = trainer
    new_id = _new_kakao_id()
    created_places.append(new_id)
    fake_kakao["docs"] = [_kakao_doc(new_id, "새 헬스장")]

    r = client.put(
        "/v1/trainer/me/gym/kakao",
        json={"kakao_place_id": new_id, "name": "새 헬스장"},
        headers=_auth(token),
    )
    assert r.status_code == 200, r.text
    gym = r.json()["gym"]
    assert gym["id"] == new_id
    assert gym["name"] == "새 헬스장"
    assert gym["address"] == "서울 마포구 새 헬스장로 1"
    assert gym["phone"] == "02-111-2222"

    db_session.expire_all()
    place = db_session.get(models.Place, new_id)
    assert place is not None
    assert place.category == "fitness"
    assert place.kakao_place_id == new_id
    assert db_session.get(models.GymProfile, new_id).is_partner is False

    # 회원 앱 헬스장 찾기·헬스장 상세에 그대로 나온다.
    assert new_id in {g["id"] for g in client.get("/v1/gyms").json()}
    listed = client.get(f"/v1/gyms/{new_id}/trainers").json()
    assert trainer_id in {t["id"] for t in listed}


def test_selection_uses_kakao_values_not_the_client_name(
    client, trainer, fake_kakao, created_places
):
    """클라이언트가 보낸 이름은 검색어일 뿐이다 — 저장값은 카카오 결과에서 온다."""
    token, _ = trainer
    new_id = _new_kakao_id()
    created_places.append(new_id)
    fake_kakao["docs"] = [_kakao_doc(new_id, "카카오 이름")]

    r = client.put(
        "/v1/trainer/me/gym/kakao",
        json={"kakao_place_id": new_id, "name": "지어낸 이름"},
        headers=_auth(token),
    )
    assert r.status_code == 200, r.text
    assert r.json()["gym"]["name"] == "카카오 이름"
    assert fake_kakao["calls"] == ["지어낸 이름"]


def test_selecting_an_id_kakao_did_not_return_is_404(
    client, trainer, fake_kakao, db_session
):
    from app.models import models

    token, _ = trainer
    missing = _new_kakao_id()
    fake_kakao["docs"] = [_kakao_doc(_new_kakao_id(), "다른 헬스장")]

    r = client.put(
        "/v1/trainer/me/gym/kakao",
        json={"kakao_place_id": missing, "name": "없는 헬스장"},
        headers=_auth(token),
    )
    assert r.status_code == 404, r.text
    db_session.expire_all()
    assert db_session.get(models.Place, missing) is None


def test_selecting_a_non_gym_kakao_place_is_404(client, trainer, fake_kakao, db_session):
    from app.models import models

    token, _ = trainer
    food_id = _new_kakao_id()
    fake_kakao["docs"] = [_kakao_doc(food_id, "헬스식당", category="음식점 > 한식")]

    r = client.put(
        "/v1/trainer/me/gym/kakao",
        json={"kakao_place_id": food_id, "name": "헬스식당"},
        headers=_auth(token),
    )
    assert r.status_code == 404, r.text
    db_session.expire_all()
    assert db_session.get(models.Place, food_id) is None


def test_selecting_an_existing_gym_does_not_call_kakao(
    client, trainer, kakao_off, db_session, created_places
):
    """이미 `places` 에 있는 카카오 헬스장은 카카오를 다시 부르지 않고 고른다.

    시드에는 실재 업체(숫자 카카오 id)가 없으므로 테스트가 직접 만든다(#2811).
    """
    from app.models import models

    token, _ = trainer
    place_id = _new_kakao_id()
    db_session.add(models.Place(
        id=place_id, name="이미 있는 헬스장", category="fitness",
        address="", lat=37.55, lng=126.93,
    ))
    db_session.commit()
    created_places.append(place_id)

    r = client.put(
        "/v1/trainer/me/gym/kakao",
        json={"kakao_place_id": place_id, "name": "아무 이름"},
        headers=_auth(token),
    )
    assert r.status_code == 200, r.text
    assert r.json()["gym"]["id"] == place_id


def test_selecting_a_non_fitness_place_is_404(client, trainer, kakao_off, db_session):
    """카카오 id 가 우연히 다른 카테고리 장소와 같아도 소속이 되지 않는다."""
    from app.models import models

    token, _ = trainer
    place_id = _new_kakao_id()
    db_session.add(models.Place(id=place_id, name="어느 병원", category="medical"))
    db_session.commit()
    try:
        r = client.put(
            "/v1/trainer/me/gym/kakao",
            json={"kakao_place_id": place_id, "name": "어느 병원"},
            headers=_auth(token),
        )
        assert r.status_code == 404, r.text
    finally:
        db_session.query(models.Place).filter(models.Place.id == place_id).delete()
        db_session.commit()


def test_new_gym_without_kakao_is_503(client, trainer, kakao_off):
    token, _ = trainer
    r = client.put(
        "/v1/trainer/me/gym/kakao",
        json={"kakao_place_id": _new_kakao_id(), "name": "새 헬스장"},
        headers=_auth(token),
    )
    assert r.status_code == 503, r.text


def test_kakao_failure_while_selecting_is_503(client, trainer, fake_kakao):
    token, _ = trainer
    fake_kakao["fail"] = True
    r = client.put(
        "/v1/trainer/me/gym/kakao",
        json={"kakao_place_id": _new_kakao_id(), "name": "새 헬스장"},
        headers=_auth(token),
    )
    assert r.status_code == 503, r.text


def test_same_gym_picked_twice_stays_one_row(
    client, trainer, fake_kakao, created_places, db_session
):
    from app.models import models

    token, _ = trainer
    new_id = _new_kakao_id()
    created_places.append(new_id)
    fake_kakao["docs"] = [_kakao_doc(new_id, "새 헬스장")]
    body = {"kakao_place_id": new_id, "name": "새 헬스장"}

    assert client.put("/v1/trainer/me/gym/kakao", json=body, headers=_auth(token)).status_code == 200
    assert client.put("/v1/trainer/me/gym/kakao", json=body, headers=_auth(token)).status_code == 200
    # 두 번째는 이미 있는 행을 쓰므로 카카오를 다시 부르지 않는다.
    assert len(fake_kakao["calls"]) == 1

    db_session.expire_all()
    assert db_session.query(models.Place).filter(
        (models.Place.id == new_id) | (models.Place.kakao_place_id == new_id)
    ).count() == 1


@pytest.mark.parametrize("body", [
    {"kakao_place_id": "abc", "name": "헬스장"},
    {"kakao_place_id": "123", "name": ""},
    {"kakao_place_id": "", "name": "헬스장"},
])
def test_select_rejects_bad_body(client, trainer, kakao_off, body):
    token, _ = trainer
    r = client.put("/v1/trainer/me/gym/kakao", json=body, headers=_auth(token))
    assert r.status_code == 422, r.text
