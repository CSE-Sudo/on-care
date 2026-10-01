"""운영 데이터에서 데모 흔적 분리. (#2811)

- 설정: 데모 시드 기본값 꺼짐, 운영에서 켜면 기동 거부.
- 시드: 실재 업체 id·상호에 가상 트레이너를 붙이지 않는다.
- 디렉터리: 데모가 꺼진 서버에서는 데모 트레이너가 목록·추천·상세·상담 대상에서 빠진다.
- 정리 스크립트: 시드 id 목록만 지우고, 실제 사용자가 참조하는 장소는 남긴다.
"""
from __future__ import annotations

from uuid import uuid4

import pytest
from pydantic import ValidationError

from app.core.config import Settings, get_settings

#: 예전 시드가 가상 트레이너를 붙였던 실재 업체(카카오 place id).
REAL_KAKAO_GYM_IDS = {"11621774", "1558845892", "328969863", "696444256"}


def _prod(**kw) -> Settings:
    base = dict(
        _env_file=None,
        env="prod",
        jwt_secret="a-strong-random-secret-value",
        cors_allow_origins="https://app.oncare.com",
        auto_create_tables=False,
    )
    base.update(kw)
    return Settings(**base)


@pytest.fixture
def no_seed_env(monkeypatch):
    """CI·로컬 환경변수(SEED_DEMO_DATA=true 등)가 설정 기본값 검사를 덮지 않게 한다."""
    monkeypatch.delenv("SEED_DEMO_DATA", raising=False)


@pytest.fixture
def demo_off(monkeypatch):
    """데모 시드가 꺼진 서버(운영과 같은 조건)."""
    monkeypatch.setattr(get_settings(), "seed_demo_data", False)


# ---- 설정 (DB 불필요) ----


def test_seed_demo_data_is_off_by_default(no_seed_env):
    """환경변수 없이 띄우면 데모 시드가 돌지 않는다."""
    assert Settings(_env_file=None).seed_demo_data is False


def test_prod_rejects_demo_seed_even_with_strong_password():
    """운영 + 데모 시드는 비밀번호 강도와 상관없이 기동 거부."""
    with pytest.raises(ValidationError):
        _prod(seed_demo_data=True)
    with pytest.raises(ValidationError):
        _prod(seed_demo_data=True, demo_login_password="Str0ng!Demo#Pass-long")


def test_prod_without_demo_seed_starts(no_seed_env):
    assert _prod().seed_demo_data is False


def test_dev_may_enable_demo_seed():
    assert Settings(_env_file=None, seed_demo_data=True).seed_demo_data is True


def test_demo_data_enabled_follows_setting(monkeypatch):
    from app.db import demo_ids

    monkeypatch.setattr(get_settings(), "seed_demo_data", True)
    assert demo_ids.demo_data_enabled() is True
    monkeypatch.setattr(get_settings(), "seed_demo_data", False)
    assert demo_ids.demo_data_enabled() is False


# ---- 시드 내용 (DB 불필요) ----


def test_seed_has_no_real_business_with_fictional_trainers():
    """시드 어디에도 실재 업체 id 에 소속된 가상 트레이너가 없다."""
    from app.db import seed_gyms

    gym_ids = {row[0] for row in seed_gyms._DEMO_NONPARTNER_GYMS}
    assert not gym_ids & REAL_KAKAO_GYM_IDS
    trainer_gyms = {row[1] for row in seed_gyms._TRAINERS}
    assert not trainer_gyms & REAL_KAKAO_GYM_IDS
    seeded = {row[0] for row in (*seed_gyms._PARTNER_GYMS, *seed_gyms._DEMO_NONPARTNER_GYMS)}
    assert trainer_gyms <= seeded


def test_virtual_nonpartner_gyms_carry_no_phone_number():
    """가상 헬스장에는 전화번호를 넣지 않는다 — 지어낸 번호가 실제 번호일 수 있다."""
    from app.db import seed_gyms

    for row in seed_gyms._DEMO_NONPARTNER_GYMS:
        assert row[8] == "", row[1]


def test_legacy_gym_map_covers_every_old_real_business():
    from app.db import seed_gyms

    assert set(seed_gyms.LEGACY_DISCOVERED_GYM_IDS) == REAL_KAKAO_GYM_IDS
    targets = set(seed_gyms.LEGACY_DISCOVERED_GYM_IDS.values())
    assert targets == {row[0] for row in seed_gyms._DEMO_NONPARTNER_GYMS}


def test_demo_id_lists_cover_every_seeded_account():
    from app.db import demo_ids, seed_gyms
    from app.db.init_db import DEMO_USER_ID
    from app.db.seed_trainer import TRAINER_ID

    trainers = demo_ids.demo_trainer_ids()
    assert TRAINER_ID in trainers
    assert set(seed_gyms.TRAINER_IDS) <= trainers
    assert DEMO_USER_ID in demo_ids.demo_member_ids()
    assert not demo_ids.demo_place_ids() & REAL_KAKAO_GYM_IDS


# ---- 시드 (DB) ----


def test_legacy_demo_trainer_moves_off_real_business(client, db_session):
    """이미 실재 업체에 붙어 있던 데모 트레이너는 가상 헬스장으로 옮겨진다."""
    from app.db import seed_gyms
    from app.models import models

    trainer_id = "trainer-demo-seo"
    old_id = "328969863"
    profile = db_session.query(models.TrainerProfile).filter_by(trainer_id=trainer_id).one()
    original = profile.gym_id
    created_place = db_session.get(models.Place, old_id) is None
    if created_place:
        db_session.add(models.Place(
            id=old_id, name="실재 업체", category="fitness", address="", lat=37.55, lng=126.93,
        ))
        db_session.flush()
    profile.gym_id = old_id
    db_session.commit()
    try:
        moved = seed_gyms._move_demo_trainers_off_real_gyms(db_session)
        db_session.commit()
        assert moved >= 1
        db_session.refresh(profile)
        assert profile.gym_id == seed_gyms.LEGACY_DISCOVERED_GYM_IDS[old_id]
    finally:
        profile.gym_id = original
        db_session.commit()
        if created_place:
            place = db_session.get(models.Place, old_id)
            if place is not None:
                db_session.delete(place)
                db_session.commit()


def test_legacy_move_leaves_real_trainers_alone(client, db_session):
    """같은 업체를 실제 트레이너가 골랐다면 그 소속은 그대로 둔다."""
    from app.db import seed_gyms
    from app.models import models

    old_id = "1558845892"
    created_place = db_session.get(models.Place, old_id) is None
    if created_place:
        db_session.add(models.Place(
            id=old_id, name="실재 업체", category="fitness", address="", lat=37.55, lng=126.93,
        ))
        db_session.flush()
    trainer_id = f"t-real-{uuid4().hex[:8]}"
    db_session.add(models.User(
        id=trainer_id, email=f"{trainer_id}@example.com", name="실제 트레이너",
        hashed_password="x", role="trainer",
    ))
    db_session.flush()
    db_session.add(models.TrainerProfile(trainer_id=trainer_id, gym_id=old_id))
    db_session.commit()
    try:
        seed_gyms._move_demo_trainers_off_real_gyms(db_session)
        db_session.commit()
        profile = db_session.query(models.TrainerProfile).filter_by(trainer_id=trainer_id).one()
        assert profile.gym_id == old_id
    finally:
        db_session.delete(db_session.get(models.User, trainer_id))
        db_session.commit()
        if created_place:
            place = db_session.get(models.Place, old_id)
            if place is not None:
                db_session.delete(place)
                db_session.commit()


# ---- 디렉터리 (DB) ----


def test_directory_lists_demo_trainers_on_demo_server(client):
    """데모 서버(시드 켜짐)는 지금처럼 데모 트레이너를 보여 준다."""
    from app.db import demo_ids

    if not demo_ids.demo_data_enabled():
        pytest.skip("데모 시드가 꺼진 서버")
    ids = {t["id"] for t in client.get("/v1/trainers").json()}
    assert ids & demo_ids.demo_trainer_ids()


def test_directory_hides_demo_trainers_when_demo_is_off(client, demo_off):
    from app.db import demo_ids

    demo = demo_ids.demo_trainer_ids()
    listed = client.get("/v1/trainers")
    assert listed.status_code == 200, listed.text
    assert not {t["id"] for t in listed.json()} & demo

    recommended = client.get("/v1/trainers/recommended")
    assert recommended.status_code == 200, recommended.text
    assert not {t["id"] for t in recommended.json()} & demo


def test_demo_trainer_detail_is_404_when_demo_is_off(client, demo_off):
    assert client.get("/v1/trainers/trainer-park").status_code == 404
    assert client.get("/v1/trainers/trainer-demo-seo").status_code == 404


def test_gym_trainer_list_hides_demo_trainers_when_demo_is_off(client, demo_off):
    r = client.get("/v1/gyms/gym-oncare-sinchon/trainers")
    assert r.status_code == 200, r.text
    from app.db import demo_ids

    assert not {t["id"] for t in r.json()} & demo_ids.demo_trainer_ids()


def test_consultation_to_demo_trainer_is_rejected_when_demo_is_off(
    client, db_session, demo_off
):
    from tests.test_consultations import _auth, _payload, _register_member

    _member_id, token = _register_member(client)
    payload = _payload(trainer_id="trainer-park", slot_id="no-slot")
    r = client.post("/v1/consultations", headers=_auth(token), json=payload)
    assert r.status_code == 404, r.text


def test_real_trainer_stays_listed_when_demo_is_off(client, db_session, demo_off):
    """데모가 아닌 트레이너는 데모 설정과 상관없이 그대로 나온다."""
    from app.models import models

    trainer_id = _user(db_session, "trainer", "real-directory")
    db_session.add(models.TrainerProfile(
        trainer_id=trainer_id, gym_id="gym-healthmate", specialty="퍼스널 트레이너",
    ))
    db_session.commit()
    try:
        ids = {t["id"] for t in client.get("/v1/trainers").json()}
        assert trainer_id in ids
    finally:
        db_session.delete(db_session.get(models.User, trainer_id))
        db_session.commit()


# ---- 정리 스크립트 (DB) ----


def _user(db, role: str, prefix: str) -> str:
    from app.models import models

    user_id = f"{prefix}-{uuid4().hex[:8]}"
    db.add(models.User(
        id=user_id, email=f"{user_id}@example.com", name=prefix,
        hashed_password="x", role=role,
    ))
    db.flush()
    return user_id


def _place(db, prefix: str) -> str:
    from app.models import models

    place_id = f"{prefix}-{uuid4().hex[:8]}"
    db.add(models.Place(
        id=place_id, name=prefix, category="fitness", address="", lat=37.5, lng=127.0,
    ))
    db.flush()
    return place_id


def test_purge_preview_counts_without_deleting(client, db_session):
    from app.models import models
    from scripts.purge_demo_data import build_plan

    trainer = _user(db_session, "trainer", "purge-trainer")
    member = _user(db_session, "member", "purge-member")
    place = _place(db_session, "purge-gym")
    db_session.add(models.TrainerProfile(trainer_id=trainer, gym_id=place))
    db_session.add(models.MemberGym(member_id=member, gym_id=place))
    db_session.commit()
    try:
        plan = build_plan(db_session, [trainer, member, "never-seeded"], [place, "no-place"])
        assert plan.user_ids == sorted([trainer, member])  # 없는 id 는 빠진다
        assert plan.place_ids == [place]                   # 데모만 참조하는 장소
        assert plan.dependent_rows.get("trainer_profiles") == 1
        assert plan.dependent_rows.get("member_gyms") == 1
        # 미리보기는 아무것도 지우지 않는다.
        db_session.expire_all()
        assert db_session.get(models.User, trainer) is not None
        assert db_session.get(models.Place, place) is not None
    finally:
        for user_id in (trainer, member):
            row = db_session.get(models.User, user_id)
            if row is not None:
                db_session.delete(row)
        db_session.commit()
        row = db_session.get(models.Place, place)
        if row is not None:
            db_session.delete(row)
            db_session.commit()


def test_purge_keeps_places_real_users_rely_on(client, db_session):
    from app.models import models
    from scripts.purge_demo_data import apply_plan, build_plan

    demo_trainer = _user(db_session, "trainer", "purge-demo")
    real_trainer = _user(db_session, "trainer", "purge-real")
    shared = _place(db_session, "purge-shared")
    demo_only = _place(db_session, "purge-demo-only")
    db_session.add(models.TrainerProfile(trainer_id=demo_trainer, gym_id=demo_only))
    db_session.add(models.TrainerProfile(trainer_id=real_trainer, gym_id=shared))
    db_session.commit()
    try:
        plan = build_plan(db_session, [demo_trainer], [shared, demo_only])
        assert plan.place_ids == [demo_only]
        assert shared in plan.kept_places

        apply_plan(db_session, plan)
        db_session.expire_all()
        assert db_session.get(models.User, demo_trainer) is None
        assert db_session.get(models.Place, demo_only) is None
        # 실제 트레이너와 그 소속은 그대로다.
        assert db_session.get(models.User, real_trainer) is not None
        assert db_session.get(models.Place, shared) is not None
        profile = db_session.query(models.TrainerProfile).filter_by(trainer_id=real_trainer).one()
        assert profile.gym_id == shared
    finally:
        for user_id in (demo_trainer, real_trainer):
            row = db_session.get(models.User, user_id)
            if row is not None:
                db_session.delete(row)
        db_session.commit()
        for place_id in (shared, demo_only):
            row = db_session.get(models.Place, place_id)
            if row is not None:
                db_session.delete(row)
        db_session.commit()


def test_purge_removes_restricting_reservations_first(client, db_session):
    """자리를 연 데모 트레이너도 지워진다 — 자리는 CASCADE, 걸린 예약은 계획에 든다."""
    from app.models import models
    from scripts.purge_demo_data import apply_plan, build_plan
    from tests.test_consultations import _create_slot

    trainer = _user(db_session, "trainer", "purge-slot-trainer")
    db_session.commit()
    slot = _create_slot(db_session, trainer)
    rows = db_session.query(models.TrainerReservation).filter_by(slot_id=slot.id).count()
    plan = build_plan(db_session, [trainer], [])
    assert len(plan.reservation_ids) == rows
    apply_plan(db_session, plan)
    db_session.expire_all()
    assert db_session.get(models.User, trainer) is None
