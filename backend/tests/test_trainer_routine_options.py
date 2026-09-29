"""Trainer routine-options endpoint and LLM fallback contract."""
from __future__ import annotations

import json
import threading
import time
from concurrent.futures import TimeoutError as FutureTimeout
from dataclasses import dataclass
from datetime import datetime, timedelta
from datetime import time as time_of_day
from uuid import uuid4

import pytest
from pydantic import ValidationError
from sqlalchemy import delete

from app.schemas.trainer_api import (
    RoutineOptionAnalysisOut,
    RoutineOptionExerciseOut,
    RoutineOptionsRequest,
)
from app.core import clock, metrics
from app.db.seed_trainer import TRAINER_ID
from app.db.session import SessionLocal
from app.models.models import (
    MemberWeeklyFeedback,
    RoutineHistory,
    TrainerClient,
    TrainerClientMemo,
    TrainerRoutine,
    TrainerSchedule,
    User,
)
from app.services import trainer_routine_options_service
from app.services.coach import prompt_safety
from app.services.coach.llm import DEFAULT_THINKING_BUDGET

#: 계약을 만족하는 LLM 응답. 여러 테스트가 같은 페이로드를 쓴다.
_VALID_LLM_JSON = """
{
  "plan_a": {
    "key": "A",
    "label": "관절 회복형",
    "total_minutes": 20,
    "intensity": "낮음",
    "exercises": [
      {"name": "저강도 걷기", "minutes": 20, "type": "유산소"}
    ],
    "reason": "부담을 낮춘 구성",
    "rationale": "최근 기록과 메모를 반영"
  },
  "plan_b": {
    "key": "B",
    "label": "근력 강화형",
    "total_minutes": 30,
    "intensity": "보통",
    "exercises": [
      {"name": "스쿼트", "minutes": 15, "type": "근력"},
      {"name": "실내 자전거", "minutes": 15, "type": "유산소"}
    ],
    "reason": "운동량을 높인 구성",
    "rationale": "목표와 완료율을 반영"
  }
}
"""


def _trainer_token(client) -> str:
    response = client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    )
    assert response.status_code == 200, response.text
    return response.json()["access_token"]


def _headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _first_client_id(client, token: str) -> str:
    """로스터에서 담당 중인 첫 회원. (#2471)

    로스터는 담당이 끝난 회원도 `registered=false` 로 돌려주고, 그 회원의 루틴
    API 는 404 다. 다른 테스트가 남긴 회원이 맨 앞에 와도 흔들리지 않게 고른다.
    """
    response = client.get("/v1/trainer/clients", headers=_headers(token))
    assert response.status_code == 200, response.text
    return next(c["id"] for c in response.json() if c["registered"])


def _register_and_link_member(client, *, goal: str = "체중 감량") -> str:
    """개인화 분석 테스트 전용 회원 — 다른 테스트의 시드 데이터와 섞이지 않게
    매번 새로 등록하고 트레이너(#776 분석 대상)에 직접 연결한다."""
    email = f"routine-options-776-{uuid4().hex[:8]}@oncare.com"
    response = client.post(
        "/v1/auth/register",
        json={"email": email, "password": "test-pw-1234", "name": "분석 테스트 회원"},
    )
    assert response.status_code == 201, response.text
    member_id = response.json()["id"]

    db = SessionLocal()
    try:
        db.add(
            TrainerClient(
                id=f"link-{member_id}", trainer_id=TRAINER_ID, member_id=member_id,
                goal=goal,
            )
        )
        db.commit()
    finally:
        db.close()
    return member_id


def _seed_routine_history(member_id: str, sessions: list[list[str]]) -> None:
    """`sessions[i]` 는 (오늘 - 7*i)일에 완료 처리된 운동 이름 목록."""
    db = SessionLocal()
    try:
        for index, exercises in enumerate(sessions):
            day = clock.today() - timedelta(days=7 * index)
            db.add(
                RoutineHistory(
                    id=f"hist-{member_id}-{index}",
                    member_id=member_id,
                    trainer_id=TRAINER_ID,
                    date=day.isoformat(),
                    completion_rate=80,
                    exercises_json=json.dumps(exercises, ensure_ascii=False),
                )
            )
        db.commit()
    finally:
        db.close()


def _seed_latest_assigned_routine(
    member_id: str,
    *,
    minutes: int,
    type_: str,
    status: str = "approved",
    id_suffix: str = "",
    created_at: object = None,
) -> None:
    db = SessionLocal()
    try:
        row = TrainerRoutine(
            id=f"assigned-{member_id}{id_suffix}",
            trainer_id=TRAINER_ID,
            member_id=member_id,
            name="이전 배정 루틴",
            minutes=minutes,
            type=type_,
            reason="",
            source="trainer",
            status=status,
        )
        if created_at is not None:
            row.created_at = created_at
        db.add(row)
        db.commit()
    finally:
        db.close()


def _six_weeks_of_squats_with_a_varying_extra() -> list[list[str]]:
    """스쿼트만 매주 반복하고 나머지 한 종목은 매번 바꾼다 — "스쿼트"만 반복
    이름으로 잡혀야 한다(#776 personalized 판정에 반복 운동 근거로 쓴다)."""
    fillers = ["플랭크", "런지", "버피", "힙쓰러스트", "마운틴클라이머", "사이드 플랭크"]
    return [[f"스쿼트 3세트", f"{name} 2세트"] for name in fillers]


def _seed_memo(
    member_id: str,
    *,
    suffix: str,
    body: str,
    days_ago: int,
    source: str = "chat_insight",
) -> None:
    """`days_ago` 일 전 KST 정오에 남긴 메모 한 건(#1655)."""
    db = SessionLocal()
    try:
        db.add(
            TrainerClientMemo(
                id=f"memo-{member_id}-{suffix}",
                trainer_id=TRAINER_ID,
                member_id=member_id,
                body=body,
                source=source,
                insight_id=(
                    f"seed-chat-{member_id}-{suffix}:discomfort"
                    if source == "chat_insight"
                    else None
                ),
                insight_kind="discomfort" if source == "chat_insight" else "",
                created_at=datetime.combine(
                    clock.today() - timedelta(days=days_ago),
                    time_of_day(12, 0),
                    tzinfo=clock.SEOUL,
                ),
            )
        )
        db.commit()
    finally:
        db.close()


def _cleanup_member(member_id: str) -> None:
    db = SessionLocal()
    try:
        db.query(TrainerClientMemo).filter(
            TrainerClientMemo.member_id == member_id
        ).delete()
        db.query(TrainerSchedule).filter(
            TrainerSchedule.member_id == member_id
        ).delete()
        db.query(MemberWeeklyFeedback).filter(
            MemberWeeklyFeedback.user_id == member_id
        ).delete()
        db.query(RoutineHistory).filter(
            RoutineHistory.member_id == member_id
        ).delete()
        db.query(TrainerRoutine).filter(
            TrainerRoutine.member_id == member_id
        ).delete()
        db.query(TrainerClient).filter(TrainerClient.member_id == member_id).delete()
        db.commit()
    finally:
        db.close()


@dataclass
class _Result:
    text: str


class _FakeLlm:
    def __init__(self, text: str) -> None:
        self._text = text
        #: 마지막 호출에 넘어온 생성 옵션. 사고 예산이 빠지면 상시 폴백으로
        #: 떨어지므로(#579) 테스트가 이 값을 직접 확인한다.
        self.last_kwargs: dict[str, object] = {}

    def generate(
        self, system_prompt: str, user_prompt: str, **kwargs: object
    ) -> _Result:
        assert "member_analysis" in user_prompt
        assert "JSON" in system_prompt
        self.last_kwargs = kwargs
        return _Result(self._text)


def _analysis() -> RoutineOptionAnalysisOut:
    return RoutineOptionAnalysisOut(
        goal="체중 감량",
        sodium_today_mg=2200,
        sodium_over_target=True,
        avg_completion_rate=65,
        latest_routine="걷기",
        note="무릎 부담 낮게",
    )


def test_routine_categories_match_the_member_app():
    """유형은 네 가지다 — 유산소 / 근력 / 스트레칭 / 기타. (#996)"""
    for category in ("유산소", "근력", "스트레칭", "기타"):
        exercise = RoutineOptionExerciseOut(
            name="테스트 운동", minutes=10, type=category
        )
        assert exercise.type == category

    with pytest.raises(ValidationError):
        RoutineOptionExerciseOut(name="테스트 운동", minutes=10, type="미지원")


def test_legacy_categories_are_folded_not_refused():
    """옛 값으로 오는 요청을 422 로 막지 않는다.

    유형 하나가 옛 이름이라고 배정이 통째로 실패하는 편이, 걷기를 유산소로
    적어 두는 것보다 나쁘다. 모르는 값은 그대로 거절한다(위 테스트).
    """
    for legacy, folded in (("걷기", "유산소"), ("요가", "스트레칭"), ("유연성", "스트레칭")):
        exercise = RoutineOptionExerciseOut(
            name="테스트 운동", minutes=10, type=legacy
        )
        assert exercise.type == folded


def test_rule_fallback_respects_requested_minutes():
    request = RoutineOptionsRequest(
        available_minutes=40,
        intensity_preference="high",
        trainer_note="무릎 부담 낮게",
    )

    result = trainer_routine_options_service.build_rule_options(
        _analysis(),
        request,
    )

    assert result.generated_by == "rule"
    assert result.plan_a.total_minutes <= 40
    assert result.plan_b.total_minutes == 40
    assert sum(item.minutes for item in result.plan_b.exercises) == 40
    assert "무릎 부담 낮게" in result.plan_b.rationale


def test_public_generator_falls_back_for_malformed_llm(monkeypatch):
    request = RoutineOptionsRequest(available_minutes=30)
    monkeypatch.setattr(
        trainer_routine_options_service,
        "build_member_analysis",
        lambda *_: _analysis(),
    )
    monkeypatch.setattr(
        trainer_routine_options_service,
        "get_coach_llm",
        lambda: _FakeLlm('{"plan_a": {"key": "A"}}'),
    )

    result = trainer_routine_options_service.generate_routine_options(
        object(),
        "trainer",
        "member",
        request,
    )

    assert result.generated_by == "rule"


def test_routine_options_uses_valid_llm_json(client, monkeypatch):
    token = _trainer_token(client)
    member_id = _first_client_id(client, token)
    monkeypatch.setattr(
        trainer_routine_options_service,
        "get_coach_llm",
        lambda: _FakeLlm(_VALID_LLM_JSON),
    )

    response = client.post(
        f"/v1/trainer/clients/{member_id}/routine-options",
        headers=_headers(token),
        json={
            "available_minutes": 30,
            "intensity_preference": "moderate",
            "trainer_note": "무릎 부담 낮게",
        },
    )

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["generated_by"] == "ai"
    assert body["plan_a"]["label"] == "관절 회복형"
    assert body["plan_b"]["total_minutes"] == 30
    assert body["analysis"]["note"] == "무릎 부담 낮게"


def test_routine_options_falls_back_when_llm_contract_is_invalid(
    client,
    monkeypatch,
):
    token = _trainer_token(client)
    member_id = _first_client_id(client, token)
    monkeypatch.setattr(
        trainer_routine_options_service,
        "get_coach_llm",
        lambda: _FakeLlm('{"plan_a": {"key": "A"}}'),
    )

    response = client.post(
        f"/v1/trainer/clients/{member_id}/routine-options",
        headers=_headers(token),
        json={"available_minutes": 40, "intensity_preference": "high"},
    )

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["generated_by"] == "rule"
    assert body["plan_a"]["total_minutes"] <= 40
    assert body["plan_b"]["total_minutes"] == 40


def test_routine_options_rejects_unowned_member_before_ai_call(
    client,
    monkeypatch,
):
    token = _trainer_token(client)

    def _unexpected_llm():
        raise AssertionError("LLM must not run for an unowned member")

    monkeypatch.setattr(
        trainer_routine_options_service,
        "get_coach_llm",
        _unexpected_llm,
    )
    response = client.post(
        "/v1/trainer/clients/not-owned/routine-options",
        headers=_headers(token),
        json={"available_minutes": 30},
    )

    assert response.status_code == 404


def test_llm_is_called_with_json_mode_and_thinking_budget(monkeypatch):
    """루틴 생성이 사고 예산과 json_mode 를 **함께** 넘긴다 (#579).

    이 옵션이 빠지면 `gemini-flash-latest` 는 짧은 JSON 하나에도 10초 이상 걸려
    (실측 10.9~12.8초) 클라이언트가 먼저 끊고, 트레이너는 AI 결과 대신 규칙형만
    보게 된다. 옵션을 주면 4.0~6.4초로 떨어진다.

    json_mode 만 켜면 오히려 크게 느려지므로 둘을 함께 확인한다.
    """
    fake = _FakeLlm(_VALID_LLM_JSON)
    monkeypatch.setattr(
        trainer_routine_options_service, "get_coach_llm", lambda: fake
    )

    result = trainer_routine_options_service._generate_with_llm(
        _analysis(),
        RoutineOptionsRequest(
            available_minutes=30, intensity_preference="moderate", trainer_note=""
        ),
    )

    assert result.generated_by == "ai"
    assert fake.last_kwargs.get("json_mode") is True
    assert fake.last_kwargs.get("thinking_budget") == DEFAULT_THINKING_BUDGET
    assert fake.last_kwargs["thinking_budget"], "budget=0 은 모델이 400 으로 거부한다"


def test_routine_and_diet_paths_share_one_thinking_budget():
    """두 LLM 경로가 같은 상수를 본다 — 한쪽만 누락되는 것이 #579 의 원인이었다."""
    from app.services import diet_recommendation_service

    assert diet_recommendation_service.LLM_THINKING_BUDGET == DEFAULT_THINKING_BUDGET
    assert (
        trainer_routine_options_service.LLM_THINKING_BUDGET
        == DEFAULT_THINKING_BUDGET
    )


# ---- LLM 타임아웃·동시성 가드 (#584) ----
#
# 이 절의 테스트는 모두 `_call_llm` 을 직접 부른다. 엔드포인트를 거치면 느린
# LLM 을 흉내내는 동안 DB 세션까지 물고 있어야 해서, 정작 검증하려는 성질
# (요청 스레드가 언제 풀려나는가)이 다른 대기에 묻힌다.


class _BlockingLlm:
    """호출부가 풀어 줄 때까지 응답하지 않는 LLM — 죽지도 않고 답도 없는 상태."""

    def __init__(self) -> None:
        self.released = threading.Event()
        self.entered = threading.Event()

    def generate(self, system_prompt: str, user_prompt: str, **kwargs: object):
        self.entered.set()
        self.released.wait(timeout=30)
        return _Result(_VALID_LLM_JSON)


@pytest.fixture
def blocking_llm(monkeypatch):
    """응답하지 않는 LLM 을 물리고, 테스트가 끝나면 반드시 풀어 준다.

    풀어 주지 않으면 워커가 남은 채 다음 테스트로 넘어가 뒤에서 엉뚱한 포화가 난다.
    """
    fake = _BlockingLlm()
    monkeypatch.setattr(
        trainer_routine_options_service, "get_coach_llm", lambda: fake
    )
    try:
        yield fake
    finally:
        fake.released.set()


def test_unresponsive_llm_gives_up_within_the_timeout(monkeypatch, blocking_llm):
    """응답하지 않는 LLM 에서도 요청이 정해진 시간 안에 끝난다 (#584).

    이 가드가 없으면 끊어 주는 건 SDK 의 HTTP 타임아웃뿐이라 Gemini 30초,
    OpenAI/LiteLLM 60초 동안 워커 하나가 통째로 묶인다.
    """
    monkeypatch.setattr(trainer_routine_options_service, "LLM_TIMEOUT_SEC", 0.3)

    started = time.monotonic()
    with pytest.raises(FutureTimeout):
        trainer_routine_options_service._call_llm("prompt")
    elapsed = time.monotonic() - started

    assert blocking_llm.entered.is_set(), "LLM 을 부르지도 않아 타임아웃이 검증되지 않았다"
    # 상한을 **설정값 기준**으로 잡는다. 고정 상수로 두면 타임아웃이 그 아래
    # 아무 값으로 회귀해도(예: 설정을 무시하고 4초) 테스트가 그대로 통과한다.
    # 여유 2초는 CI 러너에서 스레드가 뜨는 시간 몫이다.
    limit = trainer_routine_options_service.LLM_TIMEOUT_SEC + 2.0
    assert elapsed < limit, f"타임아웃이 걸리지 않았다({elapsed:.1f}s > {limit:.1f}s)"


def test_saturated_pool_falls_back_without_waiting(monkeypatch, blocking_llm):
    """빈 자리가 없으면 큐에서 기다리지 않고 즉시 포화로 알린다 (#584).

    기다려 봐야 타임아웃인데 그동안 요청 스레드만 붙잡힌다.
    """
    monkeypatch.setattr(
        trainer_routine_options_service, "_llm_slots", threading.BoundedSemaphore(1)
    )
    trainer_routine_options_service._llm_slots.acquire()  # 유일한 자리를 미리 점유

    started = time.monotonic()
    with pytest.raises(trainer_routine_options_service.LLMBusyError):
        trainer_routine_options_service._call_llm("prompt")
    elapsed = time.monotonic() - started

    assert elapsed < trainer_routine_options_service.LLM_TIMEOUT_SEC
    assert not blocking_llm.entered.is_set(), "포화 상태인데 LLM 을 불렀다"


def test_concurrent_requests_do_not_exhaust_the_worker_pool(monkeypatch, blocking_llm):
    """동시 요청이 한도를 넘겨도 초과분은 큐에 쌓이지 않고 곧장 폴백으로 내려간다.

    쌓이게 두면 워커가 전부 묶인 뒤 새 요청이 LLM 을 불러 보지도 못한 채 큐에서
    타임아웃까지 기다린다 — 규칙형만 나오면서 응답만 느려지는 최악의 조합이다.
    """
    limit = 2
    monkeypatch.setattr(
        trainer_routine_options_service,
        "_llm_slots",
        threading.BoundedSemaphore(limit),
    )
    monkeypatch.setattr(trainer_routine_options_service, "LLM_TIMEOUT_SEC", 0.3)

    outcomes: list[str] = []
    lock = threading.Lock()

    def _attempt() -> None:
        try:
            trainer_routine_options_service._call_llm("prompt")
            result = "ok"
        except trainer_routine_options_service.LLMBusyError:
            result = "busy"
        except FutureTimeout:
            result = "timeout"
        with lock:
            outcomes.append(result)

    threads = [threading.Thread(target=_attempt) for _ in range(6)]
    started = time.monotonic()
    for t in threads:
        t.start()
    for t in threads:
        t.join(timeout=10)
    elapsed = time.monotonic() - started

    assert not any(t.is_alive() for t in threads), "요청 스레드가 풀려나지 못했다"
    assert len(outcomes) == 6
    # 자리를 잡은 쪽은 타임아웃까지 가고, 초과분은 기다리지 않고 즉시 포화로 끝난다.
    assert outcomes.count("busy") == 6 - limit
    assert outcomes.count("timeout") == limit
    # 초과분이 큐에서 순서를 기다렸다면 타임아웃이 직렬로 누적됐을 것이다.
    assert elapsed < 5.0, f"초과 요청이 큐에서 기다렸다({elapsed:.1f}s)"


def test_slots_are_returned_after_a_timeout(monkeypatch, blocking_llm):
    """타임아웃으로 호출부가 떠난 뒤에도 작업이 끝나면 자리를 돌려준다.

    `future.result(timeout=...)` 은 기다리기를 포기할 뿐 작업을 취소하지 않는다.
    돌려주지 않으면 타임아웃 한 번마다 동시성 한도가 영구히 1씩 줄어, 결국 모든
    요청이 포화로 떨어진다.
    """
    slots = threading.BoundedSemaphore(1)
    monkeypatch.setattr(trainer_routine_options_service, "_llm_slots", slots)
    monkeypatch.setattr(trainer_routine_options_service, "LLM_TIMEOUT_SEC", 0.3)

    with pytest.raises(FutureTimeout):
        trainer_routine_options_service._call_llm("prompt")

    blocking_llm.released.set()  # 버려진 작업을 끝내 준다
    assert slots.acquire(timeout=5), "타임아웃 뒤 자리가 반환되지 않았다"


@pytest.mark.parametrize(
    ("failure", "reason"),
    [
        (lambda: trainer_routine_options_service.LLMBusyError("포화"), "busy"),
        (lambda: FutureTimeout(), "timeout"),
    ],
)
def test_guard_failures_return_a_rule_fallback_and_are_counted_apart(
    client, monkeypatch, failure, reason,
):
    """포화·타임아웃도 200 + 규칙 폴백으로 끝나고, 사유는 따로 센다 (#584).

    사유를 나누는 이유는 대응이 다르기 때문이다 — `busy` 는 동시성 한도를,
    `timeout` 은 공급자·모델 옵션을, `contract` 은 프롬프트를 보라는 신호다.
    한 칸에 몰아 세면 이 셋이 지표에서 구분되지 않는다.
    """
    def _raise(*args, **kwargs):
        raise failure()

    monkeypatch.setattr(
        trainer_routine_options_service, "_generate_with_llm", _raise
    )
    token = _trainer_token(client)
    member_id = _first_client_id(client, token)
    metrics.reset()

    response = client.post(
        f"/v1/trainer/clients/{member_id}/routine-options",
        headers=_headers(token),
        json={"available_minutes": 40, "intensity_preference": "high"},
    )

    assert response.status_code == 200, response.text
    assert response.json()["generated_by"] == "rule"

    counters = metrics.snapshot()["counters"]
    assert counters[f"routine_options.fallback{{reason={reason}}}"] == 1
    assert counters["routine_options.generated{by=rule}"] == 1
    other_reasons = [
        k for k in counters
        if k.startswith("routine_options.fallback")
        and k != f"routine_options.fallback{{reason={reason}}}"
    ]
    assert not other_reasons, f"사유가 섞였다: {other_reasons}"


def test_slot_is_returned_to_the_semaphore_it_was_taken_from(monkeypatch, blocking_llm):
    """워커는 자리를 딴 그 인스턴스에 돌려준다 — 전역이 바뀌어도.

    워커가 `_llm_slots` 전역을 다시 읽으면, 그 사이 전역이 교체됐을 때 잡지도 않은
    세마포어를 풀어 준다. 원래 자리는 영영 안 돌아오고, 교체된 쪽은 초기값을 넘겨
    `BoundedSemaphore` 가 ValueError 를 던진다.
    """
    original = threading.BoundedSemaphore(1)
    replacement = threading.BoundedSemaphore(1)
    monkeypatch.setattr(trainer_routine_options_service, "_llm_slots", original)
    monkeypatch.setattr(trainer_routine_options_service, "LLM_TIMEOUT_SEC", 0.3)

    with pytest.raises(FutureTimeout):
        trainer_routine_options_service._call_llm("prompt")

    # 호출부가 떠난 뒤 전역이 갈린다. 아직 워커는 블로킹 중이다.
    monkeypatch.setattr(trainer_routine_options_service, "_llm_slots", replacement)
    blocking_llm.released.set()

    assert original.acquire(timeout=5), "자리를 딴 세마포어에 돌려주지 않았다"
    # 교체본은 건드리지 않았어야 한다. 건드렸다면 초과 release 로 이미 깨졌다.
    assert replacement.acquire(blocking=False), "엉뚱한 세마포어를 풀어 줬다"


def test_slot_is_returned_when_scheduling_fails(monkeypatch):
    """`submit()` 이 실패하면 워커가 돌지 않으므로 자리를 여기서 돌려줘야 한다.

    돌려주지 않으면 실패 한 번마다 동시 호출 한도가 영구히 1씩 줄어, 끝내 모든
    요청이 포화로 떨어진다.
    """
    slots = threading.BoundedSemaphore(1)
    monkeypatch.setattr(trainer_routine_options_service, "_llm_slots", slots)

    class _DeadExecutor:
        def submit(self, fn):
            raise RuntimeError("cannot schedule new futures after shutdown")

    monkeypatch.setattr(trainer_routine_options_service, "_executor", _DeadExecutor())

    with pytest.raises(RuntimeError):
        trainer_routine_options_service._call_llm("prompt")

    assert slots.acquire(blocking=False), "스케줄링 실패로 자리가 누수됐다"


# ---- 데이터 축적도에 따른 추천 상태 분기 (#776) ----
#
# 세 테스트 모두 LLM 을 계약 위반으로 강제 폴백시킨다 — 여기서 보는 것은
# `recommendation_status` 등 분석 필드지 LLM 문장 자체가 아니고, 실제 LLM을
# 부르면 네트워크/키 여부에 테스트 결과가 흔들린다.


def _force_rule_fallback(monkeypatch) -> None:
    monkeypatch.setattr(
        trainer_routine_options_service,
        "get_coach_llm",
        lambda: _FakeLlm('{"plan_a": {"key": "A"}}'),
    )


def test_recommendation_status_is_template_without_history(client, monkeypatch):
    """기록이 거의 없는 신규 고객은 목표 기반 기본 추천으로 표시된다."""
    _force_rule_fallback(monkeypatch)
    token = _trainer_token(client)
    member_id = _register_and_link_member(client)
    try:
        response = client.post(
            f"/v1/trainer/clients/{member_id}/routine-options",
            headers=_headers(token),
            json={},
        )
        assert response.status_code == 200, response.text
        body = response.json()
        analysis = body["analysis"]
        assert analysis["recommendation_status"] == "template"
        assert analysis["frequent_exercises"] == []
        assert analysis["suggested_available_minutes"] is None
        assert analysis["suggested_intensity"] is None
        # 조건을 비웠으니 서버 기본값(30분)으로 생성돼야 한다.
        assert body["plan_b"]["total_minutes"] == (
            trainer_routine_options_service.DEFAULT_AVAILABLE_MINUTES
        )
    finally:
        _cleanup_member(member_id)


def test_recommendation_status_is_learning_with_a_few_recent_sessions(
    client, monkeypatch,
):
    """최근 운동은 있지만 반복 패턴이라 부르기엔 이른 고객은 학습 중으로 표시된다."""
    _force_rule_fallback(monkeypatch)
    token = _trainer_token(client)
    member_id = _register_and_link_member(client)
    # 서로 다른 운동 3회 — 세션은 있지만 반복은 없다.
    _seed_routine_history(
        member_id,
        [["레그프레스 3세트"], ["플랭크 2세트"], ["실내 자전거 20분"]],
    )
    try:
        response = client.post(
            f"/v1/trainer/clients/{member_id}/routine-options",
            headers=_headers(token),
            json={},
        )
        assert response.status_code == 200, response.text
        analysis = response.json()["analysis"]
        assert analysis["recommendation_status"] == "learning"
        assert analysis["history_session_count"] == 3
    finally:
        _cleanup_member(member_id)


def test_recommendation_status_is_personalized_with_repeated_weekly_pattern(
    client, monkeypatch,
):
    """여러 주에 걸쳐 반복된 운동이 있으면 개인화 추천으로 표시되고, 규칙 폴백도
    반복 운동을 유지형/강화형 A·B 로 구성한다."""
    _force_rule_fallback(monkeypatch)
    token = _trainer_token(client)
    member_id = _register_and_link_member(client)
    _seed_latest_assigned_routine(member_id, minutes=45, type_="근력")
    # 6주 연속, 매번 스쿼트를 반복하고 나머지 한 종목만 바꾼다.
    _seed_routine_history(member_id, _six_weeks_of_squats_with_a_varying_extra())
    try:
        response = client.post(
            f"/v1/trainer/clients/{member_id}/routine-options",
            headers=_headers(token),
            json={},
        )
        assert response.status_code == 200, response.text
        body = response.json()
        analysis = body["analysis"]
        assert analysis["recommendation_status"] == "personalized"
        assert analysis["history_session_count"] == 6
        assert "스쿼트" in analysis["frequent_exercises"]
        # 이전 배정 루틴(45분/근력)에서 조건을 자동으로 채운다.
        assert analysis["suggested_available_minutes"] == 45
        assert analysis["suggested_intensity"] == "high"

        assert body["plan_a"]["label"] == "기존 패턴 유지형"
        assert body["plan_b"]["label"] == "점진적 강화형"
        assert any("스쿼트" in e["name"] for e in body["plan_a"]["exercises"])
        # A안(유지형)은 요청 시간의 ~75%만, B안(강화형)은 전부 쓴다 — 유지와
        # 확대가 시간상으로도 구분돼야 한다는 계약은 데이터 부족 경로와 같다.
        assert body["plan_a"]["total_minutes"] < body["plan_b"]["total_minutes"]
        assert body["plan_b"]["total_minutes"] == 45
    finally:
        _cleanup_member(member_id)


def test_pending_or_dismissed_routines_do_not_leak_into_suggested_conditions(
    client, monkeypatch,
):
    """검토 대기중이거나 반려된 AI 후보는 아직 회원에게 나가지 않았다 — 그
    시간·강도가 다음 생성의 자동 조건에 새면 안 된다."""
    _force_rule_fallback(monkeypatch)
    token = _trainer_token(client)
    member_id = _register_and_link_member(client)
    _seed_latest_assigned_routine(member_id, minutes=45, type_="근력")
    # 승인된 루틴보다 더 최근에, 아직 검토 대기중인 후보가 생겼다.
    _seed_latest_assigned_routine(
        member_id,
        minutes=15,
        type_="스트레칭",
        status="pending",
        id_suffix="-pending",
        created_at=clock.now() + timedelta(minutes=1),
    )
    _seed_routine_history(member_id, _six_weeks_of_squats_with_a_varying_extra())
    try:
        response = client.post(
            f"/v1/trainer/clients/{member_id}/routine-options",
            headers=_headers(token),
            json={},
        )
        assert response.status_code == 200, response.text
        analysis = response.json()["analysis"]
        # pending 후보(15분/스트레칭)가 아니라 승인된 루틴(45분/근력)을 근거로 삼는다.
        assert analysis["suggested_available_minutes"] == 45
        assert analysis["suggested_intensity"] == "high"
    finally:
        _cleanup_member(member_id)


def test_trainer_supplied_conditions_always_win_over_suggestions(client, monkeypatch):
    """트레이너가 조건을 직접 넣으면 분석이 제안한 값을 덮어써도 그 값을 쓴다."""
    _force_rule_fallback(monkeypatch)
    token = _trainer_token(client)
    member_id = _register_and_link_member(client)
    _seed_latest_assigned_routine(member_id, minutes=45, type_="근력")
    _seed_routine_history(member_id, _six_weeks_of_squats_with_a_varying_extra())
    try:
        response = client.post(
            f"/v1/trainer/clients/{member_id}/routine-options",
            headers=_headers(token),
            json={"available_minutes": 20, "intensity_preference": "low"},
        )
        assert response.status_code == 200, response.text
        body = response.json()
        assert body["plan_b"]["total_minutes"] == 20
    finally:
        _cleanup_member(member_id)


def test_exercise_name_strips_the_free_text_set_count():
    fn = trainer_routine_options_service._exercise_name
    assert fn("레그프레스 3세트") == "레그프레스"
    assert fn("실내 자전거 20분") == "실내 자전거"
    assert fn({"name": "플랭크", "type": "근력"}) == "플랭크"
    assert fn(123) == ""


def test_guess_intensity_maps_exercise_type_to_a_preference():
    fn = trainer_routine_options_service._guess_intensity
    assert fn("근력") == "high"
    assert fn("스트레칭") == "low"
    assert fn("요가") == "low"
    assert fn("유산소") == "moderate"


def test_resolve_conditions_fills_blanks_from_analysis_then_defaults():
    """`_resolve_conditions` 단독 계약 — 분석값 우선, 없으면 기본값, 트레이너
    입력이 있으면 항상 그 값을 유지한다."""
    resolve = trainer_routine_options_service._resolve_conditions

    analysis_with_suggestion = _analysis().model_copy(
        update={"suggested_available_minutes": 50, "suggested_intensity": "low"}
    )
    resolved = resolve(analysis_with_suggestion, RoutineOptionsRequest())
    assert resolved.available_minutes == 50
    assert resolved.intensity_preference == "low"

    resolved_default = resolve(_analysis(), RoutineOptionsRequest())
    assert (
        resolved_default.available_minutes
        == trainer_routine_options_service.DEFAULT_AVAILABLE_MINUTES
    )
    assert (
        resolved_default.intensity_preference
        == trainer_routine_options_service.DEFAULT_INTENSITY
    )

    explicit = RoutineOptionsRequest(available_minutes=15, intensity_preference="high")
    resolved_explicit = resolve(analysis_with_suggestion, explicit)
    assert resolved_explicit.available_minutes == 15
    assert resolved_explicit.intensity_preference == "high"


# ---- 건강 주의사항이 모든 생성 경로에 닿는다 (#1440) ----


def test_prompt_tells_the_model_to_use_conditions_and_body_data():
    """시스템 프롬프트가 주의사항·신체·목표를 어떻게 쓸지 명시한다."""
    prompt = trainer_routine_options_service._SYSTEM_PROMPT

    assert "conditions" in prompt
    assert "note" in prompt
    # 신체·목표는 강도·시간·구성을 정할 때만 쓰고, 제한으로 읽지 않는다.
    assert "height_cm" in prompt and "weight_kg" in prompt
    # 무엇이 반영됐는지 트레이너가 rationale 에서 볼 수 있어야 한다.
    assert "rationale" in prompt
    # 회원에게 보이는 문구에는 민감한 정보를 옮기지 않는다.
    assert "reason" in prompt


def test_rule_fallback_avoids_the_part_the_member_is_guarding():
    """LLM 이 죽어도 주의사항은 지킨다 — 무릎이면 러닝·스쿼트를 빼고 대안을 준다."""
    analysis = _analysis().model_copy(
        update={"conditions": "무릎 통증으로 러닝 자제", "note": ""}
    )

    options = trainer_routine_options_service.build_rule_options(
        analysis, RoutineOptionsRequest(available_minutes=40, intensity_preference="high")
    )

    names = [
        exercise.name
        for plan in (options.plan_a, options.plan_b)
        for exercise in plan.exercises
    ]
    assert not any("러닝" in name for name in names)
    assert not any("스쿼트" in name for name in names)
    assert names, "대안까지 사라져 빈 루틴이 되면 안 된다"
    # 무엇이 반영됐는지 트레이너가 읽을 수 있다.
    assert "무릎" in options.plan_b.rationale


def test_rule_fallback_reads_recent_messages_when_the_profile_is_silent():
    """건강 프로필이 비어 있어도 최근 대화의 통증 언급을 놓치지 않는다."""
    analysis = _analysis().model_copy(
        update={
            "conditions": "",
            "note": "",
            "recent_messages": ["회원: 어제부터 허리가 아파요"],
        }
    )

    options = trainer_routine_options_service.build_rule_options(
        analysis, RoutineOptionsRequest(available_minutes=40, intensity_preference="high")
    )

    names = [exercise.name for exercise in options.plan_b.exercises]
    assert not any("데드리프트" in name for name in names)
    assert "허리" in options.plan_b.rationale


def test_rule_fallback_does_not_raise_intensity_when_a_check_is_needed():
    """운동으로 답할 수 없는 상태에서는 강도를 올리지 않고 확인을 권한다."""
    analysis = _analysis().model_copy(
        update={"conditions": "최근 가슴 통증 있었음", "note": ""}
    )

    options = trainer_routine_options_service.build_rule_options(
        analysis, RoutineOptionsRequest(available_minutes=40, intensity_preference="high")
    )

    assert options.plan_b.intensity != "높음"
    assert "전문가" in options.plan_b.rationale


def test_rule_fallback_invents_nothing_when_the_profile_is_empty():
    """비어 있는 프로필에서 의학적 결론이나 임의 주의사항을 만들지 않는다."""
    analysis = _analysis().model_copy(
        update={"conditions": "", "note": "", "recent_messages": []}
    )

    options = trainer_routine_options_service.build_rule_options(
        analysis, RoutineOptionsRequest(available_minutes=40, intensity_preference="high")
    )

    assert "주의사항" not in options.plan_a.rationale
    assert "전문가" not in options.plan_b.rationale
    assert options.plan_a.exercises and options.plan_b.exercises


def test_rule_fallback_drops_a_repeated_exercise_that_now_hurts():
    """반복해 온 운동이라도 지금 아픈 부위에 부담이면 그대로 다시 내밀지 않는다."""
    analysis = _analysis().model_copy(
        update={
            "conditions": "무릎 통증",
            "note": "",
            "frequent_exercises": ["인터벌 러닝", "코어 스트레칭"],
        }
    )

    options = trainer_routine_options_service.build_rule_options(
        analysis, RoutineOptionsRequest(available_minutes=40, intensity_preference="high")
    )

    names = [
        exercise.name
        for plan in (options.plan_a, options.plan_b)
        for exercise in plan.exercises
    ]
    assert not any("러닝" in name for name in names)
    assert any("스트레칭" in name for name in names)


# ---- 채팅 감지 메모가 프로그램 생성에 닿는다 (#1655) ----


def test_analysis_carries_the_last_seven_days_of_chat_insight_memos(client):
    """분석은 최근 7일(KST)의 채팅 감지 메모만, 최신 먼저, 날짜와 함께 싣는다."""
    member_id = _register_and_link_member(client)
    try:
        _seed_memo(member_id, suffix="today", body="무릎 불편 감지", days_ago=0)
        _seed_memo(member_id, suffix="d3", body="운동 부담 감지", days_ago=3)
        # 창 밖(8일 전)과 손으로 쓴 메모는 이 자리의 자료가 아니다.
        _seed_memo(member_id, suffix="d8", body="어깨 불편 감지", days_ago=8)
        _seed_memo(
            member_id,
            suffix="manual",
            body="수업 시간 조정 요청",
            days_ago=0,
            source="trainer",
        )

        db = SessionLocal()
        try:
            analysis = trainer_routine_options_service.build_member_analysis(
                db, TRAINER_ID, member_id, RoutineOptionsRequest(),
            )
        finally:
            db.close()

        today = clock.today()
        assert analysis.insight_memos == [
            f"{today:%m.%d} 무릎 불편 감지",
            f"{today - timedelta(days=3):%m.%d} 운동 부담 감지",
        ]
    finally:
        _cleanup_member(member_id)


def test_prompt_tells_the_model_to_use_insight_memos():
    """프롬프트가 감지 메모를 안전 순서 안에서 어떻게 쓸지 명시한다."""
    prompt = trainer_routine_options_service._SYSTEM_PROMPT

    assert "insight_memos" in prompt
    # 반복되는 부위는 일회성 컨디션이 아니라 이어지는 신호로 본다.
    assert "부하" in prompt


def test_rule_fallback_avoids_the_part_named_by_an_insight_memo():
    """LLM 이 죽어도 감지 메모의 부위는 피한다 — 프로필·대화가 비어 있어도."""
    analysis = _analysis().model_copy(
        update={
            "conditions": "",
            "note": "",
            "recent_messages": [],
            "insight_memos": ["09.01 무릎 불편 감지"],
        }
    )

    options = trainer_routine_options_service.build_rule_options(
        analysis,
        RoutineOptionsRequest(available_minutes=40, intensity_preference="high"),
    )

    names = [
        exercise.name
        for plan in (options.plan_a, options.plan_b)
        for exercise in plan.exercises
    ]
    assert not any("러닝" in name for name in names)
    assert not any("스쿼트" in name for name in names)
    assert names, "대안까지 사라져 빈 루틴이 되면 안 된다"
    assert "무릎" in options.plan_b.rationale


def test_first_client_skips_an_ended_member_at_the_front(client, db_session):
    """담당이 끝난 회원이 로스터 맨 앞에 있어도 담당 중인 회원을 고른다. (#2471)"""
    member_id = f"ended-front-{uuid4().hex[:10]}"
    db_session.add(
        User(
            id=member_id,
            email=f"{member_id}@oncare.com",
            name="담당 끝난 회원",
            hashed_password="unused",
            role="member",
        )
    )
    db_session.commit()
    db_session.add(
        TrainerClient(
            id=f"link-{uuid4().hex[:12]}",
            trainer_id=TRAINER_ID,
            member_id=member_id,
            active=False,
            sort_order=-1,
        )
    )
    db_session.commit()
    try:
        token = _trainer_token(client)
        roster = client.get(
            "/v1/trainer/clients", headers=_headers(token)
        ).json()
        # 전제: 끝난 회원이 정말 맨 앞에 섰다.
        assert roster[0]["id"] == member_id
        assert roster[0]["registered"] is False

        picked = _first_client_id(client, token)

        assert picked != member_id
        assert next(c for c in roster if c["id"] == picked)["registered"] is True
    finally:
        db_session.rollback()
        db_session.execute(delete(User).where(User.id == member_id))
        db_session.commit()


# ---- AI 가 참고할 자료 (#2587, #2519) ----


def _seed_schedule(
    member_id: str,
    *,
    suffix: str,
    note: str,
    days_ago: int,
    type_: str = "1:1 PT",
    status: str = "완료",
    trainer_id: str = TRAINER_ID,
) -> None:
    db = SessionLocal()
    try:
        db.add(
            TrainerSchedule(
                id=f"sch-{member_id}-{suffix}",
                trainer_id=trainer_id,
                member_id=member_id,
                date=(clock.today() - timedelta(days=days_ago)).isoformat(),
                time="10:00",
                type=type_,
                status=status,
                note=note,
            )
        )
        db.commit()
    finally:
        db.close()


def _seed_weekly_feedback(
    member_id: str,
    *,
    weeks_ago: int,
    note: str = "",
    intensity: str = "right",
    pain_area: str = "",
) -> None:
    today = clock.today()
    monday = today - timedelta(days=today.weekday()) - timedelta(weeks=weeks_ago)
    db = SessionLocal()
    try:
        db.add(
            MemberWeeklyFeedback(
                id=f"mwf-{member_id}-{weeks_ago}",
                user_id=member_id,
                week_start=monday.isoformat(),
                condition="tired",
                intensity=intensity,
                pain_area=pain_area,
                note=note,
            )
        )
        db.commit()
    finally:
        db.close()


def _analysis_for(member_id: str, **request: object) -> RoutineOptionAnalysisOut:
    db = SessionLocal()
    try:
        return trainer_routine_options_service.build_member_analysis(
            db, TRAINER_ID, member_id, RoutineOptionsRequest(**request),
        )
    finally:
        db.close()


def _other_trainer() -> str:
    """다른 트레이너 한 명. 그의 글이 섞이지 않는지 보려고 쓴다."""
    trainer_id = f"trainer-other-{uuid4().hex[:8]}"
    db = SessionLocal()
    try:
        db.add(
            User(
                id=trainer_id,
                email=f"{trainer_id}@oncare.com",
                name="다른 트레이너",
                hashed_password="",
            )
        )
        db.commit()
    finally:
        db.close()
    return trainer_id


def _drop_user(user_id: str) -> None:
    db = SessionLocal()
    try:
        db.query(TrainerClientMemo).filter(
            TrainerClientMemo.trainer_id == user_id
        ).delete()
        db.query(TrainerSchedule).filter(
            TrainerSchedule.trainer_id == user_id
        ).delete()
        db.query(User).filter(User.id == user_id).delete()
        db.commit()
    finally:
        db.close()


def test_default_sources_leave_consult_memos_out(client):
    """고르지 않으면 상담 메모만 빼고 넣는다 — 범위도 자료마다 지킨다."""
    member_id = _register_and_link_member(client)
    try:
        _seed_schedule(member_id, suffix="pt1", note="스쿼트 자세 좋아짐", days_ago=1)
        # 창 밖(14일 전), 예정 일정, 상담 일정은 PT 피드백이 아니다.
        _seed_schedule(member_id, suffix="pt-old", note="오래된 피드백", days_ago=14)
        _seed_schedule(
            member_id, suffix="pt-plan", note="다음엔 하체", days_ago=0, status="예정"
        )
        _seed_schedule(
            member_id, suffix="consult", note="등록 상담 내용", days_ago=2, type_="상담"
        )
        _seed_memo(
            member_id, suffix="manual", body="무릎 부담 낮게", days_ago=3, source="trainer"
        )
        _seed_memo(
            member_id, suffix="manual-old", body="예전 메모", days_ago=14, source="trainer"
        )
        _seed_memo(member_id, suffix="insight", body="허리 불편 감지", days_ago=0)
        _seed_weekly_feedback(
            member_id, weeks_ago=0, note="이번 주 너무 바빴어요", intensity="too_hard"
        )

        analysis = _analysis_for(member_id)

        today = clock.today()
        assert analysis.sources == [
            "pt_feedback", "trainer_memo", "chat_insight", "weekly_feedback",
        ]
        assert analysis.pt_feedbacks == [
            f"{today - timedelta(days=1):%m.%d} 스쿼트 자세 좋아짐"
        ]
        assert analysis.consult_memos == []
        assert analysis.trainer_memos == [
            f"{today - timedelta(days=3):%m.%d} 무릎 부담 낮게"
        ]
        assert analysis.insight_memos == [f"{today:%m.%d} 허리 불편 감지"]
        assert len(analysis.weekly_feedback) == 1
        line = analysis.weekly_feedback[0]
        assert "강도 너무 힘듦" in line
        assert "한 줄 피드백: 이번 주 너무 바빴어요" in line
    finally:
        _cleanup_member(member_id)


def test_consult_memos_come_in_only_when_chosen_within_thirty_days(client):
    member_id = _register_and_link_member(client)
    try:
        _seed_schedule(
            member_id, suffix="c29", note="결혼식 전 감량", days_ago=29, type_="상담"
        )
        _seed_schedule(
            member_id, suffix="c30", note="너무 오래된 상담", days_ago=30, type_="상담"
        )

        analysis = _analysis_for(member_id, sources=["consult_memo"])

        assert analysis.sources == ["consult_memo"]
        assert analysis.consult_memos == [
            f"{clock.today() - timedelta(days=29):%m.%d} 결혼식 전 감량"
        ]
        # 상담 글은 PT 피드백 칸으로 새지 않는다.
        assert analysis.pt_feedbacks == []
    finally:
        _cleanup_member(member_id)


def test_turned_off_sources_reach_neither_prompt_nor_fallback(client, monkeypatch):
    """끈 자료는 프롬프트에도, 규칙 폴백의 주의사항에도 쓰이지 않는다."""
    member_id = _register_and_link_member(client)
    prompts: list[str] = []

    class _CapturingLlm(_FakeLlm):
        def generate(self, system_prompt, user_prompt, **kwargs):
            prompts.append(user_prompt)
            return super().generate(system_prompt, user_prompt, **kwargs)

    monkeypatch.setattr(
        trainer_routine_options_service,
        "get_coach_llm",
        lambda: _CapturingLlm('{"plan_a": {"key": "A"}}'),
    )
    try:
        _seed_memo(
            member_id, suffix="manual", body="무릎 통증 있음", days_ago=1, source="trainer"
        )
        _seed_memo(member_id, suffix="insight", body="무릎 불편 감지", days_ago=1)
        _seed_schedule(member_id, suffix="pt", note="무릎 아파함", days_ago=1)
        _seed_weekly_feedback(member_id, weeks_ago=0, pain_area="무릎")

        token = _trainer_token(client)
        response = client.post(
            f"/v1/trainer/clients/{member_id}/routine-options",
            headers=_headers(token),
            json={
                "available_minutes": 40,
                "intensity_preference": "high",
                "sources": [],
            },
        )

        assert response.status_code == 200, response.text
        body = response.json()
        assert body["generated_by"] == "rule"
        analysis = body["analysis"]
        assert analysis["sources"] == []
        for key in (
            "pt_feedbacks", "consult_memos", "trainer_memos",
            "insight_memos", "weekly_feedback",
        ):
            assert analysis[key] == [], key
        assert prompts and all("무릎" not in prompt for prompt in prompts)
        # 폴백도 무릎을 모른다 — 끈 자료로 피한 흔적이 근거에 남지 않는다.
        assert "무릎" not in body["plan_b"]["rationale"]
    finally:
        _cleanup_member(member_id)


def test_rule_fallback_avoids_the_part_named_by_a_chosen_trainer_memo():
    """켠 직접 작성 메모의 부위는 LLM 이 죽어도 피한다(#2519)."""
    analysis = _analysis().model_copy(
        update={
            "conditions": "",
            "note": "",
            "trainer_memos": ["09.01 무릎 통증 있음"],
        }
    )

    options = trainer_routine_options_service.build_rule_options(
        analysis,
        RoutineOptionsRequest(available_minutes=40, intensity_preference="high"),
    )

    names = [
        exercise.name
        for plan in (options.plan_a, options.plan_b)
        for exercise in plan.exercises
    ]
    assert not any("스쿼트" in name for name in names)
    assert "무릎" in options.plan_b.rationale


def test_other_trainers_writing_never_mixes_in(client):
    """다른 트레이너의 메모·일정 글은 어떤 자료를 켜도 들어오지 않는다."""
    member_id = _register_and_link_member(client)
    other = _other_trainer()
    try:
        _seed_memo(
            member_id, suffix="mine", body="내 메모", days_ago=1, source="trainer"
        )
        db = SessionLocal()
        try:
            db.add(
                TrainerClientMemo(
                    id=f"memo-{member_id}-other",
                    trainer_id=other,
                    member_id=member_id,
                    body="남의 메모",
                    source="trainer",
                )
            )
            db.commit()
        finally:
            db.close()
        _seed_schedule(
            member_id, suffix="other-pt", note="남의 피드백", days_ago=1, trainer_id=other
        )
        _seed_schedule(
            member_id,
            suffix="other-consult",
            note="남의 상담",
            days_ago=1,
            type_="상담",
            trainer_id=other,
        )

        analysis = _analysis_for(
            member_id,
            sources=[
                "pt_feedback", "consult_memo", "trainer_memo",
                "chat_insight", "weekly_feedback",
            ],
        )

        assert analysis.trainer_memos == [
            f"{clock.today() - timedelta(days=1):%m.%d} 내 메모"
        ]
        assert analysis.pt_feedbacks == []
        assert analysis.consult_memos == []
    finally:
        _cleanup_member(member_id)
        _drop_user(other)


def test_weekly_feedback_starts_from_the_week_the_link_began(client):
    """담당이 이번 주에 시작됐으면 지난주 피드백(이전 트레이너 시절)은 뺀다."""
    member_id = _register_and_link_member(client)
    try:
        db = SessionLocal()
        try:
            link = db.query(TrainerClient).filter(
                TrainerClient.member_id == member_id
            ).one()
            link.data_consent_at = clock.now()
            db.commit()
        finally:
            db.close()
        _seed_weekly_feedback(member_id, weeks_ago=0, note="이번 주")
        _seed_weekly_feedback(member_id, weeks_ago=1, note="지난주")

        analysis = _analysis_for(member_id, sources=["weekly_feedback"])

        assert len(analysis.weekly_feedback) == 1
        assert "이번 주" in analysis.weekly_feedback[0]
    finally:
        _cleanup_member(member_id)


def test_ended_link_reads_no_sources_at_all(client):
    """담당이 해제된 회원은 어떤 자료도 읽기 전에 막힌다."""
    member_id = _register_and_link_member(client)
    try:
        _seed_memo(
            member_id, suffix="manual", body="무릎 통증", days_ago=1, source="trainer"
        )
        db = SessionLocal()
        try:
            db.query(TrainerClient).filter(
                TrainerClient.member_id == member_id
            ).update({"active": False})
            db.commit()
        finally:
            db.close()

        with pytest.raises(ValueError):
            _analysis_for(member_id, sources=["trainer_memo"])
    finally:
        _cleanup_member(member_id)


def test_prompt_guards_the_new_sources():
    """새 자료마다 신뢰 경계가 프롬프트에 붙는다(#2587)."""
    prompt = trainer_routine_options_service._SYSTEM_PROMPT

    for key in (
        "pt_feedbacks", "consult_memos", "trainer_memos", "weekly_feedback", "sources",
    ):
        assert key in prompt, key
    assert prompt_safety.TRAINER_RECORD_GUARD in prompt
    assert prompt_safety.MEMBER_FEEDBACK_GUARD in prompt
