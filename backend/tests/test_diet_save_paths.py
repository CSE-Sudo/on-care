"""식단 저장 경로의 중복 차감·날짜 범위·끼니 시각·홈 경고 음식 이름. (#3354)

- 사진 분석: 같은 멱등키가 아직 분석 중이면 409 `in_progress` 이고 하루 횟수·모델
  호출을 더 쓰지 않는다. 저장분만 보던 재생은 진행 중인 요청을 알아보지 못했다.
- 날짜 하한(작년 1월 1일)은 사진 분석·직접 입력·수정이 같은 규칙을 쓴다.
- 지난 날짜에 적는 끼니의 시각은 적는 시각이 아니라 끼니 종류의 기본 시각이다.
- 홈 나트륨 경고는 영어 화면에서 음식의 영어 표시 이름을 쓴다.

순수 검사는 DB 가 필요 없고, API·서비스 검사는 DB 테스트(로컬 skip, CI 실행)다.
"""
from __future__ import annotations

import json
from datetime import date, datetime, timedelta
from uuid import uuid4

import pytest

from app.core import clock
from app.schemas.diet import DietAnalysis, RecognizedFood

from tests.image_fixtures import JPEG as _JPEG  # 진짜 JPEG — 분석 전 정리가 픽셀을 읽는다(#3041)

#: 오늘은 2026-08-20(목) 23:05 KST 로 고정한다 — "어제 아침을 밤 11시에 적는" 때다.
_NOW = datetime(2026, 8, 20, 23, 5, tzinfo=clock.SEOUL)
_TODAY = "2026-08-20"
_YESTERDAY = "2026-08-19"
#: 그날의 하한(작년 1월 1일)과 그 하루 전.
_FLOOR = "2025-01-01"
_BEFORE_FLOOR = "2024-12-31"


@pytest.fixture
def frozen_now(monkeypatch):
    monkeypatch.setattr(clock, "now", lambda: _NOW)
    return _NOW


# ── 순수: 날짜 하한 ───────────────────────────────────────────────────────


def test_record_floor_is_january_first_of_last_year(frozen_now):
    from app.schemas import record_dates

    assert record_dates.record_floor() == date(2025, 1, 1)
    assert record_dates.not_before_floor(date(2025, 1, 1)) == date(2025, 1, 1)
    with pytest.raises(ValueError, match="작년 1월 1일"):
        record_dates.not_before_floor(date(2024, 12, 31))


def test_record_floor_moves_with_the_kst_year(monkeypatch):
    """해가 바뀌면 하한도 한 해 옮겨진다 — 서버 로컬 시계가 아니라 KST 로 본다."""
    from app.schemas import record_dates

    monkeypatch.setattr(
        clock, "now", lambda: datetime(2027, 1, 1, 0, 30, tzinfo=clock.SEOUL)
    )
    assert record_dates.record_floor() == date(2026, 1, 1)


@pytest.mark.parametrize("schema_name", ["DietEntryCreate", "DietEntryUpdate"])
def test_entry_schemas_refuse_dates_before_the_floor(frozen_now, schema_name):
    from pydantic import ValidationError

    from app.schemas import diet_api

    schema = getattr(diet_api, schema_name)
    base = {"meal_type": "lunch", "foods": [{"name": "김밥", "calories": 400}]}

    assert schema(**base, date=_FLOOR).date == _FLOOR
    assert schema(**base, date=_TODAY).date == _TODAY
    with pytest.raises(ValidationError) as exc:
        schema(**base, date=_BEFORE_FLOOR)
    assert "작년 1월 1일" in str(exc.value)
    with pytest.raises(ValidationError):
        schema(**base, date="2026-08-21")


def test_analyze_date_uses_the_same_rule_as_entries(frozen_now):
    """사진 분석의 날짜 검사가 직접 입력·수정과 같은 문구로 거절한다."""
    from app.schemas import diet_api, record_dates

    assert diet_api.analyze_record_date(_FLOOR) == date(2025, 1, 1)
    with pytest.raises(ValueError) as exc:
        diet_api.analyze_record_date(_BEFORE_FLOOR)
    assert str(exc.value) == record_dates.TOO_OLD_DATE_MESSAGE
    with pytest.raises(ValueError) as exc:
        diet_api._past_or_today(_BEFORE_FLOOR)
    assert str(exc.value) == record_dates.TOO_OLD_DATE_MESSAGE


# ── 순수: 끼니 시각 ───────────────────────────────────────────────────────


def test_todays_meal_keeps_the_time_it_was_written():
    from app.services import diet_service

    assert diet_service.record_time_label(_NOW.date(), "breakfast", _NOW) == "23:05"


@pytest.mark.parametrize(
    ("meal_type", "expected"),
    [
        ("breakfast", "08:00"),
        ("lunch", "12:00"),
        ("snack", "15:00"),
        ("dinner", "18:00"),
        ("lateNight", "22:00"),
    ],
)
def test_past_meal_gets_the_default_time_of_its_meal_type(meal_type, expected):
    from app.services import diet_service

    yesterday = _NOW.date() - timedelta(days=1)
    assert diet_service.record_time_label(yesterday, meal_type, _NOW) == expected


def test_default_times_cover_every_meal_type_in_day_order():
    from typing import get_args

    from app.schemas.diet_api import MealTypeLiteral
    from app.services import diet_service

    labels = diet_service.MEAL_DEFAULT_TIME_LABELS
    assert set(labels) == set(get_args(MealTypeLiteral))
    assert sorted(labels, key=labels.__getitem__) == [
        "breakfast", "lunch", "snack", "dinner", "lateNight",
    ]


def test_past_meal_of_an_unknown_type_has_no_time():
    from app.services import diet_service

    yesterday = _NOW.date() - timedelta(days=1)
    assert diet_service.record_time_label(yesterday, "brunch", _NOW) == ""


# ── 순수: 홈 나트륨 급원 이름 ─────────────────────────────────────────────


_MEALS_WITH_DISPLAY_NAMES = [
    json.dumps([
        {"name": "라면", "display_name": "Ramyeon", "sodium_mg": 1800},
        {"name": "김밥", "sodium_mg": 900},
    ], ensure_ascii=False),
    json.dumps([
        {"name": "라면", "display_name": "Instant noodles", "sodium_mg": 200},
        {"name": "단무지", "display_name": "  ", "sodium_mg": 100},
    ], ensure_ascii=False),
]


def test_sodium_sources_use_display_names_on_an_english_screen():
    from app.api.v1.dashboard import _rank_sodium_sources

    # 표시 이름이 없는 음식·빈 표시 이름은 저장된 이름 그대로다.
    assert _rank_sodium_sources(_MEALS_WITH_DISPLAY_NAMES, "en") == [
        "Ramyeon", "김밥", "단무지",
    ]


def test_sodium_sources_keep_stored_names_on_a_korean_screen():
    from app.api.v1.dashboard import _rank_sodium_sources

    assert _rank_sodium_sources(_MEALS_WITH_DISPLAY_NAMES, "ko") == [
        "라면", "김밥", "단무지",
    ]
    # 요청 밖에서는 기본 언어(한국어)다.
    assert _rank_sodium_sources(_MEALS_WITH_DISPLAY_NAMES) == ["라면", "김밥", "단무지"]


def test_sodium_sources_still_sum_one_food_across_meals_in_english():
    """같은 음식이 표시 이름 유무로 둘로 갈리지 않는다 — 합산은 저장 이름으로 한다."""
    from app.api.v1.dashboard import _rank_sodium_sources

    meals = [
        json.dumps([{"name": "김밥", "sodium_mg": 900}], ensure_ascii=False),
        json.dumps(
            [{"name": "김밥", "display_name": "Gimbap", "sodium_mg": 900}],
            ensure_ascii=False,
        ),
        json.dumps(
            [{"name": "라면", "display_name": "Ramyeon", "sodium_mg": 1700}],
            ensure_ascii=False,
        ),
    ]
    assert _rank_sodium_sources(meals, "en") == ["Gimbap", "Ramyeon"]


# ── 순수: 멱등키 줄 id ────────────────────────────────────────────────────


def test_keyed_usage_id_is_stable_per_member_and_key():
    from app.services import diet_analysis_quota_service as quota

    first = quota._keyed_id("user-a", "key-1")
    assert first == quota._keyed_id("user-a", "key-1")
    assert first != quota._keyed_id("user-a", "key-2")
    # 멱등키는 회원 안에서만 유일하다 — 다른 회원의 같은 키와 겹치지 않는다.
    assert first != quota._keyed_id("user-b", "key-1")
    assert first.startswith("dau-k-")
    # `diet_analysis_usages.id` 는 String(64) 다. 키가 가장 길 때도 넘지 않는다.
    assert len(quota._keyed_id("user-" + "x" * 60, "k" * 64)) <= 64


# ── DB: 분석 중인 같은 키 ─────────────────────────────────────────────────


class _CountingRecognizer:
    name = "counting-test"

    def __init__(self, *, foods=None, error: Exception | None = None):
        self.calls = 0
        self._foods = (
            foods
            if foods is not None
            else [RecognizedFood(name="바나나", amount_g=120, calories=105)]
        )
        self._error = error

    async def recognize(self, image_bytes: bytes, media_type: str) -> DietAnalysis:
        self.calls += 1
        if self._error is not None:
            raise self._error
        return DietAnalysis(engine=self.name, foods=list(self._foods))


@pytest.fixture
def recognizer(monkeypatch):
    from app.api.v1 import diet as diet_api

    def _install(**kw) -> _CountingRecognizer:
        rec = _CountingRecognizer(**kw)
        monkeypatch.setattr(diet_api, "get_recognizer", lambda engine=None: rec)
        return rec

    return _install


@pytest.fixture
def limits(monkeypatch):
    from app.core.config import get_settings

    s = get_settings()
    monkeypatch.setattr(s, "rate_limit_enabled", True)
    monkeypatch.setattr(s, "diet_analyze_per_minute", 0)
    monkeypatch.setattr(s, "diet_analyze_per_day", 3)
    return s


def _register(client) -> tuple[str, dict[str, str]]:
    email = f"save-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register", json={"email": email, "password": "test-pw-1234", "name": "u"}
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "test-pw-1234"}
    ).json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    return client.get("/v1/users/me", headers=headers).json()["id"], headers


def _analyze(client, headers, *, key=None, **data):
    form = {"meal_type": "lunch", **data}
    if key:
        form["idempotency_key"] = key
    return client.post(
        "/v1/diet/analyze",
        files={"image": ("food.jpg", _JPEG, "image/jpeg")},
        data=form,
        headers=headers,
    )


def _used(db_session, user_id: str) -> int:
    from sqlalchemy import func, select

    from app.models.models import DietAnalysisUsage

    db_session.expire_all()
    return int(
        db_session.scalar(
            select(func.count())
            .select_from(DietAnalysisUsage)
            .where(DietAnalysisUsage.user_id == user_id)
        )
        or 0
    )


def _age_reservation(db_session, user_id: str, key: str, age: timedelta) -> None:
    """그 키로 잡은 줄을 `age` 만큼 전에 잡은 것으로 만든다."""
    from sqlalchemy import func, update

    from app.models.models import DietAnalysisUsage
    from app.services import diet_analysis_quota_service as quota

    db_session.execute(
        update(DietAnalysisUsage)
        .where(DietAnalysisUsage.id == quota._keyed_id(user_id, key))
        .values(created_at=func.now() - age)
    )
    db_session.commit()


def test_reserve_refuses_the_same_key_while_the_first_is_in_flight(
    client, db_session, limits
):
    from app.services import diet_analysis_quota_service as quota

    user_id, _ = _register(client)
    key = f"idem-{uuid4().hex}"

    first = quota.reserve(db_session, user_id, key)
    with pytest.raises(quota.AnalysisInProgress):
        quota.reserve(db_session, user_id, key)

    assert first == quota._keyed_id(user_id, key)
    assert _used(db_session, user_id) == 1
    # 다른 키·키 없는 요청은 따로 센다.
    assert quota.reserve(db_session, user_id, f"idem-{uuid4().hex}") != first
    assert quota.reserve(db_session, user_id) not in (None, first)
    assert _used(db_session, user_id) == 3


def test_resend_during_analysis_answers_409_in_progress_without_spending(
    client, db_session, limits, recognizer
):
    """느린 망에서 재전송이 겹쳐도 하루 분석 횟수가 한 번만 준다."""
    from app.services import diet_analysis_quota_service as quota

    rec = recognizer()
    user_id, h = _register(client)
    key = f"idem-{uuid4().hex}"
    # 첫 요청이 한도를 잡고 모델을 기다리는 중이다.
    quota.reserve(db_session, user_id, key)

    r = _analyze(client, h, key=key)

    assert r.status_code == 409, r.text
    assert r.json()["detail"]["code"] == "in_progress"
    assert r.json()["detail"]["message"]
    assert rec.calls == 0
    assert _used(db_session, user_id) == 1
    assert client.get("/v1/diet/days/today", headers=h).json()["entries"] == []


def test_resend_after_the_first_saved_returns_the_saved_meal_once_counted(
    client, db_session, limits, recognizer
):
    rec = recognizer()
    user_id, h = _register(client)
    key = f"idem-{uuid4().hex}"

    first = _analyze(client, h, key=key)
    second = _analyze(client, h, key=key)
    third = _analyze(client, h, key=key)

    assert first.status_code == 200, first.text
    for replay in (second, third):
        assert replay.status_code == 200, replay.text
        assert replay.json()["entry_id"] == first.json()["entry_id"]
    assert rec.calls == 1
    assert _used(db_session, user_id) == 1


def test_in_progress_is_recognised_even_when_the_daily_limit_is_off(
    client, db_session, limits, monkeypatch, recognizer
):
    """상한이 꺼진 환경에서도 겹친 재전송이 모델을 한 번 더 부르지 않는다."""
    from app.services import diet_analysis_quota_service as quota

    monkeypatch.setattr(limits, "rate_limit_enabled", False)
    rec = recognizer()
    user_id, h = _register(client)
    key = f"idem-{uuid4().hex}"
    assert quota.reserve(db_session, user_id) is None
    assert quota.reserve(db_session, user_id, key) is not None

    r = _analyze(client, h, key=key)

    assert r.status_code == 409, r.text
    assert r.json()["detail"]["code"] == "in_progress"
    assert rec.calls == 0


def test_in_progress_does_not_block_another_member_using_the_same_key(
    client, db_session, limits, recognizer
):
    from app.services import diet_analysis_quota_service as quota

    rec = recognizer()
    first_id, _ = _register(client)
    _, other = _register(client)
    key = f"idem-{uuid4().hex}"
    quota.reserve(db_session, first_id, key)

    assert _analyze(client, other, key=key).status_code == 200
    assert rec.calls == 1


def test_abandoned_reservation_is_reclaimed_and_counted_once(
    client, db_session, limits, recognizer
):
    """분석하던 프로세스가 끝나 남은 줄이 그 키를 끝없이 막지 않는다."""
    from app.services import diet_analysis_quota_service as quota

    rec = recognizer()
    user_id, h = _register(client)
    key = f"idem-{uuid4().hex}"
    quota.reserve(db_session, user_id, key)
    _age_reservation(
        db_session, user_id, key, quota.RESERVATION_STALE_AFTER + timedelta(seconds=30)
    )

    r = _analyze(client, h, key=key)

    assert r.status_code == 200, r.text
    assert rec.calls == 1
    assert _used(db_session, user_id) == 1


def test_reservation_younger_than_the_stale_window_still_blocks(
    client, db_session, limits, recognizer
):
    from app.services import diet_analysis_quota_service as quota

    rec = recognizer()
    user_id, h = _register(client)
    key = f"idem-{uuid4().hex}"
    quota.reserve(db_session, user_id, key)
    _age_reservation(
        db_session, user_id, key, quota.RESERVATION_STALE_AFTER - timedelta(minutes=1)
    )

    assert _analyze(client, h, key=key).status_code == 409
    assert rec.calls == 0


def test_model_failure_frees_the_key_and_the_share(
    client, db_session, limits, recognizer
):
    user_id, h = _register(client)
    key = f"idem-{uuid4().hex}"

    recognizer(error=RuntimeError("provider down"))
    assert _analyze(client, h, key=key).status_code == 502
    assert _used(db_session, user_id) == 0

    # 같은 키로 다시 보내면 "분석 중" 이 아니라 새로 분석한다.
    rec = recognizer()
    r = _analyze(client, h, key=key)
    assert r.status_code == 200, r.text
    assert rec.calls == 1
    assert _used(db_session, user_id) == 1


def test_photo_without_food_counts_once_and_frees_the_key(
    client, db_session, limits, recognizer
):
    """끼니가 없어 돌려줄 저장분이 없다 — 같은 키가 "분석 중" 에 갇히지 않는다."""
    user_id, h = _register(client)
    key = f"idem-{uuid4().hex}"

    recognizer(foods=[])
    r = _analyze(client, h, key=key)
    assert r.status_code == 422, r.text
    assert r.json()["detail"]["code"] == "no_food_detected"
    assert _used(db_session, user_id) == 1

    rec = recognizer()
    again = _analyze(client, h, key=key)
    assert again.status_code == 200, again.text
    assert rec.calls == 1
    # 모델을 두 번 불렀다 — 두 번 센다.
    assert _used(db_session, user_id) == 2


def test_failed_save_frees_the_key_but_keeps_the_count(
    client, db_session, limits, monkeypatch, recognizer
):
    from fastapi.testclient import TestClient

    from app.api.v1 import diet as diet_api
    from app.main import app
    from app.services import diet_analysis_quota_service as quota

    recognizer()
    user_id, h = _register(client)
    key = f"idem-{uuid4().hex}"

    def _boom(*args, **kwargs):
        raise RuntimeError("save failed")

    monkeypatch.setattr(diet_api, "_persist_analysis", _boom)
    # 서버 오류를 예외가 아니라 500 응답으로 받는다.
    quiet = TestClient(app, raise_server_exceptions=False)
    assert _analyze(quiet, h, key=key).status_code == 500

    assert _used(db_session, user_id) == 1
    # 키에 묶인 줄이 남지 않았다 — 같은 키를 다시 잡을 수 있다.
    assert quota.reserve(db_session, user_id, key) == quota._keyed_id(user_id, key)


def test_settle_leaves_unkeyed_and_missing_reservations_alone(
    client, db_session, limits
):
    from app.services import diet_analysis_quota_service as quota

    user_id, _ = _register(client)
    plain = quota.reserve(db_session, user_id)

    quota.settle(db_session, None)
    quota.settle(db_session, plain)
    quota.settle(db_session, quota._keyed_id(user_id, "never-reserved"))

    assert _used(db_session, user_id) == 1
    quota.release(db_session, plain)
    assert _used(db_session, user_id) == 0


# ── DB: 날짜 하한 ─────────────────────────────────────────────────────────


_FOODS = [{"name": "김밥", "calories": 420, "carbs_g": 70, "sodium_mg": 900}]


def _create(client, headers, **overrides):
    body = {"meal_type": "lunch", "foods": _FOODS, **overrides}
    return client.post("/v1/diet/entries", json=body, headers=headers)


def test_manual_entry_before_the_floor_is_422_and_saves_nothing(client, frozen_now):
    _, h = _register(client)

    r = _create(client, h, date=_BEFORE_FLOOR)

    assert r.status_code == 422, r.text
    assert "작년 1월 1일" in r.text
    day = client.get(f"/v1/diet/days/{_BEFORE_FLOOR}", headers=h).json()
    assert day["entries"] == []


def test_manual_entry_on_the_floor_day_is_accepted(client, frozen_now):
    _, h = _register(client)

    r = _create(client, h, date=_FLOOR)

    assert r.status_code == 201, r.text
    day = client.get(f"/v1/diet/days/{_FLOOR}", headers=h).json()
    assert [e["id"] for e in day["entries"]] == [r.json()["id"]]


def test_moving_an_entry_before_the_floor_is_422_and_keeps_its_day(client, frozen_now):
    _, h = _register(client)
    entry_id = _create(client, h).json()["id"]

    r = client.put(
        f"/v1/diet/entries/{entry_id}", json={"date": _BEFORE_FLOOR}, headers=h
    )

    assert r.status_code == 422, r.text
    today = client.get(f"/v1/diet/days/{_TODAY}", headers=h).json()
    assert [e["id"] for e in today["entries"]] == [entry_id]

    # 하한 날짜로는 옮겨진다.
    ok = client.put(f"/v1/diet/entries/{entry_id}", json={"date": _FLOOR}, headers=h)
    assert ok.status_code == 200, ok.text
    moved = client.get(f"/v1/diet/days/{_FLOOR}", headers=h).json()
    assert [e["id"] for e in moved["entries"]] == [entry_id]


def test_analyze_before_the_floor_is_422_before_the_model(
    client, db_session, limits, recognizer, frozen_now
):
    rec = recognizer()
    user_id, h = _register(client)

    r = _analyze(client, h, key=f"idem-{uuid4().hex}", date=_BEFORE_FLOOR)

    assert r.status_code == 422, r.text
    assert rec.calls == 0
    assert _used(db_session, user_id) == 0


# ── DB: 끼니 시각 ─────────────────────────────────────────────────────────


def test_manual_meal_written_for_yesterday_gets_the_meal_default_time(
    client, frozen_now
):
    """어제 아침을 밤 11시에 적어도 시각이 23:05 가 아니다."""
    _, h = _register(client)

    entry = _create(client, h, date=_YESTERDAY, meal_type="breakfast").json()

    assert entry["time_label"] == "08:00"
    day = client.get(f"/v1/diet/days/{_YESTERDAY}", headers=h).json()
    assert [e["time_label"] for e in day["entries"]] == ["08:00"]


def test_manual_meal_written_for_today_keeps_the_written_time(client, frozen_now):
    _, h = _register(client)

    assert _create(client, h).json()["time_label"] == "23:05"
    # 오늘 날짜를 직접 실어도 같다.
    assert _create(client, h, date=_TODAY).json()["time_label"] == "23:05"


def test_past_meals_line_up_in_meal_order_whatever_order_they_were_written(
    client, frozen_now
):
    _, h = _register(client)
    for meal_type in ("lateNight", "dinner", "breakfast", "snack", "lunch"):
        assert _create(client, h, date=_YESTERDAY, meal_type=meal_type).status_code == 201

    day = client.get(f"/v1/diet/days/{_YESTERDAY}", headers=h).json()

    by_time = sorted(day["entries"], key=lambda e: e["time_label"])
    assert [e["meal_type"] for e in by_time] == [
        "breakfast", "lunch", "snack", "dinner", "lateNight",
    ]


def test_analyzed_meal_for_a_past_day_gets_the_meal_default_time(
    client, limits, recognizer, frozen_now
):
    recognizer()
    _, h = _register(client)
    key = f"idem-{uuid4().hex}"

    r = _analyze(client, h, key=key, date=_YESTERDAY, meal_type="dinner")

    assert r.status_code == 200, r.text
    assert r.json()["time_label"] == "18:00"
    day = client.get(f"/v1/diet/days/{_YESTERDAY}", headers=h).json()
    assert [e["time_label"] for e in day["entries"]] == ["18:00"]
    # 재전송도 저장된 시각을 그대로 돌려준다.
    assert _analyze(client, h, key=key, date=_YESTERDAY).json()["time_label"] == "18:00"


def test_analyzed_meal_for_today_keeps_the_written_time(
    client, limits, recognizer, frozen_now
):
    recognizer()
    _, h = _register(client)

    assert _analyze(client, h).json()["time_label"] == "23:05"


def test_moving_an_entry_does_not_rewrite_its_time(client, frozen_now):
    """기본 시각은 새로 적을 때만 넣는다 — 수정은 회원이 보낸 값만 바꾼다."""
    _, h = _register(client)
    entry_id = _create(client, h).json()["id"]

    moved = client.put(
        f"/v1/diet/entries/{entry_id}", json={"date": _YESTERDAY}, headers=h
    )

    assert moved.status_code == 200, moved.text
    assert moved.json()["time_label"] == "23:05"


# ── DB: 홈 나트륨 경고의 음식 이름 ────────────────────────────────────────


def test_home_sodium_warning_uses_english_food_names_on_an_english_screen(client):
    _, h = _register(client)
    # 목표를 정하지 않은 회원의 나트륨 기준은 2,000mg 이다.
    foods = [
        {"name": "라면", "display_name": "Ramyeon", "calories": 500, "sodium_mg": 1800},
        {"name": "김밥", "calories": 420, "sodium_mg": 900},
    ]
    assert _create(client, h, foods=foods).status_code == 201

    en = client.get(
        "/v1/dashboard/summary", headers={**h, "Accept-Language": "en"}
    ).json()
    ko = client.get(
        "/v1/dashboard/summary", headers={**h, "Accept-Language": "ko"}
    ).json()

    assert en["ai_advice_key"] == ko["ai_advice_key"] == "sodium_over_sources"
    # 영어 이름이 있는 음식은 그것으로, 없는 음식은 저장된 이름 그대로다.
    assert en["ai_advice_params"] == {"foods": ["Ramyeon", "김밥"]}
    assert en["sodium_warning"] == "Sodium is high from Ramyeon and 김밥."
    assert ko["ai_advice_params"] == {"foods": ["라면", "김밥"]}
    assert ko["sodium_warning"] == "라면·김밥 섭취로 나트륨이 높아요."
