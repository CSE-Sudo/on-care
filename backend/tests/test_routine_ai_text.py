"""AI 운동 추천의 문장과 근거 코드. (#2301, #3404)

지키는 계약은 넷이다.

1. **근거는 코드다.** 자동 후보의 근거는 코드로 저장·전달되고, 트레이너 웹이
   문구를 붙인다. 코드로 바꾸기 전에 문장으로 저장된 행도 읽을 때 코드로 되돌린다.
2. **AI·규칙형 출력은 한국어다.** 서버는 `Accept-Language` 를 읽지 않는다 —
   `en` 을 보내도 헤더 없는 요청과 같은 문장이다. `intensity`·`type` 은 계약값이다.
3. **시작 템플릿도 한국어다.** 저장된 템플릿(트레이너가 쓴 글)은 그대로 돌려준다.
4. **회원에게 가는 사유는 트레이너가 보낸 그대로다.**
"""
from __future__ import annotations

import json
import re
from uuid import uuid4

import pytest
from sqlalchemy import select

from app.core.security import hash_password
from app.db.session import SessionLocal
from app.models.models import TrainerProgramTemplate, TrainerRoutine, User
from app.schemas.trainer_api import (
    RoutineOptionAnalysisOut,
    RoutineOptionPlanOut,
    RoutineOptionsRequest,
)
from app.services import routine_ai
from app.services import routine_suggestion_service as suggestions
from app.services import trainer_program_template_service as templates
from app.services import trainer_routine_options_service as options_service
from app.services.trainer import _common as trainer_common_service

_HANGUL = re.compile(r"[가-힣]")

MEMBER = "user-jisu"
#: 혈압 관리가 필요한 시드 회원 — 걷기 후보와 혈압 근거가 나온다.
BP_MEMBER = "user-7d4e9a2c5f18"

EN = {"Accept-Language": "en"}
KO = {"Accept-Language": "ko"}


def _has_hangul(text: str) -> bool:
    return bool(_HANGUL.search(text))


def _h(token: str, extra: dict | None = None) -> dict:
    return {"Authorization": f"Bearer {token}", **(extra or {})}


def _trainer_token(client) -> str:
    res = client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    )
    assert res.status_code == 200, res.text
    return res.json()["access_token"]


def _member_token(client) -> str:
    res = client.post(
        "/v1/auth/login",
        data={"username": "jisu@oncare.com", "password": "oncare123"},
    )
    assert res.status_code == 200, res.text
    return res.json()["access_token"]


# ---------------------------------------------------------------------------
# 1. 근거 코드
# ---------------------------------------------------------------------------


def test_evidence_values_are_language_free_codes():
    for code in suggestions.EVIDENCE_CODES:
        assert re.fullmatch(r"[a-z_]+", code), code
        # 스키마(`RoutineSuggestionCreateRequest.evidence`) 길이 상한 안.
        assert 1 <= len(code) <= 40


def test_evidence_codes_are_unique():
    assert len(set(suggestions.EVIDENCE_CODES)) == len(suggestions.EVIDENCE_CODES)


def test_every_legacy_label_maps_to_a_known_code():
    assert set(suggestions.LEGACY_EVIDENCE_LABELS.values()) == set(
        suggestions.EVIDENCE_CODES
    )


@pytest.mark.parametrize(
    ("legacy", "code"),
    [
        ("최근 PT 피드백 반영", suggestions.EV_RECENT_PT),
        ("최근 근력운동 비중 높음", suggestions.EV_STRENGTH_HEAVY),
        ("혈압 관리 목표", suggestions.EV_BLOOD_PRESSURE),
        ("최근 유산소 비중 낮음", suggestions.EV_LOW_CARDIO),
        ("최근 운동 기록 반영", suggestions.EV_RECENT_RECORD),
    ],
)
def test_legacy_sentence_rows_are_read_back_as_codes(legacy, code):
    """코드로 바꾸기 전에 준비된 후보도 코드로 읽힌다."""
    assert trainer_common_service.suggestion_evidence(
        json.dumps([legacy], ensure_ascii=False)
    ) == [code]


def test_legacy_mapping_ignores_surrounding_whitespace():
    assert trainer_common_service.suggestion_evidence(
        json.dumps(["  혈압 관리 목표 "], ensure_ascii=False)
    ) == [suggestions.EV_BLOOD_PRESSURE]


def test_codes_and_free_text_pass_through_unchanged():
    """트레이너·다른 경로가 직접 넣은 문장은 코드가 아니어도 그대로 보인다."""
    raw = json.dumps(
        [suggestions.EV_LOW_CARDIO, "직접 적은 근거", "custom note"],
        ensure_ascii=False,
    )
    assert trainer_common_service.suggestion_evidence(raw) == [
        suggestions.EV_LOW_CARDIO,
        "직접 적은 근거",
        "custom note",
    ]


@pytest.mark.parametrize("raw", ["", "not json", "{}", '"text"', "[1, null, \"\"]"])
def test_broken_evidence_still_reads_as_an_empty_or_filtered_list(raw):
    assert trainer_common_service.suggestion_evidence(raw) == []


def test_mixed_legacy_and_code_rows_keep_order_and_item_limit():
    raw = json.dumps(
        [
            "혈압 관리 목표",
            suggestions.EV_LOW_CARDIO,
            "최근 PT 피드백 반영",
            "최근 운동 기록 반영",
            "최근 근력운동 비중 높음",
        ],
        ensure_ascii=False,
    )
    assert trainer_common_service.suggestion_evidence(raw) == [
        suggestions.EV_BLOOD_PRESSURE,
        suggestions.EV_LOW_CARDIO,
        suggestions.EV_RECENT_PT,
        suggestions.EV_RECENT_RECORD,
    ]


# ---------------------------------------------------------------------------
# 2-a. 개인운동 후보(규칙) — 이름·사유는 한국어, 근거는 코드
# ---------------------------------------------------------------------------

_ALL_SIGNALS = suggestions._Signals(
    pt_just_finished=True,
    trainer_feedback=True,
    strength_heavy=True,
    low_cardio=True,
    blood_pressure=True,
    has_records=True,
    total_minutes=240,
    strength_minutes=190,
    days_since_pt=2,
)
_RECORDS_ONLY = suggestions._Signals(has_records=True, total_minutes=60)


def test_korean_candidates_keep_their_exact_wording():
    """한국어 사유는 트레이너가 읽는 문장이다 — 회원 기록 숫자로 말한다(#2579)."""
    recovery, walking = suggestions._candidates_for(_ALL_SIGNALS)
    (light,) = suggestions._candidates_for(_RECORDS_ONLY)

    assert recovery.name == "하체·전신 회복 스트레칭"
    assert recovery.reason == (
        "최근 2주 운동 240분 중 190분(79%)이 근력이에요. "
        "2일 전 PT 가 있었어요. "
        "다음 PT 전까지 회복 스트레칭으로 풀어 두기 좋아요."
    )
    assert walking.name == "저강도 걷기"
    assert walking.reason == (
        "혈압 관리가 목표인데 최근 2주 유산소 기록이 없어요. "
        "대화할 수 있는 속도의 걷기부터 시작하기 좋아요."
    )
    assert light.name == "목·어깨 스트레칭"
    assert light.reason == (
        "최근 2주 기록에 치우침이나 건강 신호가 없어요. "
        "다음 PT 준비용으로 가장 가벼운 스트레칭만 두었어요."
    )


@pytest.mark.parametrize(
    ("signals", "expected"),
    [
        # PT 만 있고 편중이 없으면 며칠 전인지만 말한다.
        (
            suggestions._Signals(pt_just_finished=True, days_since_pt=0),
            "오늘 PT 가 있었어요. 다음 PT 전까지 회복 스트레칭으로 풀어 두기 좋아요.",
        ),
        # 근력 편중만 있으면 비율만 말한다.
        (
            suggestions._Signals(
                strength_heavy=True, total_minutes=100, strength_minutes=60
            ),
            "최근 2주 운동 100분 중 60분(60%)이 근력이에요. "
            "다음 PT 전까지 회복 스트레칭으로 풀어 두기 좋아요.",
        ),
    ],
)
def test_recovery_reason_says_only_the_signals_it_has(signals, expected):
    (recovery,) = suggestions._candidates_for(signals)
    assert recovery.reason == expected


@pytest.mark.parametrize(
    ("signals", "head"),
    [
        (suggestions._Signals(blood_pressure=True), "혈압 관리가 목표예요."),
        (
            suggestions._Signals(low_cardio=True, total_minutes=90),
            "최근 2주 운동 90분 중 유산소가 없어요.",
        ),
    ],
)
def test_walk_reason_names_the_signal(signals, head):
    (walking,) = suggestions._candidates_for(signals)
    assert walking.reason.startswith(head)


def test_candidate_evidence_is_always_codes():
    for signals in (_ALL_SIGNALS, _RECORDS_ONLY, suggestions._Signals(
        pt_just_finished=True, has_records=True
    )):
        for candidate in suggestions._candidates_for(signals):
            assert candidate.evidence
            assert set(candidate.evidence) <= set(suggestions.EVIDENCE_CODES)


def test_trainer_feedback_without_pt_uses_the_recent_pt_code():
    (light,) = suggestions._candidates_for(
        suggestions._Signals(trainer_feedback=True, has_records=True)
    )
    assert light.evidence == (suggestions.EV_RECENT_PT,)


def test_candidate_types_are_contract_values():
    for candidate in suggestions._candidates_for(_ALL_SIGNALS):
        assert candidate.type in {"스트레칭", "유산소"}


# ---------------------------------------------------------------------------
# 2-b. 개인운동 후보(API)
# ---------------------------------------------------------------------------


def _clear_prepared(member_id: str) -> None:
    db = SessionLocal()
    try:
        for row in db.scalars(
            select(TrainerRoutine).where(
                TrainerRoutine.member_id == member_id,
                TrainerRoutine.client_request_id.like("sug-%"),
            )
        ).all():
            db.delete(row)
        db.commit()
    finally:
        db.close()


@pytest.fixture()
def fresh(client):
    for member_id in (MEMBER, BP_MEMBER):
        _clear_prepared(member_id)
    yield _trainer_token(client)
    for member_id in (MEMBER, BP_MEMBER):
        _clear_prepared(member_id)


def _review_list(client, token: str, member_id: str, headers: dict | None = None):
    res = client.get(
        f"/v1/trainer/clients/{member_id}/routine-suggestions",
        headers=_h(token, headers),
    )
    assert res.status_code == 200, res.text
    return res.json()


@pytest.mark.parametrize("headers", [None, KO, EN])
def test_candidates_are_korean_whatever_the_header(client, fresh, headers):
    rows = _review_list(client, fresh, BP_MEMBER, headers)

    assert rows
    walking = [row for row in rows if row["name"] == "저강도 걷기"]
    assert walking, rows
    assert suggestions.EV_BLOOD_PRESSURE in walking[0]["evidence"]
    for row in rows:
        assert _has_hangul(row["name"])
        assert _has_hangul(row["reason"])
        # 근거는 코드다 — 문구는 앱이 붙인다.
        assert row["evidence"]
        assert set(row["evidence"]) <= set(suggestions.EVIDENCE_CODES)


def test_english_header_matches_no_header(client, fresh):
    with_header = _review_list(client, fresh, BP_MEMBER, EN)
    _clear_prepared(BP_MEMBER)
    without = _review_list(client, fresh, BP_MEMBER)

    def shape(rows):
        return [(r["name"], r["reason"], r["evidence"], r["minutes"]) for r in rows]

    assert shape(with_header) == shape(without)


def test_stored_evidence_column_holds_codes(client, fresh):
    _review_list(client, fresh, BP_MEMBER, EN)

    db = SessionLocal()
    try:
        rows = db.scalars(
            select(TrainerRoutine).where(
                TrainerRoutine.member_id == BP_MEMBER,
                TrainerRoutine.client_request_id.like("sug-%"),
            )
        ).all()
    finally:
        db.close()
    assert rows
    for row in rows:
        stored = json.loads(row.evidence_json)
        assert stored and set(stored) <= set(suggestions.EVIDENCE_CODES)


def test_prepared_candidates_are_served_as_written(client, fresh):
    """후보는 하루 한 번 준비한다 — 다시 열어도(헤더가 달라도) 같은 행·같은 문장이다."""
    first = _review_list(client, fresh, BP_MEMBER, EN)
    again = _review_list(client, fresh, BP_MEMBER, KO)

    assert [r["id"] for r in first] == [r["id"] for r in again]
    assert [r["name"] for r in first] == [r["name"] for r in again]
    assert [r["evidence"] for r in first] == [r["evidence"] for r in again]


def test_legacy_sentence_evidence_is_served_as_codes(client, fresh):
    """코드 도입 전에 준비된 검토 대기 후보도 API 에서는 코드로 나간다."""
    db = SessionLocal()
    row_id = f"legacy-ev-{uuid4().hex[:8]}"
    try:
        db.add(
            TrainerRoutine(
                id=row_id,
                trainer_id="trainer-demo",
                member_id=MEMBER,
                name="저강도 걷기",
                minutes=20,
                type="유산소",
                reason="",
                source="ai",
                status="pending",
                sort_order=999,
                evidence_json=json.dumps(
                    ["혈압 관리 목표", "최근 유산소 비중 낮음"], ensure_ascii=False
                ),
                client_request_id=f"legacy-{row_id}",
            )
        )
        db.commit()
        rows = _review_list(client, fresh, MEMBER, EN)
        legacy = [r for r in rows if r["id"] == row_id]
        assert legacy, rows
        assert legacy[0]["evidence"] == [
            suggestions.EV_BLOOD_PRESSURE,
            suggestions.EV_LOW_CARDIO,
        ]
    finally:
        found = db.get(TrainerRoutine, row_id)
        if found is not None:
            db.delete(found)
            db.commit()
        db.close()


def test_member_does_not_receive_the_suggestion_reason(client, fresh):
    """AI 제안 사유는 트레이너가 읽는 판단 재료다 — 회원 응답에서 비운다(#2579)."""
    prepared = _review_list(client, fresh, MEMBER, EN)[0]
    approved = client.post(
        f"/v1/trainer/routine-suggestions/{prepared['id']}/approve",
        headers=_h(fresh, EN),
        json={},
    )
    assert approved.status_code == 200, approved.text

    member = _member_token(client)
    for headers in (KO, EN, {}):
        mine = client.get("/v1/me/coach/routines", headers=_h(member, headers))
        assert mine.status_code == 200, mine.text
        delivered = [r for r in mine.json() if r["id"] == prepared["id"]]
        assert delivered
        assert prepared["reason"]
        assert delivered[0]["reason"] == ""
        assert delivered[0]["name"] == prepared["name"]
        # 근거는 여전히 회원에게 가지 않는다.
        assert delivered[0]["evidence"] == []


# ---------------------------------------------------------------------------
# 2-c. 규칙형 A/B (AI 폴백)
# ---------------------------------------------------------------------------

_RULE_KW = dict(
    goal="체중 감량",
    sodium_today_mg=2300,
    avg_completion_rate=45,
    available_minutes=30,
    intensity_preference="high",
    trainer_note="",
)


def test_rule_plans_korean_wording_is_unchanged():
    a, b = routine_ai.rule_based_plans(**_RULE_KW)

    assert a["label"] == "회복·지속 중심"
    assert a["reason"] == "짧고 지속하기 쉬운 회복 중심 루틴"
    assert a["rationale"] == (
        "오늘 나트륨 2300mg (목표 초과), 최근 운동 완료율 45% → "
        "부담이 적은 유산소·스트레칭으로 지속 가능성에 집중."
    )
    assert [e["name"] for e in a["exercises"]] == [
        "저강도 걷기",
        "코어 스트레칭",
        "목·어깨 스트레칭",
    ]
    assert b["label"] == "강도·운동량 중심"
    assert b["reason"] == "운동량과 강도를 높인 루틴"
    assert b["rationale"] == (
        "목표 '체중 감량' 기준, 완료율 45%로 점진적으로 "
        "근력·유산소를 더해 운동량을 높임."
    )
    assert [e["name"] for e in b["exercises"]] == ["인터벌 러닝", "스쿼트", "플랭크"]


def test_pattern_plans_korean_wording_is_unchanged():
    a, b = routine_ai.rule_based_plans(
        **_RULE_KW, frequent_exercises=["레그프레스"]
    )
    assert a["label"] == "기존 패턴 유지형"
    assert a["reason"] == "최근 자주 수행한 운동을 그대로 유지"
    assert a["rationale"] == (
        "최근 기록에서 반복 확인된 운동(레그프레스)을 유지하고 부족한 부분만 보완."
    )
    assert b["rationale"] == (
        "기존 핵심 운동(레그프레스)은 유지하고 '스쿼트'를 더해 "
        "운동량을 점진적으로 늘림."
    )


@pytest.mark.parametrize("note_length", [0, 200, 500])
@pytest.mark.parametrize("minutes", [5, 30, 180])
@pytest.mark.parametrize("pattern", [(), ("레그프레스",)])
def test_rule_plans_satisfy_the_response_schema(minutes, pattern, note_length):
    """최대 길이 메모와 주의 문장이 모두 붙어도 폴백이 죽지 않는다."""
    a, b = routine_ai.rule_based_plans(
        **{
            **_RULE_KW,
            "available_minutes": minutes,
            "trainer_note": "x" * note_length,
        },
        frequent_exercises=pattern,
        conditions="무릎 허리 어깨 발목 수술",
    )
    for plan in (a, b):
        RoutineOptionPlanOut.model_validate(plan)
        assert len(plan["rationale"]) <= routine_ai.RATIONALE_MAX_CHARS


def test_only_overlong_rationales_are_clipped():
    a, _ = routine_ai.rule_based_plans(
        **{**_RULE_KW, "trainer_note": "x" * 500}
    )
    assert len(a["rationale"]) == routine_ai.RATIONALE_MAX_CHARS
    assert a["rationale"].endswith("…")
    short, _ = routine_ai.rule_based_plans(**_RULE_KW)
    assert not short["rationale"].endswith("…")


# ---------------------------------------------------------------------------
# 2-d. AI A/B — 프롬프트와 폴백
# ---------------------------------------------------------------------------


def test_system_prompt_is_the_korean_prompt_as_written():
    assert options_service.system_prompt() is options_service._SYSTEM_PROMPT
    assert "Output language" not in options_service._SYSTEM_PROMPT


class _Result:
    def __init__(self, text: str) -> None:
        self.text = text


class _CapturingLlm:
    def __init__(self, text: str) -> None:
        self._text = text
        self.system_prompts: list[str] = []

    def generate(self, system_prompt: str, user_prompt: str, **_: object):
        self.system_prompts.append(system_prompt)
        return _Result(self._text)


_LLM_JSON = json.dumps(
    {
        "plan_a": {
            "key": "A",
            "label": "Joint-friendly recovery",
            "total_minutes": 20,
            "intensity": "낮음",
            "exercises": [
                {"name": "Low-intensity walk", "minutes": 20, "type": "유산소"}
            ],
            "reason": "A lighter mix",
            "rationale": "Reflects recent records",
        },
        "plan_b": {
            "key": "B",
            "label": "Strength builder",
            "total_minutes": 30,
            "intensity": "보통",
            "exercises": [
                {"name": "Squat", "minutes": 30, "type": "근력"}
            ],
            "reason": "More volume",
            "rationale": "Reflects the goal",
        },
    }
)


def _analysis() -> RoutineOptionAnalysisOut:
    return RoutineOptionAnalysisOut(
        goal="체중 감량",
        sodium_today_mg=2200,
        sodium_over_target=True,
        avg_completion_rate=65,
        latest_routine="걷기",
        note="",
    )


def _no_next_pt(monkeypatch) -> None:
    """DB 없이 돈다 — 연계안 기준(#3282)은 기록 없음으로 둔다."""
    monkeypatch.setattr(
        options_service,
        "build_next_pt",
        lambda *_a, **_k: options_service.routine_next_pt.choose_next(
            [], today=options_service.clock.today()
        ),
    )


def test_generator_sends_the_korean_prompt_to_the_llm(monkeypatch):
    llm = _CapturingLlm(_LLM_JSON)
    monkeypatch.setattr(options_service, "build_member_analysis", lambda *_: _analysis())
    _no_next_pt(monkeypatch)
    monkeypatch.setattr(options_service, "get_coach_llm", lambda: llm)

    result = options_service.generate_routine_options(
        object(), "trainer", "member", RoutineOptionsRequest(available_minutes=30)
    )

    assert result.generated_by == "ai"
    (system,) = llm.system_prompts
    assert system == options_service._SYSTEM_PROMPT


def test_rule_fallback_when_the_llm_breaks(monkeypatch):
    monkeypatch.setattr(options_service, "build_member_analysis", lambda *_: _analysis())
    _no_next_pt(monkeypatch)
    monkeypatch.setattr(
        options_service, "get_coach_llm", lambda: _CapturingLlm("not json")
    )

    result = options_service.generate_routine_options(
        object(), "trainer", "member", RoutineOptionsRequest(available_minutes=30)
    )

    assert result.generated_by == "rule"
    for plan in (result.plan_a, result.plan_b):
        assert _has_hangul(plan.label)
        assert _has_hangul(plan.reason)
        assert plan.intensity in {"낮음", "보통", "높음"}


def test_build_rule_options_wording():
    request = RoutineOptionsRequest(available_minutes=30, intensity_preference="high")
    options = options_service.build_rule_options(_analysis(), request)
    assert options.plan_a.label == "회복·지속 중심"


def _first_client_id(client, token: str) -> str:
    res = client.get("/v1/trainer/clients", headers=_h(token))
    assert res.status_code == 200, res.text
    return res.json()[0]["id"]


@pytest.mark.parametrize("headers", [EN, KO, {}])
def test_routine_options_api_is_korean_whatever_the_header(client, monkeypatch, headers):
    llm = _CapturingLlm("not json")
    monkeypatch.setattr(options_service, "get_coach_llm", lambda: llm)
    token = _trainer_token(client)
    member_id = _first_client_id(client, token)

    res = client.post(
        f"/v1/trainer/clients/{member_id}/routine-options",
        headers=_h(token, headers),
        json={"available_minutes": 30, "intensity_preference": "moderate"},
    )
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["generated_by"] == "rule"
    labels = [body["plan_a"]["label"], body["plan_b"]["label"]]
    assert all(_has_hangul(label) for label in labels), labels
    assert llm.system_prompts
    assert llm.system_prompts[0] == options_service._SYSTEM_PROMPT


# ---------------------------------------------------------------------------
# 3. 시작 템플릿
# ---------------------------------------------------------------------------


def test_starters_wording():
    ko = templates.starter_templates()
    assert [t.name for t in ko] == ["혈압 관리 기본", "체중 감량 순환", "하체 근력 A"]
    assert [t.goal for t in ko] == [
        "혈압 관리 · 초급",
        "체중 감량 · 중급",
        "근력 향상 · 중급",
    ]
    assert [e.name for e in ko[0].exercises] == ["준비 스트레칭", "저강도 걷기", "호흡 이완"]


# 템플릿 API 는 전용 트레이너를 만들어 본다 — 데모 트레이너가 저장한 템플릿이
# 있으면 시작 구성이 나오지 않는다.

EMAIL_PREFIX = "tpl-text-"
PASSWORD = "tpl-text-pw-1234"


@pytest.fixture()
def lone_trainer(client, db_session):
    suffix = uuid4().hex[:10]
    email = f"{EMAIL_PREFIX}{suffix}@oncare.com"
    user = User(
        id=f"tpl-text-{suffix}",
        email=email,
        name="Template Text",
        hashed_password=hash_password(PASSWORD),
        role="trainer",
        is_active=True,
    )
    db_session.add(user)
    db_session.commit()
    res = client.post("/v1/auth/login", data={"username": email, "password": PASSWORD})
    assert res.status_code == 200, res.text
    yield user, res.json()["access_token"]
    db_session.rollback()
    db_session.query(TrainerProgramTemplate).filter(
        TrainerProgramTemplate.trainer_id == user.id
    ).delete(synchronize_session=False)
    db_session.query(User).filter(User.id == user.id).delete(
        synchronize_session=False
    )
    db_session.commit()


@pytest.mark.parametrize("headers", [EN, KO, {}])
def test_template_api_serves_korean_starters(client, lone_trainer, headers):
    _, token = lone_trainer
    res = client.get("/v1/trainer/program-templates", headers=_h(token, headers))
    assert res.status_code == 200, res.text
    rows = res.json()
    assert [r["id"] for r in rows] == ["starter:0", "starter:1", "starter:2"]
    assert rows[0]["name"] == "혈압 관리 기본"


def test_saved_templates_are_served_as_written(client, lone_trainer):
    """트레이너가 쓴 템플릿은 트레이너의 글이다 — 그대로 돌려준다."""
    _, token = lone_trainer
    created = client.post(
        "/v1/trainer/program-templates",
        headers=_h(token, EN),
        json={
            "name": "내 하체 루틴",
            "goal": "근력",
            "exercises": [{"name": "스쿼트", "minutes": 10, "type": "근력"}],
        },
    )
    assert created.status_code in (200, 201), created.text

    rows = client.get(
        "/v1/trainer/program-templates", headers=_h(token, EN)
    ).json()
    assert [r["name"] for r in rows] == ["내 하체 루틴"]
    assert rows[0]["exercises"][0]["name"] == "스쿼트"


@pytest.mark.parametrize(
    "signals",
    [
        _ALL_SIGNALS,
        _RECORDS_ONLY,
        suggestions._Signals(strength_heavy=True, total_minutes=100, strength_minutes=60),
    ],
)
def test_strength_candidate_fits_the_suggestion_schema(signals):
    """근력 후보는 세트·횟수·중량을 싣고, 이름·사유는 스키마 길이 안이다 (#2703)."""
    strength = suggestions._suggestions_for(signals)[-1]
    assert strength.type == "근력"
    assert _has_hangul(strength.name) and _has_hangul(strength.reason)
    assert len(strength.name) <= 100 and len(strength.reason) <= 200
