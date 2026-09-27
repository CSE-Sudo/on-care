"""AI 폴백 계측 (#583).

핵심 성질: AI 가 조용히 죽어도 사용자는 그럴듯한 규칙형 결과를 받으므로 아무도
신고하지 않는다. 그 상태를 지표로 볼 수 있어야 한다.
"""
from __future__ import annotations

import json

import pytest

from app.core import metrics


@pytest.fixture(autouse=True)
def _clean_metrics():
    metrics.reset()
    yield
    metrics.reset()


# ---- 레지스트리 (순수) ----

def test_labels_collapse_to_one_slot_regardless_of_order():
    metrics.incr("thing", a="1", b="2")
    metrics.incr("thing", b="2", a="1")

    assert metrics.snapshot()["counters"] == {"thing{a=1,b=2}": 2}


def test_distinct_label_values_are_counted_separately():
    metrics.incr("routine_options.fallback", reason="contract")
    metrics.incr("routine_options.fallback", reason="infra")
    metrics.incr("routine_options.fallback", reason="infra")

    counters = metrics.snapshot()["counters"]
    assert counters["routine_options.fallback{reason=contract}"] == 1
    assert counters["routine_options.fallback{reason=infra}"] == 2


def test_durations_keep_a_summary_not_every_sample():
    for ms in (100.0, 300.0, 200.0):
        metrics.observe_ms("llm_ms", ms)

    d = metrics.snapshot()["durations"]["llm_ms"]
    assert d["count"] == 3
    assert d["total_ms"] == 600.0
    assert d["avg_ms"] == 200.0
    assert d["max_ms"] == 300.0


def test_snapshot_is_a_copy_so_readers_cannot_mutate_state():
    metrics.incr("thing")
    snap = metrics.snapshot()
    snap["counters"]["thing"] = 999

    assert metrics.snapshot()["counters"]["thing"] == 1


# ---- 루틴 생성 경로 (DB) ----

def _trainer_token(client) -> str:
    r = client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    )
    assert r.status_code == 200, r.text
    return r.json()["access_token"]


def _headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _generate(client, token: str, member_id: str):
    return client.post(
        f"/v1/trainer/clients/{member_id}/routine-options",
        headers=_headers(token),
        json={"available_minutes": 40},
    )


def _first_client_id(client, token: str) -> str:
    r = client.get("/v1/trainer/clients", headers=_headers(token))
    assert r.status_code == 200, r.text
    return r.json()[0]["id"]


_VALID_PLANS = {
    "plan_a": {
        "key": "A", "label": "회복 루틴", "intensity": "낮음",
        "total_minutes": 20, "reason": "회복 위주",
        "rationale": "부담을 줄인 회복 루틴입니다.",
        "exercises": [{"name": "가벼운 걷기", "minutes": 20, "type": "걷기"}],
    },
    "plan_b": {
        "key": "B", "label": "표준 루틴", "intensity": "보통",
        "total_minutes": 30, "reason": "표준 강도",
        "rationale": "평소 강도를 유지하는 루틴입니다.",
        "exercises": [{"name": "인터벌 러닝", "minutes": 30, "type": "유산소"}],
    },
}


def _stub_llm(monkeypatch, behaviour):
    from app.services import trainer_routine_options_service as svc
    from app.services.coach.llm_base import LLMResult

    class _StubLLM:
        # 실제 호출부는 json_mode·thinking_budget 을 넘긴다. 스텁이 프로토콜
        # (`llm_base.CoachLLM.generate`)을 그대로 받지 않으면 TypeError 가 나고,
        # 서비스가 그걸 폴백으로 삼켜 계측 테스트가 엉뚱한 이유로 깨진다.
        def generate(
            self,
            system_prompt: str,
            user_prompt: str,
            *,
            json_mode: bool = False,
            thinking_budget: int | None = None,
        ) -> LLMResult:
            if isinstance(behaviour, Exception):
                raise behaviour
            return LLMResult(text=behaviour, model="stub")

    monkeypatch.setattr(svc, "get_coach_llm", lambda *a, **k: _StubLLM())


def test_successful_generation_is_counted_as_ai(client, monkeypatch):
    token = _trainer_token(client)
    member_id = _first_client_id(client, token)
    _stub_llm(monkeypatch, json.dumps(_VALID_PLANS, ensure_ascii=False))
    metrics.reset()

    assert _generate(client, token, member_id).json()["generated_by"] == "ai"

    counters = metrics.snapshot()["counters"]
    assert counters["routine_options.generated{by=ai}"] == 1
    assert not any(k.startswith("routine_options.fallback") for k in counters)


def test_a_malformed_response_is_counted_as_a_contract_fallback(
    client, monkeypatch
):
    """공급자는 살아 있는데 규격이 틀렸다 — 프롬프트/스키마를 볼 신호."""
    token = _trainer_token(client)
    member_id = _first_client_id(client, token)
    _stub_llm(monkeypatch, '{"plan_a": {"key": "A"}}')
    metrics.reset()

    assert _generate(client, token, member_id).json()["generated_by"] == "rule"

    counters = metrics.snapshot()["counters"]
    assert counters["routine_options.fallback{reason=contract}"] == 1
    assert counters["routine_options.generated{by=rule}"] == 1


def test_a_provider_failure_is_counted_as_an_infra_fallback(client, monkeypatch):
    """키 미설정·네트워크·5xx — 계약 위반과 섞이면 원인을 못 가른다."""
    token = _trainer_token(client)
    member_id = _first_client_id(client, token)
    _stub_llm(monkeypatch, RuntimeError("GEMINI_API_KEY 가 설정되지 않았습니다."))
    metrics.reset()

    assert _generate(client, token, member_id).json()["generated_by"] == "rule"

    counters = metrics.snapshot()["counters"]
    assert counters["routine_options.fallback{reason=infra}"] == 1
    assert "routine_options.fallback{reason=contract}" not in counters


def test_llm_duration_is_recorded_even_when_the_call_fails(client, monkeypatch):
    """#584 의 타임아웃 값은 '실패까지 얼마나 기다렸나'에서 나온다."""
    token = _trainer_token(client)
    member_id = _first_client_id(client, token)
    _stub_llm(monkeypatch, RuntimeError("provider down"))
    metrics.reset()

    _generate(client, token, member_id)

    assert metrics.snapshot()["durations"]["routine_options.llm_ms"]["count"] == 1


def test_chat_grounded_generations_are_counted(client, monkeypatch):
    """#580 이 실환경에서도 도는지 — 근거가 실린 생성만 따로 센다."""
    token = _trainer_token(client)
    member_id = _first_client_id(client, token)
    client.post(
        f"/v1/trainer/clients/{member_id}/chat",
        headers=_headers(token),
        json={"text": "계측 확인용 메시지입니다 무릎이 불편해요"},
    )
    _stub_llm(monkeypatch, json.dumps(_VALID_PLANS, ensure_ascii=False))
    metrics.reset()

    _generate(client, token, member_id)

    assert metrics.snapshot()["counters"]["routine_options.with_chat_context"] == 1


def test_a_provider_config_typo_is_infra_not_contract(client, monkeypatch):
    """COACH_LLM 오타는 ValueError 지만 설정 문제다 — 프롬프트를 봐도 안 고쳐진다.

    `get_coach_llm()` 이 던지는 "알 수 없는 코치 LLM" 을 계약 위반으로 세면
    지표를 보고 프롬프트·스키마만 뒤지게 된다(CodeRabbit PR#600 리뷰).
    """
    from app.services import trainer_routine_options_service as svc

    token = _trainer_token(client)
    member_id = _first_client_id(client, token)

    def _unknown_provider(*_a, **_k):
        raise ValueError("알 수 없는 코치 LLM: 'gemni'. 사용 가능: ['openai', 'gemini']")

    monkeypatch.setattr(svc, "get_coach_llm", _unknown_provider)
    metrics.reset()

    assert _generate(client, token, member_id).json()["generated_by"] == "rule"

    counters = metrics.snapshot()["counters"]
    assert counters["routine_options.fallback{reason=infra}"] == 1
    assert "routine_options.fallback{reason=contract}" not in counters


def test_a_new_member_without_history_is_not_counted_as_a_fallback(
    client, db_session
):
    """LLM 을 부를 이유가 없던 것과 LLM 이 실패한 것은 다르다.

    같은 칸에 세면 신규 가입이 몰릴 때 폴백률이 치솟아 AI 가 죽은 것처럼 보인다
    (CodeRabbit PR#600 리뷰).
    """
    import uuid

    from sqlalchemy import delete

    from app.core.security import hash_password
    from app.models.models import User

    email = f"metrics-newbie-{uuid.uuid4().hex[:8]}@example.com"
    user = User(
        id=f"user-{uuid.uuid4().hex[:12]}", email=email, name="신규",
        hashed_password=hash_password("test-pw-1234"), role="member",
    )
    db_session.add(user)
    db_session.commit()
    try:
        token = client.post(
            "/v1/auth/login", data={"username": email, "password": "test-pw-1234"}
        ).json()["access_token"]
        metrics.reset()

        client.get("/v1/diet/recommendations", headers=_headers(token))

        counters = metrics.snapshot()["counters"]
        assert counters["diet_recommendations.generated{by=no_data}"] == 1
        assert not any(
            k.startswith("diet_recommendations.fallback") for k in counters
        )
    finally:
        db_session.execute(delete(User).where(User.id == user.id))
        db_session.commit()


# ---- 노출 엔드포인트 ----

def test_metrics_endpoint_requires_authentication(client):
    assert client.get("/v1/system/metrics").status_code == 401


def test_metrics_endpoint_forbidden_for_a_normal_user(client):
    """어떤 공급자가 얼마나 실패하는지는 운영 정보다."""
    email = "metrics-viewer@example.com"
    client.post(
        "/v1/auth/register",
        json={"email": email, "password": "test-pw-1234", "name": "u"},
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "test-pw-1234"}
    ).json()["access_token"]

    assert client.get("/v1/system/metrics", headers=_headers(token)).status_code == 403
