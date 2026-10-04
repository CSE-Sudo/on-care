"""AI 응답은 외부 입력이다 — 값 검사·프롬프트 경계·폴백 로그·비밀값. (#3090)

실제 모델은 부르지 않는다. 모델이 낼 수 있는 이상한 응답을 가짜로 만들어
경계마다 넣어 본다.

- 식단 인식: 음수·거대값·비유한값·문자열 영양값, 범위를 벗어난 확신도, 긴 이름·
  식단평, 수백 개 항목, 모양이 틀린 JSON.
- 운동 이름 해석: 객체가 아닌 JSON.
- 프롬프트: 경계 문구가 실제로 프롬프트에 들어가는 줄 모양을 가리키는가.
- 로그: 폴백 경로가 모델 출력·예외 메시지를 남기지 않는가.
- 설정: 객체를 찍어도 비밀값이 보이지 않는가.
- 리포트 요약: 긴 headline 은 규칙 기반으로 바뀌는가.

순수 검사는 DB 없이 돌고, 엔드포인트 검사는 DB 가 필요하다(로컬 skip, CI 실행).
"""
from __future__ import annotations

import json
import logging
from types import SimpleNamespace
from uuid import uuid4

import pytest

#: 모델 출력·예외 메시지에 심어 두는 표식. 로그 어디에도 나오면 안 된다.
LEAK = "LEAK-MARKER"

def _real_jpeg() -> bytes:
    """디코딩되는 진짜 JPEG. 업로드 사진은 디코딩 검사(#3040)를 지나야 분석까지 간다."""
    import io

    from PIL import Image

    buffer = io.BytesIO()
    Image.new("RGB", (64, 64), (120, 180, 90)).save(buffer, format="JPEG")
    return buffer.getvalue()


_JPEG = _real_jpeg()


def _gemini_parse(payload) -> object:
    from app.services.recognizer.gemini import GeminiVisionRecognizer

    raw = payload if isinstance(payload, str) else json.dumps(payload)
    return GeminiVisionRecognizer.__new__(GeminiVisionRecognizer)._parse(raw, 1)


def _litellm_parse(payload) -> object:
    from app.services.recognizer.litellm_vision import LiteLLMVisionRecognizer

    raw = payload if isinstance(payload, str) else json.dumps(payload)
    return LiteLLMVisionRecognizer.__new__(LiteLLMVisionRecognizer)._parse(raw, 1)


_PARSERS = pytest.mark.parametrize("parse", [_gemini_parse, _litellm_parse])


def _assert_no_leak(caplog) -> None:
    """포맷된 로그(스택 포함)와 레코드 속성 어디에도 표식이 없어야 한다."""
    assert LEAK not in caplog.text
    for record in caplog.records:
        assert LEAK not in record.getMessage()
        assert LEAK not in repr(record.__dict__)
        if hasattr(record, "fallback_reason"):
            assert record.exc_info is None, "AI 폴백은 스택을 남기지 않는다"


# ── 식단 인식 파서 (DB 불필요) ────────────────────────────────────────────


@_PARSERS
@pytest.mark.parametrize(
    "value",
    [-300, 1e12, "Infinity", "NaN", "많이", True, [1], {"v": 1}],
)
def test_out_of_range_calories_become_unknown(parse, value):
    analysis = parse({"foods": [{"name": "김치찌개", "calories": value, "sodium_mg": value}]})
    assert len(analysis.foods) == 1, "한 칸의 이상값 때문에 음식을 잃으면 안 된다"
    food = analysis.foods[0]
    assert food.calories is None
    assert food.sodium_mg is None
    assert analysis.total_calories == 0
    assert analysis.total_sodium_mg == 0


@_PARSERS
def test_values_inside_the_bounds_are_kept(parse):
    from app.services.recognizer import parse as rp

    analysis = parse({
        "foods": [{
            "name": "김치찌개",
            "calories": rp.CALORIES_MAX,
            "sodium_mg": "1800.4",
            "carbs_g": 30.5,
            "sugar_g": 4.6,
            "amount_g": 400,
            "confidence": 0.9,
        }]
    })
    food = analysis.foods[0]
    assert food.calories == rp.CALORIES_MAX
    assert food.sodium_mg == 1800
    assert food.carbs_g == 30.5
    assert food.sugar_g == 5
    assert food.amount_g == 400


@_PARSERS
def test_out_of_range_macros_and_amount_become_unknown(parse):
    from app.services.recognizer import parse as rp

    analysis = parse({
        "foods": [{
            "name": "밥",
            "carbs_g": -1,
            "protein_g": rp.MACRO_G_MAX + 1,
            "fat_g": "Infinity",
            "sugar_g": -3,
            "amount_g": rp.AMOUNT_G_MAX + 1,
        }]
    })
    food = analysis.foods[0]
    assert (food.carbs_g, food.protein_g, food.fat_g, food.sugar_g, food.amount_g) == (
        None, None, None, None, None,
    )


@_PARSERS
@pytest.mark.parametrize("confidence", [1.5, -0.1])
def test_only_the_invalid_item_is_dropped(parse, confidence):
    """예전에는 항목 하나의 ValidationError 가 사진 전체를 502 로 만들었다."""
    analysis = parse({
        "foods": [
            {"name": "김치찌개", "calories": 300},
            {"name": "이상한 항목", "calories": 100, "confidence": confidence},
            {"name": "현미밥", "calories": 310},
        ],
        "coach_comment": "좋아요",
    })
    assert [f.name for f in analysis.foods] == ["김치찌개", "현미밥"]
    assert analysis.total_calories == 610
    assert analysis.coach_comment == "좋아요"


@_PARSERS
def test_names_comment_and_item_count_are_capped(parse):
    from app.services.recognizer import parse as rp

    analysis = parse({
        "foods": [
            {"name": "  아주 \n 긴   " + "가" * 500, "calories": 1}
            for _ in range(rp.FOODS_MAX * 10)
        ],
        "coach_comment": "나" * 5000,
    })
    assert len(analysis.foods) == rp.FOODS_MAX
    name = analysis.foods[0].name
    assert len(name) == rp.NAME_MAX
    assert name.startswith("아주 긴 가"), "공백은 한 칸으로 접는다"
    assert len(analysis.coach_comment) == rp.COACH_COMMENT_MAX


@_PARSERS
@pytest.mark.parametrize("name", [None, "", "   ", 42, ["밥"]])
def test_missing_or_non_string_name_is_unknown(parse, name):
    from app.services.recognizer.parse import UNKNOWN_FOOD_NAME

    analysis = parse({"foods": [{"name": name, "calories": 100}]})
    assert analysis.foods[0].name == UNKNOWN_FOOD_NAME


@_PARSERS
@pytest.mark.parametrize(
    "payload",
    [
        "[1, 2]",
        "null",
        '"그냥 문장"',
        "not json",
        {"foods": "김치찌개"},
        {"foods": {"name": "김치찌개"}},
        {"foods": None},
        {"foods": ["김치찌개", 3, None]},
    ],
)
def test_wrong_shapes_give_no_foods(parse, payload):
    """음식이 없으면 API 가 "음식 없음" 422 로 답한다 — 500·502 가 아니다."""
    analysis = parse(payload)
    assert analysis.foods == []
    assert analysis.total_calories == 0


@_PARSERS
def test_non_string_comment_is_dropped(parse):
    analysis = parse({"foods": [{"name": "밥"}], "coach_comment": {"x": 1}})
    assert analysis.coach_comment == ""


def test_schema_rejects_negative_calories_and_sodium():
    from pydantic import ValidationError

    from app.schemas.diet import RecognizedFood

    with pytest.raises(ValidationError):
        RecognizedFood(name="밥", calories=-1)
    with pytest.raises(ValidationError):
        RecognizedFood(name="밥", sodium_mg=-1)


# ── 운동 이름 해석 (DB 불필요) ───────────────────────────────────────────


def _fake_name_ai(monkeypatch, *, text: str | None = None, error: Exception | None = None):
    from app.services.exercise_catalog import name_ai

    def generate_content(**_):
        if error is not None:
            raise error
        return SimpleNamespace(text=text)

    client = SimpleNamespace(models=SimpleNamespace(generate_content=generate_content))
    monkeypatch.setattr(name_ai, "_client_and_model", lambda: (client, "fake-model"))
    return name_ai


@pytest.mark.parametrize("text", ["null", "[]", '"x"', "3", '["러닝머신"]'])
def test_name_ai_non_object_json_falls_back(monkeypatch, text):
    name_ai = _fake_name_ai(monkeypatch, text=text)
    assert name_ai.resolve_name("런닝머신", ["러닝머신", "자전거"]) is None


@pytest.mark.parametrize("confidence", ["NaN", "Infinity"])
def test_name_ai_non_finite_confidence_falls_back(monkeypatch, confidence):
    name_ai = _fake_name_ai(
        monkeypatch, text=json.dumps({"match": "러닝머신", "confidence": confidence})
    )
    assert name_ai.resolve_name("런닝머신", ["러닝머신"]) is None


def test_name_ai_still_returns_a_valid_match(monkeypatch):
    name_ai = _fake_name_ai(
        monkeypatch, text=json.dumps({"match": "러닝머신", "confidence": 1.7})
    )
    assert name_ai.resolve_name("런닝머신", ["러닝머신"]) == ("러닝머신", 1.0)


def test_name_ai_failure_log_has_no_provider_message(monkeypatch, caplog):
    name_ai = _fake_name_ai(monkeypatch, error=RuntimeError(f"400 {LEAK} prompt echo"))
    with caplog.at_level(logging.DEBUG):
        assert name_ai.resolve_name("런닝머신", ["러닝머신"]) is None
    assert caplog.records, "폴백은 기록돼야 한다"
    assert caplog.records[-1].error_type == "builtins.RuntimeError"
    _assert_no_leak(caplog)


# ── 프롬프트 경계 (DB 불필요) ────────────────────────────────────────────


def _ingested_chat_lines(monkeypatch) -> list[str]:
    from app.services.coach import personal_ingest

    captured: list[str] = []
    monkeypatch.setattr(
        personal_ingest, "_safe", lambda db, user_id, text, **_: captured.append(text)
    )
    personal_ingest.record_chat(
        None, "m-1", sender="member", text="어제부터 무릎이 아파요", date="2026-08-10"
    )
    personal_ingest.record_chat(
        None, "m-1", sender="trainer", text="이번 주는 하체를 빼시죠", date="2026-08-10"
    )
    return captured


def test_quote_guard_points_at_the_chat_lines_the_coach_actually_sees(monkeypatch):
    """적재 → 코치 프롬프트 조립 → 경계 문구가 가리키는 표시가 그 줄에 있다."""
    from app.services.coach import chat as coach_chat
    from app.services.coach import prompt_safety

    docs = [SimpleNamespace(content=t) for t in _ingested_chat_lines(monkeypatch)]
    context = coach_chat._format_context({"personal": docs, "public": []})
    chat_lines = [line for line in context.splitlines() if "무릎" in line or "하체" in line]
    assert len(chat_lines) == 2

    guard = prompt_safety.UNTRUSTED_QUOTE_GUARD
    for sender, line in zip(("member", "trainer"), chat_lines):
        marker = prompt_safety.chat_quote_prefix(sender)
        assert marker in line
        assert f"'{marker}'" in guard
        # 줄은 `- 날짜 …` 로 시작한다. 예전 문구("'회원:' 으로 시작하는 줄")로는
        # 이 줄을 가리킬 수 없었다.
        assert not line.startswith(prompt_safety.speaker_label(sender))


def test_quote_guard_still_covers_routine_chat_items():
    """트레이너 루틴 후보는 `회원: …` 항목으로 대화를 받는다."""
    from app.services.coach import prompt_safety

    guard = prompt_safety.UNTRUSTED_QUOTE_GUARD
    for sender in ("member", "trainer"):
        assert f"'{prompt_safety.speaker_label(sender)}:'" in guard


def test_food_name_guard_reaches_every_coach_that_reads_health_records():
    from app.services.coach import chat as coach_chat
    from app.services.coach import domain_coaches, prompt_safety

    guard = prompt_safety.FOOD_NAME_GUARD
    assert "[내 건강 기록]" in guard
    assert guard in coach_chat._SYSTEM
    assert guard in domain_coaches._DIET_SYSTEM
    assert guard in domain_coaches._EXERCISE_SYSTEM
    # 코치가 실제로 받는 절 제목이다.
    context = coach_chat._format_context(
        {"personal": [SimpleNamespace(content="2026-08-10 식단 기록: 밥.")], "public": []}
    )
    assert context.startswith("[내 건강 기록]")


# ── 폴백 로그 (DB 불필요) ────────────────────────────────────────────────


def test_log_helper_drops_validation_error_input_and_stack(caplog):
    from pydantic import BaseModel, ValidationError

    from app.services.ai_log import log_ai_fallback

    class _Contract(BaseModel):
        n: int

    logger = logging.getLogger("tests.ai_log")
    try:
        _Contract(n=LEAK)
    except ValidationError as exc:
        assert LEAK in str(exc), "전제: ValidationError 문자열은 입력값을 싣는다"
        with caplog.at_level(logging.DEBUG, logger="tests.ai_log"):
            log_ai_fallback(
                logger, "feature", "contract", exc=exc, level=logging.ERROR,
                member_id="m-1",
            )

    (record,) = caplog.records
    assert record.levelno == logging.ERROR
    assert record.error_type == "pydantic_core._pydantic_core.ValidationError"
    assert record.fallback_reason == "contract"
    assert record.member_id == "m-1"
    # 스택 대신 발생 위치만.
    assert record.error_origin != "-"
    assert "member_id=m-1" in record.getMessage()
    _assert_no_leak(caplog)


def test_diet_sentence_failure_and_rejection_logs_have_no_model_text(monkeypatch, caplog):
    from app.services import diet_ai_sentence as svc

    kwargs = dict(
        lang="ko", analysis_text="오늘 나트륨이 많아요.", finding="나트륨 초과",
        records=["김치찌개"], notes=[], goal="체중 감량", metric="test_sentence",
    )

    def _boom(system, user):
        raise RuntimeError(f"provider echoed {LEAK}")

    monkeypatch.setattr(svc, "_call_llm", _boom)
    with caplog.at_level(logging.DEBUG):
        assert svc.generate(**kwargs) is None
    _assert_no_leak(caplog)

    caplog.clear()
    # 검사에 떨어지는 긴 문장 — 예전에는 원문을 DEBUG 로 남겼다.
    monkeypatch.setattr(svc, "_call_llm", lambda system, user: f"{LEAK} " * 200)
    with caplog.at_level(logging.DEBUG):
        assert svc.generate(**kwargs) is None
    assert caplog.records, "탈락 사유는 남긴다"
    _assert_no_leak(caplog)


# ── 설정 비밀값 (DB 불필요) ──────────────────────────────────────────────


def test_settings_repr_hides_secrets():
    from app.core.config import Settings

    s = Settings(
        _env_file=None,
        gemini_api_key=f"gemini-{LEAK}",
        jwt_secret=f"jwt-{LEAK}",
        database_url=f"postgresql+psycopg://u:{LEAK}@db:5432/oncare",
        openai_api_key=f"openai-{LEAK}",
        litellm_api_key=f"litellm-{LEAK}",
        smtp_password=f"smtp-{LEAK}",
        sentry_dsn=f"https://{LEAK}@sentry.example/1",
        kakao_rest_api_key=f"kakao-{LEAK}",
    )
    assert LEAK not in repr(s)
    assert LEAK not in str(s)
    # 사용처는 그대로 문자열을 읽는다.
    assert s.gemini_api_key == f"gemini-{LEAK}"
    assert s.jwt_secret == f"jwt-{LEAK}"
    assert LEAK in s.sqlalchemy_database_url


# ── 리포트 요약 headline (DB 불필요) ─────────────────────────────────────


def _report():
    from app.schemas.trainer_api import WeeklyReportOut

    return WeeklyReportOut(
        member_id="m", member_name="김민수",
        week_start="2026-08-03", week_end="2026-08-09",
        sessions_booked=3, sessions_done=2,
        completion_avg=70.0, sodium_over_days=3, sodium_avg=3100,
        message="",
    )


@pytest.mark.parametrize("over", [False, True])
def test_long_headline_falls_back_to_the_rule_summary(monkeypatch, caplog, over):
    from app.services import trainer_report_summary_service as svc

    report = _report()
    evidence = svc._evidence(report, "ko")
    assert evidence, "전제: 근거가 있어야 모델을 부른다"
    headline = (LEAK + "가" * svc.HEADLINE_MAX)[: svc.HEADLINE_MAX + (1 if over else 0)]
    monkeypatch.setattr(
        svc.trainer_reports_service, "build_weekly_report", lambda *a, **k: report
    )
    monkeypatch.setattr(
        svc,
        "_call_llm",
        lambda prompt, locale="ko": SimpleNamespace(
            text=json.dumps({"headline": headline, "points": evidence[:1]})
        ),
    )

    with caplog.at_level(logging.DEBUG):
        out = svc.generate_summary(None, "t-1", "m", report.week_start, locale="ko")

    if over:
        assert out.generated_by == "rule"
        assert LEAK not in out.headline
        _assert_no_leak(caplog)
    else:
        assert out.generated_by == "llm"
        assert out.headline == headline


@pytest.mark.parametrize("text", ["[]", "null", '"문장"'])
def test_non_object_summary_is_a_contract_violation(text):
    from app.services import trainer_report_summary_service as svc

    report = _report()
    with pytest.raises(ValueError):
        svc._decode(text, report, svc._evidence(report, "ko"), "ko")


# ── 엔드포인트 (DB 필요) ─────────────────────────────────────────────────


def _member_headers(client) -> dict:
    email = f"ai-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register",
        json={"email": email, "password": "test-pw-1234", "name": "u"},
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "test-pw-1234"}
    ).json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


def _fake_recognizer(monkeypatch, payload) -> None:
    from app.api.v1 import diet as diet_api

    class _Fake:
        name = "gemini"

        async def recognize(self, image_bytes, mime_type):
            return _gemini_parse(payload)

    monkeypatch.setattr(diet_api, "get_recognizer", lambda engine=None: _Fake())


def test_analyze_saves_absurd_values_without_500(client, db_session, monkeypatch):
    """음수·거대값·이상 항목이 와도 200 이고, 분석 한도는 한 번만 쓴다."""
    from app.core.security import decode_access_claims
    from app.services import diet_analysis_quota_service

    headers = _member_headers(client)
    user_id = decode_access_claims(headers["Authorization"].split()[1]).subject
    _fake_recognizer(monkeypatch, {
        "foods": [
            # 영양 DB 에 없는 이름 — 인식기 값이 그대로 저장 경로로 간다.
            {"name": f"모르는음식{uuid4().hex[:6]}", "calories": -300, "sodium_mg": 1e15},
            {"name": f"모르는음식{uuid4().hex[:6]}", "calories": 1e12, "sodium_mg": -5},
            {"name": "이상한 항목", "calories": 100, "confidence": 1.5},
            {"name": f"모르는음식{uuid4().hex[:6]}", "calories": 250, "sodium_mg": 400},
        ],
        "coach_comment": "가" * 2000,
    })
    before = diet_analysis_quota_service.used_today(db_session, user_id)

    r = client.post(
        "/v1/diet/analyze",
        files={"image": ("food.jpg", _JPEG, "image/jpeg")},
        data={"meal_type": "lunch"},
        headers=headers,
    )

    assert r.status_code == 200, r.text
    analysis = r.json()["analysis"]
    assert len(analysis["foods"]) == 3
    assert analysis["total_calories"] == 250
    assert analysis["total_sodium_mg"] == 400
    assert all(
        (f["calories"] is None or f["calories"] >= 0)
        and (f["sodium_mg"] is None or f["sodium_mg"] >= 0)
        for f in analysis["foods"]
    )
    db_session.expire_all()
    assert diet_analysis_quota_service.used_today(db_session, user_id) == before + 1


def test_analyze_with_no_readable_food_is_422(client, monkeypatch):
    _fake_recognizer(monkeypatch, "[1, 2, 3]")
    r = client.post(
        "/v1/diet/analyze",
        files={"image": ("food.jpg", _JPEG, "image/jpeg")},
        data={"meal_type": "lunch"},
        headers=_member_headers(client),
    )
    assert r.status_code == 422, r.text


@pytest.mark.parametrize("text", ["null", "[]", '"x"'])
def test_exercise_endpoints_survive_non_object_name_ai(client, monkeypatch, text):
    """예전에는 `data.get` 이 AttributeError 로 터져 500 이었다."""
    from tests.exercise_helpers import post_exercise

    _fake_name_ai(monkeypatch, text=text)
    headers = _member_headers(client)
    name = f"이상한운동{uuid4().hex[:8]}"

    preview = client.post(
        "/v1/exercise/calories",
        json={"type": "cardio", "name": name, "minutes": 30},
        headers=headers,
    )
    assert preview.status_code == 200, preview.text
    assert preview.json()["source"] == "estimate"

    created = post_exercise(
        client,
        json={
            "type": "cardio",
            "name": f"다른운동{uuid4().hex[:8]}",
            "minutes": 30,
            "calories": 0,
        },
        headers=headers,
    )
    assert created.status_code == 201, created.text


def test_routine_contract_violation_log_has_no_model_output(client, monkeypatch, caplog):
    from app.services import trainer_routine_options_service as svc
    from app.services.coach.llm_base import LLMResult

    class _StubLLM:
        def generate(self, system_prompt, user_prompt, **kwargs):
            return LLMResult(text=json.dumps({"plan_a": {"key": LEAK}}), model="stub")

    monkeypatch.setattr(svc, "get_coach_llm", lambda *a, **k: _StubLLM())
    token = client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    ).json()["access_token"]
    auth = {"Authorization": f"Bearer {token}"}
    roster = client.get("/v1/trainer/clients", headers=auth).json()
    assert roster, "데모 트레이너는 회원을 갖고 있다"

    with caplog.at_level(logging.DEBUG):
        r = client.post(
            f"/v1/trainer/clients/{roster[0]['id']}/routine-options",
            headers=auth,
            json={"available_minutes": 30},
        )

    assert r.status_code == 200, r.text
    assert r.json()["generated_by"] == "rule"
    contract = [rec for rec in caplog.records if getattr(rec, "fallback_reason", "") == "contract"]
    assert contract, "계약 위반 폴백은 기록된다"
    _assert_no_leak(caplog)
