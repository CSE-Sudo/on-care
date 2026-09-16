"""식단 사진분석(/diet/analyze) — DB 필요(로컬 skip, CI 실행).

CI 엔 GEMINI_API_KEY 가 없으므로 오프라인 스텁 인식기 경로를 검증한다
(이미지 내용과 무관하게 결정론적 식단 → 공공 영양 DB 매핑 → 저장).
"""
from __future__ import annotations

import json
import math
import uuid
from uuid import uuid4

import pytest
from pydantic import ValidationError
from sqlalchemy import delete, select

_JPEG = b"\xff\xd8\xff\xe0\x00\x10JFIF fake-image-bytes"


def _h(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _member_token(client) -> str:
    """시드 회원(지수) 토큰 — 기간 조언은 회원 자기 기록만 본다."""
    return client.post(
        "/v1/auth/login", data={"username": "jisu@oncare.com", "password": "oncare123"}
    ).json()["access_token"]



def test_macro_percentages_use_449_and_always_sum_correctly():
    from app.schemas.diet_api import calculate_macros

    equal_energy = calculate_macros(9.0, 9.0, 4.0)
    assert (equal_energy.carbs_pct, equal_energy.protein_pct, equal_energy.fat_pct) == (
        33, 33, 34,
    )
    assert equal_energy.carbs_pct + equal_energy.protein_pct + equal_energy.fat_pct == 100

    regular = calculate_macros(25.0, 12.5, 5.0)
    assert (regular.carbs_pct, regular.protein_pct, regular.fat_pct) == (51, 26, 23)
    assert regular.carbs_pct + regular.protein_pct + regular.fat_pct == 100

    zero = calculate_macros(0.0, 0.0, 0.0)
    assert (zero.carbs_pct, zero.protein_pct, zero.fat_pct) == (0, 0, 0)
    assert zero.carbs_pct + zero.protein_pct + zero.fat_pct == 0


def test_get_diet_day_by_date_aggregates_only_current_user(client, db_session):
    from app.db.init_db import DEMO_USER_ID
    from app.models.models import DietEntry, User

    date = "2001-02-03"
    suffix = uuid.uuid4().hex[:12]
    other_user_id = f"diet-date-owner-{suffix}"
    db_session.execute(
        delete(DietEntry).where(
            DietEntry.user_id == DEMO_USER_ID,
            DietEntry.date == date,
        )
    )
    db_session.add(
        User(
            id=other_user_id,
            email=f"{other_user_id}@example.com",
            name="Other User",
            hashed_password="",
        )
    )
    db_session.flush()
    db_session.add_all(
        [
            DietEntry(
                id=f"diet-date-current-{suffix}",
                user_id=DEMO_USER_ID,
                date=date,
                meal_type="lunch",
                total_calories=420,
                carbs_g=40,
                protein_g=20,
                fat_g=10,
                sodium_mg=350,
                sugar_g=7.5,
            ),
            DietEntry(
                id=f"diet-date-other-{suffix}",
                user_id=other_user_id,
                date=date,
                meal_type="dinner",
                total_calories=999,
            ),
        ]
    )
    db_session.commit()

    response = client.get(f"/v1/diet/days/{date}")

    assert response.status_code == 200
    body = response.json()
    assert len(body["entries"]) == 1
    assert body["entries"][0]["photo_asset"] is None
    assert body["total_calories"] == 420
    assert body["total_sodium_mg"] == 350
    assert body["total_sugar_g"] == 7.5
    assert body["macros"] == {
        "carbs_g": 40.0,
        "protein_g": 20.0,
        "fat_g": 10.0,
        "carbs_pct": 49,
        "protein_pct": 24,
        "fat_pct": 27,
    }


@pytest.mark.parametrize("date", ["1999-01-01", "2999-01-01"])
def test_get_diet_day_by_date_returns_empty_day(client, date):
    response = client.get(f"/v1/diet/days/{date}")

    assert response.status_code == 200
    body = response.json()
    assert body["entries"] == []
    assert body["total_calories"] == 0
    assert body["total_sodium_mg"] == 0
    assert body["total_sugar_g"] == 0
    assert body["macros"] == {
        "carbs_g": 0.0,
        "protein_g": 0.0,
        "fat_g": 0.0,
        "carbs_pct": 0,
        "protein_pct": 0,
        "fat_pct": 0,
    }


def test_get_diet_day_by_date_rejects_invalid_date(client):
    assert client.get("/v1/diet/days/not-a-date").status_code == 422


def test_today_endpoint_matches_date_endpoint(client):
    from app.services.diet_service import today_str

    today = client.get("/v1/diet/days/today")
    by_date = client.get(f"/v1/diet/days/{today_str()}")

    assert today.status_code == 200
    assert by_date.status_code == 200
    assert today.json() == by_date.json()


@pytest.mark.parametrize("field", ["carbs_g", "protein_g", "fat_g"])
@pytest.mark.parametrize("value", [-0.1, math.nan, math.inf, -math.inf])
def test_recognized_food_rejects_invalid_macros(field, value):
    from app.schemas.diet import RecognizedFood

    with pytest.raises(ValidationError):
        RecognizedFood(name="test", **{field: value})


@pytest.mark.parametrize("field", ["carbs_g", "protein_g", "fat_g"])
def test_recognized_food_allows_optional_and_positive_macros(field):
    from app.schemas.diet import RecognizedFood

    assert getattr(RecognizedFood(name="test", **{field: None}), field) is None
    assert getattr(RecognizedFood(name="test", **{field: 1.25}), field) == 1.25


def test_gemini_parser_sanitizes_and_totals_optional_macros():
    from app.services.recognizer.gemini import GeminiVisionRecognizer

    raw = json.dumps({
        "foods": [
            {
                "name": "비빔밥",
                "carbs_g": 68.5,
                "protein_g": 18,
                "fat_g": 12.25,
            },
            {
                "name": "김치",
                "carbs_g": None,
                "protein_g": 2.5,
                "fat_g": None,
            },
            {
                "name": "잘못된 값",
                "carbs_g": -1,
                "protein_g": "NaN",
                "fat_g": "Infinity",
            },
            {
                "name": "일부 정상 값",
                "carbs_g": "-Infinity",
                "protein_g": 3,
                "fat_g": 1,
            },
        ],
    })

    analysis = GeminiVisionRecognizer.__new__(GeminiVisionRecognizer)._parse(raw, 10)

    assert (analysis.foods[0].carbs_g, analysis.foods[0].protein_g, analysis.foods[0].fat_g) == (
        68.5, 18.0, 12.25,
    )
    assert (analysis.foods[1].carbs_g, analysis.foods[1].protein_g, analysis.foods[1].fat_g) == (
        None, 2.5, None,
    )
    assert (analysis.foods[2].carbs_g, analysis.foods[2].protein_g, analysis.foods[2].fat_g) == (
        None, None, None,
    )
    assert (analysis.foods[3].carbs_g, analysis.foods[3].protein_g, analysis.foods[3].fat_g) == (
        None, 3.0, 1.0,
    )
    assert (analysis.total_carbs_g, analysis.total_protein_g, analysis.total_fat_g) == (
        68.5, 23.5, 13.25,
    )


def test_litellm_parser_sanitizes_and_totals_optional_macros():
    from app.services.recognizer.litellm_vision import LiteLLMVisionRecognizer

    raw = """```json
{"foods":[
  {"name":"비빔밥","carbs_g":68.5,"protein_g":18,"fat_g":12.25},
  {"name":"김치","carbs_g":null,"protein_g":2.5,"fat_g":null},
  {"name":"잘못된 값","carbs_g":-1,"protein_g":"NaN","fat_g":"Infinity"},
  {"name":"일부 정상 값","carbs_g":"-Infinity","protein_g":3,"fat_g":1}
]}
```"""

    analysis = LiteLLMVisionRecognizer.__new__(LiteLLMVisionRecognizer)._parse(raw, 10)

    assert (analysis.foods[0].carbs_g, analysis.foods[0].protein_g, analysis.foods[0].fat_g) == (
        68.5, 18.0, 12.25,
    )
    assert (analysis.foods[1].carbs_g, analysis.foods[1].protein_g, analysis.foods[1].fat_g) == (
        None, 2.5, None,
    )
    assert (analysis.foods[2].carbs_g, analysis.foods[2].protein_g, analysis.foods[2].fat_g) == (
        None, None, None,
    )
    assert (analysis.foods[3].carbs_g, analysis.foods[3].protein_g, analysis.foods[3].fat_g) == (
        None, 3.0, 1.0,
    )
    assert (analysis.total_carbs_g, analysis.total_protein_g, analysis.total_fat_g) == (
        68.5, 23.5, 13.25,
    )


@pytest.mark.parametrize("field", ["carbs_g", "protein_g", "fat_g"])
@pytest.mark.parametrize("value", [math.nan, math.inf, -math.inf])
def test_entry_update_rejects_non_finite_macros(field, value):
    from app.schemas.diet_api import DietEntryUpdate

    with pytest.raises(ValidationError):
        DietEntryUpdate(**{field: value})


def test_analyze_offline_saves_and_reflects_macros_in_today(client, db_session):
    from app.services.diet_service import today_str as _today_str
    from app.db.init_db import DEMO_USER_ID
    from app.models.models import DietEntry

    # Isolate exact daily totals. 스텁이 읽는 세 메뉴는 시드가 탄단지까지
    # 들고 있으므로 여기서 따로 채워 줄 것이 없다(#1564).
    db_session.execute(
        delete(DietEntry).where(
            DietEntry.user_id == DEMO_USER_ID,
            DietEntry.date == _today_str(),
        )
    )
    db_session.commit()

    r = client.post(
        "/v1/diet/analyze",
        files={"image": ("food.jpg", _JPEG, "image/jpeg")},
        data={"meal_type": "lunch"},
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["entry_id"]
    foods = body["analysis"]["foods"]
    assert foods  # 인식된 음식이 있어야
    # 공공 영양 DB 매핑으로 신뢰 수치가 채워짐(비빔밥/김치는 시드에 존재)
    assert body["analysis"]["total_calories"] == 395
    # 세 메뉴가 모두 시드에 있으므로 값은 전부 공공 DB 쪽에서 온다.
    assert all(f["source"] == "db" for f in foods)
    # 값은 100g 기준이고 인식기가 양을 안 주면 알려진 1회 섭취량으로 환산된다 —
    # 시드가 1인분으로 적어 둔 값이 그 왕복을 거쳐 돌아온다.
    assert body["analysis"]["total_carbs_g"] == pytest.approx(59.0, abs=0.05)
    assert body["analysis"]["total_protein_g"] == pytest.approx(9.0, abs=0.05)
    assert body["analysis"]["total_fat_g"] == pytest.approx(14.0, abs=0.05)
    assert all({"carbs_g", "protein_g", "fat_g"} <= f.keys() for f in foods)

    stored = db_session.get(DietEntry, body["entry_id"])
    assert stored is not None
    # 저장값도 환산 후 값이어야 한다(응답과 어긋나면 화면·DB 가 갈린다).
    assert stored.carbs_g == pytest.approx(59.0, abs=0.05)
    assert stored.protein_g == pytest.approx(9.0, abs=0.05)
    assert stored.fat_g == pytest.approx(14.0, abs=0.05)
    stored_foods = json.loads(stored.foods_json)
    # 음식별 탄단지도 같이 저장한다(#1892). 응답에는 담으면서 저장에서 버리면
    # 다시 읽는 순간 사라져, 수정 화면이 음식마다 0 을 보여 준다.
    assert all({"carbs_g", "protein_g", "fat_g"} <= food.keys() for food in stored_foods)
    assert [food["carbs_g"] for food in stored_foods] == [f["carbs_g"] for f in foods]

    second = client.post(
        "/v1/diet/analyze",
        files={"image": ("food.jpg", _JPEG, "image/jpeg")},
        data={"meal_type": "dinner"},
    )
    assert second.status_code == 200, second.text

    today = client.get("/v1/diet/days/today")
    assert today.status_code == 200
    today_body = today.json()
    assert today_body["total_calories"] > 0
    assert len(today_body["entries"]) == 2
    assert all(
        entry["carbs_g"] == pytest.approx(59.0, abs=0.05)
        for entry in today_body["entries"]
    )
    assert all(
        entry["protein_g"] == pytest.approx(9.0, abs=0.05)
        for entry in today_body["entries"]
    )
    assert all(
        entry["fat_g"] == pytest.approx(14.0, abs=0.05)
        for entry in today_body["entries"]
    )
    # 하루 조회에도 음식별 탄단지가 함께 온다 — 수정 화면이 이 값을 연다(#1892).
    assert all(
        {"carbs_g", "protein_g", "fat_g"} <= food.keys()
        for entry in today_body["entries"]
        for food in entry["foods"]
    )
    # 끼니 합계는 그 끼니 음식들의 합이다.
    assert all(
        entry["carbs_g"] == pytest.approx(
            sum(food["carbs_g"] or 0 for food in entry["foods"]), abs=0.05
        )
        for entry in today_body["entries"]
    )
    macros = today_body["macros"]
    # 같은 끼니를 두 번 저장했으므로 하루 합계는 한 끼의 두 배다.
    assert macros["carbs_g"] == pytest.approx(118.0, abs=0.1)
    assert macros["protein_g"] == pytest.approx(18.0, abs=0.1)
    assert macros["fat_g"] == pytest.approx(28.0, abs=0.1)
    assert (macros["carbs_pct"], macros["protein_pct"], macros["fat_pct"]) == (
        59,
        9,
        32,
    )


def test_analyze_succeeds_when_personal_rag_ingest_fails(
    client, db_session, monkeypatch
):
    """보조 RAG 적재 실패가 이미 저장된 식단의 성공 응답을 500으로 바꾸지 않는다."""
    from app.models.models import DietEntry
    from app.services import diet_service

    def fail_record_diet(*args, **kwargs):
        raise RuntimeError("embedding unavailable")

    monkeypatch.setattr(diet_service, "record_diet", fail_record_diet)

    response = client.post(
        "/v1/diet/analyze",
        files={"image": ("food.jpg", _JPEG, "image/jpeg")},
        data={"meal_type": "lunch"},
    )

    assert response.status_code == 200, response.text
    entry_id = response.json()["entry_id"]
    db_session.expire_all()
    assert db_session.get(DietEntry, entry_id) is not None


def test_save_analyzed_entry_isolates_rag_failure_without_database(monkeypatch):
    """서비스 경계의 best-effort 처리를 DB 없이도 빠르게 검증한다."""
    from unittest.mock import MagicMock

    from app.schemas.diet import DietAnalysis
    from app.services import diet_service

    db = MagicMock()

    def fail_record_diet(*args, **kwargs):
        raise RuntimeError("embedding unavailable")

    monkeypatch.setattr(diet_service, "record_diet", fail_record_diet)
    entry, is_new = diet_service.save_analyzed_entry(
        db,
        "user-test",
        "lunch",
        DietAnalysis(engine="stub"),
        None,
    )

    assert is_new is True
    assert entry.user_id == "user-test"
    db.commit.assert_called_once()
    db.refresh.assert_called_once_with(entry)
    db.rollback.assert_called_once()


def test_analyze_idempotency_key_dedupes_retry(client):
    key = f"idem-{uuid4().hex}"
    first = client.post(
        "/v1/diet/analyze",
        files={"image": ("food.jpg", _JPEG, "image/jpeg")},
        data={"meal_type": "lunch", "idempotency_key": key},
    )
    assert first.status_code == 200, first.text
    eid = first.json()["entry_id"]

    # 응답 유실 후 재시도를 흉내 — 같은 키로 재요청하면 새 저장 없이 기존 entry 반환.
    second = client.post(
        "/v1/diet/analyze",
        files={"image": ("food.jpg", _JPEG, "image/jpeg")},
        data={"meal_type": "lunch", "idempotency_key": key},
    )
    assert second.status_code == 200, second.text
    assert second.json()["entry_id"] == eid

    today = client.get("/v1/diet/days/today").json()["entries"]
    assert sum(1 for e in today if e["id"] == eid) == 1


def test_analyze_rejects_overlong_idempotency_key(client):
    # DB 컬럼(String(64))을 넘는 키는 DB 도달 전 API 경계(max_length=64)에서
    # 422 로 거부되어야 한다(초과 시 PostgreSQL DataError→500 방지).
    overlong = "x" * 65
    r = client.post(
        "/v1/diet/analyze",
        files={"image": ("food.jpg", _JPEG, "image/jpeg")},
        data={"meal_type": "lunch", "idempotency_key": overlong},
    )
    assert r.status_code == 422, r.text

    # 경계값(정확히 64자)은 정상 처리되어야 한다.
    ok = client.post(
        "/v1/diet/analyze",
        files={"image": ("food.jpg", _JPEG, "image/jpeg")},
        data={"meal_type": "lunch", "idempotency_key": "y" * 64},
    )
    assert ok.status_code == 200, ok.text


def test_analyze_without_key_creates_distinct_entries(client):
    a = client.post(
        "/v1/diet/analyze",
        files={"image": ("food.jpg", _JPEG, "image/jpeg")},
        data={"meal_type": "lunch"},
    ).json()["entry_id"]
    b = client.post(
        "/v1/diet/analyze",
        files={"image": ("food.jpg", _JPEG, "image/jpeg")},
        data={"meal_type": "lunch"},
    ).json()["entry_id"]
    assert a != b


def test_analyze_rejects_unsupported_mime(client):
    r = client.post(
        "/v1/diet/analyze",
        files={"image": ("note.txt", b"hello", "text/plain")},
        data={"meal_type": "lunch"},
    )
    assert r.status_code == 415


def test_analyze_rejects_oversized_upload(client):
    """상한을 넘는 업로드는 413 — 앱의 8MiB 상한은 UX 보호일 뿐이라 API 직접
    호출은 막지 못한다. 서버가 최후 방어선이다(#554)."""
    from app.core.config import get_settings

    limit = get_settings().max_upload_bytes
    r = client.post(
        "/v1/diet/analyze",
        files={"image": ("food.jpg", _JPEG + b"x" * limit, "image/jpeg")},
        data={"meal_type": "lunch"},
    )

    assert r.status_code == 413
    assert "detail" in r.json()


def test_analyze_accepts_upload_under_the_limit(client):
    """상한 이하는 기존과 동일하게 동작한다(413 이 정상 업로드를 잡아먹지 않는다)."""
    r = client.post(
        "/v1/diet/analyze",
        files={"image": ("food.jpg", _JPEG, "image/jpeg")},
        data={"meal_type": "lunch"},
    )

    assert r.status_code == 200


def test_analyze_rejects_empty_file(client):
    r = client.post(
        "/v1/diet/analyze",
        files={"image": ("food.jpg", b"", "image/jpeg")},
        data={"meal_type": "lunch"},
    )
    assert r.status_code == 400


def test_enrich_marks_db_mixed_and_estimate_sources(db_session):
    from app.models.models import FoodNutrient
    from app.schemas.diet import DietAnalysis, RecognizedFood
    from app.services.nutrition.enrich import enrich_analysis

    bibimbap = db_session.scalar(select(FoodNutrient).where(FoodNutrient.name == "비빔밥"))
    assert bibimbap is not None
    bibimbap.carbs_g, bibimbap.protein_g, bibimbap.fat_g = 40.0, 20.0, 8.0
    db_session.commit()

    # amount_g=100 이면 배율 1 — DB 값이 그대로 실린다(환산 로직과 분리해 검증).
    db_only = DietAnalysis(engine="test", foods=[
        RecognizedFood(name="비빔밥", amount_g=100, carbs_g=1.0, protein_g=2.0, fat_g=3.0),
    ])
    enrich_analysis(db_session, db_only)
    assert db_only.foods[0].source == "db"
    assert (db_only.foods[0].carbs_g, db_only.foods[0].protein_g, db_only.foods[0].fat_g) == (
        40.0, 20.0, 8.0,
    )

    bibimbap.protein_g = None
    db_session.commit()
    mixed = DietAnalysis(engine="test", foods=[
        RecognizedFood(name="비빔밥", amount_g=100, carbs_g=1.0, protein_g=2.0, fat_g=3.0),
        RecognizedFood(name="없는음식", amount_g=100, carbs_g=4.0, protein_g=5.0, fat_g=6.0),
    ])
    enrich_analysis(db_session, mixed)
    assert mixed.foods[0].source == "mixed"
    assert mixed.foods[0].protein_g == 2.0
    assert mixed.foods[1].source == "estimate"

    no_recognizer_fallback = DietAnalysis(engine="test", foods=[
        RecognizedFood(name="비빔밥", carbs_g=1.0, protein_g=None, fat_g=3.0),
    ])
    enrich_analysis(db_session, no_recognizer_fallback)
    assert no_recognizer_fallback.foods[0].source == "db"
    assert no_recognizer_fallback.foods[0].protein_g is None

    bibimbap.protein_g = 20.0
    db_session.commit()


def test_delete_entry_removes_from_today(client):
    # diet 테스트는 데모 사용자를 공유하므로(무인증) 전역 합계 대신
    # 이 엔트리 id 의 유무로 검증한다.
    entry_id = client.post(
        "/v1/diet/analyze",
        files={"image": ("food.jpg", _JPEG, "image/jpeg")},
        data={"meal_type": "lunch"},
    ).json()["entry_id"]

    before = client.get("/v1/diet/days/today").json()["entries"]
    assert any(e["id"] == entry_id for e in before)

    d = client.delete(f"/v1/diet/entries/{entry_id}")
    assert d.status_code == 200, d.text
    assert d.json()["status"] == "deleted"

    after = client.get("/v1/diet/days/today").json()["entries"]
    assert all(e["id"] != entry_id for e in after)


def test_delete_entry_404_when_missing(client):
    r = client.delete("/v1/diet/entries/diet-nope")
    assert r.status_code == 404


def test_update_entry_changes_meal_type(client):
    entry_id = client.post(
        "/v1/diet/analyze",
        files={"image": ("food.jpg", _JPEG, "image/jpeg")},
        data={"meal_type": "lunch"},
    ).json()["entry_id"]

    r = client.put(
        f"/v1/diet/entries/{entry_id}",
        json={"meal_type": "dinner", "time_label": "19:30"},
    )
    assert r.status_code == 200, r.text
    assert r.json()["meal_type"] == "dinner"
    assert r.json()["time_label"] == "19:30"

    # 공유 데모 사용자라 전역 합계 대신 id 로 확인.
    today = client.get("/v1/diet/days/today").json()["entries"]
    mine = next(e for e in today if e["id"] == entry_id)
    assert mine["meal_type"] == "dinner"


def test_update_entry_changes_nutrition_and_today_totals(client, db_session):
    from app.services.diet_service import today_str as _today_str
    from app.db.init_db import DEMO_USER_ID
    from app.models.models import DietEntry

    db_session.execute(
        delete(DietEntry).where(
            DietEntry.user_id == DEMO_USER_ID,
            DietEntry.date == _today_str(),
        )
    )
    db_session.commit()
    entry_id = client.post(
        "/v1/diet/analyze",
        files={"image": ("food.jpg", _JPEG, "image/jpeg")},
        data={"meal_type": "lunch"},
    ).json()["entry_id"]

    # 음식 목록을 보내지 않은 부분 수정은 음식을 건드리지 않는다 — 끼니 합계만
    # 바뀐다(#1892). 음식별 값과 합계가 갈리는 목록을 일부러 심어 확인한다.
    row = db_session.get(DietEntry, entry_id)
    assert row is not None
    row.foods_json = json.dumps([{
        "name": "legacy food", "calories": 100, "sodium_mg": 10, "sugar_g": 2,
        "source": "estimate", "carbs_g": 99, "protein_g": 99, "fat_g": 99,
    }])
    db_session.commit()

    r = client.put(
        f"/v1/diet/entries/{entry_id}",
        json={
            "total_calories": 333,
            "carbs_g": 25.0,
            "protein_g": 12.5,
            "fat_g": 5.0,
            "sodium_mg": 444,
            "sugar_g": 7,
        },
    )
    assert r.status_code == 200, r.text
    assert r.json()["total_calories"] == 333
    assert r.json()["sodium_mg"] == 444
    assert r.json()["sugar_g"] == 7
    assert (r.json()["carbs_g"], r.json()["protein_g"], r.json()["fat_g"]) == (
        25.0, 12.5, 5.0,
    )
    assert r.json()["foods"][0]["carbs_g"] == 99, "음식을 보내지 않았으니 그대로다"
    assert r.json()["foods"][0]["name"] == "legacy food"

    today = client.get("/v1/diet/days/today").json()
    assert today["total_calories"] == 333
    assert today["total_sodium_mg"] == 444
    assert today["total_sugar_g"] == 7
    assert today["macros"] == {
        "carbs_g": 25.0,
        "protein_g": 12.5,
        "fat_g": 5.0,
        "carbs_pct": 51,
        "protein_pct": 26,
        "fat_pct": 23,
    }

    zeroed = client.put(
        f"/v1/diet/entries/{entry_id}",
        json={"carbs_g": 0, "protein_g": 0, "fat_g": 0},
    )
    assert zeroed.status_code == 200
    assert client.get("/v1/diet/days/today").json()["macros"] == {
        "carbs_g": 0.0,
        "protein_g": 0.0,
        "fat_g": 0.0,
        "carbs_pct": 0,
        "protein_pct": 0,
        "fat_pct": 0,
    }


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("total_calories", -1),
        ("sodium_mg", -1),
        ("sugar_g", -1),
        ("carbs_g", -0.1),
        ("protein_g", -0.1),
        ("fat_g", -0.1),
    ],
)
def test_update_entry_rejects_negative_nutrition(client, field, value):
    entry_id = client.post(
        "/v1/diet/analyze",
        files={"image": ("food.jpg", _JPEG, "image/jpeg")},
        data={"meal_type": "lunch"},
    ).json()["entry_id"]

    r = client.put(f"/v1/diet/entries/{entry_id}", json={field: value})
    assert r.status_code == 422


def _analyzed_entry_id(client) -> str:
    return client.post(
        "/v1/diet/analyze",
        files={"image": ("food.jpg", _JPEG, "image/jpeg")},
        data={"meal_type": "lunch"},
    ).json()["entry_id"]


# 회원이 음식마다 고친 영양이 실제로 남는가 (#1892). 이 검사들이 없던 동안
# `foods` 는 스키마에 자리가 없어 통째로 버려졌고, 응답은 200 이라 앱은 저장에
# 성공한 줄 알았다. 화면에서 고친 값이 보인 것은 앱이 응답을 로컬에서 덮어썼기
# 때문이고, 앱을 다시 켜면 옛 음식이 돌아왔다.
_EDITED_FOODS = [
    {
        "name": "회원이 고친 현미밥", "calories": 220, "sodium_mg": 3,
        "sugar_g": 0.5, "carbs_g": 46.0, "protein_g": 5.0, "fat_g": 1.8,
    },
    {
        "name": "회원이 고친 닭가슴살", "calories": 165, "sodium_mg": 74,
        "sugar_g": 0.0, "carbs_g": 0.0, "protein_g": 31.0, "fat_g": 3.6,
    },
]


def test_update_entry_stores_edited_foods(client):
    """보낸 음식 목록이 저장되고, 다시 읽어도 그대로다."""
    entry_id = _analyzed_entry_id(client)

    r = client.put(f"/v1/diet/entries/{entry_id}", json={"foods": _EDITED_FOODS})
    assert r.status_code == 200, r.text
    assert [f["name"] for f in r.json()["foods"]] == [
        "회원이 고친 현미밥", "회원이 고친 닭가슴살",
    ]

    # 다시 읽어도 살아 있어야 한다 — 응답만 맞고 저장이 안 되면 앱을 다시 켤 때
    # 옛 음식이 돌아온다.
    entry = next(
        e for e in client.get("/v1/diet/days/today").json()["entries"]
        if e["id"] == entry_id
    )
    assert [f["name"] for f in entry["foods"]] == [
        "회원이 고친 현미밥", "회원이 고친 닭가슴살",
    ]


def test_update_entry_keeps_per_food_macros(client):
    """음식별 탄단지가 저장되고 다시 읽힌다 — 수정 화면이 고칠 값이다(#1856)."""
    entry_id = _analyzed_entry_id(client)

    client.put(f"/v1/diet/entries/{entry_id}", json={"foods": _EDITED_FOODS})

    entry = next(
        e for e in client.get("/v1/diet/days/today").json()["entries"]
        if e["id"] == entry_id
    )
    first = entry["foods"][0]
    assert (first["carbs_g"], first["protein_g"], first["fat_g"]) == (46.0, 5.0, 1.8)
    assert (first["calories"], first["sodium_mg"], first["sugar_g"]) == (220, 3, 0.5)


def test_update_entry_recomputes_totals_from_foods(client):
    """끼니 합계는 음식에서 다시 낸다 — 합계와 내역이 갈리면 안 된다."""
    entry_id = _analyzed_entry_id(client)

    body = client.put(
        f"/v1/diet/entries/{entry_id}", json={"foods": _EDITED_FOODS}
    ).json()

    assert body["total_calories"] == 385
    assert body["carbs_g"] == pytest.approx(46.0)
    assert body["protein_g"] == pytest.approx(36.0)
    assert body["fat_g"] == pytest.approx(5.4)
    assert body["sodium_mg"] == 77
    assert body["sugar_g"] == pytest.approx(0.5)


def test_update_entry_prefers_foods_over_sent_totals(client):
    """음식과 합계가 함께 오면 음식이 이긴다 — 원본은 하나여야 한다."""
    entry_id = _analyzed_entry_id(client)

    body = client.put(
        f"/v1/diet/entries/{entry_id}",
        json={"foods": _EDITED_FOODS, "total_calories": 1, "sodium_mg": 1, "sugar_g": 0.0},
    ).json()

    assert body["total_calories"] == 385, "보낸 합계가 아니라 음식에서 낸 값이다"
    assert body["sodium_mg"] == 77


def test_update_entry_rejects_sugar_over_carbs_in_sent_foods(client):
    """어긋난 음식이 오면 저장된 옛 합계로 통과시키지 않는다(#1863)."""
    entry_id = _analyzed_entry_id(client)

    r = client.put(
        f"/v1/diet/entries/{entry_id}",
        json={"foods": [dict(_EDITED_FOODS[0], carbs_g=2.0, sugar_g=9.0)]},
    )
    assert r.status_code == 422
    assert "당류" in r.json()["detail"]


def test_update_entry_without_foods_keeps_stored_foods(client):
    """음식을 보내지 않은 부분 수정은 음식 목록을 건드리지 않는다."""
    entry_id = _analyzed_entry_id(client)
    before = client.put(
        f"/v1/diet/entries/{entry_id}", json={"foods": _EDITED_FOODS}
    ).json()["foods"]

    after = client.put(
        f"/v1/diet/entries/{entry_id}", json={"meal_type": "dinner"}
    ).json()

    assert after["meal_type"] == "dinner"
    assert after["foods"] == before


def test_update_entry_rejects_empty_foods(client):
    """음식이 하나도 없는 끼니는 수정이 아니라 삭제다 — 영양이 소리 없이 0 이 되면 안 된다."""
    entry_id = _analyzed_entry_id(client)

    assert client.put(
        f"/v1/diet/entries/{entry_id}", json={"foods": []}
    ).status_code == 422


def test_update_entry_rejects_sugar_over_carbs(client):
    """당류는 탄수화물의 일부라 그보다 클 수 없다. (#1863)"""
    entry_id = _analyzed_entry_id(client)

    r = client.put(
        f"/v1/diet/entries/{entry_id}",
        json={"carbs_g": 10.0, "sugar_g": 12.0},
    )
    assert r.status_code == 422
    assert "당류" in r.json()["detail"]


def test_update_entry_allows_sugar_equal_to_carbs(client):
    """전부 당인 음식이 있으므로 같은 값은 통과한다."""
    entry_id = _analyzed_entry_id(client)

    r = client.put(
        f"/v1/diet/entries/{entry_id}",
        json={"carbs_g": 10.0, "sugar_g": 10.0},
    )
    assert r.status_code == 200
    assert r.json()["sugar_g"] == 10.0


def test_update_entry_compares_sugar_against_stored_carbs(client):
    """부분 수정이라 한쪽만 와도 저장된 값과 견준다."""
    entry_id = _analyzed_entry_id(client)
    assert (
        client.put(
            f"/v1/diet/entries/{entry_id}",
            json={"carbs_g": 10.0, "sugar_g": 0.0},
        ).status_code
        == 200
    )

    # 당류만 보내도 저장해 둔 탄수화물 10g 과 견줘 막는다.
    r = client.put(f"/v1/diet/entries/{entry_id}", json={"sugar_g": 12.0})
    assert r.status_code == 422

    # 탄수화물 안쪽이면 통과한다.
    r = client.put(f"/v1/diet/entries/{entry_id}", json={"sugar_g": 4.0})
    assert r.status_code == 200
    assert r.json()["sugar_g"] == 4.0


def test_update_entry_allows_sugar_when_carbs_is_zero(client):
    """탄수화물 0 은 "없다" 가 아니라 "아직 안 적혔다" 로 본다. (#1863)

    컬럼이 NOT NULL 기본 0 이라 둘을 구분할 수 없다. 여기서 막으면 탄수화물을
    건드리지 않는 정상적인 부분 수정까지 거절된다.
    """
    entry_id = _analyzed_entry_id(client)
    assert (
        client.put(
            f"/v1/diet/entries/{entry_id}",
            json={"carbs_g": 0, "protein_g": 0, "fat_g": 0},
        ).status_code
        == 200
    )

    r = client.put(f"/v1/diet/entries/{entry_id}", json={"sugar_g": 5.0})
    assert r.status_code == 200
    assert r.json()["sugar_g"] == 5.0


def test_analyze_is_not_blocked_by_inconsistent_nutrition(client):
    """인식 엔진 출력에는 걸지 않는다 — 막으면 사진 분석 자체가 실패한다."""
    r = client.post(
        "/v1/diet/analyze",
        files={"image": ("food.jpg", _JPEG, "image/jpeg")},
        data={"meal_type": "lunch"},
    )
    assert r.status_code == 200


def test_update_entry_moves_record_to_the_chosen_day(client, db_session):
    """지난 식사의 사진을 오늘 올려도 실제로 먹은 날에 남는다. (#1241)"""
    from datetime import timedelta

    from app.core import clock
    from app.models.models import DietEntry

    entry_id = client.post(
        "/v1/diet/analyze",
        files={"image": ("food.jpg", _JPEG, "image/jpeg")},
        data={"meal_type": "lunch"},
    ).json()["entry_id"]
    assert any(
        e["id"] == entry_id
        for e in client.get("/v1/diet/days/today").json()["entries"]
    )

    two_days_ago = (clock.today() - timedelta(days=2)).isoformat()
    r = client.put(f"/v1/diet/entries/{entry_id}", json={"date": two_days_ago})
    assert r.status_code == 200, r.text

    # 오늘에서 빠지고 고른 날짜에서 보인다 — 한쪽만 옮기면 하루 합계가 두 날에
    # 겹친다.
    assert all(
        e["id"] != entry_id
        for e in client.get("/v1/diet/days/today").json()["entries"]
    )
    moved = client.get(f"/v1/diet/days/{two_days_ago}").json()["entries"]
    assert any(e["id"] == entry_id for e in moved)

    db_session.expire_all()
    assert db_session.get(DietEntry, entry_id).date == two_days_ago


def test_update_entry_rejects_a_day_that_has_not_happened(client):
    """먹지 않은 식사는 기록할 수 없다 — 앞날은 거절한다. (#1241)"""
    from datetime import timedelta

    from app.core import clock

    entry_id = client.post(
        "/v1/diet/analyze",
        files={"image": ("food.jpg", _JPEG, "image/jpeg")},
        data={"meal_type": "lunch"},
    ).json()["entry_id"]

    tomorrow = (clock.today() + timedelta(days=1)).isoformat()
    assert client.put(
        f"/v1/diet/entries/{entry_id}", json={"date": tomorrow}
    ).status_code == 422
    # 오늘은 그대로 받는다 — 경계가 하루 어긋나 있지 않은지 함께 본다.
    assert client.put(
        f"/v1/diet/entries/{entry_id}", json={"date": clock.today().isoformat()}
    ).status_code == 200


@pytest.mark.parametrize("value", ["2026-13-01", "2026-08-32", "20260801", "오늘", ""])
def test_update_entry_rejects_malformed_date(client, value):
    entry_id = client.post(
        "/v1/diet/analyze",
        files={"image": ("food.jpg", _JPEG, "image/jpeg")},
        data={"meal_type": "lunch"},
    ).json()["entry_id"]

    r = client.put(f"/v1/diet/entries/{entry_id}", json={"date": value})
    assert r.status_code == 422


def test_update_entry_hides_other_users_record(client, db_session):
    from app.services.diet_service import today_str as _today_str
    from app.models.models import DietEntry, User

    suffix = uuid.uuid4().hex[:12]
    other_user_id = f"diet-owner-{suffix}"
    other_entry_id = f"diet-other-{suffix}"
    db_session.add(User(
        id=other_user_id,
        email=f"{other_user_id}@example.com",
        name="Other User",
        hashed_password="",
    ))
    db_session.flush()
    db_session.add(DietEntry(
        id=other_entry_id,
        user_id=other_user_id,
        date=_today_str(),
        meal_type="lunch",
    ))
    db_session.commit()

    r = client.put(f"/v1/diet/entries/{other_entry_id}", json={"carbs_g": 10})
    assert r.status_code == 404


def test_update_entry_404_when_missing(client):
    r = client.put("/v1/diet/entries/diet-nope", json={"meal_type": "dinner"})
    assert r.status_code == 404


def test_update_entry_keeps_fractional_sugar(client, db_session):
    """#296 회귀: 항목 당류가 Integer 라 소수가 절삭·거부되던 문제.

    프론트는 항목 당류를 double 로 다루고 음식 단위(food_nutrients.sugar_g)도
    이미 Float 이었는데, 항목 단위만 Integer 로 남아 `sugar_g=8.5` 가 실서버
    경로에서 깨졌다.
    """
    from app.services.diet_service import today_str as _today_str
    from app.db.init_db import DEMO_USER_ID
    from app.models.models import DietEntry

    db_session.execute(
        delete(DietEntry).where(
            DietEntry.user_id == DEMO_USER_ID,
            DietEntry.date == _today_str(),
        )
    )
    db_session.commit()
    entry_id = client.post(
        "/v1/diet/analyze",
        files={"image": ("food.jpg", _JPEG, "image/jpeg")},
        data={"meal_type": "lunch"},
    ).json()["entry_id"]

    r = client.put(f"/v1/diet/entries/{entry_id}", json={"sugar_g": 8.5})
    assert r.status_code == 200, r.text
    # 예전엔 Pydantic int 검증에서 422 로 거부되거나 8 로 절삭됐다.
    assert r.json()["sugar_g"] == 8.5

    # DB 컬럼도 소수를 보존해야 한다(왕복 후 재조회).
    db_session.expire_all()
    assert db_session.get(DietEntry, entry_id).sugar_g == 8.5
    assert client.get("/v1/diet/days/today").json()["total_sugar_g"] == 8.5


def test_fractional_sugar_sums_without_truncation(client, db_session):
    """#296 회귀: 6.3 + 8.5 가 14 나 15 가 아니라 14.8 이어야 한다."""
    from app.services.diet_service import today_str as _today_str
    from app.db.init_db import DEMO_USER_ID
    from app.models.models import DietEntry

    db_session.execute(
        delete(DietEntry).where(
            DietEntry.user_id == DEMO_USER_ID,
            DietEntry.date == _today_str(),
        )
    )
    db_session.commit()
    for meal, sugar in (("lunch", 6.3), ("dinner", 8.5)):
        entry_id = client.post(
            "/v1/diet/analyze",
            files={"image": ("food.jpg", _JPEG, "image/jpeg")},
            data={"meal_type": meal},
        ).json()["entry_id"]
        assert client.put(
            f"/v1/diet/entries/{entry_id}", json={"sugar_g": sugar}
        ).status_code == 200

    assert client.get("/v1/diet/days/today").json()["total_sugar_g"] == pytest.approx(14.8)

    # 홈 지표 카드도 같은 소수를 봐야 한다(반올림 18 로 굳으면 회귀).
    summary = client.get("/v1/dashboard/summary").json()
    sugar = next(i for i in summary["indicators"] if i["label"] == "당류")
    assert sugar["current"] == pytest.approx(14.8)


def test_entry_update_rejects_non_finite_sugar():
    """float 로 넓힌 뒤 NaN/inf 가 새어 들어오지 않는지."""
    from app.schemas.diet_api import DietEntryUpdate

    for value in (math.nan, math.inf, -math.inf):
        with pytest.raises(ValidationError):
            DietEntryUpdate(sugar_g=value)


def test_diet_advice_changes_with_the_period(client, db_session):
    """기간을 바꾸면 조언도 달라진다 — 그래프만 갈아 끼우면 안 된다. (#1017)"""
    from datetime import timedelta

    from app.core import clock
    from app.models import models

    # 시드 회원(이지수)에게 기록을 더하면, 그 회원의 하루 합계를 세어 두는
    # 트레이너 로스터 테스트가 함께 어긋난다. 이 테스트만 쓰는 회원을 만든다.
    email = f"advice-week-{uuid4().hex[:8]}@oncare.com"
    created = client.post(
        "/v1/auth/register",
        json={"email": email, "password": "oncare123", "name": "조언"},
    )
    assert created.status_code in (200, 201), created.text
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "oncare123"}
    ).json()["access_token"]
    member_id = client.get("/v1/users/me", headers=_h(token)).json()["id"]

    # 이번 주에 나트륨을 사흘 넘긴다 — 오늘 하루만 보는 조언과 갈려야 한다.
    today = clock.today()
    # 월요일부터 오늘까지 채운다 — `사흘 전` 처럼 고정된 폭으로 잡으면 주 초에
    # 돌릴 때 지난주로 넘어가, `이번 주` 조언이 세지 않는 날이 생긴다.
    monday = today - timedelta(days=today.weekday())
    days = [monday + timedelta(days=i) for i in range((today - monday).days + 1)]
    for back, day in enumerate(days):
        db_session.add(
            models.DietEntry(
                id=f"diet-advice-{member_id}-{back}",
                user_id=member_id,
                date=day.isoformat(),
                meal_type="lunch",
                time_label="12:00",
                foods_json="[]",
                total_calories=900,
                sodium_mg=2600,
                sugar_g=10,
                carbs_g=100,
                protein_g=40,
                fat_g=20,
            )
        )
    db_session.commit()

    week = client.get("/v1/diet/advice?period=week", headers=_h(token))
    assert week.status_code == 200, week.text
    assert week.json()["days_logged"] == len(days)
    assert "이번 주" in week.json()["message"]

    day_view = client.get("/v1/diet/advice?period=today", headers=_h(token))
    assert day_view.status_code == 200, day_view.text
    assert day_view.json()["message"] != week.json()["message"]

    every = client.get("/v1/diet/advice?period=all", headers=_h(token))
    assert every.status_code == 200, every.text
    # 전체는 12주를 본다 — 이번 주와 시작일이 다르다.
    assert every.json()["from_date"] < week.json()["from_date"]


def test_diet_advice_says_nothing_when_there_is_nothing(client):
    """기록이 없으면 없다고 말한다 — 없는 기록으로 조언을 지어내지 않는다. (#1017)"""
    email = f"advice-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register",
        json={"email": email, "password": "oncare123", "name": "조언"},
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "oncare123"}
    ).json()["access_token"]

    for period in ("today", "week", "all"):
        response = client.get(f"/v1/diet/advice?period={period}", headers=_h(token))
        assert response.status_code == 200, response.text
        assert response.json()["days_logged"] == 0
        assert response.json()["message"]
