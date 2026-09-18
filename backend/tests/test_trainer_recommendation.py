"""회원 신호 기반 트레이너 추천 순위. (#500) DB 필요.

전에는 `/trainers/recommended` 가 `recommend_reason` 이 비지 않은 행을 그대로
돌려줘 **어떤 회원이 보든 같은 순서**였다. 여기서 확인하는 것은 두 가지다 —
목표가 다르면 순서가 달라지는가, 그리고 신호가 없는 회원이 빈 화면을 보지 않는가.
"""
from __future__ import annotations

from uuid import uuid4


def _register(client, **onboarding) -> dict:
    """새 회원을 만들고 온보딩까지 마친 뒤 인증 헤더를 준다."""
    email = f"rec-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register", json={"email": email, "password": "pw!", "name": "u"}
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "pw!"}
    ).json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    if onboarding:
        r = client.post("/v1/users/me/onboarding", json=onboarding, headers=headers)
        assert r.status_code == 200, r.text
    return headers


def _ids(client, headers) -> list[str]:
    r = client.get("/v1/trainers/recommended", headers=headers)
    assert r.status_code == 200, r.text
    return [t["id"] for t in r.json()]


def _rank_of(ids: list[str], trainer_id: str) -> int:
    assert trainer_id in ids, f"{trainer_id} 가 추천 목록에 없다: {ids}"
    return ids.index(trainer_id)


def test_goals_change_the_order(client):
    """목표가 다른 두 회원은 다른 순서를 받는다 — 이 이슈의 본질."""
    slimming = _register(client, conditions="비만")
    strength = _register(client, goals="근력을 키우고 싶어요")

    slimming_ids = _ids(client, slimming)
    strength_ids = _ids(client, strength)

    assert slimming_ids != strength_ids, "회원이 달라도 순서가 같으면 추천이 아니다"

    # 감량 정체기를 다루는 정수빈은 '비만' 회원 쪽에서 더 앞이어야 한다.
    assert _rank_of(slimming_ids, "trainer-demo-jung") < _rank_of(
        strength_ids, "trainer-demo-jung"
    )
    # 근력 전문 윤재희는 반대로 '근력' 회원 쪽에서 더 앞이다.
    assert _rank_of(strength_ids, "trainer-yoon") < _rank_of(
        slimming_ids, "trainer-yoon"
    )


def test_matched_trainer_outranks_unmatched(client):
    """목표가 맞는 트레이너가 맞지 않는 트레이너보다 앞선다."""
    headers = _register(client, conditions="비만")
    ids = _ids(client, headers)

    # 감량을 다루는 정수빈 vs 시니어 균형 운동을 다루는 조민혁.
    assert _rank_of(ids, "trainer-demo-jung") < _rank_of(ids, "trainer-cho")


def test_member_without_signals_still_gets_the_rail(client):
    """온보딩 전 회원도 빈 화면을 보지 않는다 — 기존 큐레이션 목록으로 폴백."""
    headers = _register(client)  # 온보딩 없음
    ids = _ids(client, headers)

    assert ids, "신호가 없다고 추천 레일이 비면 홈 화면에 구멍이 난다"
    # 폴백은 '사유가 있는 트레이너' 라는 기존 조건 그대로다.
    body = client.get("/v1/trainers/recommended", headers=headers).json()
    assert all(t["reason"] for t in body)


def test_curated_reason_is_not_overwritten(client):
    """사람이 쓴 사유가 자동 생성 문구로 덮이지 않는다."""
    headers = _register(client, conditions="비만")
    body = client.get("/v1/trainers/recommended", headers=headers).json()

    jung = next(t for t in body if t["id"] == "trainer-demo-jung")
    assert jung["reason"] == "감량 정체기 식사·운동량 재조정"


def test_generated_reason_fills_an_empty_one(client, db_session):
    """큐레이션 사유가 없는 트레이너는 점수 근거에서 만든 문구를 받는다."""
    from sqlalchemy import select

    from app.models import models

    yoon = db_session.scalar(
        select(models.TrainerProfile).where(
            models.TrainerProfile.trainer_id == "trainer-yoon"
        )
    )
    original = yoon.recommend_reason
    yoon.recommend_reason = ""
    db_session.commit()
    try:
        headers = _register(client, goals="근력을 키우고 싶어요")
        body = client.get("/v1/trainers/recommended", headers=headers).json()
        entry = next((t for t in body if t["id"] == "trainer-yoon"), None)
        assert entry is not None, "점수가 붙었으면 사유가 비어도 레일에 오른다"
        assert entry["reason"], "생성 문구가 비면 화면에 근거가 사라진다"
        assert "근력" in entry["reason"]
    finally:
        yoon.recommend_reason = original
        db_session.commit()


def test_joining_a_gym_lifts_its_trainers(client, db_session):
    """내 헬스장 소속이면 순위가 올라간다.

    같은 헬스장은 단일 항목으로는 가장 큰 가중치지만 **점수는 blend** 라, 목표가
    맞는 근처 트레이너가 같은 헬스장의 무관한 트레이너를 앞설 수 있다. 그건 의도한
    동작이다 — 1km 떨어진 전문가가 실제로 더 나은 추천일 수 있다. 그래서 "무조건
    1등" 이 아니라 **다른 조건을 고정했을 때 순위가 오르는가** 로 확인한다.
    """
    from sqlalchemy import select

    from app.models import models

    headers = _register(client, conditions="비만")
    me = client.get("/v1/users/me", headers=headers).json()["id"]

    # 감량과 무관하고 경력도 짧아 원래 하위인 한서준으로 확인한다. 이미 상위인
    # 트레이너를 쓰면 가점을 받아도 순위가 그대로일 수 있어(위쪽이 더 높음) 신호가
    # 살아 있는지 구분되지 않는다.
    target = "trainer-demo-han"
    before = _rank_of(_ids(client, headers), target)

    profile = db_session.scalar(
        select(models.TrainerProfile).where(
            models.TrainerProfile.trainer_id == target
        )
    )
    db_session.add(models.MemberGym(member_id=me, gym_id=profile.gym_id))
    db_session.commit()
    try:
        after = _rank_of(_ids(client, headers), target)
        assert after < before, "내 헬스장 소속인데 순위가 그대로면 신호가 죽은 것"
    finally:
        db_session.query(models.MemberGym).filter_by(member_id=me).delete()
        db_session.commit()


def test_order_is_stable_across_calls(client):
    """같은 회원은 새로고침해도 같은 순서를 본다(동점 정렬이 결정적)."""
    headers = _register(client, conditions="비만")
    assert _ids(client, headers) == _ids(client, headers)
