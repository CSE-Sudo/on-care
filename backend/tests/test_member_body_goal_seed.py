"""담당 회원의 키·몸무게와 식단·운동 목표 시드. (#2597)

트레이너 웹 신체·목표 창을 열면 거의 모든 회원이 빈칸이었다 — 김민수만 식단
목표가 있었고, 나머지 14명은 성별·건강 목표뿐이었다.
"""

from __future__ import annotations

from sqlalchemy import select

_FIELDS = (
    "height_cm", "weight_kg",
    "daily_calories", "daily_carbs_g", "daily_sugar_g",
    "daily_protein_g", "daily_fat_g", "daily_sodium_mg",
    "daily_burn_kcal", "weekly_cardio_minutes",
    "weekly_strength_sets", "weekly_flexibility_minutes",
)


def test_every_member_has_body_and_goals(client, db_session):
    from app.db.seed_trainer import _MEMBERS
    from app.models.models import HealthProfile

    for user_id, *_ in _MEMBERS:
        profile = db_session.scalar(
            select(HealthProfile).where(HealthProfile.user_id == user_id)
        )
        assert profile is not None, user_id
        missing = [name for name in _FIELDS if getattr(profile, name) is None]
        assert not missing, f"{user_id} 비어 있는 칸: {missing}"


def test_seeded_values_pass_the_trainer_edit_schema():
    """시드 값은 트레이너가 화면에서 그대로 다시 저장할 수 있는 값이어야 한다."""
    from app.db.seed_trainer import _MEMBER_BODY_GOALS, _MEMBERS
    from app.schemas.trainer_api import MemberHealthProfileUpdate

    assert set(_MEMBER_BODY_GOALS) == {user_id for user_id, *_ in _MEMBERS}
    for user_id, values in _MEMBER_BODY_GOALS.items():
        MemberHealthProfileUpdate(**dict(zip(_FIELDS, values, strict=True)))


def test_minsu_keeps_the_member_mock_diet_goals(client, db_session):
    """김민수의 식단 목표는 회원 앱 목업 값 그대로다 — 이 시드가 덮지 않는다."""
    from app.db.seed_member_data import _HEALTH_PROFILE
    from app.models.models import HealthProfile

    profile = db_session.scalar(
        select(HealthProfile).where(HealthProfile.user_id == "user-7d4e9a2c5f18")
    )
    mock = _HEALTH_PROFILE["user-7d4e9a2c5f18"]
    for name in ("daily_calories", "daily_sodium_mg", "daily_sugar_g",
                 "daily_carbs_g", "daily_protein_g", "daily_fat_g"):
        assert getattr(profile, name) == mock[name], name


def test_fill_only_touches_groups_nobody_edited():
    """한 칸이라도 값이 있는 묶음은 건드리지 않는다 — 일부러 비운 칸도 그대로다."""
    from app.db.seed_trainer import _MEMBER_BODY_GOALS, _fill_body_goals
    from app.models.models import HealthProfile

    values = _MEMBER_BODY_GOALS["user-jiho"]
    profile = HealthProfile(user_id="x", weight_kg=90.0, daily_calories=1900)

    assert _fill_body_goals(profile, values) is True

    # 신체·식단 묶음은 누가 손댔다 — 몸무게·칼로리는 그대로, 비운 키·탄수화물도 그대로.
    assert profile.weight_kg == 90.0
    assert profile.height_cm is None
    assert profile.daily_calories == 1900
    assert profile.daily_carbs_g is None
    # 운동 묶음은 비어 있었다 — 시드 값으로 채운다.
    assert profile.daily_burn_kcal == values[8]
    assert profile.weekly_flexibility_minutes == values[11]

    # 다시 돌려도 바뀌는 것이 없다.
    assert _fill_body_goals(profile, values) is False


def test_rerunning_the_seed_keeps_an_edited_value(client, db_session):
    """화면에서 고친 값은 재기동으로 되돌아가지 않는다."""
    from app.db.seed_trainer import seed_member_genders
    from app.models.models import HealthProfile

    def load():
        return db_session.scalar(
            select(HealthProfile).where(HealthProfile.user_id == "user-sera")
        )

    profile = load()
    original = (profile.weight_kg, profile.height_cm)
    profile.weight_kg = 61.5
    profile.height_cm = None
    db_session.commit()

    seed_member_genders()

    db_session.expire_all()
    profile = load()
    assert profile.weight_kg == 61.5
    assert profile.height_cm is None

    # 뒷 테스트를 위해 시드 값으로 되돌린다.
    profile.weight_kg, profile.height_cm = original
    db_session.commit()
