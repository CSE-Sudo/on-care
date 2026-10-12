"""코칭 판정은 회원 목표를 기준으로 한다. (#3350)

나트륨 목표가 1,500mg 인 회원이 1,800mg 을 먹으면 식단 탭·홈 게이지는 초과인데
코칭 카드는 "안정적이에요" 라고 했다. 운동 목표가 주 90분인 회원이 100분을 채워도
홈 조언은 "조금만 더" 였다. 코칭 쪽이 회원 목표 대신 고정값(2,000mg·주 150분)을
썼기 때문이다. 이 테스트는
- 나트륨: 오늘 판정·이번 주 초과 일수·AI 가 읽는 요약이 `daily_sodium_mg` 를 따르는지
- 운동: 코칭 카드·홈 조언이 운동 탭처럼 유산소 분을 `weekly_cardio_minutes` 와 견주는지
- 목표가 없는 회원은 예전 기본값 그대로인지
를 확인한다.
"""
from __future__ import annotations

import uuid
from datetime import datetime
from types import SimpleNamespace

import pytest
from sqlalchemy import select

from app.api.v1.dashboard import _exercise_feedback
from app.core import clock
from app.core.week import monday_of
from app.models.models import DietEntry, ExerciseSession, HealthProfile, User
from app.services import coach_service, diet_service, exercise_service, goal_defaults

#: 2026-03-12 은 목요일 — 월~목 나흘이 "이번 주" 다(`test_coach_diet_period` 와 같다).
_FROZEN_TODAY = datetime(2026, 3, 12, 9, 0, tzinfo=clock.SEOUL)
_MONDAY = "2026-03-09"


@pytest.fixture
def frozen_thursday(monkeypatch):
    monkeypatch.setattr(clock, "now", lambda: _FROZEN_TODAY)


def _make_user(db_session, **goals) -> str:
    """회원 하나. [goals] 가 있으면 그 목표를 적은 건강 프로필도 만든다."""
    user_id = f"coach-goal-{uuid.uuid4().hex[:12]}"
    db_session.add(
        User(
            id=user_id, email=f"{user_id}@example.com", name="목표 테스트",
            hashed_password="",
        )
    )
    db_session.flush()
    if goals:
        db_session.add(HealthProfile(user_id=user_id, **goals))
        db_session.flush()
    return user_id


def _add_diet(db_session, user_id: str, date: str, sodium: int) -> None:
    db_session.add(
        DietEntry(
            id=f"{user_id}-{date}-{uuid.uuid4().hex[:8]}",
            user_id=user_id, date=date, meal_type="lunch",
            total_calories=1800, sodium_mg=sodium, sugar_g=30.0,
        )
    )
    db_session.flush()


def _add_exercise(db_session, user_id: str, type_: str, minutes: int) -> None:
    db_session.add(
        ExerciseSession(
            id=f"ex-{uuid.uuid4().hex[:12]}",
            user_id=user_id, week_start=_MONDAY, day_label="월",
            type=type_, minutes=minutes, calories=100, source="member",
        )
    )
    db_session.flush()


# ---- 기준값 도우미 (순수) ----

@pytest.mark.parametrize(
    ("profile", "expected"),
    [
        (None, goal_defaults.WEEKLY_CARDIO_MINUTES),
        (SimpleNamespace(weekly_cardio_minutes=None), goal_defaults.WEEKLY_CARDIO_MINUTES),
        (SimpleNamespace(weekly_cardio_minutes=0), goal_defaults.WEEKLY_CARDIO_MINUTES),
        (SimpleNamespace(weekly_cardio_minutes=90), 90),
        (SimpleNamespace(weekly_cardio_minutes=300), 300),
    ],
)
def test_weekly_cardio_goal_falls_back_only_when_unset(profile, expected):
    assert exercise_service.weekly_cardio_goal(profile) == expected


def test_weekly_cardio_goal_ignores_the_legacy_total_minutes_goal():
    """운동 탭이 견주는 값은 유산소 목표다 — 옛 합계 목표가 있어도 그쪽을 읽지 않는다."""
    profile = SimpleNamespace(
        weekly_cardio_minutes=None, weekly_exercise_minutes_goal=400
    )
    assert (
        exercise_service.weekly_cardio_goal(profile)
        == goal_defaults.WEEKLY_CARDIO_MINUTES
    )


def test_cardio_minutes_counts_only_the_cardio_bucket():
    rows = [
        SimpleNamespace(type="cardio", minutes=30),
        SimpleNamespace(type="유산소", minutes=20),
        SimpleNamespace(type="walking", minutes=10),  # 옛 값 — 유산소로 접힌다
        SimpleNamespace(type="strength", minutes=45),
        SimpleNamespace(type="stretching", minutes=15),
        SimpleNamespace(type="other", minutes=25),
    ]
    assert exercise_service.cardio_minutes(rows) == 60
    assert exercise_service.cardio_minutes([]) == 0


def test_cardio_minutes_matches_the_exercise_tab_week_total(db_session):
    """운동 탭 응답(`build_current_week`)의 유산소 분 합계와 같은 값이어야 한다."""
    user_id = _make_user(db_session)
    _add_exercise(db_session, user_id, "cardio", 30)
    _add_exercise(db_session, user_id, "strength", 40)
    _add_exercise(db_session, user_id, "걷기", 25)
    _add_exercise(db_session, user_id, "other", 10)
    rows = list(
        db_session.scalars(
            select(ExerciseSession).where(ExerciseSession.user_id == user_id)
        ).all()
    )

    week = exercise_service.build_current_week(rows)

    assert exercise_service.cardio_minutes(rows) == 55
    assert sum(week["cardio_minutes"]) == 55


# ---- 나트륨: 기간 집계 ----

def test_period_stats_counts_over_days_against_the_given_limit(db_session):
    user_id = _make_user(db_session)
    _add_diet(db_session, user_id, "2024-05-01", 1800)
    _add_diet(db_session, user_id, "2024-05-02", 1400)
    _add_diet(db_session, user_id, "2024-05-03", 2100)

    default = diet_service.period_stats(db_session, user_id, "2024-05-01", "2024-05-03")
    personal = diet_service.period_stats(
        db_session, user_id, "2024-05-01", "2024-05-03", 1500
    )

    assert default.days_over_sodium == 1  # 2,000mg 기준 — 05-03 하루
    assert personal.days_over_sodium == 2  # 1,500mg 기준 — 05-01·05-03
    # 평균은 기준과 무관하다.
    assert personal.avg_sodium_mg == default.avg_sodium_mg


def test_period_stats_limit_is_strictly_greater_than(db_session):
    """목표와 같은 날은 초과가 아니다 — 홈 게이지(`over_budget`)와 같은 경계."""
    user_id = _make_user(db_session)
    _add_diet(db_session, user_id, "2024-05-01", 1500)
    stats = diet_service.period_stats(
        db_session, user_id, "2024-05-01", "2024-05-01", 1500
    )
    assert stats.days_over_sodium == 0


# ---- 나트륨: 코칭 카드 ----

def test_diet_suggestion_flags_today_over_the_members_goal(db_session, frozen_thursday):
    """목표 1,500mg 회원의 1,800mg 은 초과다 — 예전에는 '안정적이에요' 였다."""
    user_id = _make_user(db_session, daily_sodium_mg=1500)
    _add_diet(db_session, user_id, "2026-03-12", 1800)

    suggestion = coach_service._diet_suggestion(db_session, user_id)

    assert suggestion.title == "나트륨 섭취가 많아요"
    assert "1,800mg" in suggestion.body


def test_diet_suggestion_keeps_default_limit_without_a_goal(db_session, frozen_thursday):
    """목표가 없는 회원의 1,800mg 은 지금처럼 기본값(2,000mg) 안이다."""
    for goals in ({}, {"daily_sodium_mg": None}):
        user_id = _make_user(db_session, **goals)
        _add_diet(db_session, user_id, "2026-03-12", 1800)

        suggestion = coach_service._diet_suggestion(db_session, user_id)

        assert suggestion.title == "식단 균형이 좋아요"


def test_diet_suggestion_allows_more_for_a_higher_goal(db_session, frozen_thursday):
    """목표를 2,300mg 으로 올린 회원의 2,100mg 은 초과가 아니다."""
    user_id = _make_user(db_session, daily_sodium_mg=2300)
    _add_diet(db_session, user_id, "2026-03-12", 2100)

    suggestion = coach_service._diet_suggestion(db_session, user_id)

    assert suggestion.title == "식단 균형이 좋아요"


def test_weekly_sodium_pattern_uses_the_members_goal(db_session, frozen_thursday):
    """오늘은 목표 안이어도 이번 주 사흘이 회원 목표를 넘었으면 패턴으로 짚는다."""
    user_id = _make_user(db_session, daily_sodium_mg=1500)
    for day in ("2026-03-09", "2026-03-10", "2026-03-11"):
        _add_diet(db_session, user_id, day, 1800)  # 2,000mg 기준이면 초과 아님
    _add_diet(db_session, user_id, "2026-03-12", 900)  # 오늘, 미초과

    suggestion = coach_service._diet_suggestion(db_session, user_id)

    assert suggestion.title == "이번 주 나트륨이 계속 높았어요"
    assert "4일 중 3일" in suggestion.body


# ---- 나트륨: AI 대화·코칭 프롬프트에 들어가는 요약 ----

def test_diet_period_context_is_written_against_the_members_goal(
    db_session, frozen_thursday,
):
    user_id = _make_user(db_session, daily_sodium_mg=1500)
    for day in ("2026-03-09", "2026-03-10"):
        _add_diet(db_session, user_id, day, 1800)
    _add_diet(db_session, user_id, "2026-03-12", 900)

    text = coach_service.diet_period_context(db_session, user_id)

    assert "나트륨 목표(1500mg) 초과 2일" in text
    assert "2000mg" not in text
    assert "권장량" not in text


def test_diet_period_context_uses_default_without_a_goal(db_session, frozen_thursday):
    user_id = _make_user(db_session)
    for day in ("2026-03-09", "2026-03-10"):
        _add_diet(db_session, user_id, day, 1800)

    text = coach_service.diet_period_context(db_session, user_id)

    assert f"나트륨 목표({diet_service.SODIUM_LIMIT_MG}mg) 초과 0일" in text


# ---- 운동: 코칭 카드 ----

def test_exercise_suggestion_meets_a_lower_personal_goal(db_session, frozen_thursday):
    """목표 주 90분 회원의 유산소 100분은 달성이다 — 예전에는 '조금만 더' 였다."""
    user_id = _make_user(db_session, weekly_cardio_minutes=90)
    _add_exercise(db_session, user_id, "cardio", 100)

    suggestion = coach_service._exercise_suggestion(db_session, user_id)

    assert suggestion.title == "운동량이 충분해요"
    assert "100분" in suggestion.body


def test_exercise_suggestion_names_the_personal_goal_when_short(
    db_session, frozen_thursday,
):
    user_id = _make_user(db_session, weekly_cardio_minutes=200)
    _add_exercise(db_session, user_id, "cardio", 160)  # 150분 고정이면 달성

    suggestion = coach_service._exercise_suggestion(db_session, user_id)

    assert suggestion.title == "조금만 더 움직여봐요"
    assert "유산소 160분" in suggestion.body
    assert "주 200분" in suggestion.body
    assert "150" not in suggestion.body


def test_exercise_suggestion_counts_cardio_only(db_session, frozen_thursday):
    """근력 시간은 유산소 목표에 넣지 않는다 — 운동 탭의 달성률과 같은 합산."""
    user_id = _make_user(db_session, weekly_cardio_minutes=90)
    _add_exercise(db_session, user_id, "cardio", 40)
    _add_exercise(db_session, user_id, "strength", 120)

    suggestion = coach_service._exercise_suggestion(db_session, user_id)

    assert suggestion.title == "조금만 더 움직여봐요"
    assert "유산소 40분" in suggestion.body


def test_exercise_suggestion_keeps_default_goal_without_one(db_session, frozen_thursday):
    """목표가 없는 회원은 지금처럼 주 150분 기준이다."""
    short = _make_user(db_session)
    _add_exercise(db_session, short, "cardio", 149)
    met = _make_user(db_session, weekly_cardio_minutes=None)
    _add_exercise(db_session, met, "cardio", 150)

    assert (
        coach_service._exercise_suggestion(db_session, short).title
        == "조금만 더 움직여봐요"
    )
    assert "주 150분" in coach_service._exercise_suggestion(db_session, short).body
    assert (
        coach_service._exercise_suggestion(db_session, met).title
        == "운동량이 충분해요"
    )


def test_exercise_suggestion_strength_only_week_invites_cardio(
    db_session, frozen_thursday,
):
    """근력만 한 주 — '운동을 시작해 보세요' 도 '유산소 0분 운동했어요' 도 아니다.

    홈 조언의 `exercise_cardio_start` 와 같은 규칙·같은 문장이다.
    """
    user_id = _make_user(db_session)
    _add_exercise(db_session, user_id, "strength", 60)

    suggestion = coach_service._exercise_suggestion(db_session, user_id)

    assert suggestion.title == "유산소를 더해봐요"
    assert suggestion.body == _exercise_feedback(
        0, 150, any_exercise=True, locale="ko"
    )[0]
    assert "0분" not in suggestion.body


# ---- 운동: 홈 조언 (순수) ----

@pytest.mark.parametrize(
    ("cardio", "goal", "any_exercise", "key"),
    [
        (100, 90, True, "exercise_on_track"),   # 낮춘 목표 — 달성
        (90, 90, True, "exercise_on_track"),    # 목표와 같으면 달성
        (89, 90, True, "exercise_more"),
        (160, 200, True, "exercise_more"),      # 올린 목표 — 150분을 넘겨도 미달
        (150, 150, True, "exercise_on_track"),  # 기본값
        (149, 150, True, "exercise_more"),
        (0, 150, True, "exercise_cardio_start"),  # 근력만 한 주
        (0, 150, False, "exercise_start"),
    ],
)
def test_exercise_feedback_judges_cardio_against_the_goal(cardio, goal, any_exercise, key):
    for lang in ("ko", "en"):
        assert _exercise_feedback(
            cardio, goal, any_exercise=any_exercise, locale=lang
        )[1] == key


def test_exercise_feedback_strength_only_week_invites_cardio():
    """근력만 한 주 — "유산소 0분 운동했어요" 가 아니라 유산소를 권한다."""
    ko = _exercise_feedback(0, 150, any_exercise=True, locale="ko")
    en = _exercise_feedback(0, 150, any_exercise=True, locale="en")

    assert ko == (
        "이번 주 유산소 기록은 아직 없어요. 가볍게 걷기부터 시작해 볼까요?",
        "exercise_cardio_start",
    )
    assert en == (
        "No cardio logged yet this week. How about starting with an easy walk?",
        "exercise_cardio_start",
    )
    assert "0분" not in ko[0]
    # 기록이 아예 없는 주는 그대로 `exercise_start` 다.
    assert _exercise_feedback(0, 150, any_exercise=False, locale="ko")[1] == (
        "exercise_start"
    )


# ---- 운동·나트륨: 홈 요약 API ----

def _summary_with_profile(client, db_session, **goals) -> dict:
    """데모 회원의 목표를 잠시 바꿔 홈 요약을 읽는다. 끝나면 되돌린다."""
    from app.db.init_db import DEMO_USER_ID

    user = db_session.get(User, DEMO_USER_ID)
    profile = user.health_profile
    original = {name: getattr(profile, name) for name in goals}
    try:
        for name, value in goals.items():
            setattr(profile, name, value)
        db_session.commit()
        response = client.get("/v1/dashboard/summary")
    finally:
        for name, value in original.items():
            setattr(profile, name, value)
        db_session.commit()
    assert response.status_code == 200, response.text
    return response.json()


def test_dashboard_summary_reports_cardio_minutes(client, db_session):
    body = _summary_with_profile(client, db_session)

    assert isinstance(body["exercise_cardio_minutes"], int)
    # 유산소는 전체 운동 시간의 일부다.
    assert 0 <= body["exercise_cardio_minutes"] <= body["exercise_minutes"]


def test_dashboard_exercise_feedback_follows_the_cardio_goal(client, db_session):
    """같은 기록이라도 목표를 1분으로 낮추면 달성, 아주 높이면 미달이다.

    데모 회원의 이번 주 시드 기록에 기대지 않도록 유산소 기록을 직접 넣는다 — 요일에
    따라 그 주에 유산소가 아직 없으면 조언이 `exercise_cardio_start` 로 갈린다.
    """
    from app.db.init_db import DEMO_USER_ID

    today = clock.today()
    session = ExerciseSession(
        id=f"ex-{uuid.uuid4().hex[:12]}",
        user_id=DEMO_USER_ID,
        week_start=monday_of(today).isoformat(),
        day_label=exercise_service.WEEKDAY_LABELS[today.weekday()],
        type="cardio", minutes=30, calories=100, source="member",
    )
    db_session.add(session)
    db_session.commit()
    try:
        low = _summary_with_profile(client, db_session, weekly_cardio_minutes=1)
        high = _summary_with_profile(
            client, db_session, weekly_cardio_minutes=100000
        )
    finally:
        db_session.delete(session)
        db_session.commit()

    cardio = high["exercise_cardio_minutes"]
    assert cardio >= 30
    assert low["exercise_cardio_minutes"] == cardio
    assert low["exercise_feedback"] == (
        f"이번 주 유산소 {cardio}분 운동했어요. 목표 달성 중이에요!"
    )
    assert low["ai_advice_key"] in ("exercise_on_track", "sodium_over", "sodium_over_sources")
    assert high["exercise_feedback"] == (
        f"이번 주 유산소 {cardio}분 운동했어요. 조금만 더 힘내요!"
    )
