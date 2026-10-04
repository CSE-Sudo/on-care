"""대시보드 요약 집계."""
from __future__ import annotations

import json

import pytest
from sqlalchemy import delete

from app.api.v1.dashboard import _build_sodium_warning, _rank_sodium_sources

# 홈이 읽지 않아 응답에서 뺀 필드(#2646). 주간 점수는 지난주 운동·식단을 한 번 더
# 조회해 만들었지만 화면 어디에도 그려지지 않았다.
_REMOVED_SUMMARY_FIELDS = (
    "week_score",
    "week_score_delta",
    "nutrition_week_prev",
    "exercise_calories",
    "exercise_count",
    "exercise_burn_goal",
)


@pytest.mark.parametrize(
    ("total_sodium_mg", "source_names", "expected"),
    [
        (2000, ["라면"], None),
        (
            2100,
            [],
            "오늘 나트륨이 2100mg 으로 목표(2000mg)를 넘었어요.",
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
        "오늘 나트륨이 1600mg 으로 목표(1500mg)를 넘었어요."
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

    # 주간 추이(이번 주 월~일 7일)
    assert len(body["nutrition_week"]) == 7
    assert [d["label"] for d in body["nutrition_week"]] == \
        ["월", "화", "수", "목", "금", "토", "일"]
    # 오늘 점심(780)+저녁(570)이 이번 주 어느 요일에 집계돼야 한다.
    assert sum(d["calories"] for d in body["nutrition_week"]) >= 1350
    # 홈이 읽지 않던 필드는 싣지 않는다(#2646).
    for removed in _REMOVED_SUMMARY_FIELDS:
        assert removed not in body


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
            sodium_warning="오늘 나트륨이 3000mg 으로 목표(2000mg)를 넘었어요.",
            sodium_source_names=[],
            exercise_advice_key="exercise_start",
        )
        == "sodium_over"
    )
    # 음식 이름이 든 경고도 키를 준다(#2644) — 이름은 인자로 따로 싣고 문장
    # 틀은 앱 ARB 가 언어별로 갖는다. 키를 비우면 영어 화면이 한국어를 그린다.
    assert (
        _advice_key(
            sodium_warning="라면·김치 섭취로 나트륨이 높아요.",
            sodium_source_names=["라면", "김치"],
            exercise_advice_key="exercise_start",
        )
        == "sodium_over_sources"
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


def test_summary_schema_drops_fields_the_home_never_read():
    """응답 계약에서 빠진 필드가 스키마에 되살아나지 않는다(#2646)."""
    from app.schemas.dashboard_api import DashboardNutritionDay, DashboardSummary

    for removed in _REMOVED_SUMMARY_FIELDS:
        assert removed not in DashboardSummary.model_fields
    # 세 지표와 주간 추이의 일별 나트륨·당류는 같은 조회에서 나오므로 남긴다.
    assert "indicators" in DashboardSummary.model_fields
    assert {"sodium_mg", "sugar_g"} <= set(DashboardNutritionDay.model_fields)


def test_dashboard_summary_queries_only_this_week(client, db_session, monkeypatch):
    """지난주 운동·식단을 다시 읽지 않는다 — 그 값은 주간 점수에만 쓰였다."""
    from datetime import timedelta

    from app.api.v1 import dashboard as dashboard_module

    mondays: list[str] = []
    original = dashboard_module._nutrition_week

    def spy(db, uid, monday):
        mondays.append(monday.strftime("%Y-%m-%d"))
        return original(db, uid, monday)

    monkeypatch.setattr(dashboard_module, "_nutrition_week", spy)

    response = client.get("/v1/dashboard/summary")

    assert response.status_code == 200
    now = dashboard_module.clock.now()
    this_monday = (now - timedelta(days=now.weekday())).strftime("%Y-%m-%d")
    assert mondays == [this_monday]
