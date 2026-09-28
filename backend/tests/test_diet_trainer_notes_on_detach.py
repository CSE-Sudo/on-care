"""담당이 끝나면 트레이너 메시지로 만든 식단 AI 보관물을 내려놓는다. (#1631)

식단 AI 조언과 추천 메뉴 리스트는 담당 트레이너가 최근 보낸 메시지
(`diet_coach_inputs.trainer_notes`)를 프롬프트에 넣어 만든 뒤 보관한다 — 추천
메뉴는 4주, 전체 조언은 그 주, 이번 주 조언은 그날. 새 프롬프트는 활성 담당만
읽으므로 해제 뒤에는 메시지가 들어가지 않지만, 보관물은 그대로 쓰여 끊은
트레이너의 지시가 그 사이 회원의 "다음 식사" 를 계속 정했다.

여기서 보는 것:

* 회원의 트레이너 해제·헬스장 해제, 트레이너의 담당 해제가 이번 주·전체 조언을
  지우고 추천 메뉴 리스트를 오늘로 만료시킨다 — 다음 조회가 담당 없이 다시 만든다.
* 트레이너 메시지를 읽지 않는 `today` 상태와 지난 리스트는 남는다.
* 다른 회원의 보관물과, 담당이 없던 회원의 멱등 해제는 건드리지 않는다.
"""

from __future__ import annotations

from collections.abc import Iterator
from dataclasses import dataclass
from datetime import timedelta
from uuid import uuid4

import pytest
from sqlalchemy import select, text

from app.core import clock
from app.core.security import create_access_token
from app.models.models import DietAdviceState, DietMenuPlan, TrainerClient, User
from app.services import diet_menu_plan


@dataclass
class Pair:
    trainer_id: str
    member_id: str
    other_member_id: str


def _h(user_id: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {create_access_token(user_id)}"}


def _user(user_id: str, role: str) -> User:
    return User(
        id=user_id,
        email=f"{user_id}@oncare.com",
        name="식단 보관 확인",
        hashed_password="unused",
        role=role,
    )


def _advice(user_id: str, period: str) -> DietAdviceState:
    return DietAdviceState(
        id=f"dadv-{uuid4().hex[:16]}",
        user_id=user_id,
        period=period,
        key_date=clock.today_iso(),
        lang="ko",
        payload_json="{}",
    )


def _stash(db_session, user_id: str) -> None:
    """트레이너 메시지를 읽어 만든 것처럼 보관물을 둔다."""
    today = clock.today()
    db_session.add_all([_advice(user_id, p) for p in ("today", "week", "all")])
    db_session.add_all(
        [
            # 지난 리스트 — 이미 만료됐고 "이전 메뉴" 의 근거로만 남아 있다.
            DietMenuPlan(
                id=f"dmp-{uuid4().hex[:12]}",
                user_id=user_id,
                source="llm",
                created_on=(today - timedelta(days=40)).isoformat(),
                expires_on=(today - timedelta(days=12)).isoformat(),
            ),
            # 지금 리스트 — 3주 넘게 남아 있다.
            DietMenuPlan(
                id=f"dmp-{uuid4().hex[:12]}",
                user_id=user_id,
                source="llm",
                created_on=(today - timedelta(days=5)).isoformat(),
                expires_on=(today + timedelta(days=23)).isoformat(),
            ),
        ]
    )


@pytest.fixture()
def pair(db_session) -> Iterator[Pair]:
    suffix = uuid4().hex[:10]
    p = Pair(
        trainer_id=f"notes-trainer-{suffix}",
        member_id=f"notes-member-{suffix}",
        other_member_id=f"notes-other-{suffix}",
    )
    db_session.add_all(
        [
            _user(p.trainer_id, "trainer"),
            _user(p.member_id, "member"),
            _user(p.other_member_id, "member"),
        ]
    )
    db_session.flush()  # TrainerClient 의 FK 부모를 먼저 반영한다.
    db_session.add_all(
        [
            TrainerClient(
                id=f"tc-{uuid4().hex[:12]}",
                trainer_id=p.trainer_id,
                member_id=member_id,
                active=True,
                data_consent_at=clock.now(),
            )
            for member_id in (p.member_id, p.other_member_id)
        ]
    )
    _stash(db_session, p.member_id)
    _stash(db_session, p.other_member_id)
    db_session.commit()
    try:
        yield p
    finally:
        db_session.rollback()
        db_session.execute(
            text("DELETE FROM users WHERE id = ANY(:ids)"),
            {"ids": [p.trainer_id, p.member_id, p.other_member_id]},
        )
        db_session.commit()


def _periods(db_session, user_id: str) -> list[str]:
    db_session.expire_all()
    return sorted(
        db_session.scalars(
            select(DietAdviceState.period).where(DietAdviceState.user_id == user_id)
        ).all()
    )


def _expiries(db_session, user_id: str) -> list[str]:
    db_session.expire_all()
    return sorted(
        db_session.scalars(
            select(DietMenuPlan.expires_on).where(DietMenuPlan.user_id == user_id)
        ).all()
    )


def _assert_forgotten(db_session, user_id: str) -> None:
    today = clock.today()
    assert _periods(db_session, user_id) == ["today"]
    assert _expiries(db_session, user_id) == [
        (today - timedelta(days=12)).isoformat(),
        today.isoformat(),
    ]


def _assert_kept(db_session, user_id: str) -> None:
    today = clock.today()
    assert _periods(db_session, user_id) == ["all", "today", "week"]
    assert _expiries(db_session, user_id) == [
        (today - timedelta(days=12)).isoformat(),
        (today + timedelta(days=23)).isoformat(),
    ]


@pytest.mark.parametrize("path", ["/v1/me/coach/trainer", "/v1/me/coach"])
def test_member_detaching_forgets_the_notes_based_advice(
    client, db_session, pair, path
):
    r = client.delete(path, headers=_h(pair.member_id))
    assert r.status_code == 204, r.text

    _assert_forgotten(db_session, pair.member_id)
    _assert_kept(db_session, pair.other_member_id)


def test_trainer_removing_the_member_forgets_the_notes_based_advice(
    client, db_session, pair
):
    r = client.delete(
        f"/v1/trainer/clients/{pair.member_id}", headers=_h(pair.trainer_id)
    )
    assert r.status_code == 204, r.text

    _assert_forgotten(db_session, pair.member_id)
    _assert_kept(db_session, pair.other_member_id)


def test_the_expired_menu_plan_is_rebuilt_on_the_next_read(
    client, db_session, pair
):
    """오늘로 만료된 리스트는 다음 조회가 다시 만든다."""
    assert client.delete(
        "/v1/me/coach/trainer", headers=_h(pair.member_id)
    ).status_code == 204

    db_session.expire_all()
    latest = db_session.scalars(
        select(DietMenuPlan)
        .where(DietMenuPlan.user_id == pair.member_id)
        .order_by(DietMenuPlan.created_on.desc())
    ).first()
    assert (
        diet_menu_plan.regeneration_reason(
            latest,
            lang="ko",
            today=clock.today(),
            fingerprint=latest.goal_fingerprint,
            recent_days=0,
        )
        == "expired"
    )


def test_detaching_again_leaves_new_advice_alone(client, db_session, pair):
    """이미 담당이 없는 회원의 해제(멱등 204)는 그 뒤에 새로 만든 조언을 지우지 않는다."""
    assert client.delete(
        "/v1/me/coach/trainer", headers=_h(pair.member_id)
    ).status_code == 204
    # 담당 없이 다시 만든 조언이다.
    db_session.add_all([_advice(pair.member_id, p) for p in ("week", "all")])
    db_session.commit()

    assert client.delete(
        "/v1/me/coach/trainer", headers=_h(pair.member_id)
    ).status_code == 204
    assert _periods(db_session, pair.member_id) == ["all", "today", "week"]
