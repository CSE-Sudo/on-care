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


def test_gemini_asks_for_and_reads_the_amount_in_the_photo():
    """기본 인식기도 사진에 담긴 양을 묻고 읽는다 (#2090).

    묻지 않으면 공공 DB 에 1회 섭취량이 알려진 음식만 양이 채워지고 나머지는 비어,
    같은 끼니 안에서 어떤 음식은 양이 보이고 어떤 음식은 안 보인다. 0·음수·비유한값은
    `litellm_vision` 과 같이 "모름" 으로 눕힌다 — `gt=0` 검증에 걸려 응답 전체가
    깨지면 안 된다.
    """
    from app.services.recognizer.gemini import _PROMPT, GeminiVisionRecognizer

    assert "amount_g" in _PROMPT

    raw = json.dumps({
        "foods": [
            {"name": "비빔밥", "amount_g": 450, "calories": 600},
            {"name": "김치", "amount_g": "40", "calories": 15},
            {"name": "모름", "amount_g": 0},
            {"name": "음수", "amount_g": -5},
            {"name": "비유한", "amount_g": "NaN"},
            {"name": "빠짐"},
        ],
    })

    analysis = GeminiVisionRecognizer.__new__(GeminiVisionRecognizer)._parse(raw, 10)

    assert [f.amount_g for f in analysis.foods] == [450.0, 40.0, None, None, None, None]


def test_stub_recognizer_gives_every_food_an_amount():
    """키가 없을 때 쓰는 스텁도 음식마다 양을 준다 — 시드의 1회 섭취량 (#2090)."""
    import asyncio

    from app.services.recognizer.stub import StubFoodRecognizer

    analysis = asyncio.run(StubFoodRecognizer().recognize(b"", "image/jpeg"))

    assert [f.amount_g for f in analysis.foods] == [110, 90, 50]


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


def test_analyze_stores_the_amount_each_food_was_scaled_from(client, db_session):
    """영양을 낸 **양**을 함께 남긴다 — 앱이 그 값으로 비례 환산한다(#1876).

    양을 버리면 "이 숫자가 무엇을 재고 나온 값인가" 가 사라져, 회원이 양을
    고쳐도 영양을 다시 셀 근거가 없다. 스텁 인식기가 주는 양(시드의 1회 섭취량과
    같은 값, #2090)으로 보정이 환산하고, **그 값이 실제 기준**이라 그대로 실린다.
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

    body = client.post(
        "/v1/diet/analyze",
        files={"image": ("food.jpg", _JPEG, "image/jpeg")},
        data={"meal_type": "lunch"},
    ).json()
    foods = body["analysis"]["foods"]
    # 시드에 적힌 1회 섭취량(요거트 110g · 과일 90g · 그래놀라 50g).
    assert [f["amount_g"] for f in foods] == [110, 90, 50]
    # 영양은 그 양을 재고 나온 값이다 — 100g 기준값 × (양 / 100).
    assert foods[0]["calories"] == 135
    assert foods[2]["calories"] == 205

    stored_foods = json.loads(db_session.get(DietEntry, body["entry_id"]).foods_json)
    assert [f["amount_g"] for f in stored_foods] == [110, 90, 50], (
        "응답에만 있고 저장되지 않으면 다음에 열었을 때 기준이 사라진다"
    )

    today_foods = [
        food
        for entry in client.get("/v1/diet/days/today").json()["entries"]
        for food in entry["foods"]
    ]
    assert [f["amount_g"] for f in today_foods] == [110, 90, 50]


def test_foods_saved_before_amount_existed_still_load(client, db_session):
    """이 필드 이전 기록은 양이 없다 — 그래도 그대로 열려야 한다(#1876)."""
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

    row = db_session.get(DietEntry, entry_id)
    row.foods_json = json.dumps([
        {"name": "옛 기록", "calories": 100, "sodium_mg": 10, "sugar_g": 2,
         "source": "estimate"},
    ])
    db_session.commit()

    entry = client.get("/v1/diet/days/today").json()["entries"][0]
    assert entry["foods"][0]["name"] == "옛 기록"
    # 없는 값을 0 으로 지어내지 않는다 — 앱이 칸을 비워 두고 회원이 적는 값을
    # 기준으로 삼는다. 0 을 내려보내면 "0g 먹었다" 는 기록이 되어 버린다.
    assert entry["foods"][0].get("amount_g") is None

    # 이 기록을 수정하는 길도 막히지 않는다.
    r = client.put(f"/v1/diet/entries/{entry_id}", json={"total_calories": 100})
    assert r.status_code == 200, r.text
    assert r.json()["foods"][0].get("amount_g") is None


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


def test_food_nutrition_lookup_finds_a_known_name(client):
    """이름으로 공공 DB 값을 찾는다 — 수정 화면이 제안에 쓴다. (#1896)

    양을 주지 않으면 DB 가 아는 1회 섭취량으로 환산한다(보정과 같은 폴백).
    """
    r = client.post("/v1/diet/nutrition", json={"name": "짜장면"})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["matched_name"] == "짜장면"
    assert body["source"] == "db"
    # 시드의 1회 섭취량(가정식 분석 `자장면` 600g) × 100g 당 값(외식 분석 123kcal·368mg).
    assert body["amount_g"] == 600
    assert body["calories"] == 738
    assert body["sodium_mg"] == 2208


def test_food_nutrition_lookup_scales_to_the_amount_it_is_given(client):
    """양을 주면 그 양으로 환산한다 — 지금 먹은 양의 값을 제안해야 한다."""
    whole = client.post("/v1/diet/nutrition", json={"name": "짜장면"}).json()
    half = client.post(
        "/v1/diet/nutrition", json={"name": "짜장면", "amount_g": whole["amount_g"] / 2}
    ).json()
    assert half["amount_g"] == whole["amount_g"] / 2
    assert half["calories"] == pytest.approx(whole["calories"] / 2, abs=2)
    assert half["sodium_mg"] == pytest.approx(whole["sodium_mg"] / 2, abs=2)


def test_food_nutrition_lookup_says_nothing_when_it_cannot_be_sure(client):
    """못 찾으면 조용하다 — 앱은 그때 아무것도 제안하지 않는다.

    확정할 수 없는 숫자를 "공공 DB 근거" 로 내주는 것이 여기서 제일 나쁘다.
    """
    r = client.post("/v1/diet/nutrition", json={"name": "듣도보도못한음식"})
    assert r.status_code == 200, r.text
    assert r.json()["matched_name"] is None
    assert r.json()["calories"] is None


@pytest.mark.parametrize("name", ["", "   "])
def test_food_nutrition_lookup_rejects_an_empty_name(client, name):
    """이름 없이 확정된 숫자를 내주지 않는다(운동 칼로리와 같은 규약, #1312)."""
    r = client.post("/v1/diet/nutrition", json={"name": name})
    assert r.status_code == 400


def test_food_nutrition_lookup_matches_what_analysis_would_have_said(client, db_session):
    """이름 조회와 분석 보정이 **같은 값**을 말한다. (#1896)

    계산이 두 곳이면 같은 음식인데 화면 어디서 왔느냐에 따라 숫자가 갈린다.
    """
    from app.schemas.diet import DietAnalysis, RecognizedFood
    from app.services.nutrition.enrich import enrich_analysis

    looked_up = client.post(
        "/v1/diet/nutrition", json={"name": "비빔밥", "amount_g": 400}
    ).json()

    analysis = DietAnalysis(
        engine="test", foods=[RecognizedFood(name="비빔밥", amount_g=400)]
    )
    enrich_analysis(db_session, analysis)
    from_analysis = analysis.foods[0]

    assert looked_up["calories"] == from_analysis.calories
    assert looked_up["sodium_mg"] == from_analysis.sodium_mg
    assert looked_up["sugar_g"] == pytest.approx(from_analysis.sugar_g)
    assert looked_up["amount_g"] == from_analysis.amount_g
    assert looked_up["source"] == from_analysis.source


@pytest.mark.parametrize(
    ("name", "matched", "match"),
    [
        ("비빔밥", "비빔밥", "exact"),
        # 별칭은 같은 음식이다.
        ("흰밥", "공기밥", "exact"),
        # 이름 끝말로만 붙은 것은 비슷한 음식이다.
        ("야채비빔밥", "비빔밥", "similar"),
    ],
)
def test_food_nutrition_lookup_says_whether_it_is_the_same_food(
    client, name, matched, match
):
    """같은 음식인지 비슷한 음식인지 함께 말한다. (#2107)

    수정 화면은 같은 음식이면 곧바로 채우고, 비슷한 음식이면 제안만 한다.
    """
    body = client.post("/v1/diet/nutrition", json={"name": name}).json()
    assert body["matched_name"] == matched
    assert body["match"] == match


def test_food_nutrition_lookup_has_no_match_kind_when_nothing_was_found(client):
    body = client.post("/v1/diet/nutrition", json={"name": "듣도보도못한음식"}).json()
    assert body["match"] is None


def test_update_entry_saves_edited_foods(client, db_session):
    """고친 음식이 실제로 남는다 (#1895).

    이 경로가 없을 때는 `foods` 가 스키마에 없어 pydantic 이 말없이 버렸고,
    200 이 돌아오니 앱은 저장된 줄 알았다. 5분짜리 로컬 캐시가 만료되면
    분석 당시 값으로 되돌아갔다.
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

    r = client.put(
        f"/v1/diet/entries/{entry_id}",
        json={
            "foods": [
                {"name": "현미밥", "amount_g": 210, "calories": 310,
                 "sodium_mg": 3, "sugar_g": 0.5, "carbs_g": 68,
                 "protein_g": 6, "fat_g": 1.5},
                {"name": "김", "calories": 5, "sodium_mg": 40, "sugar_g": 0},
            ],
        },
    )
    assert r.status_code == 200, r.text
    foods = r.json()["foods"]
    assert [f["name"] for f in foods] == ["현미밥", "김"]
    assert foods[0]["amount_g"] == 210
    # 양을 모르는 음식은 null 로 남는다 — 0 으로 지어내지 않는다(#1876).
    assert foods[1]["amount_g"] is None

    # 응답에만 있고 DB 에 없으면 다음 조회에서 되돌아간다.
    stored = json.loads(db_session.get(DietEntry, entry_id).foods_json)
    assert [f["name"] for f in stored] == ["현미밥", "김"]
    assert stored[0]["amount_g"] == 210

    today_foods = client.get("/v1/diet/days/today").json()["entries"][0]["foods"]
    assert [f["name"] for f in today_foods] == ["현미밥", "김"]
    assert today_foods[0]["amount_g"] == 210


def test_update_entry_recomputes_totals_from_the_foods_it_was_given(client, db_session):
    """끼니 합계는 앱이 보낸 값이 아니라 **서버가 foods 에서 다시 센 값**이다.

    운동이 클라이언트의 `calories` 를 버리고 다시 계산하는 것과 같은 규칙(#1312).
    앱이 한 필드를 빠뜨려도(실제로 탄단지가 그랬다) 그 값만 옛 숫자에 머물지
    않는다. (#1895)
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

    r = client.put(
        f"/v1/diet/entries/{entry_id}",
        json={
            "foods": [
                {"name": "현미밥", "calories": 310, "sodium_mg": 3, "sugar_g": 0.5,
                 "carbs_g": 68, "protein_g": 6, "fat_g": 1.5},
                {"name": "닭가슴살", "calories": 165, "sodium_mg": 70, "sugar_g": 0,
                 "carbs_g": 0, "protein_g": 31, "fat_g": 3.6},
            ],
            # 앱이 틀린 합계를 보내도 서버가 쓰지 않는다.
            "total_calories": 9999,
            "sodium_mg": 9999,
            "sugar_g": 99.9,
        },
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["total_calories"] == 475
    assert body["sodium_mg"] == 73
    assert body["sugar_g"] == pytest.approx(0.5)
    # 앱이 아예 보내지도 않는 값들 — 그래서 옛날에는 수정해도 옛 숫자에 머물렀다.
    assert body["carbs_g"] == pytest.approx(68.0)
    assert body["protein_g"] == pytest.approx(37.0)
    assert body["fat_g"] == pytest.approx(5.1)

    row = db_session.get(DietEntry, entry_id)
    db_session.refresh(row)
    assert row.total_calories == 475
    assert row.protein_g == pytest.approx(37.0)


def test_update_entry_without_foods_still_sets_meal_values(client, db_session):
    """음식을 건드리지 않는 수정은 지금까지대로 끼니 값을 직접 반영한다(#495)."""
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
    before = json.loads(db_session.get(DietEntry, entry_id).foods_json)

    r = client.put(
        f"/v1/diet/entries/{entry_id}",
        json={"total_calories": 333, "sodium_mg": 444},
    )
    assert r.status_code == 200, r.text
    assert r.json()["total_calories"] == 333
    assert r.json()["sodium_mg"] == 444
    # 음식 목록은 그대로다 — 합계만 정정한 수정이다.
    assert json.loads(db_session.get(DietEntry, entry_id).foods_json) == before


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

    # 탄수화물을 0 으로 실어 보내므로 당류도 함께 비운다 — 보낸 0 은 적은
    # 값이라, 당류 7 을 남겨 두면 어긋난 요청이 된다(#1893).
    zeroed = client.put(
        f"/v1/diet/entries/{entry_id}",
        json={"carbs_g": 0, "protein_g": 0, "fat_g": 0, "sugar_g": 0},
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


def _stored_foods(client, entry_id: str) -> list[dict]:
    return next(
        e for e in client.get("/v1/diet/days/today").json()["entries"]
        if e["id"] == entry_id
    )["foods"]


def test_update_entry_keeps_the_source_each_food_was_sent_with(client):
    """음식마다 보낸 출처가 그대로 남는다. (#2105)

    예전에는 수정 저장 한 번에 모든 음식이 `estimate` 가 됐다 — 앱이 출처를 보내지
    않았고, 서버가 빠진 값을 인식기 기본값으로 채웠다. 손대지 않은 음식은 원래
    출처를, 회원이 고친 음식은 `member` 를 싣는다.
    """
    entry_id = _analyzed_entry_id(client)
    foods = _stored_foods(client, entry_id)
    assert all(f["source"] == "db" for f in foods)

    edited = [dict(f) for f in foods]
    # 둘째 음식은 회원이 나트륨을 고쳤다.
    edited[1]["sodium_mg"] = edited[1]["sodium_mg"] + 100
    edited[1]["source"] = "member"
    r = client.put(f"/v1/diet/entries/{entry_id}", json={"foods": edited})
    assert r.status_code == 200, r.text

    expected = ["db", "member"] + ["db"] * (len(foods) - 2)
    assert [f["source"] for f in r.json()["foods"]] == expected
    assert [f["source"] for f in _stored_foods(client, entry_id)] == expected


def test_update_entry_food_without_a_source_is_the_members(client):
    """출처가 빠진 음식은 `member` 다 — 수정 경로로 들어온 숫자는 인식기 추정이 아니다."""
    entry_id = _analyzed_entry_id(client)

    client.put(f"/v1/diet/entries/{entry_id}", json={"foods": _EDITED_FOODS})

    assert [f["source"] for f in _stored_foods(client, entry_id)] == [
        "member", "member",
    ]


@pytest.mark.parametrize("source", ["user", "", "DB"])
def test_update_entry_rejects_an_unknown_food_source(client, source):
    """출처는 네 값뿐이다 — 모르는 값을 저장하면 읽는 쪽이 제각각 해석한다."""
    entry_id = _analyzed_entry_id(client)
    food = dict(_EDITED_FOODS[0], source=source)

    r = client.put(f"/v1/diet/entries/{entry_id}", json={"foods": [food]})

    assert r.status_code == 422


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


def _entry_with_carbs(client, carbs: float, sugar: float = 0.0) -> str:
    """탄수화물이 `carbs` 로 저장된 끼니. 0 이면 인식기가 값을 못 준 옛 기록이다."""
    entry_id = _analyzed_entry_id(client)
    client.put(
        f"/v1/diet/entries/{entry_id}",
        json={"carbs_g": carbs, "protein_g": 0.0, "fat_g": 0.0, "sugar_g": sugar},
    )
    return entry_id


def test_update_entry_checks_sugar_per_food(client):
    """합계가 아니라 음식 하나하나를 견준다(#1893).

    합계로만 보면 탄수화물이 넉넉한 다른 음식이 어긋난 음식을 가려 준다.
    """
    entry_id = _entry_with_carbs(client, 50.0)

    r = client.put(
        f"/v1/diet/entries/{entry_id}",
        json={
            "foods": [
                # 이 음식 하나가 어긋난다 — 당류 9 > 탄수화물 2.
                {"name": "어긋난 음식", "calories": 50, "carbs_g": 2.0, "sugar_g": 9.0},
                # 합계로 보면 탄수화물 82 > 당류 9 라 통과해 버린다.
                {"name": "멀쩡한 음식", "calories": 300, "carbs_g": 80.0, "sugar_g": 0.0},
            ]
        },
    )

    assert r.status_code == 422, r.text
    assert "어긋난 음식" in r.json()["detail"], "어느 줄이 문제인지 말해 줘야 한다"
    assert "1번째" in r.json()["detail"]


def test_update_entry_allows_each_food_within_its_own_carbs(client):
    entry_id = _entry_with_carbs(client, 50.0)

    r = client.put(
        f"/v1/diet/entries/{entry_id}",
        json={
            "foods": [
                {"name": "딸기", "calories": 32, "carbs_g": 8.0, "sugar_g": 5.5},
                # 전부 당인 음식 — 같은 값은 통과한다.
                {"name": "각설탕", "calories": 20, "carbs_g": 5.0, "sugar_g": 5.0},
            ]
        },
    )

    assert r.status_code == 200, r.text
    assert r.json()["sugar_g"] == pytest.approx(10.5)


def test_update_entry_rejects_carbs_cleared_by_the_member(client):
    """회원이 탄수화물을 0 으로 바꿨으면 그 0 은 적은 값이다(#1893)."""
    entry_id = _entry_with_carbs(client, 50.0)

    r = client.put(
        f"/v1/diet/entries/{entry_id}",
        json={
            "foods": [
                {"name": "지운 음식", "calories": 50, "carbs_g": 0.0, "sugar_g": 9.0}
            ]
        },
    )

    assert r.status_code == 422, "탄수화물을 지워 검사를 피할 수 없어야 한다"


def test_update_entry_still_allows_records_that_never_had_carbs(client):
    """탄수화물 없이 저장된 옛 기록은 지금처럼 고칠 수 있다(#1877).

    이걸 막으면 그 기록의 당류를 영영 고칠 수 없다.
    """
    entry_id = _entry_with_carbs(client, 0.0)

    r = client.put(
        f"/v1/diet/entries/{entry_id}",
        json={
            "foods": [
                {"name": "옛 기록 음식", "calories": 50, "carbs_g": 0.0, "sugar_g": 9.0}
            ]
        },
    )

    assert r.status_code == 200, r.text
    assert r.json()["sugar_g"] == pytest.approx(9.0)


def test_update_entry_rejects_zero_carbs_sent_without_foods(client):
    """음식 없이 합계만 고칠 때도 보낸 0 은 적은 값이다."""
    entry_id = _entry_with_carbs(client, 0.0)

    sent = client.put(
        f"/v1/diet/entries/{entry_id}", json={"carbs_g": 0.0, "sugar_g": 9.0}
    )
    assert sent.status_code == 422, "탄수화물 0 을 실어 보냈으면 그 값으로 견준다"

    # 같은 기록이라도 탄수화물을 안 보내면 저장된 0 이라 봐준다(#1877).
    omitted = client.put(f"/v1/diet/entries/{entry_id}", json={"sugar_g": 9.0})
    assert omitted.status_code == 200, omitted.text


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
    # 탄수화물을 0 으로 **실어 보내는** 요청이라 당류도 함께 비운다 — 보낸 0 은
    # 적은 값으로 보므로(#1893), 당류를 남겨 두면 그 요청 자체가 어긋난다.
    assert (
        client.put(
            f"/v1/diet/entries/{entry_id}",
            json={"carbs_g": 0, "protein_g": 0, "fat_g": 0, "sugar_g": 0},
        ).status_code
        == 200
    )

    # 여기가 이 검사의 요점이다 — 탄수화물을 건드리지 않는 부분 수정은 저장된
    # 0 을 미기록으로 보고 통과시킨다.
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


def test_analyze_returns_stored_time_label(client):
    """분석 응답의 `time_label` 이 저장된 값이고 끼니 목록과 같다(#1897).

    결과 시트가 `날짜 시각 · 끼니` 를 적는데, 앱이 제 시계로 시각을 다시 만들면
    나중에 끼니 카드가 보여 주는 값과 어긋난다. 서버가 저장한 값을 그대로 내려
    주는지 본다.
    """
    r = client.post(
        "/v1/diet/analyze",
        files={"image": ("food.jpg", _JPEG, "image/jpeg")},
        data={"meal_type": "lunch"},
    )
    assert r.status_code == 200, r.text
    body = r.json()
    time_label = body["time_label"]
    # `HH:MM` 이다 — 끼니 카드가 그대로 그린다.
    hh, _, mm = time_label.partition(":")
    assert len(hh) == 2 and hh.isdigit(), time_label
    assert len(mm) == 2 and mm.isdigit(), time_label

    entry = next(
        e
        for e in client.get("/v1/diet/days/today").json()["entries"]
        if e["id"] == body["entry_id"]
    )
    assert entry["time_label"] == time_label


def test_analyze_retry_returns_same_time_label(client):
    """멱등 재시도도 처음 저장한 시각을 그대로 싣는다(#1897).

    재시도가 빈 문자열을 주면 재시도한 사용자만 시각 없는 결과를 보게 된다.
    """
    key = f"idem-{uuid4().hex}"
    first = client.post(
        "/v1/diet/analyze",
        files={"image": ("food.jpg", _JPEG, "image/jpeg")},
        data={"meal_type": "lunch", "idempotency_key": key},
    )
    assert first.status_code == 200, first.text

    second = client.post(
        "/v1/diet/analyze",
        files={"image": ("food.jpg", _JPEG, "image/jpeg")},
        data={"meal_type": "lunch", "idempotency_key": key},
    )
    assert second.status_code == 200, second.text
    assert second.json()["time_label"] == first.json()["time_label"]


def test_analyze_keeps_the_ai_comment_on_the_saved_entry(client, db_session):
    """사진 분석이 만든 식단평이 저장돼 다시 읽을 때도 남는가. (#1932)

    앱은 끼니 카드 아래 한 줄로 `ai_comment` 를 보여 준다. 전에는 저장할 자리가
    없어 분석 응답 한 번으로 사라졌고, **방금 찍어 저장한 끼니도 화면을 다시
    열면 코멘트가 없었다.** 데모 서버는 내려주므로 시연으로는 드러나지 않았다.
    """
    from app.db.init_db import DEMO_USER_ID
    from app.models.models import DietEntry
    from app.services.diet_service import today_str as _today_str

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
    comment = body["analysis"]["coach_comment"]
    assert comment, "인식기가 식단평을 냈는데 응답에 없다"

    stored = db_session.get(DietEntry, body["entry_id"])
    assert stored is not None
    assert stored.ai_comment == comment

    # 조회 응답에도 같은 값이 실려야 한다 — 저장만 하고 내보내지 않으면 화면은
    # 예전처럼 빈 줄을 본다.
    today = client.get("/v1/diet/days/today")
    assert today.status_code == 200
    entries = today.json()["entries"]
    assert [e["id"] for e in entries] == [body["entry_id"]]
    assert entries[0]["ai_comment"] == comment


def test_analyze_retry_returns_the_stored_ai_comment(client, db_session):
    """같은 멱등키로 다시 부르면 저장된 식단평을 그대로 돌려준다. (#1932)

    재시도 응답이 빈 코멘트를 주면, 망이 한 번 끊긴 것만으로 화면에 보이는
    내용이 처음 저장 때와 달라진다.
    """
    from app.db.init_db import DEMO_USER_ID
    from app.models.models import DietEntry
    from app.services.diet_service import today_str as _today_str

    db_session.execute(
        delete(DietEntry).where(
            DietEntry.user_id == DEMO_USER_ID,
            DietEntry.date == _today_str(),
        )
    )
    db_session.commit()

    key = f"idem-{uuid4().hex[:12]}"
    first = client.post(
        "/v1/diet/analyze",
        files={"image": ("food.jpg", _JPEG, "image/jpeg")},
        data={"meal_type": "lunch", "idempotency_key": key},
    )
    assert first.status_code == 200, first.text
    comment = first.json()["analysis"]["coach_comment"]
    assert comment

    retry = client.post(
        "/v1/diet/analyze",
        files={"image": ("food.jpg", _JPEG, "image/jpeg")},
        data={"meal_type": "lunch", "idempotency_key": key},
    )
    assert retry.status_code == 200, retry.text
    assert retry.json()["entry_id"] == first.json()["entry_id"]
    assert retry.json()["analysis"]["coach_comment"] == comment


def test_editing_a_meal_keeps_its_ai_comment(client, db_session):
    """끼니를 고쳐도 식단평은 그대로 실려 온다. (#1932)

    수정은 숫자를 고치는 일이고 식단평은 사진 분석이 남긴 글이라, 부분 수정이
    닿지 않는 열이다. 응답에서 빠지면 고치자마자 그 줄이 사라진다.
    """
    from app.db.init_db import DEMO_USER_ID
    from app.models.models import DietEntry
    from app.services.diet_service import today_str as _today_str

    db_session.execute(
        delete(DietEntry).where(
            DietEntry.user_id == DEMO_USER_ID,
            DietEntry.date == _today_str(),
        )
    )
    db_session.commit()

    created = client.post(
        "/v1/diet/analyze",
        files={"image": ("food.jpg", _JPEG, "image/jpeg")},
        data={"meal_type": "lunch"},
    )
    assert created.status_code == 200, created.text
    entry_id = created.json()["entry_id"]
    comment = created.json()["analysis"]["coach_comment"]
    assert comment

    edited = client.put(
        f"/v1/diet/entries/{entry_id}", json={"meal_type": "dinner"}
    )
    assert edited.status_code == 200, edited.text
    assert edited.json()["meal_type"] == "dinner"
    assert edited.json()["ai_comment"] == comment
