"""하루 AI 호출 상한의 HTTP 계약. (#3032) DB 필요(로컬 skip, CI 실행).

트레이너 상한(`TRAINER_AI_CALLS_PER_DAY`):

* 고객 AI 코칭·루틴 후보·리포트 요약 **세 엔드포인트의 합**을 센다. 넘으면 셋 다
  429 `{"detail": {"code": "daily_limit", ...}}` + `Retry-After`(다음 KST 자정까지 초).
* 막힌 요청은 모델을 부르지 않고, AI 코칭 대화도 저장하지 않는다.
* 트레이너마다 버킷이 따로다.

서버 전체 상한(`AI_GLOBAL_CALLS_PER_DAY`):

* 규칙형 폴백이 있는 루틴 후보·리포트 요약은 200 폴백(`generated_by: rule`).
* 대안이 없는 AI 코치 채팅(회원·트레이너)·사진 분석은 503 `ai_capacity` + `Retry-After`.
  회원의 하루 대화 횟수·포인트·사진 분석 몫은 쓰지 않는다.
"""
from __future__ import annotations

import json
from collections.abc import Iterator
from dataclasses import dataclass, field
from types import SimpleNamespace
from uuid import uuid4

import pytest
from sqlalchemy import delete, func, select, text

from app.core.config import get_settings
from app.core.security import create_access_token
from app.models.models import (
    AiCallUsage,
    DietAnalysisUsage,
    HealthProfile,
    TrainerClient,
    User,
)
from app.schemas.trainer_api import WeeklyReportDayOut, WeeklyReportOut
from app.services import ai_call_quota
from app.services.coach.llm_base import LLMResult
from tests.image_fixtures import JPEG as _JPEG  # 진짜 JPEG — 분석 전 정리가 픽셀을 읽는다(#3041)

pytest.importorskip("fastapi")


_ROUTINE_JSON = json.dumps(
    {
        "plan_a": {
            "key": "A", "label": "관절 회복형", "total_minutes": 20, "intensity": "낮음",
            "exercises": [{"name": "저강도 걷기", "minutes": 20, "type": "유산소"}],
            "reason": "부담을 낮춘 구성", "rationale": "최근 기록과 메모를 반영",
        },
        "plan_b": {
            "key": "B", "label": "근력 강화형", "total_minutes": 30, "intensity": "보통",
            "exercises": [
                {"name": "스쿼트", "minutes": 15, "type": "근력"},
                {"name": "실내 자전거", "minutes": 15, "type": "유산소"},
            ],
            "reason": "운동량을 높인 구성", "rationale": "목표와 완료율을 반영",
        },
    },
    ensure_ascii=False,
)


@dataclass
class _Calls:
    coach: list[str] = field(default_factory=list)
    routine: list[str] = field(default_factory=list)
    summary: list[str] = field(default_factory=list)


@pytest.fixture
def llms(monkeypatch) -> _Calls:
    """세 경로의 모델을 가짜로 바꾸고 호출을 센다 — 보는 것은 상한이지 답이 아니다."""
    from app.services import trainer_report_summary_service as summary_svc
    from app.services import trainer_routine_options_service as routine_svc
    from app.services.coach import chat as chat_service

    calls = _Calls()

    class _Coach:
        def generate(self, system_prompt: str, user_prompt: str) -> LLMResult:
            calls.coach.append(user_prompt)
            return LLMResult(text="확인했습니다.", model="stub")

    class _Routine:
        def generate(self, system_prompt, user_prompt, **_):
            calls.routine.append(user_prompt)
            return LLMResult(text=_ROUTINE_JSON, model="stub")

    class _Summary:
        def generate(self, system_prompt, user_prompt, **_):
            calls.summary.append(user_prompt)
            evidence = json.loads(user_prompt)["week"]["grounded_evidence"]
            return LLMResult(
                text=json.dumps(
                    {"headline": "좋은 한 주였어요.", "points": [evidence[0]]},
                    ensure_ascii=False,
                ),
                model="stub",
            )

    monkeypatch.setattr(chat_service, "get_coach_llm", lambda *a, **k: _Coach())
    monkeypatch.setattr(routine_svc, "get_coach_llm", lambda *a, **k: _Routine())
    monkeypatch.setattr(summary_svc, "get_coach_llm", lambda *a, **k: _Summary())
    return calls


@pytest.fixture
def report_with_records(monkeypatch):
    """리포트 요약이 모델을 부를 만큼 근거가 있는 주. 조립만 바꿔 끼운다."""
    from app.services.trainer import reports as trainer_reports_service

    def _build(db, trainer_id, member_id, week):
        return WeeklyReportOut(
            member_id=member_id, member_name="김민수",
            week_start="2026-08-10", week_end="2026-08-16",
            sessions_booked=1, sessions_done=1,
            completion_avg=87, sodium_over_days=4, sodium_avg=2288,
            calories_week=[1710, 1830, 1560, 1900, 1680, 1067, 0],
            days=[WeeklyReportDayOut(completion=67, exercises=["풀업 3세트"])],
            message="",
        )

    monkeypatch.setattr(trainer_reports_service, "build_weekly_report", _build)


def _clear_usage() -> None:
    from app.db.session import SessionLocal

    db = SessionLocal()
    try:
        db.execute(delete(AiCallUsage))
        db.commit()
    finally:
        db.close()


@pytest.fixture
def caps(db_session, monkeypatch):
    """한도를 켜고 빈 카운터에서 시작한다. 값은 테스트가 넣는다."""
    s = get_settings()
    monkeypatch.setattr(s, "rate_limit_enabled", True)
    monkeypatch.setattr(s, "ai_global_calls_per_day", 0)
    monkeypatch.setattr(s, "trainer_ai_calls_per_day", 0)
    _clear_usage()
    yield s
    _clear_usage()


@dataclass
class Trainer:
    id: str
    member_id: str
    headers: dict[str, str]


@pytest.fixture
def make_trainer(db_session) -> Iterator:
    created: list[str] = []

    def _make() -> Trainer:
        suffix = uuid4().hex[:10]
        trainer_id = f"ai-cap-trainer-{suffix}"
        member_id = f"ai-cap-member-{suffix}"
        db_session.add_all(
            [
                User(
                    id=trainer_id, email=f"{trainer_id}@oncare.com", name="상한 트레이너",
                    hashed_password="unused", role="trainer",
                ),
                User(
                    id=member_id, email=f"{member_id}@oncare.com", name="상한 회원",
                    hashed_password="unused", role="member",
                ),
            ]
        )
        db_session.flush()
        db_session.add(
            TrainerClient(
                id=f"tc-{uuid4().hex[:12]}", trainer_id=trainer_id,
                member_id=member_id, active=True,
            )
        )
        db_session.commit()
        created.extend([trainer_id, member_id])
        return Trainer(
            id=trainer_id,
            member_id=member_id,
            headers={"Authorization": f"Bearer {create_access_token(trainer_id)}"},
        )

    yield _make
    db_session.rollback()
    db_session.expire_all()
    db_session.execute(text("DELETE FROM users WHERE id = ANY(:ids)"), {"ids": created})
    db_session.commit()


def _routine(client, t: Trainer):
    return client.post(
        f"/v1/trainer/clients/{t.member_id}/routine-options",
        headers=t.headers,
        json={"available_minutes": 30},
    )


def _summary(client, t: Trainer):
    return client.get(
        f"/v1/trainer/clients/{t.member_id}/report/summary",
        headers=t.headers,
    )


def _assert_daily_limit(response) -> None:
    assert response.status_code == 429, response.text
    detail = response.json()["detail"]
    assert detail["code"] == "daily_limit"
    assert detail["message"]
    retry = int(response.headers["Retry-After"])
    assert 1 <= retry <= 86400


def _assert_ai_capacity(response) -> None:
    assert response.status_code == 503, response.text
    detail = response.json()["detail"]
    assert detail["code"] == "ai_capacity"
    assert detail["message"]
    assert 1 <= int(response.headers["Retry-After"]) <= 86400


# ---------- 트레이너 하루 상한 ----------


@pytest.mark.parametrize("endpoint", ["routine", "summary"])
def test_each_trainer_endpoint_answers_429_daily_limit_at_the_cap(
    client, caps, make_trainer, llms, report_with_records, monkeypatch, endpoint
):
    monkeypatch.setattr(caps, "trainer_ai_calls_per_day", 1)
    t = make_trainer()
    call = {"routine": _routine, "summary": _summary}[endpoint]

    assert call(client, t).status_code == 200
    _assert_daily_limit(call(client, t))

    # 막힌 요청은 모델을 부르지 않았다.
    assert len(getattr(llms, endpoint)) == 1


def test_the_trainer_endpoints_share_one_trainer_bucket(
    client, caps, make_trainer, llms, report_with_records, monkeypatch
):
    # 트레이너 AI 는 프로그램 추천·리포트 요약 두 곳이다(트레이너 AI 코칭 API 는 #3085 로 삭제).
    monkeypatch.setattr(caps, "trainer_ai_calls_per_day", 1)
    t = make_trainer()

    assert _routine(client, t).status_code == 200
    _assert_daily_limit(_summary(client, t))
    _assert_daily_limit(_routine(client, t))
    assert ai_call_quota.used_today(ai_call_quota.trainer_bucket(t.id)) == 1


def test_another_trainer_is_not_affected(
    client, caps, make_trainer, llms, monkeypatch
):
    monkeypatch.setattr(caps, "trainer_ai_calls_per_day", 1)
    first, second = make_trainer(), make_trainer()

    assert _routine(client, first).status_code == 200
    _assert_daily_limit(_routine(client, first))
    assert _routine(client, second).status_code == 200


def test_routine_daily_limit_is_not_hidden_behind_a_rule_fallback(
    client, caps, make_trainer, llms, monkeypatch
):
    """트레이너 상한은 규칙형 후보로 덮지 않는다 — 덮으면 한도를 모른 채 계속 누른다."""
    monkeypatch.setattr(caps, "trainer_ai_calls_per_day", 1)
    t = make_trainer()
    first = _routine(client, t)
    assert first.json()["generated_by"] == "ai"
    blocked = _routine(client, t)
    _assert_daily_limit(blocked)
    assert "plan_a" not in blocked.json()


def test_daily_limit_message_follows_the_request_language(
    client, caps, make_trainer, llms, monkeypatch
):
    monkeypatch.setattr(caps, "trainer_ai_calls_per_day", 1)
    t = make_trainer()
    _routine(client, t)
    en = client.post(
        f"/v1/trainer/clients/{t.member_id}/routine-options",
        headers={**t.headers, "Accept-Language": "en"},
        json={"available_minutes": 30},
    )
    _assert_daily_limit(en)
    assert "today" in en.json()["detail"]["message"].lower()


def test_trainer_cap_off_means_no_daily_limit(
    client, caps, make_trainer, llms, monkeypatch
):
    t = make_trainer()  # trainer_ai_calls_per_day == 0
    for _ in range(3):
        assert _routine(client, t).status_code == 200


# ---------- 서버 전체 하루 상한 ----------


def _spend_the_global_share(caps, monkeypatch, limit: int = 1) -> None:
    monkeypatch.setattr(caps, "ai_global_calls_per_day", limit)
    for _ in range(limit):
        ai_call_quota.acquire(ai_call_quota.FEATURE_DIET_ADVICE)


def test_global_cap_falls_back_for_routine_options(
    client, caps, make_trainer, llms, monkeypatch
):
    _spend_the_global_share(caps, monkeypatch)
    t = make_trainer()

    r = _routine(client, t)
    assert r.status_code == 200, r.text
    assert r.json()["generated_by"] == "rule"
    assert llms.routine == []


def test_global_cap_falls_back_for_report_summary(
    client, caps, make_trainer, llms, report_with_records, monkeypatch
):
    _spend_the_global_share(caps, monkeypatch)
    t = make_trainer()

    r = _summary(client, t)
    assert r.status_code == 200, r.text
    assert r.json()["generated_by"] == "rule"
    assert llms.summary == []


def _member(client, db_session, points: int = 100) -> tuple[str, dict[str, str]]:
    email = f"ai-cap-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register", json={"email": email, "password": "test-pw-1234", "name": "u"}
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "test-pw-1234"}
    ).json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    member_id = client.get("/v1/users/me", headers=headers).json()["id"]
    db_session.expire_all()
    profile = db_session.scalar(
        select(HealthProfile).where(HealthProfile.user_id == member_id)
    )
    if profile is None:
        db_session.add(HealthProfile(user_id=member_id, activity_points=points))
    else:
        profile.activity_points = points
    db_session.commit()
    return member_id, headers


def test_global_cap_answers_503_for_member_coach_without_spending(
    client, db_session, caps, llms, monkeypatch
):
    s = get_settings()
    monkeypatch.setattr(s, "coach_chat_free_per_day", 0)
    monkeypatch.setattr(s, "coach_chat_paid_per_day", 3)
    monkeypatch.setattr(s, "coach_chat_paid_cost", 50)
    _, h = _member(client, db_session, points=100)
    before = client.get("/v1/ai-coach/quota", headers=h).json()

    _spend_the_global_share(caps, monkeypatch)
    r = client.post(
        "/v1/ai-coach/chat",
        headers=h,
        json={"message": "물 얼마나?", "pay_with_points": True},
    )

    _assert_ai_capacity(r)
    assert llms.coach == []
    # 포인트·하루 대화 횟수 모두 그대로다.
    after = client.get("/v1/ai-coach/quota", headers=h).json()
    assert after == before


def _gemini_recognizer():
    """실제 Gemini 인식기를 네트워크 없이 — 상한 확인이 인식기 안에 있는지 본다."""
    from app.services.recognizer.gemini import GeminiVisionRecognizer

    calls: list[object] = []

    def generate_content(*, model, contents, config):  # noqa: ARG001
        calls.append(config)
        return SimpleNamespace(
            text=json.dumps({"foods": [{"name": "바나나", "calories": 105}]}),
            candidates=[],
        )

    rec = GeminiVisionRecognizer.__new__(GeminiVisionRecognizer)
    rec._client = SimpleNamespace(models=SimpleNamespace(generate_content=generate_content))
    rec._model = "test-model"
    return rec, calls


def _analysis_usage(db_session, user_id: str) -> int:
    db_session.expire_all()
    return int(
        db_session.scalar(
            select(func.count())
            .select_from(DietAnalysisUsage)
            .where(DietAnalysisUsage.user_id == user_id)
        )
        or 0
    )


def test_global_cap_answers_503_for_photo_analysis_and_returns_the_share(
    client, db_session, caps, monkeypatch
):
    from app.api.v1 import diet as diet_api

    rec, calls = _gemini_recognizer()
    monkeypatch.setattr(diet_api, "get_recognizer", lambda engine=None: rec)
    member_id, h = _member(client, db_session)
    _spend_the_global_share(caps, monkeypatch)

    r = client.post(
        "/v1/diet/analyze",
        files={"image": ("food.jpg", _JPEG, "image/jpeg")},
        data={"meal_type": "lunch"},
        headers=h,
    )

    _assert_ai_capacity(r)
    assert calls == [], "상한에 걸리면 비전 모델을 부르지 않는다"
    assert _analysis_usage(db_session, member_id) == 0, "회원의 하루 분석 몫을 돌려준다"


def test_photo_analysis_passes_the_output_cap_when_under_the_global_cap(
    client, db_session, caps, monkeypatch
):
    from app.api.v1 import diet as diet_api
    from app.services.recognizer.base import RECOGNIZER_MAX_OUTPUT_TOKENS

    rec, calls = _gemini_recognizer()
    monkeypatch.setattr(diet_api, "get_recognizer", lambda engine=None: rec)
    monkeypatch.setattr(caps, "ai_global_calls_per_day", 5)
    _, h = _member(client, db_session)

    r = client.post(
        "/v1/diet/analyze",
        files={"image": ("food.jpg", _JPEG, "image/jpeg")},
        data={"meal_type": "lunch"},
        headers=h,
    )

    assert r.status_code == 200, r.text
    assert calls[0].max_output_tokens == RECOGNIZER_MAX_OUTPUT_TOKENS
    assert ai_call_quota.used_today(ai_call_quota.GLOBAL_BUCKET) == 1


def test_capacity_message_follows_the_request_language(
    client, db_session, caps, llms, monkeypatch
):
    _spend_the_global_share(caps, monkeypatch)
    _, headers = _member(client, db_session)
    r = client.post(
        "/v1/ai-coach/chat",
        headers={**headers, "Accept-Language": "en"},
        json={"message": "How was the week?"},
    )
    _assert_ai_capacity(r)
    assert "AI" in r.json()["detail"]["message"]
    assert not any("가" <= ch <= "힣" for ch in r.json()["detail"]["message"])
