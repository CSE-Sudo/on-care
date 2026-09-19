"""트레이너 리포트 · 프로필 수정 · 고객 AI 코칭 엔드포인트.

순수 로직(주 경계, 리포트 문구)은 DB 없이 돌고, 엔드포인트는 DB 필요
(로컬 skip, CI 실행).
"""
from __future__ import annotations

from datetime import date, timedelta
from uuid import uuid4

import pytest

from app.core import clock


def _trainer_token(client) -> str:
    return client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    ).json()["access_token"]


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


# ---- 순수 로직 ----

def test_week_start_of_normalises_any_day_to_monday():
    from app.services.trainer_service import week_start_of

    monday = date(2026, 8, 3)
    for offset in range(7):
        assert week_start_of(date(2026, 8, 3 + offset)) == monday


def test_meal_kr_labels_all_five_meal_types():
    """다섯 끼니가 모두 제 라벨로 간다 (#1988).

    키는 회원 앱 `MealType.name` 이다 — `lateNight` 만 camelCase 인 것은 그
    이름이 곧 전송값이기 때문이다.
    """
    from app.services.trainer_service import _meal_kr

    assert _meal_kr("breakfast") == "아침"
    assert _meal_kr("lunch") == "점심"
    assert _meal_kr("dinner") == "저녁"
    assert _meal_kr("snack") == "간식"
    assert _meal_kr("lateNight") == "야식"


def test_meal_kr_does_not_fold_late_night_into_snack():
    """야식이 간식으로 접히면 밤늦게 먹은 것을 낮의 간식과 갈라 볼 수 없다."""
    from app.services.trainer_service import _meal_kr

    assert _meal_kr("lateNight") != _meal_kr("snack")


def test_meal_kr_passes_through_unknown_meal_types():
    """모르는 값은 간식으로 접지 않고 그대로 둔다 — 새 끼니가 조용히 섞이면
    트레이너가 틀린 근거로 코칭한다."""
    from app.services.trainer_service import _meal_kr

    assert _meal_kr("brunch") == "brunch"


def test_report_message_omits_figures_without_data():
    """기록이 없는 항목은 빈 값을 적지 않고 아예 뺀다 — '이행률 0%'는 거짓말."""
    from app.schemas.trainer_api import WeeklyReportOut
    from app.services.trainer_service import report_message

    report = WeeklyReportOut(
        member_id="m", member_name="김민수",
        week_start="2026-08-03", week_end="2026-08-09",
        sessions_booked=0, sessions_done=0,
        completion_avg=None, sodium_over_days=0, sodium_avg=None,
        message="",
    )
    text = report_message(report)
    assert "주간 리포트" in text
    assert "이행률" not in text
    assert "나트륨" not in text


def test_report_message_praises_only_a_genuinely_good_week():
    from app.schemas.trainer_api import WeeklyReportOut
    from app.services.trainer_service import report_message

    def message(completion: int, over_days: int) -> str:
        return report_message(WeeklyReportOut(
            member_id="m", member_name="김민수",
            week_start="2026-08-03", week_end="2026-08-09",
            sessions_booked=2, sessions_done=2,
            completion_avg=completion, sodium_over_days=over_days,
            sodium_avg=1500, message="",
        ))

    assert "잘하셨어요" in message(80, 1)
    # 이행률이 좋아도 식단이 무너졌으면 칭찬만 하고 넘어가지 않는다.
    assert "잘하셨어요" not in message(80, 4)
    assert "잘하셨어요" not in message(40, 0)


# ---- 엔드포인트 ----

def test_report_returns_the_week_containing_the_requested_day(client):
    token = _trainer_token(client)
    r = client.get(
        "/v1/trainer/clients/user-jisu/report",
        params={"week_start": "2026-08-05"},  # 수요일
        headers=_auth(token),
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["week_start"] == "2026-08-03"
    assert body["week_end"] == "2026-08-09"
    assert body["member_id"] == "user-jisu"
    # 미리보기와 전송 본문이 갈라지지 않도록 메시지를 함께 내려준다.
    assert body["message"]


def test_report_rejects_a_malformed_week_start(client):
    token = _trainer_token(client)
    r = client.get(
        "/v1/trainer/clients/user-jisu/report",
        params={"week_start": "2026-08"},
        headers=_auth(token),
    )
    assert r.status_code == 422


def test_report_of_someone_elses_client_is_404(client):
    token = _trainer_token(client)
    r = client.get("/v1/trainer/clients/user-nobody/report", headers=_auth(token))
    assert r.status_code == 404


def test_send_report_lands_in_the_member_chat_thread(client):
    token = _trainer_token(client)
    r = client.post(
        "/v1/trainer/clients/user-jisu/report/send",
        json={"week_start": "2026-08-05"},
        headers=_auth(token),
    )
    assert r.status_code == 201, r.text
    assert "주간 리포트" in r.json()["body"]

    thread = client.get(
        "/v1/trainer/clients/user-jisu/chat", headers=_auth(token)
    ).json()
    assert any("주간 리포트" in m["body"] for m in thread)


def test_send_report_uses_the_trainers_own_edit_when_given(client):
    token = _trainer_token(client)
    r = client.post(
        "/v1/trainer/clients/user-jisu/report/send",
        json={"message": "이번 주 컨디션 어땠어요? 다음 주 계획 같이 봐요."},
        headers=_auth(token),
    )
    assert r.status_code == 201, r.text
    assert r.json()["body"] == "이번 주 컨디션 어땠어요? 다음 주 계획 같이 봐요."


# ---- 피드백 초안 (#821) ----

def test_feedback_draft_is_empty_before_anything_is_saved(client):
    """저장한 적 없는 주는 404 가 아니라 빈 본문이다 — 아직 안 쓴 것은 오류가 아니다."""
    token = _trainer_token(client)
    r = client.get(
        "/v1/trainer/clients/user-jisu/report/feedback",
        params={"week_start": "2026-08-05"},
        headers=_auth(token),
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["body"] == ""
    assert body["updated_at"] is None
    assert body["week_start"] == "2026-08-03"


def test_feedback_draft_survives_leaving_and_coming_back(client):
    token = _trainer_token(client)
    saved = client.put(
        "/v1/trainer/clients/user-jisu/report/feedback",
        json={"week_start": "2026-08-05", "body": "어깨 안정화 위주로 한 주 더 갑니다."},
        headers=_auth(token),
    )
    assert saved.status_code == 200, saved.text
    assert saved.json()["updated_at"] is not None

    again = client.get(
        "/v1/trainer/clients/user-jisu/report/feedback",
        params={"week_start": "2026-08-07"},  # 같은 주의 다른 요일
        headers=_auth(token),
    )
    assert again.json()["body"] == "어깨 안정화 위주로 한 주 더 갑니다."


def test_saving_again_replaces_the_same_week_instead_of_stacking(client):
    token = _trainer_token(client)
    for text in ("처음 쓴 초안", "고쳐 쓴 초안"):
        r = client.put(
            "/v1/trainer/clients/user-jisu/report/feedback",
            json={"week_start": "2026-07-27", "body": text},
            headers=_auth(token),
        )
        assert r.status_code == 200, r.text
    assert (
        client.get(
            "/v1/trainer/clients/user-jisu/report/feedback",
            params={"week_start": "2026-07-27"},
            headers=_auth(token),
        ).json()["body"]
        == "고쳐 쓴 초안"
    )


def test_each_week_keeps_its_own_draft(client):
    """주차가 키에 들어가야 지난 주를 열었을 때 그때 문구가 나온다."""
    token = _trainer_token(client)
    for week, text in (("2026-06-01", "6월 첫 주"), ("2026-06-08", "6월 둘째 주")):
        client.put(
            "/v1/trainer/clients/user-jisu/report/feedback",
            json={"week_start": week, "body": text},
            headers=_auth(token),
        )
    for week, text in (("2026-06-01", "6월 첫 주"), ("2026-06-08", "6월 둘째 주")):
        assert (
            client.get(
                "/v1/trainer/clients/user-jisu/report/feedback",
                params={"week_start": week},
                headers=_auth(token),
            ).json()["body"]
            == text
        )


def test_saving_an_empty_draft_is_a_real_save(client):
    """지운 것을 '저장한 적 없음' 으로 되돌리면 다음에 열 때 지운 문구가 되살아난다."""
    token = _trainer_token(client)
    client.put(
        "/v1/trainer/clients/user-jisu/report/feedback",
        json={"week_start": "2026-05-04", "body": "지울 문구"},
        headers=_auth(token),
    )
    client.put(
        "/v1/trainer/clients/user-jisu/report/feedback",
        json={"week_start": "2026-05-04", "body": ""},
        headers=_auth(token),
    )
    body = client.get(
        "/v1/trainer/clients/user-jisu/report/feedback",
        params={"week_start": "2026-05-04"},
        headers=_auth(token),
    ).json()
    assert body["body"] == ""
    # 저장한 적 없는 상태와 구분된다 — 시각이 남는다.
    assert body["updated_at"] is not None


def test_feedback_draft_does_not_reach_the_member_chat(client):
    """저장은 회원에게 아무것도 보내지 않는다 — 전송과 별개의 동작이다."""
    token = _trainer_token(client)
    before = client.get(
        "/v1/trainer/clients/user-jisu/chat", headers=_auth(token)
    ).json()
    client.put(
        "/v1/trainer/clients/user-jisu/report/feedback",
        json={"week_start": "2026-08-05", "body": "아직 보내지 않은 문구"},
        headers=_auth(token),
    )
    after = client.get(
        "/v1/trainer/clients/user-jisu/chat", headers=_auth(token)
    ).json()
    assert len(after) == len(before)
    assert not any("아직 보내지 않은 문구" in m["body"] for m in after)


def test_feedback_draft_of_someone_elses_client_is_404(client):
    token = _trainer_token(client)
    assert (
        client.get(
            "/v1/trainer/clients/user-nobody/report/feedback", headers=_auth(token)
        ).status_code
        == 404
    )
    assert (
        client.put(
            "/v1/trainer/clients/user-nobody/report/feedback",
            json={"body": "남의 고객"},
            headers=_auth(token),
        ).status_code
        == 404
    )


def test_feedback_draft_rejects_a_body_longer_than_a_report_message(client):
    """저장은 됐는데 보낼 수 없는 길이가 생기면 안 된다 — 전송과 같은 2000자."""
    token = _trainer_token(client)
    r = client.put(
        "/v1/trainer/clients/user-jisu/report/feedback",
        json={"week_start": "2026-08-05", "body": "가" * 2001},
        headers=_auth(token),
    )
    assert r.status_code == 422


def test_feedback_draft_rejects_a_malformed_week_start(client):
    token = _trainer_token(client)
    assert (
        client.get(
            "/v1/trainer/clients/user-jisu/report/feedback",
            params={"week_start": "2026-08"},
            headers=_auth(token),
        ).status_code
        == 422
    )


# ---- 프로필 수정 ----

def test_put_me_updates_only_the_sent_fields(client):
    token = _trainer_token(client)
    before = client.get("/v1/trainer/me", headers=_auth(token)).json()

    try:
        r = client.put(
            "/v1/trainer/me",
            json={"phone": "010-9999-0000", "career_years": 9},
            headers=_auth(token),
        )
        assert r.status_code == 200, r.text
        body = r.json()
        assert body["phone"] == "010-9999-0000"
        assert body["career"] == "9년"
        # 보내지 않은 값은 그대로 — 부분 수정이 나머지를 지우면 안 된다.
        assert body["specialty"] == before["specialty"]
        assert body["gym"]["name"] == before["gym"]["name"]
    finally:
        # 실패해도 되돌린다 — 오염된 시드는 같은 파일의 뒤 테스트를 연달아
        # 무너뜨린다.
        client.put(
            "/v1/trainer/me",
            json={
                "phone": before["phone"],
                "career_years": int(before["career"].rstrip("년")),
            },
            headers=_auth(token),
        )


def test_put_me_rejects_an_explicit_null(client):
    """NOT NULL 컬럼에 null 을 반영하면 IntegrityError 500 이 된다.
    누락(변경 없음)과 null(잘못된 값)을 구분한다."""
    token = _trainer_token(client)
    r = client.put("/v1/trainer/me", json={"phone": None}, headers=_auth(token))
    assert r.status_code == 422


def test_put_me_replaces_certifications_wholesale(client):
    token = _trainer_token(client)
    before = client.get("/v1/trainer/me", headers=_auth(token)).json()

    try:
        r = client.put(
            "/v1/trainer/me",
            json={"certifications": ["  스포츠 영양사  ", "", "  "]},
            headers=_auth(token),
        )
        assert r.status_code == 200, r.text
        # 공백만 있는 항목은 버리고 나머지는 trim.
        assert r.json()["certifications"] == ["스포츠 영양사"]
    finally:
        client.put(
            "/v1/trainer/me",
            json={"certifications": before["certifications"]},
            headers=_auth(token),
        )


def test_put_me_with_no_fields_is_rejected(client):
    """빈 본문을 200 으로 돌려주면 클라이언트가 저장됐다고 오해한다."""
    token = _trainer_token(client)
    r = client.put("/v1/trainer/me", json={}, headers=_auth(token))
    assert r.status_code == 400


# ---- 트레이너 연락처 형식 (#1914) ----
#
# 회원 쪽은 #1780(가입)·#1883(프로필 수정)이 한 기준으로 맞췄는데 이 경로만
# 길이(20자)만 보고 있었다. 같은 종류의 값을 두 앱이 다른 기준으로 받으면,
# 나중에 이 번호를 회원 화면에 보일 때 그 자리에서 정리부터 해야 한다.


@pytest.mark.parametrize("phone", ["없음", "0101234", "010-1234-567"])
def test_put_me_rejects_a_malformed_phone(client, phone):
    """전에는 20자 안이면 무엇이든 200 이었다."""
    token = _trainer_token(client)
    r = client.put("/v1/trainer/me", json={"phone": phone}, headers=_auth(token))
    assert r.status_code == 422, r.text


def test_put_me_normalizes_phone_like_the_member_paths(client):
    """하이픈 없이 보내도 회원 경로와 같은 한 표기로 저장된다."""
    token = _trainer_token(client)
    before = client.get("/v1/trainer/me", headers=_auth(token)).json()
    try:
        r = client.put(
            "/v1/trainer/me", json={"phone": "01098765432"}, headers=_auth(token)
        )
        assert r.status_code == 200, r.text
        assert r.json()["phone"] == "010-9876-5432"
        again = client.get("/v1/trainer/me", headers=_auth(token))
        assert again.json()["phone"] == "010-9876-5432"
    finally:
        client.put(
            "/v1/trainer/me", json={"phone": before["phone"]}, headers=_auth(token)
        )


def test_put_me_allows_clearing_the_phone(client):
    """트레이너 가입은 전화번호를 받지 않는다 — 처음부터 없는 값을 요구하면 안 된다.

    회원 쪽의 "있던 번호는 못 지운다"(#1883)는 가입이 필수로 받기 때문이고,
    여기는 그 전제가 없다.
    """
    token = _trainer_token(client)
    before = client.get("/v1/trainer/me", headers=_auth(token)).json()
    try:
        r = client.put("/v1/trainer/me", json={"phone": ""}, headers=_auth(token))
        assert r.status_code == 200, r.text
        assert r.json()["phone"] == ""
    finally:
        client.put(
            "/v1/trainer/me", json={"phone": before["phone"]}, headers=_auth(token)
        )


@pytest.mark.parametrize(
    "gym_phone", ["02-1234-5678", "02-332-1720", "0502-5552-4212", "010-7616-9819"]
)
def test_gym_phone_keeps_every_shape_a_gym_number_takes(gym_phone):
    """헬스장 대표번호에는 휴대전화 규칙을 걸지 않는다. (DB 불필요)

    시드의 실제 번호만 봐도 9~12자리가 섞여 있다(`seed_gyms`). 휴대전화 3-4-4 를
    요구하면 **정상 번호가 422** 로 막히고, 더 나쁘게는 소속을 설정할 때
    `Place.phone` 이 이 칸에 그대로 들어오므로(`set_trainer_gym`) 그 뒤로 이 폼을
    저장할 수 없게 된다.

    엔드포인트가 아니라 스키마에서 보는 이유는, 소속이 있는 트레이너는 헬스장
    칸을 직접 고칠 수 없어(409) 형식 검사까지 가지 않기 때문이다.
    """
    from app.schemas.trainer_api import TrainerMeUpdate

    assert TrainerMeUpdate(gym_phone=gym_phone).gym_phone == gym_phone


# ---- 고객 AI 코칭 ----

def test_client_ai_coach_answers_about_the_member(client):
    token = _trainer_token(client)
    r = client.post(
        "/v1/trainer/clients/user-jisu/ai-coach",
        json={"message": "이번 주 식단에서 뭘 조정하면 좋을까요?"},
        headers=_auth(token),
    )
    # LLM 키가 없어도 검색 기반 폴백이 답을 돌려준다.
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["member_id"] == "user-jisu"
    assert body["reply"]


def test_client_ai_coach_rejects_an_empty_message(client):
    token = _trainer_token(client)
    r = client.post(
        "/v1/trainer/clients/user-jisu/ai-coach",
        json={"message": "   "},
        headers=_auth(token),
    )
    assert r.status_code == 400


def test_client_ai_coach_of_someone_elses_client_is_404(client):
    """남의 고객이면 존재조차 드러내지 않는다(권한 경계)."""
    token = _trainer_token(client)
    r = client.post(
        "/v1/trainer/clients/user-nobody/ai-coach",
        json={"message": "안녕하세요"},
        headers=_auth(token),
    )
    assert r.status_code == 404


# ---- 비밀번호 변경 ----

def test_password_change_requires_the_current_password(client):
    """토큰만으로 비밀번호를 바꿀 수 있으면 탈취 = 계정 탈취가 된다."""
    token = _trainer_token(client)
    r = client.post(
        "/v1/trainer/me/password",
        json={"current_password": "wrong-password", "new_password": "newpass123"},
        headers=_auth(token),
    )
    # 401 이 아니라 400 — 토큰은 유효하므로 클라이언트가 로그아웃으로 오인하면 안 된다.
    assert r.status_code == 400, r.text
    assert "현재 비밀번호" in r.json()["detail"]


def test_password_change_rejects_the_same_password(client):
    token = _trainer_token(client)
    r = client.post(
        "/v1/trainer/me/password",
        json={"current_password": "oncare123", "new_password": "oncare123"},
        headers=_auth(token),
    )
    assert r.status_code == 400, r.text


def test_password_change_rejects_a_short_password(client):
    token = _trainer_token(client)
    r = client.post(
        "/v1/trainer/me/password",
        json={"current_password": "oncare123", "new_password": "short"},
        headers=_auth(token),
    )
    assert r.status_code == 422


def test_password_change_takes_effect_and_can_be_reverted(client):
    token = _trainer_token(client)
    r = client.post(
        "/v1/trainer/me/password",
        json={"current_password": "oncare123", "new_password": "oncare45678"},
        headers=_auth(token),
    )
    assert r.status_code == 200, r.text

    try:
        # 옛 비밀번호로는 더 이상 로그인되지 않고, 새 비밀번호로는 된다.
        old = client.post(
            "/v1/auth/login",
            data={"username": "trainer@oncare.com", "password": "oncare123"},
        )
        assert old.status_code == 401
        new = client.post(
            "/v1/auth/login",
            data={"username": "trainer@oncare.com", "password": "oncare45678"},
        )
        assert new.status_code == 200, new.text
    finally:
        # 반드시 되돌린다 — 시드 비밀번호가 남으면 이 파일의 다른 테스트가
        # _trainer_token() 에서 KeyError 로 줄줄이 죽는다. 토큰도 여기서
        # 새로 얻는다(위 로그인이 실패했을 수 있다).
        recovered = client.post(
            "/v1/auth/login",
            data={"username": "trainer@oncare.com", "password": "oncare45678"},
        )
        if recovered.status_code == 200:
            revert = client.post(
                "/v1/trainer/me/password",
                json={
                    "current_password": "oncare45678",
                    "new_password": "oncare123",
                },
                headers=_auth(recovered.json()["access_token"]),
            )
            assert revert.status_code == 200, revert.text


def test_password_change_needs_a_trainer_account(client):
    """회원 계정은 /trainer/* 전체가 403 이다."""
    email = f"member-{uuid4().hex[:8]}@oncare.com"
    client.post("/v1/auth/register", json={"email": email, "password": "pw!", "name": "u"})
    member = client.post(
        "/v1/auth/login", data={"username": email, "password": "pw!"}
    ).json()["access_token"]
    r = client.post(
        "/v1/trainer/me/password",
        json={"current_password": "pw!", "new_password": "newpass123"},
        headers=_auth(member),
    )
    assert r.status_code == 403


# ---- 알림 수신 설정 (#379) ----

def test_settings_defaults_come_from_the_server(client):
    """클라이언트마다 기본값을 들고 있으면 기기별로 갈라진다."""
    token = _trainer_token(client)
    r = client.get("/v1/trainer/me/settings", headers=_auth(token))
    assert r.status_code == 200, r.text
    body = r.json()
    assert set(body) == {
        "notify_new_message", "notify_session_reminder", "reminder_lead_minutes",
    }
    assert body["notify_new_message"] is True
    assert body["notify_session_reminder"] is True
    assert body["reminder_lead_minutes"] == 30


def test_settings_update_persists_and_is_partial(client):
    token = _trainer_token(client)
    before = client.get("/v1/trainer/me/settings", headers=_auth(token)).json()
    try:
        r = client.put(
            "/v1/trainer/me/settings",
            json={"notify_new_message": False},
            headers=_auth(token),
        )
        assert r.status_code == 200, r.text
        assert r.json()["notify_new_message"] is False
        # 보내지 않은 값은 그대로.
        assert r.json()["reminder_lead_minutes"] == before["reminder_lead_minutes"]

        # 다시 읽어도 유지된다(기기가 아니라 계정에 붙어 있다).
        again = client.get("/v1/trainer/me/settings", headers=_auth(token)).json()
        assert again["notify_new_message"] is False
    finally:
        client.put("/v1/trainer/me/settings", json=before, headers=_auth(token))


def test_settings_reject_a_lead_time_outside_the_options(client):
    token = _trainer_token(client)
    r = client.put(
        "/v1/trainer/me/settings",
        json={"reminder_lead_minutes": 45},
        headers=_auth(token),
    )
    assert r.status_code == 422


def test_settings_reject_an_explicit_null(client):
    """명시적 null 은 422 — NOT NULL 컬럼에 그대로 넣으면 500 이 난다.

    누락(변경 없음)과 null(잘못된 값)을 구분한다. TrainerMeUpdate ·
    ScheduleUpdateRequest 와 같은 규약.
    """
    token = _trainer_token(client)
    for payload in (
        {"notify_new_message": None},
        {"notify_session_reminder": None},
        {"reminder_lead_minutes": None},
    ):
        r = client.put("/v1/trainer/me/settings", json=payload, headers=_auth(token))
        assert r.status_code == 422, (payload, r.status_code, r.text)


def test_settings_update_with_no_fields_is_rejected(client):
    token = _trainer_token(client)
    r = client.put("/v1/trainer/me/settings", json={}, headers=_auth(token))
    assert r.status_code == 400


def test_settings_need_a_trainer_account(client):
    email = f"member-{uuid4().hex[:8]}@oncare.com"
    client.post("/v1/auth/register", json={"email": email, "password": "pw!", "name": "u"})
    member = client.post(
        "/v1/auth/login", data={"username": email, "password": "pw!"}
    ).json()["access_token"]
    assert client.get("/v1/trainer/me/settings", headers=_auth(member)).status_code == 403


def test_report_carries_the_requested_weeks_daily_series(client, db_session):
    """계열은 **그 주** 것이다. (#752)

    로스터가 주는 계열은 이번 주 것이라, 과거 주 화면이 그것을 쓰면 지난 주
    날짜 아래 이번 주 수치가 실린다. 리포트가 자기 주의 계열을 들고 온다.
    """
    import json

    from app.models.models import DietEntry, ExerciseSession, RoutineHistory
    from app.services.trainer_service import week_start_of

    last_week = week_start_of(clock.today()) - timedelta(days=7)
    sunday = (last_week + timedelta(days=6)).isoformat()
    tuesday = (last_week + timedelta(days=1)).isoformat()
    # 시드가 최근 며칠을 채워 두고 테스트 DB 는 실행 사이에 남는다. 이 주만
    # 비우고 시작해야 몇 번을 돌려도 같은 결과가 나온다.
    for model in (DietEntry, RoutineHistory):
        owner = model.user_id if model is DietEntry else model.member_id
        db_session.query(model).filter(
            owner == "user-jisu",
            model.date >= last_week.isoformat(),
            model.date <= sunday,
        ).delete(synchronize_session=False)
    # 운동 기록은 날짜가 아니라 (그 주 월요일, 요일) 로 저장된다 — 주차로 지운다.
    db_session.query(ExerciseSession).filter(
        ExerciseSession.user_id == "user-jisu",
        ExerciseSession.week_start == last_week.isoformat(),
    ).delete(synchronize_session=False)
    db_session.add(
        DietEntry(
            id=f"t-diet-{uuid4().hex[:8]}",
            user_id="user-jisu",
            date=tuesday,
            meal_type="lunch",
            time_label="",
            foods_json=json.dumps([{"name": "지난 주 점심"}], ensure_ascii=False),
            total_calories=700,
            sodium_mg=2400,
            sugar_g=12.5,
            engine="test",
        )
    )
    db_session.add(
        RoutineHistory(
            id=f"t-hist-{uuid4().hex[:8]}",
            member_id="user-jisu",
            trainer_id=None,
            date=tuesday,
            kind_label="자율 운동",
            completion_rate=80,
            exercises_json=json.dumps(
                ["걷기 30분 ✓", "코어 강화 ✓", "스트레칭 ✗"], ensure_ascii=False
            ),
        )
    )
    # 요일 칸이 읽는 곳은 여기다 — 이행률과 달리 실제로 한 운동만 남는다(#1288).
    # id 앞자리를 공유해 뒤의 순번이 정렬을 정한다 — 리포트가 그 순서로 적는다.
    batch = uuid4().hex[:8]
    for order, (kind, name) in enumerate((("cardio", "걷기 30분"), ("strength", "코어 강화"))):
        db_session.add(
            ExerciseSession(
                id=f"t-ex-{batch}-{order}",
                user_id="user-jisu",
                week_start=last_week.isoformat(),
                day_label="화",
                type=kind,
                name=name,
                minutes=30,
                calories=150,
            )
        )
    db_session.commit()

    token = _trainer_token(client)
    r = client.get(
        "/v1/trainer/clients/user-jisu/report",
        params={"week_start": last_week.isoformat()},
        headers=_auth(token),
    )
    assert r.status_code == 200, r.text
    body = r.json()

    for key in ("week_completion", "sodium_week", "calories_week", "sugar_week"):
        assert len(body[key]) == 7, key
    # 화요일 자리에 그 주의 값이 놓인다.
    assert body["sodium_week"][1] == 2400
    assert body["calories_week"][1] == 700
    assert body["sugar_week"][1] == 12.5
    assert body["week_completion"][1] == 80
    # 그날 **실제로 한** 운동이 함께 온다(#754, #1288). 배정 목록이 아니라 운동
    # 기록에서 오므로 미수행(✗)은 실리지 않는다 — 배정에 날짜가 없어 "그날
    # 배정됐는데 안 했다" 가 만들어지지 않는다.
    assert len(body["days"]) == 7
    assert body["days"][1]["completion"] == 80
    assert body["days"][1]["exercises"] == ["걷기 30분", "코어 강화"]
    assert all("✗" not in name for name in body["days"][1]["exercises"])
    assert body["days"][0]["completion"] == 0
    assert body["days"][0]["exercises"] == []
    # 기록이 없는 날은 0 이고, 이번 주 수치가 섞여 들어오지 않는다.
    assert body["sodium_week"][0] == 0
    assert body["sodium_avg"] == 2400  # 기록된 하루만 나눈다
    assert body["sodium_over_days"] == 1
    assert body["completion_avg"] == 80


def test_report_lists_exercise_a_member_logged_alone(client, db_session):
    """회원 혼자 한 운동도 요일 칸에 온다. (#1288)

    예전에는 요일 칸이 `routine_history` 에서 왔는데, 그 표에 쓰는 경로는 PT 세션
    완료 하나뿐이었다. 회원이 배정 루틴을 수행하든 직접 기록하든 결과는
    `exercise_sessions` 로 가므로, PT 가 없던 날은 트레이너가 리포트에서 아무것도
    볼 수 없었다.
    """
    from app.models.models import ExerciseSession, RoutineHistory
    from app.services.trainer_service import week_start_of

    last_week = week_start_of(clock.today()) - timedelta(days=7)
    sunday = (last_week + timedelta(days=6)).isoformat()
    # 이행률의 재료(`routine_history`)를 비워 둔 채로 확인한다 — 요일 칸이 그것과
    # 무관하게 채워져야 이 이슈가 풀린 것이다.
    db_session.query(RoutineHistory).filter(
        RoutineHistory.member_id == "user-jisu",
        RoutineHistory.date >= last_week.isoformat(),
        RoutineHistory.date <= sunday,
    ).delete(synchronize_session=False)
    db_session.query(ExerciseSession).filter(
        ExerciseSession.user_id == "user-jisu",
        ExerciseSession.week_start == last_week.isoformat(),
    ).delete(synchronize_session=False)
    db_session.add(
        ExerciseSession(
            id=f"t-solo-{uuid4().hex[:8]}",
            user_id="user-jisu",
            week_start=last_week.isoformat(),
            day_label="목",
            type="strength",
            name="데드리프트",
            minutes=40,
            calories=260,
            source="member",
        )
    )
    db_session.commit()

    token = _trainer_token(client)
    r = client.get(
        "/v1/trainer/clients/user-jisu/report",
        params={"week_start": last_week.isoformat()},
        headers=_auth(token),
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["days"][3]["exercises"] == ["데드리프트"]
    # 이행률은 여전히 배정 쪽 지표라 비어 있다 — 두 값의 출처가 다르다.
    assert body["days"][3]["completion"] == 0


def test_report_falls_back_to_the_type_label_when_a_record_has_no_name(
    client, db_session
):
    """이름 칸이 생기기 전(#1276)의 기록도 무엇을 했는지는 남는다. (#1288)"""
    from app.models.models import ExerciseSession

    last_week_monday = clock.today() - timedelta(days=clock.today().weekday() + 7)
    db_session.query(ExerciseSession).filter(
        ExerciseSession.user_id == "user-jisu",
        ExerciseSession.week_start == last_week_monday.isoformat(),
    ).delete(synchronize_session=False)
    db_session.add(
        ExerciseSession(
            id=f"t-noname-{uuid4().hex[:8]}",
            user_id="user-jisu",
            week_start=last_week_monday.isoformat(),
            day_label="월",
            type="cardio",
            name="",
            minutes=25,
            calories=180,
        )
    )
    db_session.commit()

    token = _trainer_token(client)
    r = client.get(
        "/v1/trainer/clients/user-jisu/report",
        params={"week_start": last_week_monday.isoformat()},
        headers=_auth(token),
    )
    assert r.status_code == 200, r.text
    assert r.json()["days"][0]["exercises"] == ["유산소"]


def test_report_rejects_a_week_that_has_not_arrived(client):
    """아직 오지 않은 주는 값이 전부 0 인 리포트가 되어 회원에게 보낼 수 있다."""
    token = _trainer_token(client)
    next_week = (clock.today() + timedelta(days=7)).isoformat()
    r = client.get(
        "/v1/trainer/clients/user-jisu/report",
        params={"week_start": next_week},
        headers=_auth(token),
    )
    assert r.status_code == 422

    sent = client.post(
        "/v1/trainer/clients/user-jisu/report/send",
        json={"week_start": next_week},
        headers=_auth(token),
    )
    assert sent.status_code == 422


# ---- 리포트 요약 (#755) ----
#
# 요약은 화면이 이미 보여 주는 수치만 인용해야 한다. 모델이 근거를 지어내면
# 트레이너가 그걸 회원에게 그대로 보낸다 — 그래서 계약 위반으로 보고 규칙 기반
# 요약으로 되돌아간다.

def _report(**over):
    from app.schemas.trainer_api import WeeklyReportDayOut, WeeklyReportOut

    base = dict(
        member_id="m", member_name="김민수",
        week_start="2026-08-10", week_end="2026-08-16",
        sessions_booked=1, sessions_done=1,
        completion_avg=87, sodium_over_days=4, sodium_avg=2288,
        calories_week=[1710, 1830, 1560, 1900, 1680, 1067, 0],
        days=[WeeklyReportDayOut(completion=67, exercises=["풀업 3세트 ✗"])],
        message="",
    )
    base.update(over)
    return WeeklyReportOut(**base)


def test_summary_evidence_quotes_only_screen_figures():
    """근거 문장은 화면의 수치에서 만든다 — 여기 없는 말은 인용될 수 없다."""
    from app.services import trainer_report_summary_service as svc

    lines = svc._evidence(_report())

    assert "운동 이행률 평균 87%" in lines
    # 수치는 화면과 같은 서식으로 적는다 — 그래프가 `2,288mg` 이라고 적는 값을
    # 요약만 `2288mg` 이라고 쓰면 트레이너는 다른 값으로 읽는다(#1177).
    assert any("나트륨 평균 2,288mg" in line for line in lines)
    # 건너뛴 운동은 분량을 떼고 묶는다 — 같은 운동을 요일마다 건너뛴 것이
    # 서로 다른 운동으로 읽히면 안 된다(#1177).
    assert any("건너뛴 운동: 풀업" in line for line in lines)


def test_summary_headline_does_not_call_an_over_week_on_target():
    """평균이 목표 안이어도 사흘을 넘긴 주는 `목표 범위 안` 이 아니다(#1177)."""
    from app.services import trainer_report_summary_service as svc

    report = _report(sodium_avg=1916, sodium_over_days=3, completion_avg=81)
    summary = svc._rule_summary(report, svc._evidence(report))

    assert "목표 범위 안" not in summary.headline
    assert "나트륨 목표 초과 3일" in summary.headline
    # 잘한 쪽도 함께 말한다 — 챙길 것만 남으면 보낼 만한 글이 못 된다.
    assert "운동 이행률 81%" in summary.headline


def test_summary_falls_back_when_model_invents_evidence():
    """입력에 없는 근거를 만들어 오면 규칙 기반으로 되돌린다."""
    import json

    import pytest

    from app.services import trainer_report_summary_service as svc

    report = _report()
    evidence = svc._evidence(report)
    invented = json.dumps(
        {"headline": "좋았습니다", "points": ["체지방 3kg 감소"]}, ensure_ascii=False
    )

    with pytest.raises(ValueError):
        svc._decode(invented, report, evidence)


def test_summary_accepts_verbatim_evidence():
    import json

    from app.services import trainer_report_summary_service as svc

    report = _report()
    evidence = svc._evidence(report)
    ok = json.dumps(
        {"headline": "이행률은 좋았고 나트륨을 챙기면 됩니다.", "points": [evidence[0]]},
        ensure_ascii=False,
    )

    out = svc._decode(ok, report, evidence)

    assert out.generated_by == "llm"
    assert out.points == [evidence[0]]
    assert out.week_start == "2026-08-10"


def test_rule_summary_names_both_the_good_and_the_watch():
    """잘한 점만 적으면 트레이너가 고칠 게 없고, 지적만 적으면 회원에게 못 보낸다."""
    from app.services import trainer_report_summary_service as svc

    report = _report()
    out = svc._rule_summary(report, svc._evidence(report))

    assert out.generated_by == "rule"
    assert "87%" in out.headline
    # 목표를 넘긴 주는 평균이 아니라 **넘긴 날 수**로 말한다 — 평균만 적으면
    # 나흘을 넘긴 사실이 헤드라인에서 사라진다(#1177).
    assert "나트륨 목표 초과 4일" in out.headline


def test_rule_summary_without_records_does_not_invent_a_week():
    from app.services import trainer_report_summary_service as svc

    report = _report(
        completion_avg=None, sodium_avg=None, sodium_over_days=0,
        sessions_booked=0, sessions_done=0, calories_week=[], days=[],
    )
    out = svc._rule_summary(report, svc._evidence(report))

    assert out.points == []
    assert "기록이 없어" in out.headline


# ---- 주간 주의사항 통합 (#1430) ----
#
# 예전에는 AI 입력이 이행률·나트륨·칼로리 평균만 담고, 당류는 앱이 따로 계산해
# `다음 주 할 일` 에만 적었다. 나트륨 외 주의사항만 있는 주는 요약이 "목표 범위
# 안"이라고 말할 수 있었다. 판정을 한 곳(`watchpoints`)으로 모은다.

def test_sugar_only_week_is_still_a_watch_week():
    """당류만 넘긴 주도 근거와 규칙 요약이 그 사실을 말한다."""
    from app.services import trainer_report_summary_service as svc

    report = _report(
        completion_avg=95,
        sodium_avg=1500,
        sodium_over_days=0,
        sugar_week=[72, 80, 61, 90, 0, 0, 0],
        calories_week=[2000, 2000, 2000, 2000, 0, 0, 0],
        days=[],
    )
    evidence = svc._evidence(report)
    out = svc._rule_summary(report, evidence)

    assert any("당류" in line for line in evidence)
    assert "목표 범위 안" not in out.headline
    assert "당류" in out.headline


def test_calories_are_judged_against_the_personal_target():
    """평균만 싣지 않는다 — 목표와 견준 결과가 근거에 담긴다."""
    from app.services import trainer_report_summary_service as svc

    report = _report(
        completion_avg=95,
        sodium_avg=1400,
        sodium_over_days=0,
        calorie_target=2600,
        calories_week=[1700, 1750, 1680, 1720, 0, 0, 0],
        days=[],
    )
    kinds = {w.kind for w in svc.watchpoints(report)}
    evidence = svc._evidence(report)

    assert "calories" in kinds
    # 어느 기준으로 판정했는지도 문장에 남는다 — 고객마다 목표가 다르다.
    assert any("개인 목표 2,600kcal" in line and "부족" in line for line in evidence)


def test_macro_balance_uses_personal_targets_only():
    """탄·단·지는 개인 목표가 있을 때만 본다 — 지어낸 기준으로 나무라지 않는다."""
    from app.services import trainer_report_summary_service as svc

    without = _report(
        completion_avg=95, sodium_avg=1400, sodium_over_days=0,
        protein_week=[40, 45, 38, 0, 0, 0, 0], days=[],
    )
    assert not any(w.kind == "macro" for w in svc.watchpoints(without))

    with_target = without.model_copy(update={"protein_target": 120})
    watch = [w for w in svc.watchpoints(with_target) if w.kind == "macro"]
    assert watch and "단백질" in watch[0].text and "부족" in watch[0].text


def test_no_record_and_future_days_are_not_counted_as_over():
    """기록 없는 날(0)은 초과·미달 계산에 들어가지 않는다."""
    from app.services import trainer_report_summary_service as svc

    # 화요일까지만 기록한 주 — 나머지 0 을 함께 나누면 평균이 반토막 난다.
    report = _report(
        completion_avg=95, sodium_avg=1400, sodium_over_days=0,
        calories_week=[2000, 2050, 0, 0, 0, 0, 0],
        sugar_week=[20, 22, 0, 0, 0, 0, 0],
        days=[],
    )
    kinds = {w.kind for w in svc.watchpoints(report)}

    assert "calories" not in kinds
    assert "sugar" not in kinds


def test_many_watchpoints_are_not_silently_dropped():
    """근거를 잘라야 하면 위험한 것부터 남기고, 잘린 수를 카드가 말한다."""
    from app.services import trainer_report_summary_service as svc

    report = _report(
        completion_avg=40,
        sodium_avg=2600,
        sodium_over_days=5,
        sugar_week=[80, 90, 75, 70, 60, 0, 0],
        calories_week=[3000, 3100, 2900, 3050, 0, 0, 0],
    )
    evidence = svc._evidence(report)
    out = svc._rule_summary(report, evidence)

    assert len(svc.watchpoints(report)) > svc.MAX_POINTS
    assert len(out.points) == svc.MAX_POINTS
    assert out.points[-1].startswith("외 ")
    # 가장 위험한 항목이 먼저 남는다.
    assert "운동 이행률" in out.points[0]
    assert "목표 범위 안" not in out.headline


def test_llm_and_rule_paths_share_the_same_watchpoints():
    """모델이 고르는 근거와 규칙 기반 요약이 같은 목록에서 나온다."""
    import json

    from app.services import trainer_report_summary_service as svc

    report = _report(
        completion_avg=95, sodium_avg=1400, sodium_over_days=0,
        sugar_week=[80, 90, 75, 0, 0, 0, 0], days=[],
    )
    evidence = svc._evidence(report)
    sugar_line = next(line for line in evidence if "당류" in line)

    out = svc._decode(
        json.dumps(
            {"headline": "당류를 함께 챙기면 좋겠습니다.", "points": [sugar_line]},
            ensure_ascii=False,
        ),
        report,
        evidence,
    )

    assert out.points == [sugar_line]
    assert sugar_line in svc._evidence(report)
