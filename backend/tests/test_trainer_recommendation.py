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


#: 데모 시드에 담당 트레이너가 없는 건강 목표. (#2121)
#:
#: 사전을 넓혀도 채울 수 없다 — 레일에 오르는 트레이너(`seed_gyms._TRAINERS`) 중
#: 혈압·심혈관을 다룬다고 적은 사람이 아무도 없다. `seed_trainer.py` 의 데모
#: 트레이너가 유일하게 `혈압 관리` 를 적어 두었지만 `gym_id` 가 없어 디렉터리
#: 조건(`_trainer_query`)에서 빠진다. 시드 쪽에서 해결할 일이라 여기서는 목록으로
#: 남겨 둔다 — 채워지면 이 집합을 비운다.
_FOCUS_WITHOUT_TRAINER = {"혈압 관리"}


def test_every_focus_matches_someone():
    """온보딩이 고를 수 있는 건강 목표마다 매칭되는 트레이너가 있는가. (#2121)

    키워드 사전은 **트레이너가 실제로 쓰는 말**과 맞물려야만 동작한다. 한쪽만
    바뀌면 그 목표를 고른 회원은 목표 일치 30점을 통째로 못 받고 거리·경력만으로
    줄 세워지는데, 화면에는 아무 표시가 없어 누구도 알아차리지 못한다. 선택지를
    늘리거나 시드 문구를 고칠 때 여기서 걸린다.
    """
    from app.db.seed_gyms import _TRAINERS
    from app.services import health_focus
    from app.services.trainer_recommendation import _CONDITION_NEEDS

    uncovered = []
    for focus in health_focus.FOCUS_OPTIONS:
        need = _CONDITION_NEEDS[focus]
        # score_trainer 와 같은 haystack — specialty · intro · recommend_reason.
        matched = [
            name
            for _id, _gym, name, specialty, reason, _career, intro, _certs in _TRAINERS
            if any(k in f"{specialty} {intro} {reason}" for k in need.keywords)
        ]
        if not matched:
            uncovered.append(need.label)

    assert set(uncovered) == _FOCUS_WITHOUT_TRAINER, (
        f"매칭되는 트레이너가 없는 목표: {uncovered} "
        f"(알려진 공백: {sorted(_FOCUS_WITHOUT_TRAINER)})"
    )


def test_recommend_reason_counts_as_specialty_text():
    """운영자가 적어 둔 추천 사유도 목표 일치 판정에 쓰인다. (#2121)

    `recommend_reason` 은 그 트레이너의 강점을 한 줄로 적은 값이고, 레일 노출
    조건이자 회원 화면에 그대로 나가는 문구다. 점수에서만 빠져 있으면 화면은
    "혈압 관리 지도" 라고 말하는데 정작 혈압 관리 회원에게 가점이 없다.
    """
    from app.models import models
    from app.services.trainer_recommendation import (
        MemberSignals,
        _CONDITION_NEEDS,
        score_trainer,
    )
    from app.services import health_focus

    need = _CONDITION_NEEDS[health_focus.FOCUS_BLOOD_PRESSURE]
    signals = MemberSignals(needs=[need])
    profile = models.TrainerProfile(
        trainer_id="t", specialty="퍼스널 트레이너", intro="1:1 수업을 진행합니다.",
        recommend_reason="혈압 관리와 운동 병행 지도", career_years=0,
    )

    scored = score_trainer(signals, profile, None)

    assert scored.score > 0
    assert need.label in scored.reason
