"""사진 분석·수정의 끼니 구분과 시각 검증. (#2882)

직접 기록(`POST /diet/entries`)만 다섯 끼니 값을 막고, 사진 분석과 수정은 아무
문자열이나 받았다. 짧은 엉뚱한 값은 저장된 뒤 끼니별 집계·트레이너 화면에서 어느
끼니에도 들지 않았고, 컬럼(String(20))보다 긴 값은 DB 오류(500)였다.
"""
from __future__ import annotations

from datetime import datetime
from uuid import uuid4

import pytest

from app.core import clock

_JPEG = b"\xff\xd8\xff\xe0\x00\x10JFIF fake-image-bytes"

#: 오늘은 2026-08-20(목) 12:00 KST 로 고정한다.
_NOW = datetime(2026, 8, 20, 12, 0, tzinfo=clock.SEOUL)

_MEALS = ["breakfast", "lunch", "dinner", "snack", "lateNight"]


@pytest.fixture(autouse=True)
def _demo_member_auth(request):
    """이 모듈의 엔드포인트 검사는 데모 회원의 기록을 쓰고 읽는다.

    쓰기·삭제 라우트는 데모 폴백 없이 회원 토큰을 요구하므로(#2831), 토큰 없이
    보내던 요청에 데모 회원 토큰을 기본 헤더로 붙인다. 요청마다 `headers=` 를 준
    검사는 그 값이 우선한다. DB 가 필요 없는 순수 검사는 건드리지 않는다.
    """
    if "client" not in request.fixturenames:
        yield
        return
    from app.core.security import create_access_token
    from app.db.init_db import DEMO_USER_ID
    from app.db.session import SessionLocal
    from app.models.models import User

    client = request.getfixturevalue("client")
    with SessionLocal() as db:
        version = db.get(User, DEMO_USER_ID).token_version
    previous = client.headers.get("Authorization")
    client.headers["Authorization"] = (
        f"Bearer {create_access_token(DEMO_USER_ID, token_version=version)}"
    )
    try:
        yield
    finally:
        if previous is None:
            client.headers.pop("Authorization", None)
        else:
            client.headers["Authorization"] = previous


@pytest.fixture
def frozen_today(monkeypatch):
    monkeypatch.setattr(clock, "now", lambda: _NOW)
    return _NOW.date()


def _analyze(client, meal_type: str | None, **extra):
    data = {} if meal_type is None else {"meal_type": meal_type}
    return client.post(
        "/v1/diet/analyze",
        files={"image": ("food.jpg", _JPEG, "image/jpeg")},
        data={**data, **extra},
    )


# ── 스키마 ───────────────────────────────────────────────────────────────


@pytest.mark.parametrize("meal", _MEALS)
def test_update_schema_accepts_the_five_meals(meal):
    from app.schemas.diet_api import DietEntryUpdate

    assert DietEntryUpdate(meal_type=meal).meal_type == meal


@pytest.mark.parametrize("bad", ["brunch", "Lunch", "late_night", "", "x" * 21])
def test_update_schema_rejects_other_meals(bad):
    from pydantic import ValidationError

    from app.schemas.diet_api import DietEntryUpdate

    with pytest.raises(ValidationError):
        DietEntryUpdate(meal_type=bad)


@pytest.mark.parametrize("ok", ["00:00", "07:05", "19:30", "23:59", ""])
def test_update_schema_accepts_hhmm_or_empty_time(ok):
    from app.schemas.diet_api import DietEntryUpdate

    assert DietEntryUpdate(time_label=ok).time_label == ok


@pytest.mark.parametrize("bad", ["24:00", "7:05", "19:60", "오후 7:30", "19:30:00", "noon"])
def test_update_schema_rejects_other_times(bad):
    from pydantic import ValidationError

    from app.schemas.diet_api import DietEntryUpdate

    with pytest.raises(ValidationError):
        DietEntryUpdate(time_label=bad)


def test_create_and_update_share_the_same_meal_values():
    from typing import get_args

    from app.schemas.diet_api import MealTypeLiteral

    assert list(get_args(MealTypeLiteral)) == _MEALS


# ── API ─────────────────────────────────────────────────────────────────


@pytest.mark.parametrize("meal", _MEALS)
def test_analyze_accepts_the_five_meals(client, frozen_today, meal):
    r = _analyze(client, meal)
    assert r.status_code == 200, r.text


def test_analyze_without_meal_type_is_lunch(client, frozen_today):
    r = _analyze(client, None)
    assert r.status_code == 200, r.text
    eid = r.json()["entry_id"]
    entries = client.get("/v1/diet/days/2026-08-20").json()["entries"]
    assert next(e for e in entries if e["id"] == eid)["meal_type"] == "lunch"


@pytest.mark.parametrize("bad", ["brunch", "late_night", "x" * 40])
def test_analyze_rejects_other_meals_before_saving(client, frozen_today, bad):
    key = f"meal-{uuid4().hex}"
    r = _analyze(client, bad, idempotency_key=key)
    assert r.status_code == 422, r.text

    # 저장되지 않았다 — 같은 키로 올바른 값을 보내면 새로 저장된다.
    ok = _analyze(client, "dinner", idempotency_key=key)
    assert ok.status_code == 200, ok.text
    entries = client.get("/v1/diet/days/2026-08-20").json()["entries"]
    assert next(e for e in entries if e["id"] == ok.json()["entry_id"])["meal_type"] == "dinner"


@pytest.fixture
def entry_id(client, frozen_today):
    r = _analyze(client, "lunch")
    assert r.status_code == 200, r.text
    return r.json()["entry_id"]


@pytest.mark.parametrize("bad", ["brunch", "", "x" * 40])
def test_update_rejects_other_meals(client, entry_id, bad):
    r = client.put(f"/v1/diet/entries/{entry_id}", json={"meal_type": bad})
    assert r.status_code == 422, r.text
    entries = client.get("/v1/diet/days/2026-08-20").json()["entries"]
    assert next(e for e in entries if e["id"] == entry_id)["meal_type"] == "lunch"


def test_update_accepts_late_night(client, entry_id):
    r = client.put(f"/v1/diet/entries/{entry_id}", json={"meal_type": "lateNight"})
    assert r.status_code == 200, r.text
    assert r.json()["meal_type"] == "lateNight"


@pytest.mark.parametrize("bad", ["25:00", "오후 7:30", "x" * 40])
def test_update_rejects_bad_time_label(client, entry_id, bad):
    r = client.put(f"/v1/diet/entries/{entry_id}", json={"time_label": bad})
    assert r.status_code == 422, r.text


def test_update_accepts_hhmm_time_label(client, entry_id):
    r = client.put(f"/v1/diet/entries/{entry_id}", json={"time_label": "19:30"})
    assert r.status_code == 200, r.text
    assert r.json()["time_label"] == "19:30"
