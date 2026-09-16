"""프로필 / 온보딩 / 건강 목표 / 회원 탈퇴 — DB 필요(로컬 skip, CI 실행)."""

from __future__ import annotations

from uuid import uuid4

import pytest


def _register_and_login(client, name: str = "테스터") -> tuple[str, str]:
    """가입+로그인 후 (access_token, email) 반환."""
    email = f"prof-{uuid4().hex[:8]}@oncare.com"
    password = "pw-12345!"
    r = client.post(
        "/v1/auth/register", json={"email": email, "password": password, "name": name}
    )
    assert r.status_code == 201, r.text
    login = client.post(
        "/v1/auth/login", data={"username": email, "password": password}
    )
    assert login.status_code == 200, login.text
    return login.json()["access_token"], email


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def test_onboarding_saves_profile_and_marks_done(client):
    token, email = _register_and_login(client)
    body = {
        "name": "온보딩유저",
        "birth_date": "1990-01-15",
        "gender": "male",
        "height_cm": 175.0,
        "weight_kg": 72.5,
        # 옛 질환 이름으로 보내면 새 건강 목표로 정리해 저장한다(#1814).
        "conditions": "고혈압, 당뇨 전단계",
        "goals": "혈압 정상화",
        "daily_calories": 2000,
        "daily_sodium_mg": 2000,
    }
    r = client.post("/v1/users/me/onboarding", json=body, headers=_auth(token))
    assert r.status_code == 200, r.text
    p = r.json()
    assert p["onboarded"] is True
    assert p["name"] == "온보딩유저"
    assert p["conditions"] == "혈압 관리"
    assert p["height_cm"] == 175.0
    assert p["weight_kg"] == 72.5
    assert p["daily_calories"] == 2000

    # GET 으로도 동일하게 조회돼야 한다
    got = client.get("/v1/users/me/profile", headers=_auth(token))
    assert got.status_code == 200
    assert got.json()["onboarded"] is True
    assert got.json()["daily_sodium_mg"] == 2000


def test_onboarding_saves_the_same_goal_columns_as_health_goals(client):
    """온보딩이 채운 목표 열 칸이 MY 건강 목표가 고치는 열과 같은 열이어야 한다.

    예전에는 온보딩이 칼로리·나트륨·당류 셋만 받아, 탄단지와 운동 목표는 화면이
    보내도 조용히 버려졌다 — 가입 직후의 홈·식단·운동 탭이 회원이 정한 적 없는
    기본값을 목표선으로 그렸다.
    """
    token, _ = _register_and_login(client)
    goals = {
        "daily_calories": 2565,
        "daily_sodium_mg": 2000,
        "daily_sugar_g": 64,
        "daily_carbs_g": 353,
        "daily_protein_g": 128,
        "daily_fat_g": 71,
        "daily_burn_kcal": 300,
        "weekly_cardio_minutes": 150,
        "weekly_strength_sets": 21,
        "weekly_flexibility_minutes": 60,
    }
    r = client.post("/v1/users/me/onboarding", json=goals, headers=_auth(token))
    assert r.status_code == 200, r.text
    for field, value in goals.items():
        assert r.json()[field] == value, field

    # 다시 읽어도 그대로다 — 응답만 맞고 저장이 안 되는 일이 없어야 한다.
    got = client.get("/v1/users/me/profile", headers=_auth(token))
    assert got.status_code == 200
    for field, value in goals.items():
        assert got.json()[field] == value, field

    # 이어서 MY 건강 목표가 같은 열을 고칠 수 있다.
    put = client.put(
        "/v1/users/me/health-goals",
        json={"weekly_cardio_minutes": 210},
        headers=_auth(token),
    )
    assert put.status_code == 200, put.text
    assert put.json()["weekly_cardio_minutes"] == 210
    assert put.json()["daily_carbs_g"] == 353


@pytest.mark.parametrize(
    "invalid_body",
    [
        {"gender": "invalid"},
        {"height_cm": 49},
        {"height_cm": 301},
    ],
)
def test_onboarding_rejects_invalid_gender_and_height(client, invalid_body):
    token, _ = _register_and_login(client)
    response = client.post(
        "/v1/users/me/onboarding",
        json=invalid_body,
        headers=_auth(token),
    )
    assert response.status_code == 422, response.text


def test_update_me_changes_name_and_phone(client):
    token, _ = _register_and_login(client)
    r = client.put(
        "/v1/users/me",
        json={"name": "새이름", "phone": "010-1234-5678", "birth_date": "1988-03-03"},
        headers=_auth(token),
    )
    assert r.status_code == 200, r.text
    assert r.json()["name"] == "새이름"
    assert r.json()["phone"] == "010-1234-5678"

    me = client.get("/v1/users/me", headers=_auth(token))
    assert me.json()["name"] == "새이름"


def test_update_me_changes_body_profile_and_goal(client):
    token, _ = _register_and_login(client)
    response = client.put(
        "/v1/users/me",
        json={
            "gender": "female",
            "height_cm": 163.5,
            "weight_kg": 54.2,
            "goals": "주 3회 근력 운동",
        },
        headers=_auth(token),
    )
    assert response.status_code == 200, response.text
    profile = response.json()
    assert profile["gender"] == "female"
    assert profile["height_cm"] == 163.5
    assert profile["weight_kg"] == 54.2
    assert profile["goals"] == "주 3회 근력 운동"

    cleared = client.put(
        "/v1/users/me",
        json={"height_cm": None, "weight_kg": None},
        headers=_auth(token),
    )
    assert cleared.status_code == 200, cleared.text
    assert cleared.json()["height_cm"] is None
    assert cleared.json()["weight_kg"] is None


def test_update_me_still_rejects_null_for_non_nullable_profile_fields(client):
    token, _ = _register_and_login(client)
    for field in ("phone", "birth_date", "gender", "goals"):
        response = client.put(
            "/v1/users/me",
            json={field: None},
            headers=_auth(token),
        )
        assert response.status_code == 422, (field, response.text)


def test_update_me_duplicate_email_conflicts_409(client):
    token_a, email_a = _register_and_login(client)
    token_b, _ = _register_and_login(client)
    r = client.put("/v1/users/me", json={"email": email_a}, headers=_auth(token_b))
    assert r.status_code == 409


def test_weekly_exercise_goals_are_saved_per_user(client):
    token_a, _ = _register_and_login(client)
    token_b, _ = _register_and_login(client)

    updated = client.put(
        "/v1/users/me/health-goals",
        json={
            "weekly_workout_goal": 5,
            "weekly_exercise_minutes_goal": 240,
            "weekly_burn_goal": 900,
        },
        headers=_auth(token_a),
    )
    assert updated.status_code == 200, updated.text
    assert updated.json()["weekly_workout_goal"] == 5
    assert updated.json()["weekly_exercise_minutes_goal"] == 240
    assert updated.json()["weekly_burn_goal"] == 900

    profile_a = client.get("/v1/users/me/profile", headers=_auth(token_a))
    assert profile_a.status_code == 200
    assert profile_a.json()["weekly_workout_goal"] == 5
    assert profile_a.json()["weekly_exercise_minutes_goal"] == 240
    assert profile_a.json()["weekly_burn_goal"] == 900

    profile_b = client.get("/v1/users/me/profile", headers=_auth(token_b))
    assert profile_b.status_code == 200
    assert profile_b.json()["weekly_workout_goal"] is None
    assert profile_b.json()["weekly_exercise_minutes_goal"] is None
    assert profile_b.json()["weekly_burn_goal"] is None


def test_exercise_type_goals_are_saved_and_cleared(client):
    """운동 탭이 견주는 목표(일일 소모 + 유형별 주간)를 저장·해제한다. (#1139)"""
    token, _ = _register_and_login(client)

    updated = client.put(
        "/v1/users/me/health-goals",
        json={
            "daily_burn_kcal": 400,
            "weekly_cardio_minutes": 240,
            "weekly_strength_sets": 30,
            "weekly_flexibility_minutes": 90,
        },
        headers=_auth(token),
    )
    assert updated.status_code == 200, updated.text
    assert updated.json()["daily_burn_kcal"] == 400
    assert updated.json()["weekly_cardio_minutes"] == 240
    assert updated.json()["weekly_strength_sets"] == 30
    assert updated.json()["weekly_flexibility_minutes"] == 90

    stored = client.get("/v1/users/me/profile", headers=_auth(token))
    assert stored.json()["daily_burn_kcal"] == 400
    assert stored.json()["weekly_strength_sets"] == 30

    # 명시적 null 은 목표 해제다 — 지운 목표는 지워져야 한다.
    cleared = client.put(
        "/v1/users/me/health-goals",
        json={"daily_burn_kcal": None, "weekly_cardio_minutes": None},
        headers=_auth(token),
    )
    assert cleared.status_code == 200, cleared.text
    assert cleared.json()["daily_burn_kcal"] is None
    assert cleared.json()["weekly_cardio_minutes"] is None
    # 손대지 않은 값은 그대로 남는다.
    assert cleared.json()["weekly_strength_sets"] == 30


def test_delete_me_removes_account(client):
    token, email = _register_and_login(client)
    r = client.delete("/v1/users/me", headers=_auth(token))
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "deleted"

    # 계정이 사라졌으므로 재로그인 불가
    again = client.post(
        "/v1/auth/login", data={"username": email, "password": "pw-12345!"}
    )
    assert again.status_code == 401


def test_profile_writes_require_auth(client):
    # require_auth 는 데모 폴백을 쓰지 않으므로 토큰 없으면 401
    assert client.post("/v1/users/me/onboarding", json={}).status_code == 401
    assert client.put("/v1/users/me", json={"name": "x"}).status_code == 401
    assert client.delete("/v1/users/me").status_code == 401


# ---- 건강 목표가 관리 초점·자유 입력 목표까지 다룬다 (#1471) ----


def test_health_goals_saves_focus_and_free_text_goal(client):
    """온보딩이 저장하던 두 값을 MY `건강 목표` 도 같은 열로 고친다."""
    token, _ = _register_and_login(client)

    saved = client.put(
        "/v1/users/me/health-goals",
        json={"conditions": "혈압 관리, 체중 감량", "goals": "3개월 안에 5km 완주"},
        headers=_auth(token),
    )

    assert saved.status_code == 200
    assert saved.json()["conditions"] == "체중 감량, 혈압 관리"
    assert saved.json()["goals"] == "3개월 안에 5km 완주"

    # 다시 읽어도 그대로다 — 온보딩과 MY 가 같은 값을 본다.
    again = client.get("/v1/users/me/profile", headers=_auth(token))
    assert again.json()["conditions"] == "체중 감량, 혈압 관리"
    assert again.json()["goals"] == "3개월 안에 5km 완주"


def test_health_goals_does_not_wipe_focus_when_only_numbers_change(client):
    """수치 목표만 보낸 저장이 관리 초점을 지우지 않는다."""
    token, _ = _register_and_login(client)
    client.put(
        "/v1/users/me/health-goals",
        json={"conditions": "근력 향상", "goals": "주 3회 근력"},
        headers=_auth(token),
    )

    client.put(
        "/v1/users/me/health-goals",
        json={"daily_calories": 2100},
        headers=_auth(token),
    )

    view = client.get("/v1/users/me/profile", headers=_auth(token))
    assert view.json()["conditions"] == "근력 향상"
    assert view.json()["goals"] == "주 3회 근력"
    assert view.json()["daily_calories"] == 2100


def test_health_goals_cleans_legacy_condition_names_but_keeps_trainer_notes(client):
    """옛 질환 이름은 새 목표로 정리하고, 트레이너가 적은 주의사항은 남긴다. (#1814)"""
    token, _ = _register_and_login(client)

    saved = client.put(
        "/v1/users/me/health-goals",
        json={"conditions": "당뇨, 고혈압, 무릎 통증으로 러닝 자제, 비만"},
        headers=_auth(token),
    )

    assert saved.status_code == 200
    assert saved.json()["conditions"] == "체중 감량, 혈압 관리, 무릎 통증으로 러닝 자제"


# ---- 연락처 형식 (#1883) ----
#
# 가입은 #1780 이 막았지만 이 화면은 같은 값을 다른 문으로 쓴다. 이메일은
# **로그인하는 값**이라, 형식을 보지 않으면 오타 한 번이 계정 잠김이 된다.


@pytest.mark.parametrize("email", ["asdf", "member@oncare", "", "  "])
def test_update_me_rejects_malformed_email(client, email):
    token, original = _register_and_login(client)
    r = client.put("/v1/users/me", json={"email": email}, headers=_auth(token))
    assert r.status_code == 422, r.text

    # 계정은 그대로다 — 원래 주소로 계속 로그인할 수 있다.
    again = client.post(
        "/v1/auth/login", data={"username": original, "password": "pw-12345!"}
    )
    assert again.status_code == 200, again.text


@pytest.mark.parametrize("phone", ["없음", "010-1234-567", "0101234"])
def test_update_me_rejects_malformed_phone(client, phone):
    token, _ = _register_and_login(client)
    r = client.put("/v1/users/me", json={"phone": phone}, headers=_auth(token))
    assert r.status_code == 422, r.text


def test_update_me_normalizes_phone_like_signup(client):
    """가입과 같은 표기로 정리한다 — 여기서 되돌려지면 정규화가 무의미하다."""
    token, _ = _register_and_login(client)
    r = client.put("/v1/users/me", json={"phone": "01012345678"}, headers=_auth(token))
    assert r.status_code == 200, r.text
    assert r.json()["phone"] == "010-1234-5678"

    profile = client.get("/v1/users/me/profile", headers=_auth(token))
    assert profile.json()["phone"] == "010-1234-5678"


def test_update_me_rejects_clearing_an_existing_phone(client):
    """있던 연락처는 지울 수 없다.

    가입 화면이 전화번호를 필수로 받는데(#1634) 이 화면에서 비울 수 있으면 그
    필수가 무의미해지고, 트레이너가 담당 회원에게 연락할 방법이 사라진다.
    """
    token, _ = _register_and_login(client)
    assert (
        client.put(
            "/v1/users/me", json={"phone": "010-1234-5678"}, headers=_auth(token)
        ).status_code
        == 200
    )
    r = client.put("/v1/users/me", json={"phone": ""}, headers=_auth(token))
    assert r.status_code == 422, r.text

    # 지워지지 않았다.
    profile = client.get("/v1/users/me/profile", headers=_auth(token))
    assert profile.json()["phone"] == "010-1234-5678"


def test_update_me_allows_empty_phone_when_there_was_none(client):
    """처음부터 없던 회원에게는 요구하지 않는다.

    소셜 로그인 가입자와 #1634 이전 가입자는 연락처를 넣을 자리가 없었다. 그
    사람들까지 막으면 이름만 고치려는데 전화번호를 내놓으라고 막는 화면이 된다.
    """
    token, _ = _register_and_login(client)  # 가입 시 phone 을 보내지 않는다
    assert client.get("/v1/users/me/profile", headers=_auth(token)).json()["phone"] == ""

    r = client.put(
        "/v1/users/me", json={"name": "이름만", "phone": ""}, headers=_auth(token)
    )
    assert r.status_code == 200, r.text
    assert r.json()["name"] == "이름만"
    assert r.json()["phone"] == ""


def test_update_me_accepts_a_valid_email_change(client):
    """막는 것은 형식이 틀린 값뿐이다 — 제대로 된 주소로는 바꿀 수 있다."""
    token, _ = _register_and_login(client)
    new_email = f"prof-moved-{uuid4().hex[:8]}@oncare.com"
    r = client.put("/v1/users/me", json={"email": new_email}, headers=_auth(token))
    assert r.status_code == 200, r.text
    assert r.json()["email"] == new_email

    moved = client.post(
        "/v1/auth/login", data={"username": new_email, "password": "pw-12345!"}
    )
    assert moved.status_code == 200, moved.text
