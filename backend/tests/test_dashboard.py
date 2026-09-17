"""대시보드 요약 집계."""
from __future__ import annotations

import json

import pytest
from sqlalchemy import delete

from app.api.v1.dashboard import (
    _avg_sodium_of_logged, _build_sodium_warning, _rank_sodium_sources,
    _score_for,
)
from app.schemas.dashboard_api import DashboardNutritionDay


def _nday(label: str, *, calories: int, sodium_mg: int) -> DashboardNutritionDay:
    return DashboardNutritionDay(
        date="2026-07-27", label=label, calories=calories,
        sodium_mg=sodium_mg, sugar_g=0,
    )


def test_avg_sodium_of_logged_ignores_unlogged_days():
    # 미래 요일(칼로리 0)은 평균에서 빠진다 — 월·화만 기록됐다면 그 둘의 평균.
    week = [
        _nday("월", calories=1600, sodium_mg=2400),
        _nday("화", calories=1500, sodium_mg=1600),
        _nday("수", calories=0, sodium_mg=0),
        _nday("목", calories=0, sodium_mg=0),
    ]
    assert _avg_sodium_of_logged(week) == pytest.approx(2000.0)


def test_avg_sodium_of_logged_is_none_when_nothing_logged():
    week = [_nday("월", calories=0, sodium_mg=0)]
    assert _avg_sodium_of_logged(week) is None


def test_weekly_score_uses_average_not_single_day():
    # 지난 주는 기록된 날 평균 나트륨이 초과(2400>2000)라 나트륨 보너스가 빠지고,
    # 이번 주는 평균이 예산 이내(1800<=2000)라 보너스가 붙는다 — 하루치가 아니라
    # 주간 평균으로 두 점수를 같은 잣대로 비교한다.
    this_week = [
        _nday("월", calories=1500, sodium_mg=1800),
        _nday("화", calories=1500, sodium_mg=1800),
        _nday("수", calories=0, sodium_mg=0),  # 미래 요일은 무시
    ]
    prev_week = [
        _nday("월", calories=1500, sodium_mg=2400),
        _nday("화", calories=1500, sodium_mg=2400),
    ]
    this_avg = _avg_sodium_of_logged(this_week)
    prev_avg = _avg_sodium_of_logged(prev_week)
    assert this_avg == pytest.approx(1800.0)
    assert prev_avg == pytest.approx(2400.0)
    # 운동량 동일(0)일 때: 이번 주는 +20, 지난 주는 미포함 → delta = 20.
    this_score = _score_for(this_avg <= 2000, 0)
    prev_score = _score_for(prev_avg <= 2000, 0)
    assert this_score - prev_score == 20


def test_score_for_combines_sodium_and_exercise():
    assert _score_for(True, 200) == 100   # 50 + 20(나트륨) + 30(운동 150+)
    assert _score_for(True, 100) == 85    # 50 + 20 + 15(운동 1~149)
    assert _score_for(True, 0) == 70      # 50 + 20
    assert _score_for(False, 0) == 50     # 기본만


@pytest.mark.parametrize(
    ("total_sodium_mg", "source_names", "expected"),
    [
        (2000, ["라면"], None),
        (
            2100,
            [],
            "오늘 나트륨이 2100mg 으로 권장량(2000mg)을 넘었어요.",
        ),
        (2100, ["라면"], "라면 섭취로 나트륨이 높아요."),
        (2100, ["김밥", "라면"], "김밥·라면 섭취로 나트륨이 높아요."),
        (
            2100,
            ["김치찌개", "배추김치", "라면"],
            "김치찌개·배추김치 섭취로 나트륨이 높아요.",
        ),
    ],
)
def test_build_sodium_warning(
    total_sodium_mg: int,
    source_names: list[str],
    expected: str | None,
):
    assert _build_sodium_warning(total_sodium_mg, source_names) == expected


def test_build_sodium_warning_uses_personal_goal():
    assert _build_sodium_warning(1600, [], 1500) == (
        "오늘 나트륨이 1600mg 으로 권장량(1500mg)을 넘었어요."
    )


def test_rank_sodium_sources_combines_duplicate_food_names():
    foods_json_values = [
        json.dumps([
            {"name": "라면", "sodium_mg": 600},
            {"name": "김밥", "sodium_mg": 700},
        ]),
        json.dumps([
            {"name": " 라면 ", "sodium_mg": 600},
            {"name": "샐러드", "sodium_mg": 800},
        ]),
    ]

    assert _rank_sodium_sources(foods_json_values) == ["라면", "샐러드", "김밥"]


def test_dashboard_summary_includes_macros_and_sodium_sources(client, db_session):
    from app.db.init_db import DEMO_USER_ID
    from app.models.models import DietEntry
    from app.services.diet_service import today_str

    db_session.execute(
        delete(DietEntry).where(
            DietEntry.user_id == DEMO_USER_ID,
            DietEntry.date == today_str(),
        )
    )
    db_session.add_all([
        DietEntry(
            id="dashboard-lunch",
            user_id=DEMO_USER_ID,
            date=today_str(),
            meal_type="lunch",
            foods_json=json.dumps([
                {"name": "라면", "sodium_mg": 600},
                {"name": "김밥", "sodium_mg": 700},
            ]),
            total_calories=780,
            carbs_g=86,
            protein_g=40,
            fat_g=29.3,
            sodium_mg=1643,
            sugar_g=7,
        ),
        DietEntry(
            id="dashboard-dinner",
            user_id=DEMO_USER_ID,
            date=today_str(),
            meal_type="dinner",
            foods_json=json.dumps([
                {"name": "라면", "sodium_mg": 600},
                {"name": "샐러드", "sodium_mg": 800},
            ]),
            total_calories=570,
            carbs_g=69,
            protein_g=41,
            fat_g=14.5,
            sodium_mg=535,
            sugar_g=11,
        ),
    ])
    db_session.commit()

    response = client.get("/v1/dashboard/summary")

    assert response.status_code == 200
    body = response.json()
    macros = body["macros"]
    assert macros["carbs_g"] == pytest.approx(155.0)
    assert macros["protein_g"] == pytest.approx(81.0)
    assert macros["fat_g"] == pytest.approx(43.8)
    assert {
        "carbs_pct": macros["carbs_pct"],
        "protein_pct": macros["protein_pct"],
        "fat_pct": macros["fat_pct"],
    } == {
        "carbs_pct": 46,
        "protein_pct": 24,
        "fat_pct": 30,
    }
    assert body["sodium_warning"] == "라면·샐러드 섭취로 나트륨이 높아요."
    assert isinstance(body["exercise_minutes"], int)
    assert isinstance(body["exercise_calories"], int)
    assert isinstance(body["exercise_count"], int)

    # 주간 추이(이번 주 월~일 7일) + 지난 주 비교선 7일
    assert len(body["nutrition_week"]) == 7
    assert len(body["nutrition_week_prev"]) == 7
    assert [d["label"] for d in body["nutrition_week"]] == \
        ["월", "화", "수", "목", "금", "토", "일"]
    # 오늘 점심(780)+저녁(570)이 이번 주 어느 요일에 집계돼야 한다.
    assert sum(d["calories"] for d in body["nutrition_week"]) >= 1350
    # 소모 목표 필드(기본값) + 지난주 대비 변화량은 정수
    assert body["exercise_burn_goal"] == 500
    assert isinstance(body["week_score_delta"], int)


def test_dashboard_summary_uses_personal_nutrition_goals(client, db_session):
    from app.db.init_db import DEMO_USER_ID
    from app.models.models import User

    user = db_session.get(User, DEMO_USER_ID)
    profile = user.health_profile
    original = (
        profile.daily_calories,
        profile.daily_sodium_mg,
        profile.daily_sugar_g,
    )
    try:
        profile.daily_calories = 1800
        profile.daily_sodium_mg = 1500
        profile.daily_sugar_g = 35
        db_session.commit()
        response = client.get("/v1/dashboard/summary")
    finally:
        (
            profile.daily_calories,
            profile.daily_sodium_mg,
            profile.daily_sugar_g,
        ) = original
        db_session.commit()

    assert response.status_code == 200
    indicators = {item["label"]: item for item in response.json()["indicators"]}
    assert indicators["칼로리"]["max"] == 1800
    assert indicators["나트륨"]["max"] == 1500
    assert indicators["당류"]["max"] == 35
    for indicator in indicators.values():
        assert indicator["over_budget"] == (
            indicator["current"] > indicator["max"]
        )


def test_dashboard_summary_falls_back_per_missing_goal(client, db_session):
    from app.db.init_db import DEMO_USER_ID
    from app.models.models import User

    user = db_session.get(User, DEMO_USER_ID)
    profile = user.health_profile
    original = (
        profile.daily_calories,
        profile.daily_sodium_mg,
        profile.daily_sugar_g,
    )
    try:
        profile.daily_calories = 1800
        profile.daily_sodium_mg = None
        profile.daily_sugar_g = 35
        db_session.commit()
        response = client.get("/v1/dashboard/summary")
    finally:
        (
            profile.daily_calories,
            profile.daily_sodium_mg,
            profile.daily_sugar_g,
        ) = original
        db_session.commit()

    assert response.status_code == 200
    indicators = {item["label"]: item for item in response.json()["indicators"]}
    assert indicators["칼로리"]["max"] == 1800
    assert indicators["나트륨"]["max"] == 2000
    assert indicators["당류"]["max"] == 35


def test_dashboard_names_the_advice_it_chose(client, db_session):
    """홈 조언에 로케일 독립 식별자를 함께 싣는가. (#1943)

    앱은 이 키를 먼저 보고 자기 문장을 그린다. 키가 없으면 서버가 만든 한국어
    고정 문장으로 떨어져 **영어 회원이 한국어 조언을 읽는다.** 데모 서버만 이
    키를 내려주고 있었다.
    """
    from app.api.v1.dashboard import _advice_key

    # 나트륨 경고가 있으면 그것이 조언이다 — 앱이 고르는 순서와 같다.
    assert (
        _advice_key(
            sodium_warning="오늘 나트륨이 3000mg 으로 권장량(2000mg)을 넘었어요.",
            sodium_source_names=[],
            exercise_advice_key="exercise_start",
        )
        == "sodium_over"
    )
    # 음식 이름이 든 경고는 키를 주지 않는다 — 그 이름은 번역 대상이 아니라
    # 회원이 적은 데이터라, 문장을 통째로 보내는 편이 맞다.
    assert (
        _advice_key(
            sodium_warning="라면·김치 섭취로 나트륨이 높아요.",
            sodium_source_names=["라면", "김치"],
            exercise_advice_key="exercise_start",
        )
        is None
    )
    # 경고가 없으면 운동 되먹임이 조언이다.
    for key in ("exercise_on_track", "exercise_more", "exercise_start"):
        assert (
            _advice_key(
                sodium_warning=None,
                sodium_source_names=[],
                exercise_advice_key=key,
            )
            == key
        )

    # 응답에도 실려야 한다 — 계산만 하고 내보내지 않으면 화면은 예전 그대로다.
    r = client.get("/v1/dashboard/summary")
    assert r.status_code == 200, r.text
    assert "ai_advice_key" in r.json()
