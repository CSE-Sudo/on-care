"""사진 분석의 기록 날짜 — `POST /diet/analyze` 의 선택 `date` 폼 필드. (#2849)

식단 탭에서 지난 날짜를 보며 `식단 추가` 로 사진을 올리면, 서버가 날짜를 받지
않아 늘 오늘로 저장됐다. 회원은 어제 화면에서 추가했는데 기록은 오늘에 쌓였다.
이제 앱이 그 날짜를 싣고 서버는 처음부터 그 날로 저장한다. 앞날·작년 1월 1일
이전·형식이 틀린 값은 인식(비용이 드는 호출) 전에 422 로 거절한다.
"""
from __future__ import annotations

from datetime import date, datetime
from uuid import uuid4

import pytest

from app.core import clock

_JPEG = b"\xff\xd8\xff\xe0\x00\x10JFIF fake-image-bytes"

#: 오늘은 2026-08-20(목) 09:00 KST 로 고정한다.
_NOW = datetime(2026, 8, 20, 9, 0, tzinfo=clock.SEOUL)


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


# ── 순수 검증 ────────────────────────────────────────────────────────────


def test_record_date_is_none_when_omitted(frozen_today):
    from app.schemas.diet_api import analyze_record_date

    assert analyze_record_date(None) is None


@pytest.mark.parametrize(
    "value, expected",
    [
        ("2026-08-20", date(2026, 8, 20)),
        ("2026-08-19", date(2026, 8, 19)),
        ("2025-01-01", date(2025, 1, 1)),
    ],
)
def test_record_date_accepts_today_and_the_past(frozen_today, value, expected):
    from app.schemas.diet_api import analyze_record_date

    assert analyze_record_date(value) == expected


@pytest.mark.parametrize(
    "value",
    [
        "2026-08-21",  # 앞날
        "2024-12-31",  # 작년 1월 1일 이전
        "20260819",  # 축약 표기
        "2026-02-30",  # 달력에 없는 날
        "yesterday",
    ],
)
def test_record_date_rejects_future_old_and_malformed(frozen_today, value):
    from app.schemas.diet_api import analyze_record_date

    with pytest.raises(ValueError):
        analyze_record_date(value)


# ── API ─────────────────────────────────────────────────────────────────


def _analyze(client, **data):
    return client.post(
        "/v1/diet/analyze",
        files={"image": ("food.jpg", _JPEG, "image/jpeg")},
        data={"meal_type": "dinner", **data},
    )


def _ids_on(client, day: str) -> set[str]:
    return {e["id"] for e in client.get(f"/v1/diet/days/{day}").json()["entries"]}


def test_analyze_saves_on_the_given_past_date(client, frozen_today):
    r = _analyze(client, date="2026-08-19")
    assert r.status_code == 200, r.text
    eid = r.json()["entry_id"]

    assert eid in _ids_on(client, "2026-08-19")
    assert eid not in _ids_on(client, "2026-08-20")


def test_analyze_without_date_saves_today(client, frozen_today):
    r = _analyze(client)
    assert r.status_code == 200, r.text
    assert r.json()["entry_id"] in _ids_on(client, "2026-08-20")


def test_analyze_stores_the_date_on_the_row(client, db_session, frozen_today):
    from app.models.models import DietEntry

    eid = _analyze(client, date="2026-08-18").json()["entry_id"]
    db_session.expire_all()
    row = db_session.get(DietEntry, eid)
    assert row is not None
    assert row.date == "2026-08-18"


@pytest.mark.parametrize("bad", ["2026-08-21", "2024-12-31", "20260819", "nope"])
def test_analyze_rejects_bad_dates_with_422(client, frozen_today, bad):
    key = f"date-{uuid4().hex}"
    r = _analyze(client, date=bad, idempotency_key=key)
    assert r.status_code == 422, r.text

    # 저장되지 않았다 — 같은 키로 오늘 날짜를 보내면 새로 저장된다.
    ok = _analyze(client, idempotency_key=key)
    assert ok.status_code == 200, ok.text
    assert ok.json()["entry_id"] in _ids_on(client, "2026-08-20")


def test_analyze_retry_with_same_key_keeps_the_first_date(client, frozen_today):
    """멱등키 재시도는 처음 저장분을 그대로 돌려준다 — 날짜가 바뀌지 않는다."""
    key = f"date-retry-{uuid4().hex}"
    first = _analyze(client, date="2026-08-17", idempotency_key=key)
    assert first.status_code == 200, first.text
    second = _analyze(client, idempotency_key=key)
    assert second.status_code == 200, second.text
    assert second.json()["entry_id"] == first.json()["entry_id"]
    assert first.json()["entry_id"] in _ids_on(client, "2026-08-17")
