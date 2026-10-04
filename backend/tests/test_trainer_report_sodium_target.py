"""주간 리포트의 나트륨 초과일 기준과 요일 칸 운동 유형 라벨의 언어. (#2885)

- 초과일은 그 회원의 나트륨 목표(`daily_sodium_mg`)로 센다. 목표가 없거나 0
  이하일 때만 공통 기준(2,000mg)이다. 같은 응답의 `sodium_target` 과 초안 문장의
  `목표(…mg)` 가 같은 기준을 말한다.
- 이름이 빈 옛 운동 기록의 유형 라벨은 요청 언어로 고른다 — 영어 리포트에
  `근력` 이 남지 않는다.
"""
from __future__ import annotations

from datetime import date, datetime, timedelta, timezone
from types import SimpleNamespace
from uuid import uuid4

import pytest
from sqlalchemy import delete

from app.core import locale as locale_mod
from app.models.models import (
    DietEntry,
    HealthProfile,
    TrainerClient,
    User,
)
from app.schemas.trainer_api import WeeklyReportOut
from app.services import exercise_types
from app.services.trainer import _common as trainer_common_service
from app.services.trainer import reports as trainer_reports_service

#: 지난 날짜로 고정한 한 주(월요일).
WEEK = date(2026, 2, 2)

_created: list[str] = []


@pytest.fixture(autouse=True)
def _drop_created_accounts(db_session):
    yield
    if not _created:
        return
    db_session.rollback()
    db_session.execute(delete(User).where(User.id.in_(list(_created))))
    db_session.commit()
    _created.clear()


@pytest.fixture
def request_locale():
    """요청 언어 컨텍스트를 바꾼다 — 미들웨어가 하는 일과 같다."""
    tokens: list = []

    def _set(value: str) -> None:
        tokens.append(locale_mod._request_locale_ctx.set(value))

    yield _set
    for token in reversed(tokens):
        locale_mod._request_locale_ctx.reset(token)


def _user(db, prefix: str, role: str) -> str:
    user_id = f"{prefix}-{uuid4().hex[:10]}"
    _created.append(user_id)
    db.add(
        User(
            id=user_id,
            email=f"{user_id}@oncare.com",
            name="나트륨 회원",
            hashed_password="unused",
            role=role,
        )
    )
    db.commit()
    return user_id


def _linked_member(db, *, sodium_target: int | None) -> tuple[str, str]:
    trainer_id = _user(db, "sodium-trainer", "trainer")
    member_id = _user(db, "sodium-member", "member")
    db.add(
        TrainerClient(
            id=f"link-{uuid4().hex[:12]}",
            trainer_id=trainer_id,
            member_id=member_id,
            active=True,
            data_consent_at=datetime.now(timezone.utc),
        )
    )
    if sodium_target is not None:
        db.add(HealthProfile(user_id=member_id, daily_sodium_mg=sodium_target))
    db.commit()
    return trainer_id, member_id


def _meal(db, member_id: str, offset: int, sodium_mg: int) -> None:
    db.add(
        DietEntry(
            id=f"sodium-d-{uuid4().hex[:10]}",
            user_id=member_id,
            date=(WEEK + timedelta(days=offset)).isoformat(),
            meal_type="lunch",
            time_label="",
            foods_json="[]",
            total_calories=500,
            sodium_mg=sodium_mg,
            engine="test",
        )
    )
    db.commit()


def _week(db, member_id: str, sodium: list[int]) -> None:
    for offset, mg in enumerate(sodium):
        if mg:
            _meal(db, member_id, offset, mg)


# ---- 기준 ----


@pytest.mark.parametrize(
    ("target", "limit"),
    [(None, 2000), (0, 2000), (-5, 2000), (1500, 1500), (2300, 2300)],
)
def test_sodium_limit_is_the_members_target_or_the_common_default(target, limit):
    assert trainer_reports_service.sodium_limit_mg(target) == limit


# ---- 서비스: 초과일 ----


def test_target_1500_counts_an_1800mg_day_as_over(db_session):
    trainer, member = _linked_member(db_session, sodium_target=1500)
    _week(db_session, member, [1800, 1800, 1400, 0, 0, 0, 0])

    report = trainer_reports_service.build_weekly_report(db_session, trainer, member, WEEK)

    assert report.sodium_target == 1500
    assert report.sodium_over_days == 2


def test_target_2300_keeps_a_2100mg_day_inside_the_target(db_session):
    trainer, member = _linked_member(db_session, sodium_target=2300)
    _week(db_session, member, [2100, 2100, 2400, 0, 0, 0, 0])

    report = trainer_reports_service.build_weekly_report(db_session, trainer, member, WEEK)

    assert report.sodium_target == 2300
    # 2,000mg 로 셌다면 3일이다.
    assert report.sodium_over_days == 1


def test_member_without_a_target_is_counted_against_the_common_default(db_session):
    trainer, member = _linked_member(db_session, sodium_target=None)
    _week(db_session, member, [2100, 1800, 0, 0, 0, 0, 0])

    report = trainer_reports_service.build_weekly_report(db_session, trainer, member, WEEK)

    assert report.sodium_target is None
    assert report.sodium_over_days == 1


def test_draft_message_names_the_target_the_days_were_counted_against(db_session):
    trainer, member = _linked_member(db_session, sodium_target=1500)
    _week(db_session, member, [1800, 1800, 1400, 0, 0, 0, 0])

    report = trainer_reports_service.build_weekly_report(db_session, trainer, member, WEEK)

    assert "목표(1,500mg)를 넘긴 날이 2일" in report.message
    assert "2,000mg" not in report.message


def test_report_endpoint_counts_against_the_members_target(client, db_session):
    from app.core.security import create_access_token

    trainer, member = _linked_member(db_session, sodium_target=1500)
    _week(db_session, member, [1800, 1600, 1400, 0, 0, 0, 0])

    r = client.get(
        f"/v1/trainer/clients/{member}/report",
        params={"week_start": WEEK.isoformat()},
        headers={"Authorization": f"Bearer {create_access_token(trainer)}"},
    )

    assert r.status_code == 200, r.text
    body = r.json()
    assert body["sodium_target"] == 1500
    assert body["sodium_over_days"] == 2


# ---- 초안 문장 ----


def _report(**over) -> WeeklyReportOut:
    base = dict(
        member_id="m", member_name="김민수",
        week_start="2026-08-10", week_end="2026-08-16",
        sessions_booked=1, sessions_done=1,
        completion_avg=87, sodium_over_days=2, sodium_avg=1700,
        calories_week=[], days=[], message="",
    )
    base.update(over)
    return WeeklyReportOut(**base)


def test_korean_message_names_the_personal_target_when_over():
    message = trainer_reports_service.report_message(_report(sodium_target=1500), "ko")
    assert "목표(1,500mg)를 넘긴 날이 2일" in message


def test_korean_message_names_the_personal_target_when_inside():
    message = trainer_reports_service.report_message(
        _report(sodium_target=2300, sodium_over_days=0, sodium_avg=2100), "ko"
    )
    assert "목표(2,300mg) 안에서" in message


def test_english_message_names_the_personal_target():
    message = trainer_reports_service.report_message(_report(sodium_target=1500), "en")
    assert "went over the 1,500mg goal on 2 days." in message


def test_message_without_a_target_keeps_the_common_default():
    message = trainer_reports_service.report_message(_report(), "ko")
    assert "목표(2,000mg)" in message


# ---- 운동 유형 라벨 ----


@pytest.mark.parametrize(
    ("value", "locale", "label"),
    [
        ("strength", "en", "Strength"),
        ("근력", "en", "Strength"),
        ("cardio", "en", "Cardio"),
        ("걷기", "en", "Cardio"),
        ("stretching", "en", "Stretching"),
        (None, "en", "Other"),
        ("strength", "ko", "근력"),
        ("cardio", "ko", "유산소"),
        (None, "ko", "기타"),
        ("strength", "ja", "근력"),
    ],
)
def test_normalize_label_picks_the_requested_language(value, locale, label):
    assert exercise_types.normalize_label(value, locale) == label


def test_normalize_label_defaults_to_korean():
    assert exercise_types.normalize_label("strength") == exercise_types.normalize_ko(
        "strength"
    )


def _row(day: str, kind: str, name: str | None = None) -> SimpleNamespace:
    return SimpleNamespace(day_label=day, type=kind, name=name)


def test_english_report_day_uses_the_english_type_label(request_locale):
    request_locale("en")
    days = trainer_common_service._week_days(
        [_row("화", "strength"), _row("화", "cardio", "Running")], [0] * 7
    )
    assert days[1].exercises == ["Strength", "Running"]


def test_korean_report_day_keeps_the_korean_type_label(request_locale):
    request_locale("ko")
    days = trainer_common_service._week_days([_row("화", "strength")], [0] * 7)
    assert days[1].exercises == ["근력"]


def test_named_records_keep_their_own_name_in_any_language(request_locale):
    request_locale("en")
    days = trainer_common_service._week_days([_row("월", "strength", "스쿼트")], [0] * 7)
    assert days[0].exercises == ["스쿼트"]
