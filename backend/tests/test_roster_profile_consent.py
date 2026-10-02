"""담당 해제·동의 철회 회원의 로스터 카드는 성별·나이·건강 목표를 비운다. (#2814)

로스터는 해제·철회 관계도 이름·상태와 함께 남긴다(관계 이력 식별용). 식단·메시지·
루틴·신호는 이미 가렸지만, `HealthProfile` 에서 읽는 성별·나이·건강 목표는
그대로 내려가 철회 뒤 회원이 바꾼 **새 목표**까지 트레이너에게 보였다.

여기서 보는 것:

* 활성·동의 링크 — 세 값이 지금처럼 내려온다.
* 동의 기능 이전 링크(동의·철회 둘 다 없음) — 막지 않는다.
* 담당 해제 링크 — 세 값이 빈다.
* 활성이지만 철회 뒤 새 동의 없는 링크 — 세 값이 빈다.
* 철회 뒤 회원이 목표를 바꿔도 트레이너 쪽에는 보이지 않는다.
* 다시 동의하면 값이 돌아온다.
"""
from __future__ import annotations

from datetime import timedelta
from uuid import uuid4

import pytest
from sqlalchemy import select

from app.core import clock
from app.models.models import HealthProfile, TrainerClient, User
from app.services import trainer_service

PREFIX = "roster2814-"


@pytest.fixture
def trainer(db_session):
    trainer = User(
        id=f"{PREFIX}t-{uuid4().hex[:8]}",
        email=f"{PREFIX}{uuid4().hex[:8]}@example.com",
        name="감사트레이너",
        role="trainer",
    )
    db_session.add(trainer)
    db_session.commit()
    yield trainer
    db_session.rollback()
    ids = [
        row[0]
        for row in db_session.query(User.id).filter(User.id.like(f"{PREFIX}%")).all()
    ]
    db_session.query(TrainerClient).filter(
        TrainerClient.trainer_id.in_(ids) | TrainerClient.member_id.in_(ids)
    ).delete(synchronize_session=False)
    db_session.query(HealthProfile).filter(HealthProfile.user_id.in_(ids)).delete(
        synchronize_session=False
    )
    db_session.query(User).filter(User.id.in_(ids)).delete(synchronize_session=False)
    db_session.commit()


def _member_with_profile(db_session, trainer: User, *, order: int, **link_fields):
    member = User(
        id=f"{PREFIX}m-{uuid4().hex[:8]}",
        email=f"{PREFIX}{uuid4().hex[:8]}@example.com",
        name=f"회원{order}",
        role="member",
    )
    db_session.add(member)
    db_session.flush()
    db_session.add(HealthProfile(
        user_id=member.id,
        gender="female",
        conditions="혈압 관리",
        birth_date="1990-01-01",
    ))
    link = TrainerClient(
        id=f"{PREFIX}tc-{uuid4().hex[:8]}",
        trainer_id=trainer.id,
        member_id=member.id,
        sort_order=order,
        **link_fields,
    )
    db_session.add(link)
    db_session.commit()
    return member, link


def _card(db_session, trainer: User, member_id: str):
    rows = trainer_service.build_roster(db_session, trainer.id, limit=50)
    return next(r for r in rows if r.id == member_id)


def _assert_hidden(card) -> None:
    assert card.gender == ""
    assert card.age is None
    assert card.goal == ""


def test_consented_active_link_keeps_profile_fields(db_session, trainer):
    member, _ = _member_with_profile(
        db_session, trainer, order=1, active=True,
        data_consent_at=clock.now() - timedelta(days=3),
    )

    card = _card(db_session, trainer, member.id)

    assert card.gender == "female"
    assert card.age is not None and card.age > 0
    assert card.goal == "혈압 관리"


def test_legacy_link_without_consent_history_is_not_blocked(db_session, trainer):
    """#1022 이전 담당은 소급해서 가리지 않는다(`blocks_access` 와 같은 기준)."""
    member, _ = _member_with_profile(
        db_session, trainer, order=2, active=True,
        data_consent_at=None, data_consent_revoked_at=None,
    )

    card = _card(db_session, trainer, member.id)

    assert card.gender == "female"
    assert card.goal == "혈압 관리"


def test_released_link_hides_gender_age_and_goal(db_session, trainer):
    member, _ = _member_with_profile(
        db_session, trainer, order=3, active=False,
        data_consent_at=None,
        data_consent_revoked_at=clock.now() - timedelta(days=1),
    )

    card = _card(db_session, trainer, member.id)

    # 이름·상태는 관계 이력 식별용으로 남는다(이슈 범위 밖).
    assert card.name == member.name
    assert card.registered is False
    _assert_hidden(card)


def test_released_legacy_link_also_hides_profile(db_session, trainer):
    """동의 기록이 없던 옛 링크라도 해제되면 가린다 — 해제 자체가 기준이다."""
    member, _ = _member_with_profile(
        db_session, trainer, order=4, active=False,
        data_consent_at=None, data_consent_revoked_at=None,
    )

    _assert_hidden(_card(db_session, trainer, member.id))


def test_revoked_but_active_link_hides_profile(db_session, trainer):
    member, _ = _member_with_profile(
        db_session, trainer, order=5, active=True,
        data_consent_at=None,
        data_consent_revoked_at=clock.now() - timedelta(hours=2),
    )

    card = _card(db_session, trainer, member.id)

    assert card.registered is True
    _assert_hidden(card)


def test_goal_changed_after_revocation_does_not_reach_the_trainer(
    db_session, trainer
):
    member, _ = _member_with_profile(
        db_session, trainer, order=6, active=False,
        data_consent_at=None,
        data_consent_revoked_at=clock.now() - timedelta(days=2),
    )
    profile = db_session.scalar(
        select(HealthProfile).where(HealthProfile.user_id == member.id)
    )
    profile.conditions = "재활"
    profile.gender = "male"
    db_session.commit()

    card = _card(db_session, trainer, member.id)

    assert "재활" not in card.goal
    _assert_hidden(card)


def test_new_consent_brings_the_fields_back(db_session, trainer):
    member, link = _member_with_profile(
        db_session, trainer, order=7, active=True,
        data_consent_at=None,
        data_consent_revoked_at=clock.now() - timedelta(days=5),
    )
    _assert_hidden(_card(db_session, trainer, member.id))

    link.data_consent_at = clock.now()
    db_session.commit()

    card = _card(db_session, trainer, member.id)
    assert card.gender == "female"
    assert card.goal == "혈압 관리"


def test_roster_api_hides_fields_for_a_released_member(client, db_session, trainer):
    """라우트까지 — 응답 JSON 에 값이 실리지 않는다."""
    from app.core.security import create_access_token

    member, _ = _member_with_profile(
        db_session, trainer, order=8, active=False,
        data_consent_at=None,
        data_consent_revoked_at=clock.now() - timedelta(days=1),
    )
    token = create_access_token(trainer.id)

    r = client.get(
        "/v1/trainer/clients?limit=50",
        headers={"Authorization": f"Bearer {token}"},
    )

    assert r.status_code == 200, r.text
    row = next(x for x in r.json() if x["id"] == member.id)
    assert row["gender"] == ""
    assert row["age"] is None
    assert row["goal"] == ""
