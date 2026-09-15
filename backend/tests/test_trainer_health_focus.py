"""트레이너 화면의 회원 목표 = 회원 건강 목표. (#1818) DB 필요.

예전에는 트레이너가 따로 적은 자유 문장(`TrainerClient.goal`)을 보여 줘, 회원앱이
고르는 건강 목표와 같은 사람을 두 화면이 다르게 말했다. 여기서는 한 칸을 둘이
함께 읽고 고치는지 본다.
"""
from __future__ import annotations

from sqlalchemy import select


def _h(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _login(client, email: str) -> str:
    return client.post(
        "/v1/auth/login", data={"username": email, "password": "oncare123"}
    ).json()["access_token"]


def _roster_goal(client, trainer_token: str, member_id: str) -> str:
    roster = client.get("/v1/trainer/clients", headers=_h(trainer_token))
    assert roster.status_code == 200, roster.text
    return next(c for c in roster.json() if c["id"] == member_id)["goal"]


def test_roster_goal_is_the_member_health_goal(client):
    trainer = _login(client, "trainer@oncare.com")
    member = _login(client, "jisu@oncare.com")
    conditions = client.get("/v1/users/me/profile", headers=_h(member)).json()["conditions"]

    from app.services import health_focus

    assert _roster_goal(client, trainer, "user-jisu") == health_focus.focus_label(conditions)
    assert _roster_goal(client, trainer, "user-jisu") == "체중 감량 · 체력 강화"


def test_trainer_edit_changes_the_same_goal_the_member_sees(client, db_session):
    from app.models.models import HealthProfile

    trainer = _login(client, "trainer@oncare.com")
    member = _login(client, "jisu@oncare.com")
    original = db_session.scalar(
        select(HealthProfile.conditions).where(HealthProfile.user_id == "user-jisu")
    )
    try:
        saved = client.put(
            "/v1/trainer/clients/user-jisu/health-profile",
            headers=_h(trainer),
            # 세 개를 보내고 옛 질환 이름·주의사항을 섞어도 회원앱과 같은 규칙으로 정리한다.
            json={"conditions": "재활, 근력 향상, 체력 강화, 당뇨, 무릎 통증으로 러닝 자제"},
        )
        assert saved.status_code == 200, saved.text
        assert saved.json()["conditions"] == "근력 향상, 체력 강화, 무릎 통증으로 러닝 자제"

        member_view = client.get("/v1/users/me/profile", headers=_h(member)).json()
        assert member_view["conditions"] == "근력 향상, 체력 강화, 무릎 통증으로 러닝 자제"
        assert _roster_goal(client, trainer, "user-jisu") == "근력 향상 · 체력 강화"
        coach = client.get("/v1/me/coach", headers=_h(member)).json()
        assert coach["goal"] == "근력 향상 · 체력 강화"
    finally:
        db_session.expire_all()
        profile = db_session.scalar(
            select(HealthProfile).where(HealthProfile.user_id == "user-jisu")
        )
        profile.conditions = original
        db_session.commit()


def test_member_edit_shows_up_in_the_trainer_roster(client, db_session):
    from app.models.models import HealthProfile

    trainer = _login(client, "trainer@oncare.com")
    member = _login(client, "jisu@oncare.com")
    original = db_session.scalar(
        select(HealthProfile.conditions).where(HealthProfile.user_id == "user-jisu")
    )
    try:
        saved = client.put(
            "/v1/users/me/health-goals",
            headers=_h(member),
            json={"conditions": "자세 교정"},
        )
        assert saved.status_code == 200, saved.text
        assert _roster_goal(client, trainer, "user-jisu") == "자세 교정"
    finally:
        db_session.expire_all()
        profile = db_session.scalar(
            select(HealthProfile).where(HealthProfile.user_id == "user-jisu")
        )
        profile.conditions = original
        db_session.commit()
